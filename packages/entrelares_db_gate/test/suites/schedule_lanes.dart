import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-07 (PR 2) — the plan per child, where it is actually enforced.
///
/// A schedule row has a LANE: NULL in a single-plan family (every family
/// before this item), the child in a `per_child` one. Every rule that used to
/// find "the day" by (family, date) now finds it in the same lane:
///
/// * **the lane guard** — a single-plan day names no child, a per-child day
///   names one of the family's children, a date belongs to one mode only, and
///   a row never changes lane;
/// * **the T-27/T-45 transition** reads D-1 of the SAME lane;
/// * **the frozen day** — a pending request freezes its own lane, and the
///   one-pending-per-date index is one pending per date PER LANE; the request
///   is stamped with its day's lane, never the client's;
/// * **the range RPCs** clear / time one lane or all of them;
/// * **the audit row** names the lane;
/// * **remove_child** refuses a child whose lane holds a plan.
///
/// The mode is written by the service role here: the switch RPC is PR 3.
void scheduleLaneTests(GateFixture fx) {
  const agendaFlag = 'feature.child_agenda';

  group('F-07 · schedule lanes', () {
    late ThrowawayFamily fam;
    late String agendaBefore;
    late int childA;
    late int childB;

    Future<void> setMode(String mode) => fx.service
        .from('families')
        .update({'schedule_mode': mode}).eq('id', fam.familyId);

    Future<Map<String, dynamic>> insertDay(SupabaseClient who, DateTime date,
            {int? child, int? parent, String? handoff}) async =>
        (await who
                .from('care_schedules')
                .insert({
                  'schedule_date': isoDate(date),
                  'scheduled_parent_id': parent ?? fam.adminProfile.id,
                  'child_id': ?child,
                  'handoff_time': ?handoff,
                })
                .select())
            .single;

    Future<Map<String, dynamic>> row(int id) async => (await fx.service
            .from('care_schedules')
            .select()
            .eq('id', id))
        .single;

    Future<List<Map<String, dynamic>>> lane(DateTime date) async =>
        (await fx.service
                .from('care_schedules')
                .select()
                .eq('family_id', fam.familyId)
                .eq('schedule_date', isoDate(date))
                .order('child_id', ascending: true))
            .cast<Map<String, dynamic>>();

    /// The member asks for the admin's day — the admin is the target.
    Future<Map<String, dynamic>> openSwap(Map<String, dynamic> day) async =>
        (await fam.member
                .from('swap_requests')
                .insert({
                  'schedule_date': day['schedule_date'],
                  'schedule_id': day['id'],
                  'requesting_profile_id': fam.memberProfile.id,
                  'target_profile_id': fam.adminProfile.id,
                  'previous_actual_parent_id': null,
                  'proposed_actual_parent_id': fam.memberProfile.id,
                  'status': 'pending',
                })
                .select())
            .single;

    setUpAll(() async {
      agendaBefore = await readFlag(fx, agendaFlag);
      await writeFlag(fx, agendaFlag, 'true');
      fam = await fx.createFamily('f07lane');
      await fx.service.from('families').update({
        'comp_premium_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', fam.familyId);
      childA = await fam.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Lia'}) as int;
      childB = await fam.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Theo'}) as int;
    });

    tearDownAll(() async => writeFlag(fx, agendaFlag, agendaBefore));

    late DateTime singleDay;

    test('single plan: a day names no child, and a child lane is refused',
        () async {
      singleDay = fx.nextFutureDate();
      final day = await insertDay(fam.admin, singleDay);
      expect(day['child_id'], isNull);
      await expectRejected(
          () => insertDay(fam.admin, fx.nextFutureDate(), child: childA),
          contains: 'único para todas as crianças');
    });

    test('per child: a day without a child is refused', () async {
      await setMode('per_child');
      await expectRejected(() => insertDay(fam.admin, fx.nextFutureDate()),
          contains: 'escolha a criança do dia');
    });

    test('per child: the same date holds one row per child', () async {
      final d = fx.nextFutureDate();
      await insertDay(fam.admin, d, child: childA);
      await insertDay(fam.admin, d, child: childB, parent: fam.memberProfile.id);
      final rows = await lane(d);
      expect([for (final r in rows) r['child_id']], [childA, childB]);
      // …and still ONE per child: the key is (family, child, date).
      await expectRejected(() => insertDay(fam.admin, d, child: childA),
          contains: 'care_schedules_family_schedule_date_key');
    });

    test("a child of another family is refused", () async {
      final other = (await fx.service
              .from('children')
              .insert({
                'family_id': fx.founderProfile.familyId,
                'first_name': 'Outra F07',
              })
              .select('id'))
          .single['id'] as int;
      try {
        await expectRejected(
            () => insertDay(fam.admin, fx.nextFutureDate(), child: other),
            contains: 'Criança não encontrada');
      } finally {
        await fx.service.from('children').delete().eq('id', other);
      }
    });

    test('a date planned in the other mode is refused', () async {
      await expectRejected(() => insertDay(fam.admin, singleDay, child: childA),
          contains: 'no outro modo do plano');
    });

    test('a row never changes lane', () async {
      final day = await insertDay(fam.admin, fx.nextFutureDate(), child: childA);
      await expectRejected(() async {
        await fam.admin.from('care_schedules').update({
          'child_id': childB,
          'submitted_token': day['revision_token'],
        }).eq('id', day['id'] as int);
      }, contains: 'não pode passar para outra');
      expect((await row(day['id'] as int))['child_id'], childA);
    });

    test('the handoff rule reads D-1 of the SAME lane', () async {
      final [d0, d1] = fx.nextFutureDates(2);
      // Lia: admin → admin (no transition). Theo: member → admin (transition).
      await insertDay(fam.admin, d0, child: childA);
      await insertDay(fam.admin, d0, child: childB, parent: fam.memberProfile.id);
      final lia = await insertDay(fam.admin, d1, child: childA, handoff: '18:00');
      final theo = await insertDay(fam.admin, d1, child: childB, handoff: '18:00');
      expect(lia['handoff_time'], isNull,
          reason: "Lia's D-1 is the same carer: no handoff on this day");
      expect(lia['handoff_time_backup'], '18:00:00');
      expect(theo['handoff_time'], '18:00:00',
          reason: "Theo's D-1 is another carer: this day IS a transition");
    });

    test("a pending request freezes only its own lane, and carries it",
        () async {
      final d = fx.nextFutureDate();
      final lia = await insertDay(fam.admin, d, child: childA);
      final theo = await insertDay(fam.admin, d, child: childB);
      final request = await openSwap(lia);
      expect(request['child_id'], childA,
          reason: 'the lane is stamped from schedule_id');

      await expectRejected(() async {
        await fam.member.from('care_schedules').update({
          'handoff_time': '19:00',
          'submitted_token': lia['revision_token'],
        }).eq('id', lia['id'] as int);
      }, contains: 'solicitação pendente');

      await fam.member.from('care_schedules').update({
        'handoff_time': '19:00',
        'submitted_token': theo['revision_token'],
      }).eq('id', theo['id'] as int);
      expect((await row(theo['id'] as int))['revision'],
          greaterThan(theo['revision'] as int));
    });

    test('one pending request per date PER LANE', () async {
      final d = fx.nextFutureDate();
      final lia = await insertDay(fam.admin, d, child: childA);
      final theo = await insertDay(fam.admin, d, child: childB);
      await openSwap(lia);
      final second = await openSwap(theo);
      expect(second['child_id'], childB);
      await expectRejected(() => openSwap(lia),
          contains: 'swap_requests_one_pending_per_date');
    });

    test('the range operations clear one lane, or every lane', () async {
      final days = fx.nextFutureDates(3);
      for (final d in days) {
        await insertDay(fam.admin, d, child: childA);
        await insertDay(fam.admin, d, child: childB);
      }
      final one = await fam.admin.rpc<dynamic>('clear_schedule_range', params: {
        'p_from': isoDate(days.first),
        'p_to': isoDate(days.last),
        'p_child_id': childA,
      }) as Map<String, dynamic>;
      expect(one['deleted'], 3);
      for (final d in days) {
        expect([for (final r in await lane(d)) r['child_id']], [childB]);
      }
      final all = await fam.admin.rpc<dynamic>('clear_schedule_range', params: {
        'p_from': isoDate(days.first),
        'p_to': isoDate(days.last),
      }) as Map<String, dynamic>;
      expect(all['deleted'], 3);
      for (final d in days) {
        expect(await lane(d), isEmpty);
      }
    });

    test("a replace for one child refuses a day of another", () async {
      final d = fx.nextFutureDate();
      await expectRejected(
          () => fam.admin.rpc<dynamic>('replace_schedule_range', params: {
                'p_from': isoDate(d),
                'p_to': isoDate(d),
                'p_child_id': childA,
                'p_days': [
                  {
                    'schedule_date': isoDate(d),
                    'scheduled_parent_id': fam.adminProfile.id,
                    'child_id': childB,
                  }
                ],
              }),
          contains: 'da criança substituída');
      final done = await fam.admin.rpc<dynamic>('replace_schedule_range', params: {
        'p_from': isoDate(d),
        'p_to': isoDate(d),
        'p_child_id': childA,
        'p_days': [
          {
            'schedule_date': isoDate(d),
            'scheduled_parent_id': fam.adminProfile.id,
            'child_id': childA,
          }
        ],
      }) as Map<String, dynamic>;
      expect(done['inserted'], 1);
      expect([for (final r in await lane(d)) r['child_id']], [childA]);
    });

    test('the handoff range times the transitions of one lane only', () async {
      final [d0, d1] = fx.nextFutureDates(2);
      // Lia: admin → member (d1 is a transition). Theo: member → member.
      await insertDay(fam.admin, d0, child: childA);
      await insertDay(fam.admin, d1, child: childA, parent: fam.memberProfile.id);
      await insertDay(fam.admin, d0, child: childB, parent: fam.memberProfile.id);
      await insertDay(fam.admin, d1, child: childB, parent: fam.memberProfile.id);
      final done =
          await fam.admin.rpc<dynamic>('set_handoff_time_range', params: {
        'p_from': isoDate(d1),
        'p_to': isoDate(d1),
        'p_time': '20:00',
        'p_child_id': childA,
      }) as Map<String, dynamic>;
      expect(done['updated'], 1);
      final rows = await lane(d1);
      expect(rows.firstWhere((r) => r['child_id'] == childA)['handoff_time'],
          '20:00:00');
      expect(rows.firstWhere((r) => r['child_id'] == childB)['handoff_time'],
          isNull);
    });

    test('the audit row names its lane', () async {
      final day = await insertDay(fam.admin, fx.nextFutureDate(), child: childB);
      final logs = await fx.service
          .from('activity_logs')
          .select('child_id, action')
          .eq('schedule_id', day['id'] as int);
      expect(logs.single['child_id'], childB);
      expect(logs.single['action'], 'INSERT');
    });

    test('a child whose lane holds a plan cannot be removed', () async {
      await expectRejected(
          () => fam.admin
              .rpc<dynamic>('remove_child', params: {'p_child_id': childA}),
          contains: 'tem dias no plano');
    });
  });
}
