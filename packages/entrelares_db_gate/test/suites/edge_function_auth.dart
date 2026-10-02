import 'dart:convert';

import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// S-16 — the IN-CODE authorization that REPLACED the platform's `verify_jwt`
/// gate.
///
/// Five functions had to give the gate up: it only understands the legacy
/// JWT-based keys, so a caller presenting a new-model key (`sb_secret_…` on
/// `apikey`) is rejected at the gateway before the function runs. Turning the
/// gate off is safe ONLY because each of those functions now checks its own
/// callers — and that is what this suite pins.
///
/// Without it the regression is invisible in the happy path: the app and the
/// crons keep working while the functions quietly answer to anyone. An e-mail
/// relay, an account purge and the auto-approval worker are exactly the things
/// that must not become anonymous endpoints.
///
/// `register-invitee` is deliberately absent: it authorizes by invitation token
/// (its caller has no account yet and holds only the public publishable key),
/// and its own suite covers the garbage-token refusal.
///
/// This suite needs NO family — it is here for the aggregating entrypoint's
/// convenience, and it touches nothing the fixture owns.
///
/// Port of `db-gate/Entrelares.IntegrationTests/EdgeFunctionAuthTests.cs`.
void edgeFunctionAuthTests(GateFixture fx) {
  /// The edge runtime answers 503 `SUPABASE_EDGE_RUNTIME_SERVICE_DEGRADED` while
  /// a freshly deployed function is still booting, and CI redeploys ALL
  /// functions minutes before this suite runs. It first blocked the gate in Aug
  /// 2026: five cases red inside a TWO-SECOND window, with `deployment_id` null
  /// in the Supabase logs and the same functions answering 401 correctly on both
  /// sides of it.
  ///
  /// A 503 is never OUR answer — the function did not run, so there is no
  /// authorization verdict to assert. Retrying ONLY that status keeps the
  /// regressions this suite exists for failing on the first attempt: a 200 (wide
  /// open) or a 500 (the function ran and failed later, i.e. the check is
  /// missing). A runtime that stays down still fails the assertion, with the
  /// body printed.
  const bootRetries = 4;

  Future<(int status, String body)> send(String function,
      {String? apiKey, String? bearer}) async {
    final response = await http.post(
      Uri.parse('${TestEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}'
          '/functions/v1/$function'),
      headers: {
        'apikey': ?apiKey,
        if (bearer != null) 'Authorization': 'Bearer $bearer',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(const <String, dynamic>{}),
    );
    return (response.statusCode, response.body);
  }

  Future<(int status, String body)> call(String function,
      {String? apiKey, String? bearer}) async {
    var result = await send(function, apiKey: apiKey, bearer: bearer);
    for (var attempt = 1; attempt <= bootRetries && result.$1 == 503; attempt++) {
      await Future<void>.delayed(Duration(seconds: 2 * attempt));
      result = await send(function, apiKey: apiKey, bearer: bearer);
    }
    return result;
  }

  void expectRefused(String function, (int, String) result, String what) {
    expect(result.$1, 401,
        reason: '$function answered ${result.$1} to $what (expected 401). '
            'Body: ${result.$2}');
  }

  group('EdgeFunctionAuthTests', () {
    const gateless = [
      'auto-approve-expired',
      'purge-deleted',
      'send-swap-email',
      'send-account-email',
      // T-99: the weekly operator bulletin — it mails the real operator inbox.
      'weekly-bulletin',
    ];

    for (final function in gateless) {
      test('$function refuses a call with no credentials', () async {
        // The heart of it. A 500 here means the function DID run and failed
        // later — i.e. the check is missing; a 200 means it is wide open. Both
        // are the regression.
        expectRefused(function, await call(function), 'an anonymous call');
      });

      test('$function refuses a WRONG secret', () async {
        // The check has to compare the key, not merely notice that some `apikey`
        // header arrived.
        expectRefused(
            function,
            await call(function, apiKey: 'sb_secret_not_the_real_one'),
            'a bogus secret key');
      });
    }

    for (final function in ['auto-approve-expired', 'send-swap-email']) {
      test('$function refuses the PUBLISHABLE key', () async {
        // It is PUBLIC — holding it proves nothing, so it must not open a
        // function whose callers are our own backends or signed-in users.
        expectRefused(function, await call(function, apiKey: TestEnv.anonKey),
            'the public publishable key');
      });
    }

    test('send-auth-email refuses an unsigned call', () async {
      // U-13: the sixth gateless function, and it authorizes differently — GoTrue
      // calls it with no JWT and no key, signing the body with the Standard
      // Webhooks scheme. So the checks above do not describe it.
      //
      // The stake is higher here than anywhere else in this suite: the function
      // sends password-reset and sign-up-confirmation mail. Open, it is a relay
      // that will mail an account-recovery link to whatever address a caller
      // names.
      expectRefused('send-auth-email', await call('send-auth-email'),
          'an unsigned call');
    });

    test("send-auth-email refuses the project's OWN keys", () async {
      // A secret key opens the other five, so this pins that this function did
      // not quietly inherit their check.
      expectRefused(
          'send-auth-email',
          await call('send-auth-email', apiKey: TestEnv.anonKey),
          'the publishable key');
      expectRefused(
          'send-auth-email',
          await call('send-auth-email', apiKey: TestEnv.serviceRoleKey),
          'the secret key');
    });

    test('a garbage session token is not a session', () async {
      // Guards the other half of the check — the user-JWT branch the app's own
      // calls rely on.
      expectRefused(
          'send-swap-email',
          await call('send-swap-email',
              apiKey: TestEnv.anonKey, bearer: 'not.a.jwt'),
          'a garbage session token');
    });
  });
}
