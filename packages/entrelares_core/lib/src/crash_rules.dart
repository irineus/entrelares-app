/// T-66 client mirror — the NO-PII contract of crash reporting, and the whole
/// shape of what leaves the device when the app breaks.
///
/// The reasoning is the T-37 one, one notch stricter. Analytics sends what a
/// call site CHOSE to send; a crash sends what an exception HAPPENED to carry,
/// which is the same difference as between a form and a confession. So the
/// rule S-13 states — no personal data leaves for a third party — cannot be a
/// property of the transport here: it has to be a property of the payload, and
/// the payload is built in this file, pure and tested, exactly like
/// [sanitizeAnalyticsPath] owns the analytics promise.
///
/// **What is deliberately NOT collected**, and would be if this were an SDK:
/// no user id, e-mail or session; no breadcrumbs (they record navigation and
/// HTTP, which is where family and request ids live); no device name or
/// `server_name`; no request or response bodies; no route arguments; no
/// screenshots or view hierarchy. The event carries the exception type, a
/// scrubbed message, the stack, and four coarse dimensions (release,
/// environment, channel, platform). Nothing else has a field to travel in.
///
/// **What this file cannot promise.** A first name has no shape a regular
/// expression can catch, so a server message that interpolates one would carry
/// it. That is why [crashMessageMaxChars] is small and why the app never
/// attaches a response body: the known-shaped secrets (e-mail, token, id) are
/// masked here, and the unknown-shaped ones are kept out by not sending the
/// places they live.
library;

import 'dart:convert';

/// Cap on the exception message that travels. Short on purpose — a message
/// long enough to be a paragraph is long enough to be a row of data.
const int crashMessageMaxChars = 1000;

/// Cap on stack frames. Sentry groups on the top of the stack; the tail is
/// framework plumbing that costs bytes and says nothing.
const int crashMaxFrames = 60;

/// What the event calls this client. Not an SDK name — there is no SDK.
const String crashClientName = 'entrelares.envelope';

final _email = RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');

/// A JWT — the legacy anon key, a GoTrue access/refresh token, anything else
/// with three dot-separated segments that starts the way a JOSE header does.
final _jwt =
    RegExp(r'eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+');

/// The S-16 key shapes. The publishable one is public, the secret one must
/// never exist on a client at all — both are masked, because a key printed in
/// an error is a key someone can read, and telling them apart is not this
/// function's job.
final _supabaseKey = RegExp(r'sb_(?:publishable|secret)_[A-Za-z0-9_-]+');

/// `Bearer …`, `apikey=…`, `access_token=…` — the header and query shapes that
/// carry a credential in plain text.
final _credentialPair = RegExp(
    r'(?:[Bb]earer|[Aa]pikey|[Aa]pi[_-]?key|access_token|refresh_token|token)'
    r'["\x27]?\s*[=:]?\s*["\x27]?([A-Za-z0-9._-]{12,})');

/// Everything after the `?` or `#` of a URL. Stripped ENTIRELY and first-ish,
/// for the same reason the analytics sanitizer does it first: that is where an
/// invitation token and a recovery hash live, and no later rule would catch
/// them.
final _urlTail = RegExp(r'((?:[a-z][a-z0-9+.-]*):\/\/[^\s"\x27]*?)[?#][^\s"\x27]*');

final _uuid = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');

/// Six digits or more standing alone. The S-21 elevation code is exactly six,
/// single-use and short-lived — but it is still a credential, and an exception
/// that echoes the code someone typed is precisely the shape this catches.
/// Applied to MESSAGES only: a stack frame's line and column are digits too,
/// and they travel as integers in their own fields, never through here.
final _longDigits = RegExp(r'(?<![\d.:])\d{6,}(?![\d.])');

