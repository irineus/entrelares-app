import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-51 — `clear_schedule_range` / `replace_schedule_range`: the two SECURITY
/// INVOKER RPCs behind "Limpar mês" and the wizard's "substituir os dias já
/// planejados". One statement per operation, as the CALLER, so
/// `enforce_day_protection` and RLS judge every row exactly as they judge a
/// single-day write.
///
/// What is worth proving here, and nowhere else:
///   · the WHERE spares what the trigger would refuse (frozen days, approved
///     swaps) and what the item forbids for every tier (the past), and the
///     counts describe the same rows the DELETE saw;
///   · the replace is ONE transaction — an insert that fails leaves the old
///     plan intact, never a family with no plan at all;
///   · the day just after the cleared range keeps a correct handoff time
///     through the T-45 cascade, on the clear and on both directions of a
///     replace;
///   · every row a batch writes carries the same `context.batch_id`.
///
/// Every scenario runs in ONE throwaway family: a range DELETE in the shared
/// family would eat the days every other suite seeded inside it.
void scheduleRangeTests(GateFixture fx) {
  const sixPm = '18:00:00';

  ThrowawayFamily? family;
  Future<ThrowawayFamily> fam() async =>
      family ??= await fx.createFamily('f51-range');

  Future<CareSchedule> seedDay(
    SupabaseClient creator,
    int scheduledParentId,
    DateTime date, {
    String? handoffTime,
  }) async {
    final rows = await creator.from('care_schedules').insert({
      'schedule_date': isoDate(date),
      'scheduled_parent_id': scheduledParentId,
      'handoff_time': ?handoffTime,
    }).select();
    return CareSchedule.fromJson(rows.single);
  }

  Future<Map<String, dynamic>> clearRange(
          SupabaseClient who, DateTime from, DateTime to) async =>
      Map<String, dynamic>.from(await who.rpc<dynamic>('clear_schedule_range',
          params: {'p_from': isoDate(from), 'p_to': isoDate(to)}) as Map);

  Future<Map<String, dynamic>> replaceRange(SupabaseClient who, DateTime from,
          DateTime to, List<Map<String, dynamic>> days) async =>
      Map<String, dynamic>.from(await who.rpc<dynamic>(
          'replace_schedule_range',
          params: {
            'p_from': isoDate(from),
            'p_to': isoDate(to),
            'p_days': days,
          }) as Map);

  /// The generated plan the wizard would send: one row per day of
  /// [from, to], all for [parentId].
  List<Map<String, dynamic>> planFor(int parentId, DateTime from, DateTime to) =>
      [
        for (var d = from; !d.isAfter(to); d = addDays(d, 1))
          {
            'schedule_date': isoDate(d),
            'scheduled_parent_id': parentId,
            'handoff_time': null,
            'notes': null,
          },
      ];

  /// The family's rows in [from, to], by ISO date, as the service sees them —
  /// the raw row, because `handoff_time_backup` is not part of the client
  /// model and the T-45 assertions need it.
  Future<Map<String, Map<String, dynamic>>> rowsIn(
      int familyId, DateTime from, DateTime to) async {
    final rows = await fx.service
        .from('care_schedules')
        .select()
        .eq('family_id', familyId)
        .gte('schedule_date', isoDate(from))
        .lte('schedule_date', isoDate(to));
    return {
      for (final r in rows)
        r['schedule_date'] as String: Map<String, dynamic>.from(r)
    };
  }

  /// The audit rows a batch left behind, read with the service client (a
  /// DELETE row has no schedule_id, so the batch id is the only join).
  Future<List<ActivityLog>> logsOfBatch(int familyId, String batchId) async => [
        for (final row in await fx.service
            .from('activity_logs')
            .select()
            .eq('family_id', familyId)
            .eq('context->>batch_id', batchId)
            .order('created_at', ascending: true))
          ActivityLog.fromJson(row)
      ];

  /// The member opens a swap for [day], making the ADMIN the target — the
  /// day is frozen for everyone, and the admin is the only one the trigger
  /// would let delete it, which is exactly what the RPC must not do.
  Future<void> freeze(ThrowawayFamily f, CareSchedule day) async {
    await f.member.from('swap_requests').insert({
      'schedule_date': isoDate(day.scheduleDate),
      'schedule_id': day.id,
      'requesting_profile_id': f.memberProfile.id,
      'target_profile_id': f.adminProfile.id,
      'previous_actual_parent_id': null,
      'proposed_actual_parent_id': f.memberProfile.id,
      'status': 'pending',
    });
  }

  /// An approved swap as the calendar records one: the real parent differs
  /// from the planned one. Written by the service (system context) so no
  /// workflow has to be driven for a fact the RPC only reads.
  Future<void> approvedSwapOn(ThrowawayFamily f, CareSchedule day) async {
    await fx.service
        .from('care_schedules')
        .update({'actual_parent_id': f.memberProfile.id}).eq('id', day.id);
  }

  group('ScheduleRangeTests', () {
    test('a non-admin is refused by both RPCs, even over an empty range',
        () async {
      // The trigger's sentence, raised BEFORE any row is looked at: a silent
      // "0 deleted" would read as permission.
      final f = await fam();
      final from = addDays(today(), 400);
      await expectRejected(
        () => clearRange(f.member, from, addDays(from, 3)),
        contains: 'só pode ser limpo por um administrador',
      );
      await expectRejected(
        () => replaceRange(f.member, from, addDays(from, 3),
            planFor(f.memberProfile.id, from, addDays(from, 3))),
        contains: 'só pode ser limpo por um administrador',
      );
    });

    test('the clear deletes the plain days and keeps frozen, approved-swap '
        'and past days, with the counts to match', () async {
      final f = await fam();
      final from = addDays(today(), 30);
      final to = addDays(from, 6);
      final past = addDays(today(), -5);

      final days = [
        for (var d = from; !d.isAfter(to); d = addDays(d, 1))
          await seedDay(f.admin, f.adminProfile.id, d),
      ];
      await freeze(f, days[2]);
      await approvedSwapOn(f, days[3]);
      await seedDay(fx.service, f.adminProfile.id, past);

      // The range starts in the past on purpose: the floor is today for
      // every tier, and asking for more than that must simply not reach it.
      final result = await clearRange(f.admin, past, to);
      expect(result['deleted'], 5);
      expect(result['kept_frozen'], 1);
      expect(result['kept_swap'], 1);
      expect(result['batch_id'], isA<String>());

      final left = await rowsIn(f.familyId, past, to);
      expect(left.keys.toSet(), {
        isoDate(past),
        isoDate(days[2].scheduleDate),
        isoDate(days[3].scheduleDate),
      });

      // F-51: every DELETE the batch wrote carries the same stamp.
      final logs = await logsOfBatch(f.familyId, result['batch_id'] as String);
      expect(logs, hasLength(5));
      expect(logs.every((l) => l.action == 'DELETE'), isTrue);
      expect(logs.every((l) => l.context?.batchKind == 'clear_range'), isTrue);
      expect(logs.map((l) => isoDate(l.affectedDate)).toSet(), {
        for (final i in [0, 1, 4, 5, 6]) isoDate(days[i].scheduleDate),
      });
    });

    test('a range entirely in the past clears nothing', () async {
      final f = await fam();
      final result =
          await clearRange(f.admin, addDays(today(), -9), addDays(today(), -3));
      expect(result['deleted'], 0);
      expect(result['kept_frozen'], 0);
      expect(result['kept_swap'], 0);
    });

    test('the replace swaps the plan in one call and keeps the frozen day, '
        'reporting the generated day it could not plant', () async {
      final f = await fam();
      final from = addDays(today(), 40);
      final to = addDays(from, 6);
      final days = [
        for (var d = from; !d.isAfter(to); d = addDays(d, 1))
          await seedDay(f.admin, f.adminProfile.id, d),
      ];
      await freeze(f, days[3]);

      final result = await replaceRange(
          f.admin, from, to, planFor(f.memberProfile.id, from, to));
      expect(result['deleted'], 6);
      expect(result['kept_frozen'], 1);
      expect(result['kept_swap'], 0);
      expect(result['inserted'], 6);
      // The generated day for the frozen date collided with the row the
      // WHERE spared — reported, never a unique-violation abort.
      expect(result['kept_existing'], 1);

      final after = await rowsIn(f.familyId, from, to);
      expect(after, hasLength(7));
      for (final entry in after.entries) {
        final expected = entry.key == isoDate(days[3].scheduleDate)
            ? f.adminProfile.id
            : f.memberProfile.id;
        expect(entry.value['scheduled_parent_id'], expected,
            reason: 'day ${entry.key}');
      }

      final logs = await logsOfBatch(f.familyId, result['batch_id'] as String);
      expect(logs.where((l) => l.action == 'DELETE'), hasLength(6));
      expect(logs.where((l) => l.action == 'INSERT'), hasLength(6));
      expect(
          logs.every((l) => l.context?.batchKind == 'replace_range'), isTrue);
    });

    test('a replace whose insert fails leaves the old plan intact', () async {
      // A day planned for someone from ANOTHER family: trigger_a stamps that
      // family, the INSERT policy refuses, and the whole call — the DELETE
      // included — must roll back. A family with no plan is the worst
      // outcome this item can produce.
      final f = await fam();
      final from = addDays(today(), 50);
      final to = addDays(from, 2);
      for (var d = from; !d.isAfter(to); d = addDays(d, 1)) {
        await seedDay(f.admin, f.adminProfile.id, d);
      }

      final plan = planFor(f.memberProfile.id, from, to);
      plan[1]['scheduled_parent_id'] = fx.founderBProfile.id;
      await expectRejected(() => replaceRange(f.admin, from, to, plan));

      final after = await rowsIn(f.familyId, from, to);
      expect(after, hasLength(3));
      expect(
          after.values
              .every((r) => r['scheduled_parent_id'] == f.adminProfile.id),
          isTrue);
    });

    test('a generated day outside the range is refused before anything moves',
        () async {
      final f = await fam();
      final from = addDays(today(), 56);
      final to = addDays(from, 1);
      await seedDay(f.admin, f.adminProfile.id, from);

      final plan = planFor(f.memberProfile.id, from, addDays(to, 1));
      await expectRejected(
        () => replaceRange(f.admin, from, to, plan),
        contains: 'dentro do intervalo',
      );
      final after = await rowsIn(f.familyId, from, addDays(to, 1));
      expect(after.keys.toList(), [isoDate(from)]);
      expect(after[isoDate(from)]!['scheduled_parent_id'], f.adminProfile.id);
    });

    test("the day after the range keeps a correct handoff through the T-45 "
        "cascade, on the clear and on both directions of a replace", () async {
      final f = await fam();
      final from = addDays(today(), 60);
      final to = addDays(from, 2);
      final next = addDays(to, 1);
      for (var d = from; !d.isAfter(to); d = addDays(d, 1)) {
        await seedDay(f.admin, f.adminProfile.id, d);
      }
      // The member takes over the day after the range at 18:00 — a genuine
      // transition, so the time survives its own insert.
      await seedDay(f.admin, f.memberProfile.id, next, handoffTime: sixPm);
      expect((await rowsIn(f.familyId, next, next))[isoDate(next)]!
          ['handoff_time'], sixPm);

      // Clearing the range: D+1 has no previous day → still a transition.
      final cleared = await clearRange(f.admin, from, to);
      expect(cleared['deleted'], 3);
      var row = (await rowsIn(f.familyId, next, next))[isoDate(next)]!;
      expect(row['handoff_time'], sixPm);

      // Re-planning the range FOR THE MEMBER: the day after it is no longer a
      // transition, and its time is parked — not destroyed.
      await replaceRange(
          f.admin, from, to, planFor(f.memberProfile.id, from, to));
      row = (await rowsIn(f.familyId, next, next))[isoDate(next)]!;
      expect(row['handoff_time'], isNull);
      expect(row['handoff_time_backup'], sixPm);

      // Re-planning it back for the admin: the transition returns, and so
      // does the parked time.
      await replaceRange(
          f.admin, from, to, planFor(f.adminProfile.id, from, to));
      row = (await rowsIn(f.familyId, next, next))[isoDate(next)]!;
      expect(row['handoff_time'], sixPm);
    });

    test('a single-day write carries no batch stamp', () async {
      // The stamp is the RPC's own: an ordinary insert must not look like a
      // batch of one, or the history would fold it.
      final f = await fam();
      final date = addDays(today(), 70);
      final day = await seedDay(f.admin, f.adminProfile.id, date);
      final rows = await fx.service
          .from('activity_logs')
          .select()
          .eq('family_id', f.familyId)
          .eq('schedule_id', day.id);
      final log = ActivityLog.fromJson(rows.single);
      expect(log.context?.batchId, isNull);
      expect(log.context?.batchKind, isNull);
    });
  });
}
