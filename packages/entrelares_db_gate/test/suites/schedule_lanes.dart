import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

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
      // F-99: Theo's day is the member's, so the member is an end of its
      // handoff and may write the time — the probe is the frozen lane, not
      // who may change a handoff.
      final theo = await insertDay(fam.admin, d,
          child: childB, parent: fam.memberProfile.id);
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

    // F-85: the sibling of a per-child swap now gets the SAME unchanged base
    // write the main lane does before its request. The fix rests on this:
    // that write logs the day as it stands in `old_data`, so the request's
    // `pre_edit_log_id` (the lane's newest log) carries a snapshot — not the
    // wizard's INSERT, whose `old_data` is null and made the revert DELETE
    // the sibling's day.
    test("F-85: an unchanged base write logs the lane's day as its snapshot",
        () async {
      final d = fx.nextFutureDate();
      final inserted = await insertDay(fam.admin, d, child: childB);
      final insertLog = (await fx.service
              .from('activity_logs')
              .select('id, action, old_data')
              .eq('affected_date', isoDate(d))
              .eq('child_id', childB)
              .order('id', ascending: false)
              .limit(1))
          .single;
      expect(insertLog['old_data'], isNull,
          reason: 'the premise: a wizard day carries no snapshot');

      await saveDay(fam.admin, await readDayById(fam.admin, inserted['id'] as int));

      final newest = (await fx.service
              .from('activity_logs')
              .select('id, old_data')
              .eq('affected_date', isoDate(d))
              .eq('child_id', childB)
              .order('id', ascending: false)
              .limit(1))
          .single;
      expect(newest['id'], greaterThan(insertLog['id'] as int));
      final snapshot = newest['old_data'] as Map<String, dynamic>;
      expect(snapshot['id'], inserted['id']);
      expect(snapshot['child_id'], childB);
      expect(snapshot['scheduled_parent_id'], fam.adminProfile.id);
    });

    test('a child whose lane holds a plan cannot be removed', () async {
      await expectRejected(
          () => fam.admin
              .rpc<dynamic>('remove_child', params: {'p_child_id': childA}),
          contains: 'tem dias no plano');
    });
  });

  // F-07 (PR 3): the ONLY writer of `families.schedule_mode`.
  group('F-07 · plan mode switch', () {
    const flag = 'feature.per_child_schedule';
    late ThrowawayFamily fam;
    late String agendaBefore;
    late String flagBefore;
    late int childA;
    late int childB;
    final today = saoPauloToday();
    final days = [for (var i = 0; i < 4; i++) addDays(today, i)];

    Future<Map<String, dynamic>> switchTo(SupabaseClient who, String mode,
            {int? base}) async =>
        Map<String, dynamic>.from(await who.rpc<dynamic>('set_schedule_mode',
            params: {'p_mode': mode, 'p_base_child_id': base}) as Map);

    Future<List<Map<String, dynamic>>> rowsOn(DateTime d) async =>
        (await fx.service
                .from('care_schedules')
                .select()
                .eq('family_id', fam.familyId)
                .eq('schedule_date', isoDate(d))
                .order('child_id', ascending: true, nullsFirst: true))
            .cast<Map<String, dynamic>>();

    Future<String> mode() async => (await fx.service
            .from('families')
            .select('schedule_mode')
            .eq('id', fam.familyId))
        .single['schedule_mode'] as String;

    setUpAll(() async {
      agendaBefore = await readFlag(fx, agendaFlag);
      flagBefore = await readFlag(fx, flag);
      await writeFlag(fx, agendaFlag, 'true');
      fam = await fx.createFamily('f07mode');
      await fx.service.from('families').update({
        'comp_premium_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', fam.familyId);
      childA = await fam.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Lia'}) as int;

      // Yesterday, written by the system: the past the switch must not move.
      await fx.service.from('care_schedules').insert({
        'schedule_date': isoDate(addDays(today, -1)),
        'scheduled_parent_id': fam.adminProfile.id,
      });
      // Today on: admin, member, admin, member.
      for (var i = 0; i < days.length; i++) {
        await fam.admin.from('care_schedules').insert({
          'schedule_date': isoDate(days[i]),
          'scheduled_parent_id':
              i.isEven ? fam.adminProfile.id : fam.memberProfile.id,
        });
      }
      // An APPROVED swap on days[2]: the member asked, the admin approved.
      final day2 = (await rowsOn(days[2])).single;
      final req = (await fam.member
              .from('swap_requests')
              .insert({
                'schedule_date': isoDate(days[2]),
                'schedule_id': day2['id'],
                'requesting_profile_id': fam.memberProfile.id,
                'target_profile_id': fam.adminProfile.id,
                'previous_actual_parent_id': null,
                'proposed_actual_parent_id': fam.memberProfile.id,
                'status': 'pending',
              })
              .select())
          .single;
      await fam.admin.from('care_schedules').update({
        'actual_parent_id': fam.memberProfile.id,
        'submitted_token': day2['revision_token'],
      }).eq('id', day2['id'] as int);
      await fam.admin.from('swap_requests').update({
        'status': 'approved',
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', req['id'] as int);
    });

    tearDownAll(() async {
      await writeFlag(fx, flag, flagBefore);
      await writeFlag(fx, agendaFlag, agendaBefore);
    });

    test('with the flag OFF nobody switches', () async {
      await writeFlag(fx, flag, 'false');
      await expectRejected(() => switchTo(fam.admin, 'per_child'),
          contains: 'ainda não está disponível');
      await writeFlag(fx, flag, 'true');
    });

    test('only an admin switches', () async {
      await expectRejected(() => switchTo(fam.member, 'per_child'),
          contains: 'Somente administradores');
    });

    test('one child is not enough for a plan per child', () async {
      await expectRejected(() => switchTo(fam.admin, 'per_child'),
          contains: 'pelo menos duas crianças');
      childB = await fam.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Theo'}) as int;
    });

    test('a pending request from today on refuses the switch', () async {
      final day3 = (await rowsOn(days[3])).single;
      final req = (await fam.admin
              .from('swap_requests')
              .insert({
                'schedule_date': isoDate(days[3]),
                'schedule_id': day3['id'],
                'requesting_profile_id': fam.adminProfile.id,
                'target_profile_id': fam.memberProfile.id,
                'previous_actual_parent_id': null,
                'proposed_actual_parent_id': fam.adminProfile.id,
                'status': 'pending',
              })
              .select())
          .single;
      await expectRejected(() => switchTo(fam.admin, 'per_child'),
          contains: 'pedidos de troca pendentes');
      await fam.admin.from('swap_requests').update({
        'status': 'cancelled',
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', req['id'] as int);
      expect(await mode(), 'single');
    });

    test('single → per child copies today on into every lane, past untouched',
        () async {
      final result = await switchTo(fam.admin, 'per_child');
      expect(result['changed'], isTrue);
      expect(result['days'], days.length);
      expect(result['written'], days.length * 2);
      expect(await mode(), 'per_child');

      final past = await rowsOn(addDays(today, -1));
      expect([for (final r in past) r['child_id']], [null]);

      for (var i = 0; i < days.length; i++) {
        final rows = await rowsOn(days[i]);
        expect([for (final r in rows) r['child_id']], [childA, childB]);
        for (final r in rows) {
          expect(r['scheduled_parent_id'],
              i.isEven ? fam.adminProfile.id : fam.memberProfile.id);
        }
      }
      // The approved swap is a fact: every lane keeps the real carer.
      for (final r in await rowsOn(days[2])) {
        expect(r['actual_parent_id'], fam.memberProfile.id);
      }
      // ONE batch, folded by the Histórico.
      final logs = await fx.service
          .from('activity_logs')
          .select('context')
          .eq('family_id', fam.familyId)
          .eq('affected_date', isoDate(days[0]))
          .order('id', ascending: false)
          .limit(3);
      expect({for (final l in logs) (l['context'] as Map)['batch_kind']},
          {'mode_switch'});
    });

    test('switching to the mode already in place changes nothing', () async {
      final result = await switchTo(fam.admin, 'per_child');
      expect(result['changed'], isFalse);
    });

    test('back to single asks whose plan becomes the family plan', () async {
      await expectRejected(() => switchTo(fam.admin, 'single'),
          contains: 'Escolha de qual criança');
      // The second lane diverges on days[1]: the admin plans it for themself.
      final second = (await rowsOn(days[1]))
          .firstWhere((r) => r['child_id'] == childB);
      await fam.admin.from('care_schedules').update({
        'scheduled_parent_id': fam.adminProfile.id,
        'submitted_token': second['revision_token'],
      }).eq('id', second['id'] as int);

      final result = await switchTo(fam.admin, 'single', base: childB);
      expect(result['days'], days.length);
      expect(await mode(), 'single');
      for (var i = 0; i < days.length; i++) {
        final rows = await rowsOn(days[i]);
        expect([for (final r in rows) r['child_id']], [null]);
      }
      expect((await rowsOn(days[1])).single['scheduled_parent_id'],
          fam.adminProfile.id,
          reason: 'the chosen lane is the family plan now');
    });
  });

  // F-07 (PR 5a): the aviso, the plan's end — the rest of the server per lane.
  group('F-07 · lanes beyond the day', () {
    late ThrowawayFamily fam;
    late String agendaBefore;
    late int childA;
    late int childB;
    final today = saoPauloToday();

    Future<List<Map<String, dynamic>>> rowsOn(DateTime d) async =>
        (await fx.service
                .from('care_schedules')
                .select()
                .eq('family_id', fam.familyId)
                .eq('schedule_date', isoDate(d))
                .order('child_id', ascending: true))
            .cast<Map<String, dynamic>>();

    setUpAll(() async {
      agendaBefore = await readFlag(fx, agendaFlag);
      await writeFlag(fx, agendaFlag, 'true');
      fam = await fx.createFamily('f07more');
      await fx.service.from('families').update({
        'comp_premium_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', fam.familyId);
      childA = await fam.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Lia'}) as int;
      childB = await fam.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Theo'}) as int;
      await fx.service
          .from('families')
          .update({'schedule_mode': 'per_child'}).eq('id', fam.familyId);
      // Today both children are with the member; Lia's plan runs 10 days
      // ahead, Theo's only 3.
      for (final (child, days) in [(childA, 10), (childB, 3)]) {
        for (var i = 0; i <= days; i++) {
          await fam.admin.from('care_schedules').insert({
            'schedule_date': isoDate(addDays(today, i)),
            'scheduled_parent_id': fam.memberProfile.id,
            'child_id': child,
          });
        }
      }
    });

    tearDownAll(() async => writeFlag(fx, agendaFlag, agendaBefore));

    test('the plan ends when the FIRST child runs out', () async {
      final last = await fam.admin.rpc<dynamic>('my_plan_last_day');
      expect(last, isoDate(addDays(today, 3)));
    });

    test("the member holds today in every lane: the aviso offers the day, "
        "and taking it moves every lane", () async {
      final noticeId = await fam.member.rpc<dynamic>('send_day_notice',
          params: {'p_reason': 'atraso', 'p_request': 'keep'}) as int;
      final swapId = await fam.admin.rpc<dynamic>('answer_day_notice',
          params: {'p_notice_id': noticeId, 'p_outcome': 'keeping'});
      expect(swapId, isNotNull);

      final rows = await rowsOn(today);
      expect([for (final r in rows) r['child_id']], [childA, childB]);
      for (final r in rows) {
        expect(r['actual_parent_id'], fam.adminProfile.id,
            reason: 'lane ${r['child_id']} moved');
      }
      final swaps = await fx.service
          .from('swap_requests')
          .select('child_id, status')
          .eq('family_id', fam.familyId)
          .eq('schedule_date', isoDate(today));
      expect({for (final s in swaps) s['child_id']}, {childA, childB});
      expect({for (final s in swaps) s['status']}, {'approved'});
    });
  });
}