/// Mask everything known-shaped out of free text — an exception message, a
/// context label — and cap what is left.
///
/// Order is load-bearing, as in [sanitizeAnalyticsPath]: the URL tail goes
/// before the id masking, so `?invite=<token>` cannot survive by not looking
/// like anything; the e-mail goes first because a mailbox is the one datum
/// that identifies a person on its own.
String scrubCrashMessage(String input) {
  if (input.trim().isEmpty) return '';
  var out = input;
  out = out.replaceAll(_email, '[email]');
  out = out.replaceAll(_jwt, '[token]');
  out = out.replaceAll(_supabaseKey, '[token]');
  out = out.replaceAllMapped(_credentialPair, (m) {
    final whole = m[0]!;
    final secret = m[1]!;
    return '${whole.substring(0, whole.length - secret.length)}[token]';
  });
  out = out.replaceAllMapped(_urlTail, (m) => '${m[1]}?[redacted]');
  out = out.replaceAll(_uuid, '[id]');
  out = out.replaceAll(_longDigits, '[digits]');
  out = out.trim();
  return out.length <= crashMessageMaxChars
      ? out
      : '${out.substring(0, crashMessageMaxChars)}…';
}

/// The same, for a code location — a `package:` path, a `dart:` library, or
/// the web build's own asset URL. Narrower on purpose: a file path carries no
/// digits worth masking, and mangling it would cost the only thing a frame is
/// for.
String scrubCrashLocation(String input) {
  var out = input.trim();
  if (out.isEmpty) return '';
  out = out.replaceAllMapped(_urlTail, (m) => m[1]!);
  final cut = out.indexOf(RegExp(r'[?#]'));
  if (cut >= 0) out = out.substring(0, cut);
  out = out.replaceAll(_uuid, '[id]');
  return out;
}

/// One line of a stack, reduced to what Sentry groups on.
class CrashFrame {
  const CrashFrame({
    required this.function,
    required this.filename,
    this.lineNo,
    this.colNo,
  });

  final String function;
  final String filename;
  final int? lineNo;
  final int? colNo;

  /// Ours versus the framework's. Sentry uses it to pick the frame it shows
  /// first, which is the difference between "the app broke" and "Flutter
  /// broke".
  bool get isInApp =>
      filename.startsWith('package:entrelares') ||
      filename.contains('/main.dart.js');

  Map<String, Object?> toSentryFrame() => {
        'function': function,
        'filename': filename,
        if (lineNo != null) 'lineno': lineNo,
        if (colNo != null) 'colno': colNo,
        'in_app': isInApp,
      };
}

/// `#12     Foo.bar (package:entrelares_app/x.dart:34:5)` — the Dart VM shape,
/// which is what Android produces.
final _vmFrame = RegExp(r'^#\d+\s+(.+?)\s+\((\S+?):(\d+)(?::(\d+))?\)$');

/// `    at Foo.bar (https://web.entrelares.app/main.dart.js:1:2)` — the dart2js
/// shape, which is what the web produces. The web channel is the one where a
/// failure is invisible today, so its stack has to parse too, even minified.
final _jsFrame =
    RegExp(r'^\s*at\s+(?:(.+?)\s+)?\(?([^\s()]+?):(\d+):(\d+)\)?$');

/// Parse a stack trace into frames, OLDEST FIRST — the order Sentry expects,
/// which is the reverse of the order both Dart and JS print.
///
/// Unparsed lines are dropped rather than guessed at. When nothing parses the
/// caller still has the raw text, and [buildCrashEvent] sends it as an extra:
/// a stack nobody can read beats a stack nobody gets.
List<CrashFrame> parseCrashFrames(String trace) {
  final frames = <CrashFrame>[];
  for (final raw in const LineSplitter().convert(trace)) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    final vm = _vmFrame.firstMatch(line);
    if (vm != null) {
      frames.add(CrashFrame(
        function: scrubCrashLocation(vm[1]!),
        filename: scrubCrashLocation(vm[2]!),
        lineNo: int.tryParse(vm[3]!),
        colNo: vm[4] == null ? null : int.tryParse(vm[4]!),
      ));
      continue;
    }
    final js = _jsFrame.firstMatch(line);
    if (js != null) {
      frames.add(CrashFrame(
        function: scrubCrashLocation(js[1] ?? '<anonymous>'),
        filename: scrubCrashLocation(js[2]!),
        lineNo: int.tryParse(js[3]!),
        colNo: int.tryParse(js[4]!),
      ));
    }
  }
  final capped =
      frames.length <= crashMaxFrames ? frames : frames.sublist(0, crashMaxFrames);
  return capped.reversed.toList(growable: false);
}

