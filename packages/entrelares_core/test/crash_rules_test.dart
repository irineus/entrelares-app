import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// T-66 — the suite that stands in for the promise the transport cannot make.
///
/// The centrepiece is the "realistic dirty event" group: it feeds the builder
/// the kind of exception this app actually produces — a PostgREST error with a
/// unique-violation detail, a GoTrue message with a recovery URL, an invitation
/// link with its token — and asserts on the SERIALIZED event, because a leak
/// that slips into a nested field is still a leak.
void main() {
  group('scrubCrashMessage', () {
    test('masks an e-mail address', () {
      expect(
        scrubCrashMessage('duplicate key (email)=(maria.silva@gmail.com)'),
        'duplicate key (email)=([email])',
      );
    });

    test('masks a JWT, whatever it is doing in the message', () {
      // Shaped like a JWT, signed by nobody. A fixture must never be a COPY of
      // a live key — the value is public either way, but a scanner cannot tell
      // a test from a leak, and neither can the next reader.
      const jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJpc3MiOiJmaXh0dXJlIiwicm9sZSI6ImFub24ifQ'
          '.nOtArEaLsIgNaTuReJuStAfIxTuReFoRtEsTsXxXxXx';
      expect(scrubCrashMessage('apikey $jwt rejected'), contains('[token]'));
      expect(scrubCrashMessage('apikey $jwt rejected'), isNot(contains('eyJ')));
    });

    test('masks both S-16 key shapes', () {
      expect(
        scrubCrashMessage('sb_publishable_FiXtUrEoNlY0000NotARealKey0'),
        '[token]',
      );
      expect(scrubCrashMessage('sb_secret_abc123XYZ_deadbeef'), '[token]');
    });

    test('masks a bearer token but keeps the word that names it', () {
      final out = scrubCrashMessage(
          'Authorization: Bearer abcdefghijklmnop.qrstuvwxyz failed');
      expect(out, contains('Bearer [token]'));
      expect(out, isNot(contains('abcdefghijklmnop')));
    });

    test('strips the query of a URL — this is where the invite token lives',
        () {
      final out = scrubCrashMessage(
          'GET https://web.entrelares.app/invite?token=9f8a7b6c5d4e3f2a1b failed');
      expect(out, contains('https://web.entrelares.app/invite?[redacted]'));
      expect(out, isNot(contains('9f8a7b6c5d4e3f2a1b')));
    });

    test('strips a recovery FRAGMENT too, which no id rule would catch', () {
      final out = scrubCrashMessage(
          'https://web.entrelares.app/#access_token=xyzxyzxyzxyz&type=recovery');
      expect(out, isNot(contains('access_token=xyz')));
      expect(out, contains('[redacted]'));
    });

    test('masks a UUID — the family and profile ids travel as one', () {
      expect(
        scrubCrashMessage('family 3d42f3f4-b9b2-819d-b0d8-c845b7aa1ae5 denied'),
        'family [id] denied',
      );
    });

    test('masks a six-digit run — the S-21 elevation code is exactly six', () {
      expect(scrubCrashMessage('invalid code 481920'), 'invalid code [digits]');
    });

    test('leaves a short number alone — a seat count is not a secret', () {
      expect(scrubCrashMessage('seats 3 of 4'), 'seats 3 of 4');
    });

    test('caps a long message and says it cut', () {
      final out = scrubCrashMessage('x' * (crashMessageMaxChars + 500));
      expect(out.length, crashMessageMaxChars + 1);
      expect(out.endsWith('…'), isTrue);
    });

    test('an empty message stays empty rather than becoming noise', () {
      expect(scrubCrashMessage('   '), '');
    });
  });

  group('scrubCrashLocation', () {
    test('keeps a package path intact — it is the whole point of a frame', () {
      expect(
        scrubCrashLocation('package:entrelares_app/screens/family_screen.dart'),
        'package:entrelares_app/screens/family_screen.dart',
      );
    });

    test('keeps the line-number digits out of it (they are not in the text)',
        () {
      expect(scrubCrashLocation('dart:async/zone.dart'), 'dart:async/zone.dart');
    });

    test('drops a query from a web asset URL', () {
      expect(
        scrubCrashLocation('https://web.entrelares.app/main.dart.js?v=123456'),
        'https://web.entrelares.app/main.dart.js',
      );
    });
  });

  group('parseCrashFrames', () {
    const vmTrace = '''
#0      FamilyScreen.build (package:entrelares_app/screens/family_screen.dart:120:15)
#1      StatefulElement.build (package:flutter/src/widgets/framework.dart:5666:27)
<asynchronous suspension>
#2      main (package:entrelares_app/main.dart:96:3)
''';

    test('parses the Dart VM shape', () {
      final frames = parseCrashFrames(vmTrace);
      expect(frames, hasLength(3));
    });

    test('returns OLDEST FIRST — the order Sentry expects', () {
      final frames = parseCrashFrames(vmTrace);
      expect(frames.first.function, 'main');
      expect(frames.last.function, 'FamilyScreen.build');
      expect(frames.last.lineNo, 120);
      expect(frames.last.colNo, 15);
    });

    test('marks our own frames in_app and the framework not', () {
      final frames = parseCrashFrames(vmTrace);
      expect(frames.last.isInApp, isTrue);
      expect(
        frames.firstWhere((f) => f.filename.startsWith('package:flutter')).isInApp,
        isFalse,
      );
    });

    test('parses the dart2js shape — the web channel has to group too', () {
      final frames = parseCrashFrames('''
    at Object.wrapException (https://web.entrelares.app/main.dart.js:4521:19)
    at https://web.entrelares.app/main.dart.js:9812:7
''');
      expect(frames, hasLength(2));
      expect(frames.every((f) => f.isInApp), isTrue);
      expect(frames.last.lineNo, 4521);
    });

    test('drops what it cannot read instead of guessing', () {
      expect(parseCrashFrames('something that is not a frame at all'), isEmpty);
    });

    test('caps the number of frames', () {
      final long = List.generate(
          crashMaxFrames + 20,
          (i) => '#$i      f$i (package:entrelares_app/x.dart:$i:1)').join('\n');
      expect(parseCrashFrames(long), hasLength(crashMaxFrames));
    });
  });

  group('parseSentryDsn', () {
    const dsn = 'https://207fdf4ae55dd391583ecaa369b3319b'
        '@o4511910022217728.ingest.us.sentry.io/4512066983231488';

    test('splits a DSN into endpoint, key and project', () {
      final parsed = parseSentryDsn(dsn)!;
      expect(parsed.publicKey, '207fdf4ae55dd391583ecaa369b3319b');
      expect(parsed.projectId, '4512066983231488');
      expect(
        parsed.endpoint,
        'https://o4511910022217728.ingest.us.sentry.io'
        '/api/4512066983231488/envelope/',
      );
    });

    test('builds the auth header Sentry expects', () {
      expect(
        parseSentryDsn(dsn)!.authHeader('entrelares.envelope/2.6.9+73'),
        'Sentry sentry_version=7, '
        'sentry_client=entrelares.envelope/2.6.9+73, '
        'sentry_key=207fdf4ae55dd391583ecaa369b3319b',
      );
    });

    test('an EMPTY dsn is a state, not an error — it returns null', () {
      expect(parseSentryDsn(''), isNull);
      expect(parseSentryDsn('   '), isNull);
    });

    test('a malformed dsn returns null rather than a half-built client', () {
      expect(parseSentryDsn('not a url'), isNull);
      expect(parseSentryDsn('https://o123.ingest.sentry.io/42'), isNull,
          reason: 'no public key');
      expect(parseSentryDsn('https://key@o123.ingest.sentry.io'), isNull,
          reason: 'no project id');
    });
  });

  group('a realistic dirty event', () {
    // Everything below is the shape this app really produces. If any of it
    // survives into the serialized event, the S-13 invariant is broken.
    const dirtyMessage =
        'PostgrestException(message: duplicate key value violates unique '
        'constraint "family_invitations_email_key", detail: Key (email)='
        '(joana.pereira@gmail.com) already exists in family '
        '3d42f3f4-b9b2-819d-b0d8-c845b7aa1ae5, hint: null, code: 23505) while '
        'POSTing https://jptqbwfziyzlhlmoekzu.supabase.co/rest/v1/'
        'family_invitations?select=*&apikey=sb_publishable_FiXtUrEoNlY00';

    const dirtyStack = '''
#0      SupabaseCustodyDataSource.createInvitation (package:entrelares_app/services/supabase_custody_data_source.dart:412:7)
#1      FamilyScreen._invite (package:entrelares_app/screens/family_screen.dart:288:22)
''';

    late String encoded;

    setUp(() {
      final event = buildCrashEvent(
        eventId: 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
        timestamp: DateTime.utc(2026, 9, 11, 12, 30),
        type: 'PostgrestException',
        message: dirtyMessage,
        stackTrace: dirtyStack,
        release: 'entrelares-app@2.6.9+73',
        environment: 'dev',
        channel: 'store',
        isWeb: false,
        context: 'while inviting joana.pereira@gmail.com',
      );
      encoded = jsonEncode(event);
    });

    test('no e-mail address survives anywhere in the event', () {
      expect(encoded, isNot(contains('joana.pereira')));
      expect(encoded, isNot(contains('@gmail.com')));
    });

    test('no key survives anywhere in the event', () {
      expect(encoded, isNot(contains('sb_publishable')));
      expect(encoded, isNot(contains('apikey=sb')));
    });

    test('no family id survives anywhere in the event', () {
      expect(encoded, isNot(contains('3d42f3f4')));
    });

    test('the CONTEXT label is scrubbed too — it is free text like any other',
        () {
      expect(encoded, contains('while inviting [email]'));
    });

    test('what remains is still diagnosable', () {
      final event = jsonDecode(encoded) as Map<String, Object?>;
      final values = (event['exception'] as Map)['values'] as List;
      final first = values.single as Map<String, Object?>;
      expect(first['type'], 'PostgrestException');
      expect(first['value'], contains('unique constraint'));
      expect(first['value'], contains('code: 23505'),
          reason: 'a five-digit SQLSTATE is a diagnosis, not a credential — '
              'the six-digit rule leaves it, and leaving it is the point');
      final frames = ((first['stacktrace'] as Map)['frames'] as List)
          .cast<Map<String, Object?>>();
      // Last is the CRASHING frame, because the list is oldest-first: the
      // screen that asked comes first, the data source that threw comes last.
      expect(frames.first['function'], 'FamilyScreen._invite');
      expect(frames.last['function'],
          'SupabaseCustodyDataSource.createInvitation');
      expect(frames.last['lineno'], 412);
      expect(frames.last['in_app'], isTrue);
    });

    test('carries the four coarse dimensions and nothing identifying', () {
      final event = jsonDecode(encoded) as Map<String, Object?>;
      expect(event['release'], 'entrelares-app@2.6.9+73');
      expect(event['environment'], 'dev');
      expect((event['tags'] as Map)['channel'], 'store');
      expect(event['platform'], 'other');
      // The fields an SDK would have filled in, and this one has no place for.
      expect(event.containsKey('user'), isFalse);
      expect(event.containsKey('breadcrumbs'), isFalse);
      expect(event.containsKey('server_name'), isFalse);
      expect(event.containsKey('contexts'), isFalse);
    });

    test('an unreadable stack still travels, scrubbed, as an extra', () {
      final event = buildCrashEvent(
        eventId: 'b' * 32,
        timestamp: DateTime.utc(2026, 9, 11),
        type: 'StateError',
        message: 'boom',
        stackTrace: 'totally unparseable 3d42f3f4-b9b2-819d-b0d8-c845b7aa1ae5',
        release: 'entrelares-app@2.6.9+73',
        environment: 'dev',
        channel: 'web',
        isWeb: true,
      );
      final extra = event['extra'] as Map<String, Object?>;
      expect(extra['raw_stack_trace'], contains('[id]'));
      expect(event['platform'], 'javascript');
    });
  });

  group('buildCrashEnvelope', () {
    test('is three NDJSON lines, with a length the server can trust', () {
      final event = buildCrashEvent(
        eventId: 'c' * 32,
        timestamp: DateTime.utc(2026, 9, 11),
        type: 'StateError',
        message: 'boom',
        stackTrace: '',
        release: 'entrelares-app@2.6.9+73',
        environment: 'production',
        channel: 'web',
        isWeb: true,
      );
      final envelope =
          buildCrashEnvelope(event: event, sentAt: DateTime.utc(2026, 9, 11));
      final lines = const LineSplitter().convert(envelope);
      expect(lines, hasLength(3));

      final header = jsonDecode(lines[0]) as Map<String, Object?>;
      expect(header['event_id'], 'c' * 32);
      expect(header['sent_at'], '2026-09-11T00:00:00.000Z');

      final itemHeader = jsonDecode(lines[1]) as Map<String, Object?>;
      expect(itemHeader['type'], 'event');
      expect(itemHeader['length'], utf8.encode(lines[2]).length);

      expect(jsonDecode(lines[2]), isA<Map<String, Object?>>());
    });
  });

  group('crashFingerprint', () {
    test('the same crash twice is the same key', () {
      final frames = parseCrashFrames(
          '#0      f (package:entrelares_app/x.dart:10:1)');
      expect(
        crashFingerprint('StateError', 'boom', frames),
        crashFingerprint('StateError', 'boom', frames),
      );
    });

    test('a different line is a different key', () {
      final a = parseCrashFrames('#0      f (package:entrelares_app/x.dart:10:1)');
      final b = parseCrashFrames('#0      f (package:entrelares_app/x.dart:11:1)');
      expect(
        crashFingerprint('StateError', 'boom', a),
        isNot(crashFingerprint('StateError', 'boom', b)),
      );
    });
  });
}
