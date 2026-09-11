// T-66 — the transport half of crash reporting. The no-PII rule itself is
// proven in `crash_rules_test.dart` (core); what this suite pins is what the
// APP can still get wrong: sending when the environment has no DSN, shouting
// the same crash on every frame, letting a failed POST reach the user, or
// swallowing the error it was supposed to only observe.
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:entrelares_core/entrelares_core.dart';

import 'package:entrelares_app/env.dart';
import 'package:entrelares_app/services/crash_reporter.dart';

void main() {
  const dsn = 'https://207fdf4ae55dd391583ecaa369b3319b'
      '@o4511910022217728.ingest.us.sentry.io/4512066983231488';

  late List<http.Request> sent;

  http.Client recording({int status = 200, bool throws = false}) {
    sent = [];
    return MockClient((request) async {
      sent.add(request);
      if (throws) throw const SocketExceptionStub();
      return http.Response('', status);
    });
  }

  CrashReporter reporter({
    String dsnValue = dsn,
    int maxEventsPerSession = 20,
    bool throws = false,
  }) =>
      CrashReporter(
        dsn: dsnValue,
        client: recording(throws: throws),
        maxEventsPerSession: maxEventsPerSession,
        now: () => DateTime.utc(2026, 9, 11, 12),
        random: Random(1),
      );

  final pt = Localization(AppLanguage.ptBr);

  Map<String, Object?> eventOf(http.Request request) {
    final lines = const LineSplitter().convert(request.body);
    return jsonDecode(lines[2]) as Map<String, Object?>;
  }

  group('disabled', () {
    test('an empty DSN makes reporting a no-op', () async {
      final crash = reporter(dsnValue: '');

      await crash.report(StateError('boom'), StackTrace.current);

      expect(crash.isEnabled, isFalse);
      expect(sent, isEmpty);
    });

    test('a malformed DSN is silent, never half-configured', () async {
      final crash = reporter(dsnValue: 'https://o1.ingest.sentry.io');

      await crash.report(StateError('boom'), StackTrace.current);

      expect(crash.isEnabled, isFalse);
      expect(sent, isEmpty);
    });

    test('both environments carry their OWN project', () {
      // The separation that matters is not a tag: a QA run writes into a
      // different project entirely, so nothing dev-flavoured can reach the
      // stream someone reads to decide whether production is on fire.
      expect(Env.dev.sentryDsn, isNotEmpty);
      expect(Env.prod.sentryDsn, isNotEmpty);
      expect(Env.dev.sentryDsn, isNot(Env.prod.sentryDsn));
    });
  });

  group('the POST', () {
    test('goes to the envelope endpoint with the auth in the QUERY', () async {
      final crash = reporter();

      await crash.report(StateError('boom'), StackTrace.current);

      expect(sent, hasLength(1));
      final uri = sent.single.url;
      expect(uri.path, '/api/4512066983231488/envelope/');
      expect(uri.queryParameters['sentry_key'],
          '207fdf4ae55dd391583ecaa369b3319b');
      expect(uri.queryParameters['sentry_version'], '7');
      expect(uri.queryParameters['sentry_client'], contains(Env.appVersion));
    });

    test('stays a CORS-simple request — no custom header, text/plain body', () {
      // The web channel is half the point of this item; a preflight the
      // collector refuses would make it silently report nothing there.
      final crash = reporter();

      return crash.report(StateError('boom'), StackTrace.current).then((_) {
        final headers = sent.single.headers;
        expect(headers['content-type'], 'text/plain;charset=UTF-8');
        expect(headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('x-sentry-auth')));
      });
    });

    test('sends a three-line envelope whose event names this build', () async {
      final crash = reporter();

      await crash.report(StateError('boom'), StackTrace.current);

      final lines = const LineSplitter().convert(sent.single.body);
      expect(lines, hasLength(3));
      final event = eventOf(sent.single);
      expect(event['release'], 'entrelares-app@${Env.appVersion}');
      expect(event['environment'], 'dev',
          reason: 'flutter test resolves to the dev flavor by construction');
      expect((event['tags'] as Map)['channel'], 'store');
      expect(event['level'], 'fatal');
    });

    test('a handled error is reported as error, not fatal', () async {
      final crash = reporter();

      await crash.report(StateError('boom'), StackTrace.current, fatal: false);

      expect(eventOf(sent.single)['level'], 'error');
    });

    test('scrubs on the way out — the app never posts raw text', () async {
      final crash = reporter();

      await crash.report(
        StateError('invite of maria@example.com failed'),
        StackTrace.current,
        context: 'family 3d42f3f4-b9b2-819d-b0d8-c845b7aa1ae5',
      );

      expect(sent.single.body, isNot(contains('maria@example.com')));
      expect(sent.single.body, isNot(contains('3d42f3f4')));
    });
  });

  group('not shouting', () {
    test('the same crash twice is sent once', () async {
      final crash = reporter();
      final stack = StackTrace.current;

      await crash.report(StateError('boom'), stack);
      await crash.report(StateError('boom'), stack);
      await crash.report(StateError('boom'), stack);

      expect(sent, hasLength(1));
    });

    test('a different crash still gets through', () async {
      final crash = reporter();
      final stack = StackTrace.current;

      await crash.report(StateError('boom'), stack);
      await crash.report(ArgumentError('other'), stack);

      expect(sent, hasLength(2));
    });

    test('the per-session ceiling holds', () async {
      final crash = reporter(maxEventsPerSession: 2);
      final stack = StackTrace.current;

      for (var i = 0; i < 10; i++) {
        await crash.report(StateError('boom $i'), stack);
      }

      expect(sent, hasLength(2));
    });
  });

  group('never in the way', () {
    test('a transport failure is swallowed', () async {
      final crash = reporter(throws: true);

      await expectLater(
        crash.report(StateError('boom'), StackTrace.current),
        completes,
      );
    });

    test('a null stack still produces an event', () async {
      final crash = reporter();

      await crash.report(StateError('boom'), null);

      expect(sent, hasLength(1));
    });
  });

  // T-66 (PR 2) — the handled half, wired through the core seam.
  group('an error the app caught and could not explain', () {
    tearDown(() => saveErrorObserver = null);

    test('reaches the sink as its own type, at error level', () async {
      final crash = reporter();
      saveErrorObserver = crash.reportUnexplainedSaveError;

      translateSaveError('total garbage', 'Erro ao salvar.', pt);
      await Future<void>.delayed(Duration.zero);

      expect(sent, hasLength(1));
      final values = (eventOf(sent.single)['exception'] as Map)['values'] as List;
      expect((values.single as Map)['type'], 'UnexplainedSaveError');
      expect(eventOf(sent.single)['level'], 'error',
          reason: 'the app kept working and told the reader something — it is '
              'a signal, not a crash');
    });

    test('tags a stable slug, never the translated sentence', () async {
      final crash = reporter();
      saveErrorObserver = crash.reportUnexplainedSaveError;

      translateSaveError('total garbage', 'Erro ao salvar.', pt);
      await Future<void>.delayed(Duration.zero);

      expect((eventOf(sent.single)['tags'] as Map)['context'],
          'unexplained-save-error',
          reason: 'a tag whose value is a localized paragraph splits one event '
              'into one per language');
    });

    test('stays quiet on a refusal the product explained', () async {
      final crash = reporter();
      saveErrorObserver = crash.reportUnexplainedSaveError;

      translateSaveError(
        'PostgrestException(message: Esta família já atingiu o limite de 4 '
        'responsáveis., code: 23514, details: Bad Request, hint: null)',
        'Erro ao salvar.',
        pt,
      );
      await Future<void>.delayed(Duration.zero);

      expect(sent, isEmpty);
    });
  });

  group('install', () {
    setUp(CrashReporter.resetInstallForTest);

    tearDown(() {
      CrashReporter.resetInstallForTest();
      FlutterError.onError = FlutterError.presentError;
      PlatformDispatcher.instance.onError = null;
    });

    test('installing twice does not stack the handlers', () {
      var previousCalled = 0;
      FlutterError.onError = (_) => previousCalled++;

      reporter().install();
      reporter().install();
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('boom')));

      expect(previousCalled, 1,
          reason: 'the E2E lane boots main() once per user; without the guard '
              'the chain grows a layer each time');
    });

    test('keeps the PREVIOUS handler — the console still gets the error', () {
      var previousCalled = 0;
      FlutterError.onError = (_) => previousCalled++;

      reporter().install();
      FlutterError.onError!(FlutterErrorDetails(exception: StateError('boom')));

      expect(previousCalled, 1,
          reason: 'additive, never a replacement: a reporter that swallows '
              'the error it reports turns debugging into guessing');
    });

    test('the platform hook reports but answers "not handled"', () {
      reporter().install();

      final handled = PlatformDispatcher.instance.onError!
          .call(StateError('boom'), StackTrace.current);

      expect(handled, isFalse,
          reason: 'false is what keeps the framework printing it');
    });
  });
}

/// A stand-in for the network failure a real client throws — the test only
/// needs "the transport threw", not a platform-specific type.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
