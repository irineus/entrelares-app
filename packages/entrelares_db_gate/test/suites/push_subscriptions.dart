import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-09 — the device registry, and the one rule that is NOT family-scoped.
///
/// Almost everything in this schema is visible to the whole family: the
/// calendar, the swap history, the audit trail. `push_subscriptions` is
/// deliberately the exception. A registration token is a capability to
/// interrupt someone's phone, and sharing a family is not consent to hold it —
/// so the policies are OWN ROWS ONLY, and these tests exist to keep a future
/// "make it consistent with the rest" refactor from quietly widening them.
///
/// **The one deliberate exception, and it is worth stating plainly: whoever
/// PRESENTS a token claims that device.** Registering a token another profile
/// holds moves it, deleting their row — the `push_subscriptions_claim_token`
/// trigger. That is not a hole in the rule above, it IS the rule: a token
/// identifies a telephone, and one family sharing one telephone is the common
/// case here, not the attack. Holding the token is being the device. So the
/// two tests below that refuse a direct UPDATE and a direct DELETE are not
/// pinning "another caregiver's row is unreachable" — they pin the SHAPE:
/// nothing may sweep rows it cannot name, which is what a `USING (true)` on
/// the UPDATE policy would have allowed with a single WHERE-less statement.
///
/// The second half covers the dispatcher trigger. It fires on every
/// notification INSERT and, on a project with no Vault secrets, must do
/// nothing at all — quietly, without taking the INSERT down with it. That is
/// the state of the dev project this gate runs against, so what these tests
/// really pin is the fail-closed path: the one that runs everywhere until the
/// Firebase console work is done, and the one a broken push must fall back to.
void pushSubscriptionsTests(GateFixture fx) {
  /// The rows the service role sees for [profileId] — the truth, past RLS.
  Future<List<Map<String, dynamic>>> tokensOf(int profileId) async =>
      (await fx.service
              .from('push_subscriptions')
              .select()
              .eq('profile_id', profileId))
          .cast<Map<String, dynamic>>();

  Future<String> registerFor(
    SupabaseClient who,
    int profileId, {
    String platform = 'android',
  }) async {
    final token = 'e2e-${uniqueMarker()}';
    await who.from('push_subscriptions').insert({
      'profile_id': profileId,
      'token': token,
      'platform': platform,
    });
    return token;
  }

  group('PushSubscriptionsTests', () {
    test('a member registers a device for their own profile', () async {
      final token = await registerFor(fx.member, fx.memberProfile.id);

      final mine = await tokensOf(fx.memberProfile.id);
      expect(mine.map((r) => r['token']), contains(token));
      expect(mine.firstWhere((r) => r['token'] == token)['platform'], 'android');
    });

    test('a member cannot register a device for someone else', () async {
      await expectRejected(() => fx.member.from('push_subscriptions').insert({
            'profile_id': fx.founderProfile.id,
            'token': 'e2e-forged-${uniqueMarker()}',
            'platform': 'android',
          }));

      // Nothing was written under the founder's name.
      final founderTokens = await tokensOf(fx.founderProfile.id);
      expect(founderTokens.where((r) => (r['token'] as String).contains('forged')),
          isEmpty);
    });

    test("a member cannot read another caregiver's tokens", () async {
      await registerFor(fx.founder, fx.founderProfile.id);

      // RLS on SELECT does not throw — it returns nothing. Asserting emptiness
      // is the only assertion that can tell the two apart.
      final seen = await fx.member
          .from('push_subscriptions')
          .select('token')
          .eq('profile_id', fx.founderProfile.id);
      expect(seen, isEmpty);
    });

    test("a member cannot move another caregiver's token to themselves",
        () async {
      final victim = await registerFor(fx.founder, fx.founderProfile.id);

      // An UPDATE the client may not make does NOT throw — it matches 0 rows,
      // and PostgREST answers success. So the assertion is on the ROW, read
      // back with the service client.
      await fx.member
          .from('push_subscriptions')
          .update({'profile_id': fx.memberProfile.id}).eq('token', victim);

      final row = (await fx.service
              .from('push_subscriptions')
              .select('profile_id')
              .eq('token', victim))
          .single;
      expect(row['profile_id'], fx.founderProfile.id,
          reason: 'the token was re-pointed at another profile');
    });

    test("a member cannot delete another caregiver's device", () async {
      final victim = await registerFor(fx.founder, fx.founderProfile.id);

      await fx.member.from('push_subscriptions').delete().eq('token', victim);

      final still = await fx.service
          .from('push_subscriptions')
          .select('token')
          .eq('token', victim);
      expect(still, hasLength(1), reason: 'the device was unregistered by someone else');
    });

    test('a member unregisters their own device', () async {
      final token = await registerFor(fx.member, fx.memberProfile.id);
      await fx.member.from('push_subscriptions').delete().eq('token', token);

      final gone =
          await fx.service.from('push_subscriptions').select('token').eq('token', token);
      expect(gone, isEmpty);
    });

    test('a device that changes accounts moves to the new one', () async {
      final token = await registerFor(fx.member, fx.memberProfile.id);

      // THE SHAPE THE APP ACTUALLY SENDS. `registerPushToken` upserts on the
      // token, because the row that holds it may belong to another profile —
      // the same phone, a different sign-in, which in this product is the
      // ordinary case of one family sharing one telephone.
      //
      // For a day in production this raised `new row violates row-level
      // security policy (USING expression)`: the conflict took the DO UPDATE
      // branch, and the UPDATE policy's USING requires the row to be yours
      // ALREADY. The `push_subscriptions_claim_token` trigger clears the
      // previous holder first, so the INSERT stands on its own — and its WITH
      // CHECK still refuses any profile_id but the caller's.
      await fx.founder.from('push_subscriptions').upsert({
        'profile_id': fx.founderProfile.id,
        'token': token,
        'platform': 'android',
      }, onConflict: 'token');

      final rows = (await fx.service
              .from('push_subscriptions')
              .select('profile_id')
              .eq('token', token))
          .cast<Map<String, dynamic>>();

      // One row, and it belongs to whoever signed in last. Two rows would mean
      // the previous account keeps receiving its notices on a phone it no
      // longer has.
      expect(rows, hasLength(1));
      expect(rows.single['profile_id'], fx.founderProfile.id);
    });

    test('a plain INSERT of a held token claims it just the same', () async {
      // Same rule, reached without the upsert: the trigger is on the INSERT,
      // not on the statement's shape, so a caller that never learned about
      // `onConflict` cannot end up with a 23505 either.
      final token = await registerFor(fx.member, fx.memberProfile.id);

      await fx.founder.from('push_subscriptions').insert({
        'profile_id': fx.founderProfile.id,
        'token': token,
        'platform': 'android',
      });

      final rows = await fx.service
          .from('push_subscriptions')
          .select('profile_id')
          .eq('token', token);
      expect(rows, hasLength(1));
      expect((rows.single)['profile_id'], fx.founderProfile.id);
    });

    test('claiming a token does not touch the rest of the previous owner',
        () async {
      // The blast radius of the trigger, pinned: it may delete ONE row, the one
      // holding the token being claimed. A `DELETE ... WHERE token = NEW.token`
      // that lost its WHERE would empty the registry of every family at once,
      // and nothing else in this suite would notice.
      final kept = await registerFor(fx.member, fx.memberProfile.id);
      final claimed = await registerFor(fx.member, fx.memberProfile.id);

      await fx.founder.from('push_subscriptions').upsert({
        'profile_id': fx.founderProfile.id,
        'token': claimed,
        'platform': 'android',
      }, onConflict: 'token');

      final survivors = await tokensOf(fx.memberProfile.id);
      expect(survivors.map((r) => r['token']), contains(kept));
      expect(survivors.map((r) => r['token']), isNot(contains(claimed)));
    });

    test('re-registering your own device keeps the row it already had',
        () async {
      // The common path — the app repairing its registration on every session.
      // It must take the DO UPDATE branch (the row is already yours, so RLS
      // allows it) and NOT be deleted and reinserted: `created_at` is when this
      // device enrolled, and the trigger must leave your own row alone.
      final token = await registerFor(fx.member, fx.memberProfile.id);
      final before = (await fx.service
              .from('push_subscriptions')
              .select('id, created_at')
              .eq('token', token))
          .single;

      await fx.member.from('push_subscriptions').upsert({
        'profile_id': fx.memberProfile.id,
        'token': token,
        'platform': 'android',
        'last_seen_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');

      final after = (await fx.service
              .from('push_subscriptions')
              .select('id, created_at')
              .eq('token', token))
          .single;
      expect(after['id'], before['id']);
      expect(after['created_at'], before['created_at']);
    });

    test('an unknown platform is refused', () async {
      await expectRejected(() => fx.member.from('push_subscriptions').insert({
            'profile_id': fx.memberProfile.id,
            'token': 'e2e-${uniqueMarker()}',
            'platform': 'symbian',
          }));
    });

    // ── T-109: two kinds of target, and a registry that forgets ──────────

    test('a row written the old way is a registration token', () async {
      // Every Android build in the stores before T-109 PR 2 upserts
      // (profile_id, token, platform, last_seen_at) and knows nothing of
      // `kind`. The DEFAULT is what keeps those pushes going through the
      // `token` field after the server learned to read the column.
      final token = await registerFor(fx.member, fx.memberProfile.id);
      final row = (await fx.service
              .from('push_subscriptions')
              .select('kind')
              .eq('token', token))
          .single;
      expect(row['kind'], 'token');
    });

    test('an installation ID is stored as one', () async {
      // The 22-symbol shape the Firebase SDK generates: c–f, then 21 more.
      final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
      final fid = 'c${stamp.padLeft(21, 'x')}'.substring(0, 22);
      await fx.member.from('push_subscriptions').insert({
        'profile_id': fx.memberProfile.id,
        'token': fid,
        'kind': 'fid',
        'platform': 'web',
      });
      final row = (await fx.service
              .from('push_subscriptions')
              .select('kind, platform')
              .eq('token', fid))
          .single;
      expect(row['kind'], 'fid');
      await fx.service.from('push_subscriptions').delete().eq('token', fid);
    });

    test('a row that says fid but holds a token is refused', () async {
      // The client bug this CHECK exists for: a registration token stored as
      // an FID would go out through `message.fid`, FCM would refuse it, and the
      // server would retire a live device as dead — with no error anywhere.
      await expectRejected(
        () => fx.member.from('push_subscriptions').insert({
          'profile_id': fx.memberProfile.id,
          'token': 'e2e-${uniqueMarker()}:APA91b-a-registration-token',
          'kind': 'fid',
          'platform': 'android',
        }),
        contains: 'push_subscriptions_fid_shape',
      );
    });

    test('an unknown kind is refused', () async {
      await expectRejected(
        () => fx.member.from('push_subscriptions').insert({
          'profile_id': fx.memberProfile.id,
          'token': 'e2e-${uniqueMarker()}',
          'kind': 'apns',
          'platform': 'ios',
        }),
        contains: 'push_subscriptions_kind_check',
      );
    });

    test('the prune drops targets past the window and keeps the rest',
        () async {
      // Read the window from the row, not from the seed: the console may have
      // moved it, and the rule is "older than the key", whatever it holds.
      final days = int.parse(await readFlag(fx, 'push.stale_after_days'));
      String ago(int d) => DateTime.now()
          .toUtc()
          .subtract(Duration(days: d))
          .toIso8601String();

      final fam = await fx.createFamily('push-prune');
      final stale = 'e2e-stale-${uniqueMarker()}';
      final fresh = 'e2e-fresh-${uniqueMarker()}';
      await fx.service.from('push_subscriptions').insert([
        {
          'profile_id': fam.adminProfile.id,
          'token': stale,
          'platform': 'android',
          'last_seen_at': ago(days + 5),
        },
        {
          'profile_id': fam.adminProfile.id,
          'token': fresh,
          'platform': 'android',
          'last_seen_at': ago(days - 5),
        },
      ]);

      final pruned = await fx.service.rpc('prune_push_subscriptions');
      expect(pruned, greaterThanOrEqualTo(1));

      final left = (await tokensOf(fam.adminProfile.id))
          .map((r) => r['token'])
          .toSet();
      expect(left, contains(fresh));
      expect(left, isNot(contains(stale)));
    });

    test("the prune drops a departed member's devices at once", () async {
      // S-11: a member who left is frozen and is never a recipient again, so
      // their registration can only ever deliver to nobody — or, on a phone
      // handed on, to the wrong person.
      final fam = await fx.createFamily('push-gone');
      final mine = 'e2e-gone-${uniqueMarker()}';
      final kept = 'e2e-kept-${uniqueMarker()}';
      await fx.service.from('push_subscriptions').insert([
        {'profile_id': fam.memberProfile.id, 'token': mine, 'platform': 'web'},
        {'profile_id': fam.adminProfile.id, 'token': kept, 'platform': 'web'},
      ]);
      await fx.service.from('profiles').update({
        'left_at': DateTime.now().toUtc().toIso8601String()
      }).eq('id', fam.memberProfile.id);

      await fx.service.rpc('prune_push_subscriptions');

      expect(await tokensOf(fam.memberProfile.id), isEmpty);
      expect((await tokensOf(fam.adminProfile.id)).map((r) => r['token']),
          contains(kept));
    });

    test('a client cannot run the prune', () async {
      await expectRejected(
          () => fx.member.rpc('prune_push_subscriptions'));
    });

    test('the dispatcher never fails the notification it rides on', () async {
      // The whole point of the AFTER trigger being async and swallowing its own
      // errors: on this project there are no Vault secrets, so the dispatcher
      // returns without doing anything. If it ever raised instead, THIS insert
      // is what would start failing — and with it every swap in the product.
      final marker = uniqueMarker();
      await fx.service.from('notifications').insert({
        'recipient_profile_id': fx.memberProfile.id,
        'type': 'swap_requested',
        'title': 'Nova solicitação de troca',
        'message': 'gate $marker',
        'params': {'date': '2026-12-24', 'proposed': 'target', 'name': 'QA'},
      });

      final written = await fx.service
          .from('notifications')
          .select('id')
          .eq('recipient_profile_id', fx.memberProfile.id)
          .eq('message', 'gate $marker');
      expect(written, hasLength(1));
    });

    test('a non-pushable notification is written just the same', () async {
      final marker = uniqueMarker();
      await fx.service.from('notifications').insert({
        'recipient_profile_id': fx.memberProfile.id,
        'type': 'member_joined',
        'title': 'Novo responsável na família',
        'message': 'gate $marker',
        'params': {'name': 'QA'},
      });

      final written = await fx.service
          .from('notifications')
          .select('id')
          .eq('recipient_profile_id', fx.memberProfile.id)
          .eq('message', 'gate $marker');
      expect(written, hasLength(1));
    });
  });
}