/// A Sentry DSN, split into the three things a hand-written POST needs.
///
/// The DSN is PUBLIC by construction — it is shipped to every browser that
/// loads any Sentry-instrumented web page, and it can only WRITE events. That
/// is what lets it live in `env.dart` under rule 1 of `CLAUDE.md` (T-44), and
/// it is worth restating because "key" in a config file reads like a secret
/// even when it is not.
class SentryDsn {
  const SentryDsn({
    required this.endpoint,
    required this.publicKey,
    required this.projectId,
  });

  /// Where the envelope is POSTed.
  final String endpoint;

  /// The `sentry_key` of the auth header.
  final String publicKey;
  final String projectId;

  /// The value of `X-Sentry-Auth`. [client] names this client and its version
  /// so a malformed event can be traced back to a release of ours.
  String authHeader(String client) => 'Sentry sentry_version=7, '
      'sentry_client=$client, '
      'sentry_key=$publicKey';
}

/// Parse `https://<key>@<host>/<projectId>`.
///
/// Returns null for an empty or malformed DSN, and an EMPTY DSN IS A STATE,
/// not an omission — the same fail-closed shape as `WebPushConfig` in
/// `env.dart` before T-62 was armed. A null here makes the reporter a no-op
/// that says so, never a half-configured client that fails at POST time.
SentryDsn? parseSentryDsn(String raw) {
  final dsn = raw.trim();
  if (dsn.isEmpty) return null;
  final uri = Uri.tryParse(dsn);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final key = uri.userInfo.split(':').first;
  if (key.isEmpty) return null;
  final projectId = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  if (projectId == null || projectId.isEmpty) return null;
  return SentryDsn(
    endpoint: '${uri.scheme}://${uri.host}/api/$projectId/envelope/',
    publicKey: key,
    projectId: projectId,
  );
}

/// What the client considers "the same crash", for the rate limiter that keeps
/// a build-loop failure — which throws on EVERY frame — from spending a day's
/// quota in a second. Grouping proper is the server's job; this is only about
/// not shouting.
String crashFingerprint(String type, String message, List<CrashFrame> frames) {
  final top = frames.isEmpty ? '' : frames.last.filename;
  final line = frames.isEmpty ? '' : '${frames.last.lineNo ?? ''}';
  return '$type|$message|$top:$line';
}

/// Build the event body. Everything that can carry text is scrubbed HERE, so
/// no transport can forget to.
Map<String, Object?> buildCrashEvent({
  required String eventId,
  required DateTime timestamp,
  required String type,
  required String message,
  required String stackTrace,
  required String release,
  required String environment,
  required String channel,
  required bool isWeb,
  String? context,
  bool fatal = true,
}) {
  final frames = parseCrashFrames(stackTrace);
  final scrubbedMessage = scrubCrashMessage(message);
  return <String, Object?>{
    'event_id': eventId,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'platform': isWeb ? 'javascript' : 'other',
    'level': fatal ? 'fatal' : 'error',
    'logger': 'flutter',
    'release': release,
    'environment': environment,
    'sdk': {'name': crashClientName, 'version': release},
    'tags': <String, String>{
      'channel': channel,
      if (context != null && context.isNotEmpty)
        'context': scrubCrashMessage(context),
    },
    'exception': {
      'values': [
        <String, Object?>{
          'type': scrubCrashMessage(type),
          'value': scrubbedMessage,
          if (frames.isNotEmpty)
            'stacktrace': {
              'frames': frames.map((f) => f.toSentryFrame()).toList(),
            },
        }
      ],
    },
    // Only when nothing parsed: a stack we could not read still beats none,
    // and it is scrubbed like any other free text.
    if (frames.isEmpty && stackTrace.trim().isNotEmpty)
      'extra': {'raw_stack_trace': scrubCrashMessage(stackTrace)},
  };
}

/// Wrap an event in the Sentry envelope — three NDJSON lines: the envelope
/// header, the item header, the item.
String buildCrashEnvelope({
  required Map<String, Object?> event,
  required DateTime sentAt,
}) {
  final body = jsonEncode(event);
  final envelopeHeader = jsonEncode({
    'event_id': event['event_id'],
    'sent_at': sentAt.toUtc().toIso8601String(),
  });
  final itemHeader = jsonEncode({
    'type': 'event',
    'content_type': 'application/json',
    'length': utf8.encode(body).length,
  });
  return '$envelopeHeader\n$itemHeader\n$body\n';
}
