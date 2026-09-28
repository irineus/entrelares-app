// T-93 — the refresh loop, reproduced through the REAL gotrue, and the guard
// that ends it.
//
// Production (27/09/2026, read-only SQL on `auth.refresh_tokens`): one session
// of the Play pre-launch account refreshed 169 times in four minutes on
// 30/08/2026, median 0.25 s apart, never more than one 10 s tick. gotrue reads
// `exp` (the server's clock) against `DateTime.now()` (the device's), so a
// device clock an hour ahead makes every fresh token look expired, and
// `getSession()` refreshes before every request. The server here issues
// exactly such tokens — already expired by THIS machine's clock — which is the
// same thing seen from the device, without touching the clock.
//
// Only the server's answers are stubbed; the SDK deciding to refresh, the
// retry and the sign-out are gotrue's own (the offline_transport_test lesson:
// a fake that reimplements the thing under test agrees with it by
// construction). Only `test()`, no `testWidgets`, for the reason that file
// gives.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:entrelares_app/services/session_gate.dart';
import 'package:entrelares_app/services/refresh_guard_client.dart';

const _url = 'http://127.0.0.1:1/auth/v1';

String _b64(Map<String, Object?> json) =>
    base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');

/// A session whose access token expires [expiresIn] from now by THIS clock.
Map<String, Object?> _session(String refreshToken, {required Duration expiresIn}) {
  final exp = DateTime.now().add(expiresIn).millisecondsSinceEpoch ~/ 1000;
  return {
    'access_token': '${_b64({
          'alg': 'HS256',
          'typ': 'JWT'
        })}.${_b64({'sub': 'u1', 'exp': exp, 'role': 'authenticated'})}.sig',
    'expires_in': 3600,
    'refresh_token': refreshToken,
    'token_type': 'bearer',
    'user': {
      'id': 'u1',
      'aud': 'authenticated',
      'app_metadata': <String, Object?>{},
      'user_metadata': <String, Object?>{},
      'created_at': '2026-09-01T00:00:00Z',
    },
  };
}

/// What a device two hours ahead sees: the server's fresh one-hour token has
/// "expired" an hour ago.
const _skewed = Duration(hours: -1);

http.Response _json(http.BaseRequest request, Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        request: request,
        headers: {'content-type': 'application/json; charset=utf-8'});

/// GoTrue, as far as the refresh grant goes: every refresh issues a new
/// refresh token and an access token that is [issued] from now.
class _Server {
  int refreshes = 0;
  int other = 0;
  Duration issued = _skewed;
  int? failWith;

  late final MockClient client = MockClient((request) async {
    if (request.url.queryParameters['grant_type'] != 'refresh_token') {
      other++;
      return _json(request, _session('rt-signin-$other', expiresIn: issued));
    }
    refreshes++;
    final status = failWith;
    if (status != null) {
      return _json(
          request,
          {
            'code': status,
            'error_code': 'over_request_rate_limit',
            'msg': 'Request rate limit reached',
          },
          status);
    }
    return _json(request, _session('rt-$refreshes', expiresIn: issued));
  });
}

Future<GoTrueClient> _auth(http.Client transport) async {
  final auth = GoTrueClient(
      url: _url, httpClient: transport, autoRefreshToken: false);
  await auth.setInitialSession(
      jsonEncode(_session('rt-0', expiresIn: const Duration(minutes: -5))));
  return auth;
}

