import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '_helpers.dart';

/// S-21 — the sudo gate's SECOND proof: a one-time code mailed to the account's
/// address, for a session that has no password to confirm.
///
/// Why this suite exists at all, and why it is not a paragraph in
/// `sudo_elevation.dart`: the defect it pins could not have been caught by any
/// test that signs in with a password. Four production accounts had none — three
/// of them the sole admin of a one-seat family — and every sudo-gated operation
/// was therefore unreachable to them, including deleting their own account,
/// which is the Play policy requirement behind T-59. A suite that only ever
/// holds password-backed sessions agrees with the broken behaviour forever.
///
/// So the password-less session is the SUBJECT here, not a variation: the
/// account is created with no credential at all and its token comes from a
/// generated magic link, because that is the only door such an account has.
///
/// The plaintext code never leaves the Edge Function — it goes into an e-mail,
/// and on the dev project that e-mail is suppressed (T-49, `@resend.dev`). So
/// the tests that need to REDEEM one plant it themselves: they compute the
/// digest here, store it through `request_elevation_code`, and then hand the
/// plaintext to the deployed function. That is a stronger assertion than a
/// round-trip would be — it only passes if both sides derive the same digest
/// from the same inputs, which is exactly the drift that would otherwise lock
/// every user out with nothing failing.
void elevationCodeTests(GateFixture fx) {
  /// The digest the function computes, computed independently. Drift here is
  /// the failure this suite is built to catch, so it is spelled out rather than
  /// shared with anything.
  String digestOf(String userId, String code) =>
      sha256.convert(utf8.encode('$userId:$code')).toString();

  Uri functionUri(String name) => Uri.parse(
      '${TestEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}/functions/v1/$name');

  Future<http.Response> callElevate(
          String accessToken, Map<String, dynamic> body) =>
      http.post(
        functionUri('elevate'),
        headers: {
          'apikey': TestEnv.anonKey,
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );

  /// Stores a digest directly, bypassing the resend throttle — the interval is
  /// the FUNCTION's number, passed in by it, so a test that needs two codes in
  /// a row simply asks for none.
  Future<Map<String, dynamic>> plantCode(
    String userId,
    String code, {
    int ttlSeconds = 600,
    int minIntervalSeconds = 0,
  }) async {
    final result = await fx.service.rpc<dynamic>('request_elevation_code',
        params: {
          'p_user_id': userId,
          'p_code_hash': digestOf(userId, code),
          'p_ttl_seconds': ttlSeconds,
          'p_min_interval_seconds': minIntervalSeconds,
        });
    final row = result is List ? result.first : result;
    return Map<String, dynamic>.from(row as Map);
  }

  Future<String> consume(String userId, String code) async {
    final verdict = await fx.service.rpc<dynamic>('consume_elevation_code',
        params: {'p_user_id': userId, 'p_code_hash': digestOf(userId, code)});
    return verdict as String;
  }

  Future<Map<String, dynamic>?> codeRowOf(String userId) async {
    final rows = await fx.service
        .from('auth_elevation_codes')
        .select()
        .eq('user_id', userId);
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first);
  }

  group('ElevationCodeTests', () {
    // ── The two RPCs ────────────────────────────────────────────────────────

    test('the stored row carries a digest, never the code', () async {
      final userId = fx.founderProfile.userId!;
      await plantCode(userId, '424242');

      final row = await codeRowOf(userId);
      expect(row, isNotNull, reason: 'no code row was written');
      expect(row!['code_hash'], digestOf(userId, '424242'));
      // The assertion that matters to a leaked backup: nothing in the row can
      // be typed into the prompt.
      expect(row.values.map((v) => '$v'), isNot(contains('424242')));
      expect(row['attempts'], 0);

      await consume(userId, '424242');
    });

    test('the same code for two users is two different digests', () {
      // Not decoration: an unsalted digest would make one leaked row a key to
      // every account that happened to draw the same six digits.
      expect(digestOf(fx.founderProfile.userId!, '111111'),
          isNot(digestOf(fx.memberProfile.userId!, '111111')));
    });

    test('a second request inside the interval is throttled, and the first '
        'code stays valid', () async {
      final userId = fx.founderProfile.userId!;
      final first = await plantCode(userId, '100001', minIntervalSeconds: 60);

      final second = await plantCode(userId, '200002', minIntervalSeconds: 60);
      expect(second['status'], 'throttled');
      expect(second['expires_at'], first['expires_at'],
          reason: 'the throttled answer must report the EXISTING expiry — the '
              'old code is the one still sitting in the inbox');

      // And it really is the first code that works, not the refused one.
      expect(await consume(userId, '200002'), 'invalid');
      expect(await consume(userId, '100001'), 'ok');
    });

    test('a code is consumed exactly once', () async {
      final userId = fx.founderProfile.userId!;
      await plantCode(userId, '314159');

      expect(await consume(userId, '314159'), 'ok');
      // The row is destroyed with the verdict, so a replay is not "invalid"
      // (which would spend an attempt on a code that no longer exists) but
      // "there is nothing to redeem".
      expect(await consume(userId, '314159'), 'none');
      expect(await codeRowOf(userId), isNull);
    });

    test('the third wrong guess destroys the code', () async {
      final userId = fx.founderProfile.userId!;
      await plantCode(userId, '777777');

      expect(await consume(userId, '000001'), 'invalid');
      expect((await codeRowOf(userId))!['attempts'], 1);
      expect(await consume(userId, '000002'), 'invalid');
      expect((await codeRowOf(userId))!['attempts'], 2);
      expect(await consume(userId, '000003'), 'locked');

      expect(await codeRowOf(userId), isNull,
          reason: 'a locked row left behind would make the next verdict '
              'ambiguous, and the right code would still be refused');
      // Even the RIGHT code is gone with it — the ceiling is on the code, not
      // on the guess.
      expect(await consume(userId, '777777'), 'none');
    });

    test('an expired code says so, and is cleared', () async {
      final userId = fx.founderProfile.userId!;
      await plantCode(userId, '555555', ttlSeconds: -1);

      expect(await consume(userId, '555555'), 'expired');
      expect(await codeRowOf(userId), isNull);
    });

    test('no code at all is `none`', () async {
      final userId = fx.memberProfile.userId!;
      await fx.service
          .from('auth_elevation_codes')
          .delete()
          .eq('user_id', userId);
      expect(await consume(userId, '123456'), 'none');
    });

    // ── The security property ───────────────────────────────────────────────

    test('an authenticated user can neither read the codes nor mint one',
        () async {
      final userId = fx.founderProfile.userId!;
      await plantCode(userId, '868686');

      // No SELECT policy: the digest of one's own pending code is not something
      // to look up. A read with no policy matches nothing rather than throwing,
      // so the assertion is on the ROWS (the trap the RLS detail page names).
      final visible =
          await fx.founder.from('auth_elevation_codes').select();
      expect(visible, isEmpty,
          reason: 'the code table must be invisible to every end user');

      await expectRejected(
        () => fx.founder.rpc<dynamic>('request_elevation_code', params: {
          'p_user_id': userId,
          'p_code_hash': digestOf(userId, '999999'),
          'p_ttl_seconds': 600,
          'p_min_interval_seconds': 0,
        }),
      );
      await expectRejected(
        () => fx.founder.rpc<dynamic>('consume_elevation_code', params: {
          'p_user_id': userId,
          'p_code_hash': digestOf(userId, '868686'),
        }),
      );

      await consume(userId, '868686');
    });

    // ── The password-less session, end to end ───────────────────────────────

    test('a password-less account cannot elevate with a password, but can with '
        'a code — and the gated RPC then accepts it', () async {
      final who = await fx.createPasswordlessMember('s21',
          fullName: 'E2E Sem Senha');

      // 1. The defect itself: there is no credential to confirm, so the only
      //    door the gate had is shut. This is the assertion that would have
      //    failed on 10/09/2026 for four real people.
      final byPassword =
          await callElevate(who.accessToken, {'password': fx.password});
      expect(byPassword.statusCode, 401);

      // 2. And the gated RPC is unreachable while that is the only proof.
      //    (The account was promoted first, so what refuses below is the
      //    ELEVATION, not the admin check.)
      await fx.elevate(fx.founderProfile);
      await fx.founder.rpc<dynamic>('set_member_admin',
          params: {'p_profile_id': who.profile.id, 'p_is_admin': true});
      await fx.clearElevation(fx.founderProfile);

      await expectRejected(
        () => who.client.rpc<dynamic>('set_member_admin',
            params: {'p_profile_id': fx.memberProfile.id, 'p_is_admin': true}),
        contains: 'ELEVATION_REQUIRED',
      );

      // 3. The second proof. The digest is planted here and the PLAINTEXT is
      //    handed to the deployed function — which only works if it derives the
      //    same digest from the same user id and code.
      await plantCode(who.userId, '246810');
      final byCode = await callElevate(who.accessToken, {'code': '246810'});
      expect(byCode.statusCode, 200,
          reason: 'the function refused a code it should have redeemed: '
              '${byCode.body}');
      expect(jsonDecode(byCode.body), containsPair('elevated_until', isNotNull));

      // 4. And the window it opened is the SAME window the password opens —
      //    `is_elevated()` cannot tell which proof was given, by design.
      await who.client.rpc<dynamic>('set_member_admin',
          params: {'p_profile_id': fx.memberProfile.id, 'p_is_admin': true});

      // Put the fixture back the way the rest of the run expects it.
      await fx.elevate(fx.founderProfile);
      await fx.founder.rpc<dynamic>('set_member_admin',
          params: {'p_profile_id': fx.memberProfile.id, 'p_is_admin': false});
      await fx.clearElevation(fx.founderProfile);
    });

    test('a wrong code is refused with the code sentence, not the password one',
        () async {
      final userId = fx.founderProfile.userId!;
      await plantCode(userId, '135790');

      final response = await callElevate(
          fx.founder.auth.currentSession!.accessToken, {'code': '000000'});

      expect(response.statusCode, 401);
      // The sentence is the next STEP, and "senha incorreta" would send someone
      // without a password looking for one.
      expect(response.body, contains('Código incorreto'));

      await consume(userId, '135790');
    });

    test('asking for a code over HTTP mints one and spends no allowance',
        () async {
      final userId = fx.founderProfile.userId!;
      await fx.service
          .from('auth_elevation_codes')
          .delete()
          .eq('user_id', userId);

      final response = await callElevate(
          fx.founder.auth.currentSession!.accessToken, {'request_code': true});

      expect(response.statusCode, 200, reason: response.body);
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      expect(body['code_sent'], isTrue);
      expect(body['expires_in_minutes'], isNotNull);

      // The row exists and holds a digest of something this test never saw —
      // which is the whole contract with the mail rail. T-49 suppressed the
      // message itself: the fixture's addresses are `@resend.dev`.
      final row = await codeRowOf(userId);
      expect(row, isNotNull);
      expect('${row!['code_hash']}'.length, 64);

      // The throttle is live on the real path, not only in the RPC's arguments.
      final again = await callElevate(
          fx.founder.auth.currentSession!.accessToken, {'request_code': true});
      expect(again.statusCode, 429);
      expect(jsonDecode(again.body), containsPair('throttled', true));

      await fx.service
          .from('auth_elevation_codes')
          .delete()
          .eq('user_id', userId);
    });
  });
}
