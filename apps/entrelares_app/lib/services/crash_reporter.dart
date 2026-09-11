import 'dart:async';
import 'dart:math';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../env.dart';

/// T-66 — the sink a crash finally has, on both channels.
///
/// Until this existed, a widget that threw painted the red screen (or, on the
/// web, nothing at all) and the event ended there: no sink, no counter, no
/// alert. Every defect found since the cutover was found by a person who
/// happened to say something.
///
/// **A hand-written envelope POST, not an SDK**, for the same three reasons the
/// T-37 analytics transport is hand-written, plus one that is specific here:
/// nothing enters the payload that we did not write, so the S-13 invariant is
/// structural instead of a configuration somebody can undo. The payload itself
/// — and every scrub in it — lives in `entrelares_core`
/// ([buildCrashEvent]/[buildCrashEnvelope]), tested without a device; this
/// class is only the wire.
///
/// **Best-effort, always**: reporting never throws, never blocks a frame and
/// never surfaces to the reader. A crash reporter that can break the app is
/// worse than no crash reporter.
class CrashReporter {
  CrashReporter({
    String? dsn,
    http.Client? client,
    this.maxEventsPerSession = 20,
    DateTime Function()? now,
    Random? random,
  })  : _dsn = parseSentryDsn(dsn ?? Env.current.sentryDsn),
        _client = client ?? http.Client(),
        _now = now ?? DateTime.now,
        _random = random ?? Random();

  final SentryDsn? _dsn;
  final http.Client _client;
  final DateTime Function() _now;
  final Random _random;

  /// Ceiling per process. A failure inside `build()` throws on EVERY frame, so
  /// without a ceiling one bad release spends the quota — and the reader's
  /// battery — in seconds.
  final int maxEventsPerSession;

  /// Fingerprints already sent in this process. The server groups properly;
  /// this only keeps the client from shouting the same sentence 400 times.
  final Set<String> _sent = <String>{};
  int _count = 0;

  /// The E2E lane defines the dev service_role key to build its throwaway
  /// family. That define exists in NO user build, which makes it the honest
  /// signal for "this is a harness, not a person": an integration run that
  /// deliberately drives failure paths must not fill the dev project with
  /// events nobody will read.
  static const bool _isTestHarness =
      String.fromEnvironment('E2E_SUPABASE_SERVICE_ROLE_KEY') != '';

  /// False when the DSN is blank or malformed, and when this is a harness. An
  /// empty DSN is a STATE — the same fail-closed shape `WebPushConfig` uses —
  /// so an unarmed environment is silent rather than half-configured.
  bool get isEnabled => _dsn != null && !_isTestHarness;

  /// How the event names this build. Both halves matter: `release` is what
  /// Sentry shows beside a regression, and `environment` is what keeps a dev
  /// crash out of the production project's face — though the real separation
  /// is that the two environments carry DIFFERENT DSNs and land in different
  /// projects entirely.
  String get release => 'entrelares-app@${Env.appVersion}';
  String get environment => Env.current.isProduction ? 'production' : 'dev';

  /// Whether the hooks are already in place in this PROCESS. Guarded for the
  /// same reason `usePathUrlStrategy()` is in `main.dart`: `main()` runs ONCE
  /// in production, and TWICE per execution in the E2E lane — one boot per
  /// user, which is what a two-party workflow test has to do. Without the
  /// guard the second boot wraps the first boot's handlers, and the chain
  /// grows one layer per user.
  static bool _installed = false;

  /// Install the two hooks. They catch different failures and both are needed:
  /// [FlutterError.onError] is the framework's (a throw inside build, layout or
  /// paint), [PlatformDispatcher.instance.onError] is the zone's (an
  /// unawaited Future that rejects). `runZonedGuarded` is deliberately NOT
  /// used — since Flutter 3.3 the platform hook covers what it used to, and
  /// wrapping `main` in a zone would put every `print` and every test binding
  /// inside it for nothing.
  ///
  /// Both hooks keep the previous behaviour: the error still reaches the
  /// console and the red screen still paints. This is additive, never a
  /// replacement — a reporter that swallows the error it reports is how a
  /// debug session becomes a guessing game.
  void install() {
    if (_installed) return;
    _installed = true;
    final previousFlutterOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      previousFlutterOnError?.call(details);
      unawaited(report(
        details.exception,
        details.stack,
        context: details.context?.toString(),
      ));
    };

    final previousPlatformOnError = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(report(error, stack));
      // False on purpose: "not handled here", so the framework still prints it.
      return previousPlatformOnError?.call(error, stack) ?? false;
    };
  }

  /// Send one event. Safe to call from anywhere, including from inside an
  /// error handler — it swallows everything it can go wrong at.
  Future<void> report(
    Object error,
    StackTrace? stack, {
    String? context,
    bool fatal = true,
  }) async {
    final dsn = _dsn;
    if (dsn == null || !isEnabled) return;
    try {
      final trace = (stack ?? StackTrace.current).toString();
      final type = error.runtimeType.toString();
      final message = error.toString();

      final fingerprint =
          crashFingerprint(type, scrubCrashMessage(message), parseCrashFrames(trace));
      if (_count >= maxEventsPerSession || !_sent.add(fingerprint)) return;
      _count++;

      final event = buildCrashEvent(
        eventId: _eventId(),
        timestamp: _now(),
        type: type,
        message: message,
        stackTrace: trace,
        release: release,
        environment: environment,
        channel: analyticsChannel(isWeb: kIsWeb),
        isWeb: kIsWeb,
        context: context,
        fatal: fatal,
      );

      // Auth travels in the QUERY, and the body as `text/plain`, so the web
      // channel's POST stays a CORS-SIMPLE request with no preflight — the same
      // reasoning (and the same trap avoided) as the Umami transport. The
      // response is never read: an event we cannot confirm still arrived.
      final uri = Uri.parse(dsn.endpoint).replace(queryParameters: {
        'sentry_key': dsn.publicKey,
        'sentry_version': '7',
        'sentry_client': '$crashClientName/${Env.appVersion}',
      });

      await _client
          .post(
            uri,
            headers: const {'Content-Type': 'text/plain;charset=UTF-8'},
            body: buildCrashEnvelope(event: event, sentAt: _now()),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // By contract. The one thing a crash reporter may never do is crash.
    }
  }

  /// Undo the install guard. Only the suite needs this: a test that proves the
  /// hooks chain has to install them more than once in one process.
  @visibleForTesting
  static void resetInstallForTest() => _installed = false;

  /// 32 hex characters, no dashes — Sentry's `event_id` shape. Not a security
  /// token, so `Random` is the right amount of machinery.
  String _eventId() {
    const hex = '0123456789abcdef';
    return List.generate(32, (_) => hex[_random.nextInt(16)]).join();
  }
}
