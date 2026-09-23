import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// T-78 — one row per member × day × channel, and nobody but the service role
/// reads it.
///
/// What these tests pin, in the order the item's acceptance names them:
///   · a touch writes ONE row for the caller's own profile, and a second touch
///     the same day writes nothing — the table can only grow by a row per
///     member per channel per day;
///   · the channel is a closed list;
///   · NO client reads the table, not even about themselves — "when did the
///     other caregiver last open the app" is surveillance (§6 of the policy),
///     and an own-rows policy would be one refactor away from a family one;
///   · the rows die after 400 days (§11) and the moment the account leaves
///     GoTrue — the profile survives as a tombstone (S-11), so the FK's cascade
///     alone would keep them.
void memberActivityTests(GateFixture fx) {
  Future<List<Map<String, dynamic>>> rowsOf(int profileId) async =>
      (await fx.service
              .from('member_activity_days')
              .select('day, channel')
              .eq('profile_id', profileId)
              .order('day'))
          .cast<Map<String, dynamic>>();

  Future<bool> touch(dynamic who, String channel) async =>
      await who.rpc<dynamic>('touch_activity', params: {'p_channel': channel})
          as bool;

  String iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
      '-${d.day.toString().padLeft(2, '0')}';

  group('MemberActivityTests', () {
    test('a touch records today once per channel, for the caller only',
        () async {
      final fam = await fx.createFamily('act-once');

      expect(await touch(fam.member, 'web'), isTrue);
      expect(await touch(fam.member, 'web'), isFalse,
          reason: 'a second open the same day must write nothing');
      expect(await touch(fam.member, 'web-installed'), isTrue);

      final rows = await rowsOf(fam.memberProfile.id);
      expect(rows.map((r) => r['channel']).toSet(), {'web', 'web-installed'});
      expect(rows.map((r) => r['day']).toSet(), hasLength(1),
          reason: 'both rows are the same (São Paulo) day');

      // The call names no profile: the admin's own day is untouched.
      expect(await rowsOf(fam.adminProfile.id), isEmpty);
    });

    test('an unknown channel is refused', () async {
      await expectRejected(() => touch(fx.member, 'ios'),
          contains: 'Canal de atividade desconhecido');
    });

    test('no client can read, write or purge the table', () async {
      await touch(fx.member, 'android');

      // No grant at all to `authenticated`/`anon`: 42501 before any policy —
      // stronger than an empty read, which a missing row would also give.
      await expectRejected(
        () => fx.member.from('member_activity_days').select(),
        contains: 'permission denied',
        caseInsensitive: true,
      );
      await expectRejected(
        () => fx.founder
            .from('member_activity_days')
            .select()
            .eq('profile_id', fx.memberProfile.id),
        contains: 'permission denied',
        caseInsensitive: true,
      );
      await expectRejected(
        () => fx.member.from('member_activity_days').insert({
          'profile_id': fx.founderProfile.id,
          'day': '2026-01-01',
          'channel': 'web',
        }),
        contains: 'permission denied',
        caseInsensitive: true,
      );
      await expectRejected(
          () => fx.newAnonClient().rpc<dynamic>('touch_activity',
              params: {'p_channel': 'web'}));
      await expectRejected(
          () => fx.member.rpc<dynamic>('purge_old_member_activity'));
    });

    test('retention drops rows older than 400 days, and only those', () async {
      final fam = await fx.createFamily('act-ret');
      await touch(fam.admin, 'android');
      final today = DateTime.parse(
          (await rowsOf(fam.adminProfile.id)).single['day'] as String);

      final kept = iso(today.subtract(const Duration(days: 400)));
      final dropped = iso(today.subtract(const Duration(days: 401)));
      await fx.service.from('member_activity_days').insert([
        {'profile_id': fam.adminProfile.id, 'day': kept, 'channel': 'android'},
        {'profile_id': fam.adminProfile.id, 'day': dropped, 'channel': 'android'},
      ]);

      await fx.service.rpc<dynamic>('purge_old_member_activity');

      final days = (await rowsOf(fam.adminProfile.id)).map((r) => r['day']);
      expect(days, containsAll([kept, iso(today)]));
      expect(days, isNot(contains(dropped)));
    });

    test('the rows go the moment the account leaves GoTrue', () async {
      final fam = await fx.createFamily('act-gone');
      await touch(fam.member, 'web');
      expect(await rowsOf(fam.memberProfile.id), hasLength(1));

      // The purge-deleted path: GoTrue deletes the user, the FK sets
      // profiles.user_id to NULL, the profile row itself stays.
      await fx.deleteAuthUser(fam.memberProfile.userId!);

      final profile = await fx.service
          .from('profiles')
          .select('id, user_id')
          .eq('id', fam.memberProfile.id)
          .single();
      expect(profile['user_id'], isNull,
          reason: 'the precondition: the tombstone keeps the profile row');
      expect(await rowsOf(fam.memberProfile.id), isEmpty);
    });
  });
}
