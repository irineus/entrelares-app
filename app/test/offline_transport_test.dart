// T-18 — the connectivity state and the session gate, driven by the REAL stack.
//
// Two lessons shape this file. `save_errors.dart` (27/08/2026): a classifier
// tested against hand-written error text passes while production never
// matches, because the platform's real exception has another shape. And the
// 01/09/2026 month-window defect: a fake that reimplements the thing under
// test agrees with it by construction. So the offline cases here fail on a
// REAL socket — the platform `IOClient` refused by a closed local port — and
// run through the real `SupabaseClient` and the real `GoTrueClient`. Only the
// server's ANSWERS are stubbed, because an answer is exactly what an offline
// test must not have.
//
// Only `test()` here, no `testWidgets`: the widget binding replaces
// `HttpClient` with one that answers 400 to everything, and a 400 is the
// server answering — the opposite of what these cases need.
import 'dart:async';
import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:entrelares_app/services/connectivity_status.dart';
import 'package:entrelares_app/services/session_gate.dart';
import 'package:entrelares_app/services/supabase_custody_data_source.dart';

/// Nothing listens on port 1: the connect is refused at once, by the OS.
const _unreachable = 'http://127.0.0.1:1';

http.Response _json(http.BaseRequest request, Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'});

String _b64(Map<String, Object?> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// A session shaped as supabase_flutter persists it, with an access token that
/// is a real JWT (gotrue reads `exp` out of it).
String _restoredSession({required Duration expiresIn}) {
  final exp = DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  final token = '${_b64({
        'alg': 'HS256',
        'typ': 'JWT'
      })}.${_b64({'sub': 'u1', 'exp': exp, 'role': 'authenticated'})}.sig';
  return jsonEncode({
    'access_token': token,
    'expires_in': expiresIn.inSeconds,
    'refresh_token': 'refresh-1',
    'token_type': 'bearer',
    'user': {
      'id': 'u1',
      'aud': 'authenticated',
      'app_metadata': <String, Object?>{},
      'user_metadata': <String, Object?>{},
      'created_at': '2026-09-01T00:00:00Z',
    },
  });
}

Future<GoTrueClient> _authWithRestoredSession(http.Client transport) async {
  final auth = GoTrueClient(
    url: '$_unreachable/auth/v1',
    httpClient: transport,
    autoRefreshToken: false,
  );
  // Expired: the refresh the gate asks for is the one a morning boot needs.
  await auth.setInitialSession(
      _restoredSession(expiresIn: const Duration(minutes: -5)));
  return auth;
}

void main() {
  group('ConnectivityHttpClient — the one place the state is learned', () {
    test('a refused connect through the REAL data source reads as offline',
        () async {
      final status = ConnectivityStatus();
      final source = SupabaseCustodyDataSource(SupabaseClient(
        _unreachable,
        'stub-key',
        httpClient: ConnectivityHttpClient(status),
      ));

      Object? thrown;
      try {
        // The production configuration, retries included: what reaches the
        // calendar is what postgrest rethrows after its last attempt.
        await source.fetchMembers();
      } catch (e) {
        thrown = e;
      }

      expect(thrown, isNotNull);
      expect(isNetworkFailure(thrown.toString()), isTrue,
          reason: 'the real exception reads: $thrown');
      expect(status.offline, isTrue);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('the next answer from the server ends it, whatever the answer was',
        () async {
      // A 42501 is the server refusing, which proves the network is fine.
      final status = ConnectivityStatus()..lostServer();
      final source = SupabaseCustodyDataSource(SupabaseClient(
        'https://stub.supabase.test',
        'stub-key',
        httpClient: ConnectivityHttpClient(status,
            inner: MockClient((request) async => _json(
                request,
                {'code': '42501', 'message': 'permission denied'},
                403))),
      ));

      await expectLater(source.fetchMembers(), throwsA(anything));
      expect(status.offline, isFalse);
    });

    test('an HTML page where our JSON should be is not the server', () async {
      // The captive portal: the interface is up, a page answers, and the plan
      // still cannot be refreshed.
      final status = ConnectivityStatus();
      final client = ConnectivityHttpClient(status,
          inner: MockClient((request) async => http.Response(
              '<html><body>Faça login no Wi-Fi</body></html>', 200,
              request: request,
              headers: {'content-type': 'text/html; charset=utf-8'})));

      await client.get(Uri.parse('https://stub.supabase.test/rest/v1/profiles'));
      expect(status.offline, isTrue);
    });

    test('the request and the error pass through untouched', () async {
      // It observes; it never retries, caches or translates.
      final status = ConnectivityStatus();
      var calls = 0;
      final client = ConnectivityHttpClient(status,
          inner: MockClient((request) async {
        calls++;
        throw http.ClientException('Connection refused', request.url);
      }));

      await expectLater(
          client.get(Uri.parse('https://stub.supabase.test/rest/v1/x')),
          throwsA(isA<http.ClientException>()));
      expect(calls, 1);
    });

    test('nextLoss completes at the failure, or at once when already offline',
        () async {
      final status = ConnectivityStatus();
      var completed = false;
      unawaited(status.nextLoss().then((_) => completed = true));
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);

      status.lostServer();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isTrue);

      await status.nextLoss(); // already offline: must not hang
    });
  });

  group('SessionGate — only a REFUSAL signs the reader out (T-18)', () {
    test('no network at boot keeps the session and opens the app offline',
        () async {
      // The defect: this used to call signOutSafely() and land on login.
      final status = ConnectivityStatus();
      final auth = await _authWithRestoredSession(ConnectivityHttpClient(status));
      final gate = SessionGate(auth);

      final started = DateTime.now();
      final verdict =
          await gate.validateRestoredSession(networkLost: status.nextLoss());

      expect(verdict, RestoredSession.offline);
      expect(auth.currentSession, isNotNull,
          reason: 'the session must survive a boot with no signal');
      // Gotrue retries a refresh for ~10 s before throwing; the race against
      // the first transport failure is what keeps the splash short.
      expect(DateTime.now().difference(started), lessThan(const Duration(seconds: 5)));
    });

    test('a refresh token the server REFUSES still signs out', () async {
      final auth = await _authWithRestoredSession(MockClient((request) async {
        if (request.url.path.endsWith('/token')) {
          return _json(
              request,
              {
                'code': 400,
                'error_code': 'refresh_token_not_found',
                'msg': 'Invalid Refresh Token: Refresh Token Not Found',
              },
              400);
        }
        return http.Response('', 204, request: request);
      }));

      final verdict = await SessionGate(auth)
          .validateRestoredSession(networkLost: ConnectivityStatus().nextLoss());

      expect(verdict, RestoredSession.signedOut);
      expect(auth.currentSession, isNull);
    });

    test('a refresh that goes through opens the app', () async {
      final auth = await _authWithRestoredSession(MockClient((request) async {
        final fresh = jsonDecode(
            _restoredSession(expiresIn: const Duration(hours: 1)));
        return _json(request, fresh);
      }));

      final verdict = await SessionGate(auth).validateRestoredSession();

      expect(verdict, RestoredSession.alive);
      expect(auth.currentSession, isNotNull);
    });

    test('no restored session at all is signed out, without a request',
        () async {
      var calls = 0;
      final auth = GoTrueClient(
        url: '$_unreachable/auth/v1',
        autoRefreshToken: false,
        httpClient: MockClient((request) async {
          calls++;
          return http.Response('', 500, request: request);
        }),
      );

      expect(await SessionGate(auth).validateRestoredSession(),
          RestoredSession.signedOut);
      expect(calls, 0);
    });
  });
}