void main() {
  group('the loop (gotrue alone — the premise this item rests on)', () {
    test('a device clock ahead makes EVERY request refresh', () async {
      final server = _Server();
      final auth = await _auth(server.client);

      for (var i = 0; i < 10; i++) {
        await auth.getSession();
      }

      // Ten reads, ten refreshes: what 169 in four minutes looked like.
      expect(server.refreshes, 10);
    });

    test('a 429 on the refresh signs the reader out', () async {
      final server = _Server()..failWith = 429;
      final auth = await _auth(server.client);
      final events = <AuthChangeEvent>[];
      final sub = auth.onAuthStateChange.listen((s) => events.add(s.event));

      await expectLater(auth.refreshSession(), throwsA(isA<AuthApiException>()));
      await Future<void>.delayed(Duration.zero);

      // If gotrue ever reads a 429 as retryable, this goes red — and the
      // second half of the guard can be retired.
      expect(auth.currentSession, isNull);
      expect(events, contains(AuthChangeEvent.signedOut));
      await sub.cancel();
    });
  });

  group('RefreshGuardHttpClient — the floor', () {
    test('the same loop reaches the network once per floor', () async {
      final server = _Server();
      var now = Duration.zero;
      final auth = await _auth(
          RefreshGuardHttpClient(server.client, elapsed: () => now));

      for (var i = 0; i < 10; i++) {
        final session = await auth.getSession();
        expect(session?.refreshToken, 'rt-1',
            reason: 'every read still holds a session the server issued');
      }
      expect(server.refreshes, 1);

      now = const Duration(seconds: 59);
      await auth.getSession();
      expect(server.refreshes, 1);

      now = const Duration(seconds: 60);
      await auth.getSession();
      expect(server.refreshes, 2);
      expect(auth.currentSession?.refreshToken, 'rt-2');
    });

    test('a new session inside the floor is never handed the previous one',
        () async {
      final server = _Server();
      const now = Duration.zero;
      final auth = await _auth(
          RefreshGuardHttpClient(server.client, elapsed: () => now));

      await auth.getSession();
      expect(server.refreshes, 1);

      // Another sign-in on the same process (the E2E harness switches users).
      await auth.setInitialSession(jsonEncode(
          _session('rt-other', expiresIn: const Duration(minutes: -5))));
      await auth.getSession();

      expect(server.refreshes, 2);
      expect(auth.currentSession?.refreshToken, 'rt-2');
    });

    test('a healthy clock refreshes exactly as before', () async {
      final server = _Server()..issued = const Duration(hours: 1);
      final auth = await _auth(RefreshGuardHttpClient(server.client));

      for (var i = 0; i < 10; i++) {
        await auth.getSession();
      }

      // The restored session was expired: one refresh, then a valid token.
      expect(server.refreshes, 1);
    });

    test('every other request passes untouched', () async {
      final server = _Server();
      final guard = RefreshGuardHttpClient(server.client);

      for (var i = 0; i < 3; i++) {
        await guard.post(Uri.parse('$_url/token?grant_type=password'),
            body: '{"email":"a@b.c","password":"x"}');
      }

      expect(server.other, 3);
    });
  });

  group('RefreshGuardHttpClient — a 429 is a pause, not a verdict', () {
    test('the session is KEPT, the gate opens offline, the retries stay local',
        () async {
      final server = _Server()..failWith = 429;
      var now = Duration.zero;
      final auth = await _auth(
          RefreshGuardHttpClient(server.client, elapsed: () => now));
      final events = <AuthChangeEvent>[];
      // A retryable failure reaches the stream as an ERROR, not an event — the
      // app's own listener swallows it the same way (main.dart).
      final sub = auth.onAuthStateChange
          .listen((s) => events.add(s.event), onError: (Object _) {});

      final verdict = await SessionGate(auth).validateRestoredSession();
      await Future<void>.delayed(Duration.zero);

      expect(verdict, RestoredSession.offline);
      expect(auth.currentSession?.refreshToken, 'rt-0');
      expect(events, isNot(contains(AuthChangeEvent.signedOut)));
      // gotrue retried for ~6 s; only the first attempt left the device.
      expect(server.refreshes, 1);

      // The pause ends; the server answers again, and the session goes on.
      server.failWith = null;
      now = const Duration(seconds: 60);
      await auth.refreshSession();
      expect(server.refreshes, 2);
      expect(auth.currentSession?.refreshToken, 'rt-2');
      await sub.cancel();
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  test('main.dart hands Supabase the guard around the connectivity client', () {
    // Outside, so an answer from memory never counts as reaching the server.
    final main = File('lib/main.dart').readAsStringSync();
    expect(main,
        contains('RefreshGuardHttpClient(ConnectivityHttpClient(appConnectivity))'));
  });
}
