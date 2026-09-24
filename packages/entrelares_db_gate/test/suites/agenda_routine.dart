import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-55 (PR 3) — the routine: a weekly model applied to the rest of the plan.
///
/// * **until the end of the plan** — the last planned day (inside the tier
///   horizon); nothing planned from that day on refuses the routine;
/// * **ordinary events** — each generated day passes the single-event rule,
///   and one refused day refuses the whole routine, naming the day;
/// * **re-apply replaces the future** — the routine's events from a day on
///   are soft-deleted and regenerated; the ones before it stay;
/// * **a hand edit leaves the routine** — a re-apply never overwrites it;
/// * **stop** — removes the routine's events from a day on.
void agendaRoutineTests(GateFixture fx) {
  const flag = 'feature.child_agenda';
  final today = saoPauloToday();
  DateTime ahead(int days) => addDays(today, days);
  String br(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> seedPlan(ThrowawayFamily fam, int days) async {
    await fx.service.from('care_schedules').insert([
      for (var i = 0; i < days; i++)
        {
          'family_id': fam.familyId,
          'schedule_date': isoDate(ahead(i)),
          'scheduled_parent_id': fam.adminProfile.id,
        }
    ]);
  }

  Future<Map<String, dynamic>> save(
    SupabaseClient who, {
    String? routineId,
    required DateTime from,
    required String kind,
    required List<int> weekdays,
    int? childId,
    String? start,
    String? body,
  }) async =>
      Map<String, dynamic>.from(
          await who.rpc<dynamic>('save_child_routine', params: {
        'p_routine_id': routineId,
        'p_from': isoDate(from),
        'p_kind': kind,
        'p_weekdays': weekdays,
        'p_child_id': childId,
        'p_start': start,
        'p_body': body,
      }) as Map);

  Future<List<Map<String, dynamic>>> batch(String id,
          {bool live = true}) async =>
      List<Map<String, dynamic>>.from(await (live
          ? fx.service
              .from('child_events')
              .select()
              .eq('batch_id', id)
              .isFilter('deleted_at', null)
              .order('event_date', ascending: true)
          : fx.service
              .from('child_events')
              .select()
              .eq('batch_id', id)
              .order('event_date', ascending: true)));

  int matching(int from, int to, List<int> weekdays) => [
        for (var i = from; i <= to; i++)
          if (weekdays.contains(ahead(i).weekday)) i
      ].length;

  group('F-55 · routine', () {
    late ThrowawayFamily prem;
    late ThrowawayFamily free;
    late int child;
    late int freeChild;
    late String flagBefore;
    late String routineId;
    final days = [ahead(0).weekday, ahead(2).weekday];

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
      prem = await fx.createFamily('f55rtp');
      free = await fx.createFamily('f55rtf');
      await fx.service
          .from('families')
          .update({'comp_premium_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', prem.familyId);
      await fx.service.from('families').update({
        'plan': 'free',
        'trial_ends_at': null,
        'comp_premium_at': null,
      }).eq('id', free.familyId);
      child = await prem.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Nina'}) as int;
      freeChild = await free.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Caio'}) as int;
    });

    tearDownAll(() async => writeFlag(fx, flag, flagBefore));

    test('with nothing planned from that day on, the routine is refused',
        () async {
      await expectRejected(
          () => save(prem.member,
              from: today, kind: 'school', weekdays: days, childId: child),
          contains: 'ainda não tem dias planejados');
    });

    test('with the flag OFF, and on a past day, the server refuses',
        () async {
      await seedPlan(prem, 21);
      await writeFlag(fx, flag, 'false');
      try {
        await expectRejected(
            () => save(prem.member,
                from: today, kind: 'school', weekdays: days, childId: child),
            contains: 'ainda não está disponível');
      } finally {
        await writeFlag(fx, flag, 'true');
      }
      await expectRejected(
          () => save(prem.member,
              from: ahead(-1), kind: 'school', weekdays: days, childId: child),
          contains: 'hoje em diante');
      await expectRejected(
          () => save(prem.member,
              from: today, kind: 'school', weekdays: [], childId: child),
          contains: 'dia da semana');
    });

    test('applies the weekdays until the last planned day, as one batch',
        () async {
      final r = await save(prem.member,
          from: today,
          kind: 'school',
          weekdays: days,
          childId: child,
          start: '13:00',
          body: 'turma B');
      routineId = r['routine_id'] as String;
      expect(r['until'], isoDate(ahead(20)));
      expect(r['created'], matching(0, 20, days));
      expect(r['removed'], 0);

      final rows = await batch(routineId);
      expect(rows, hasLength(matching(0, 20, days)));
      for (final e in rows) {
        expect(days, contains(DateTime.parse(e['event_date'] as String).weekday));
        expect(e['kind'], 'school');
        expect(e['child_id'], child);
        expect(e['start_time'], '13:00:00');
        expect(e['body'], 'turma B');
        expect(e['created_by'], prem.memberProfile.id);
      }
      final routine = (await fx.service
              .from('child_routines')
              .select()
              .eq('id', routineId)
              .limit(1))
          .single;
      expect(routine['family_id'], prem.familyId);
      expect(routine['starts_on'], isoDate(today));
      expect(routine['ends_on'], isoDate(ahead(20)));
      expect(List<int>.from(routine['weekdays'] as List),
          (days.toSet().toList()..sort()));
    });

    test('a hand edit leaves the routine; re-apply replaces only the future',
        () async {
      final before = await batch(routineId);
      final edited = before.last;
      await prem.admin.rpc<dynamic>('update_child_event', params: {
        'p_event_id': edited['id'],
        'p_date': edited['event_date'],
        'p_kind': 'school',
        'p_child_id': child,
        'p_start': '14:00',
        'p_body': 'mudou',
      });
      final after = (await fx.service
              .from('child_events')
              .select()
              .eq('id', edited['id'] as int)
              .limit(1))
          .single;
      expect(after['batch_id'], isNull);

      final other = [ahead(9).weekday];
      final r = await save(prem.admin,
          routineId: routineId,
          from: ahead(7),
          kind: 'activity',
          weekdays: other,
          childId: child);
      expect(r['routine_id'], routineId);
      // The hand-edited event is no longer the routine's to remove.
      expect(r['removed'], matching(7, 20, days) - 1);
      expect(r['created'], matching(7, 20, other));

      final live = await batch(routineId);
      final early = live.where((e) =>
          DateTime.parse(e['event_date'] as String).isBefore(ahead(7)));
      expect(early.length, matching(0, 6, days));
      expect(early.every((e) => e['kind'] == 'school'), isTrue);
      final later = live.where((e) =>
          !DateTime.parse(e['event_date'] as String).isBefore(ahead(7)));
      expect(later.every((e) => e['kind'] == 'activity'), isTrue);

      // The replaced ones stay in the record, with who removed them.
      final gone = (await batch(routineId, live: false))
          .where((e) => e['deleted_at'] != null)
          .toList();
      expect(gone, hasLength(matching(7, 20, days) - 1));
      expect(gone.every((e) => e['deleted_by'] == prem.adminProfile.id),
          isTrue);
      final kept = (await fx.service
              .from('child_events')
              .select()
              .eq('id', edited['id'] as int)
              .limit(1))
          .single;
      expect(kept['deleted_at'], isNull);
    });

    test('stop removes the routine\'s events from a day on', () async {
      final removed = await prem.member.rpc<dynamic>('stop_child_routine',
          params: {'p_routine_id': routineId, 'p_from': isoDate(ahead(14))});
      expect(removed, matching(14, 20, [ahead(9).weekday]));
      final live = await batch(routineId);
      expect(
          live.every((e) =>
              DateTime.parse(e['event_date'] as String).isBefore(ahead(14))),
          isTrue);
      await expectRejected(
          () => save(prem.admin,
              routineId: routineId,
              from: today,
              kind: 'school',
              weekdays: days,
              childId: child),
          contains: 'Rotina não encontrada');
    });

    test('free: a structured routine is Premium; a refused day is named',
        () async {
      await seedPlan(free, 2);
      await expectRejected(
          () => save(free.admin,
              from: today, kind: 'school', weekdays: days, childId: freeChild),
          contains: 'recurso Premium');

      await free.member.rpc<dynamic>('add_child_event', params: {
        'p_date': isoDate(ahead(1)),
        'p_kind': 'note',
        'p_body': 'já tem',
      });
      await expectRejected(
          () => save(free.admin,
              from: today,
              kind: 'note',
              weekdays: [ahead(0).weekday, ahead(1).weekday],
              body: 'lanche'),
          contains: 'Em ${br(ahead(1))}: No plano gratuito');
      // Nothing of the refused routine was left behind.
      final rows = await fx.service
          .from('child_events')
          .select('id')
          .eq('family_id', free.familyId);
      expect(rows, hasLength(1));

      final r = await save(free.admin,
          from: today, kind: 'note', weekdays: [ahead(0).weekday], body: 'lanche');
      expect(r['created'], 1);

      await expectRejected(
          () => save(free.admin,
              from: today,
              kind: 'note',
              weekdays: [
                for (var w = 1; w <= 7; w++)
                  if (w != ahead(0).weekday && w != ahead(1).weekday) w
              ],
              body: 'x'),
          contains: 'Nenhum dia planejado');
    });

    test('no client writes the routine table directly', () async {
      await expectRejected(
          () => prem.admin.from('child_routines').insert({
                'family_id': prem.familyId,
                'kind': 'note',
                'body': 'x',
                'weekdays': [1],
                'starts_on': isoDate(today),
                'ends_on': isoDate(today),
              }));
    });

    test('another family neither reads nor stops the routine', () async {
      final seen = await free.admin
          .from('child_routines')
          .select('id')
          .eq('id', routineId);
      expect(seen, isEmpty);
      await expectRejected(
          () => free.admin.rpc<dynamic>('stop_child_routine',
              params: {'p_routine_id': routineId, 'p_from': isoDate(today)}),
          contains: 'Rotina não encontrada');
    });
  });
}
