import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// U-55 — `set_handoff_time_range`: one handoff time for every FUTURE
/// TRANSITION day that has none, in one SECURITY INVOKER statement (F-51's
/// shape).
///
/// What is worth proving here, and nowhere else:
///   · only transition days are written (T-27, the trigger's own test), so a
///     non-transition day gains neither a time nor a parked backup nor an
///     audit row;
///   · a time already set is kept and counted, a frozen day is spared and
///     counted, the past is never reached;
///   · the batch carries ONE stamp, `handoff_range`, so the Histórico folds it;
///   · admin-only, refused before any row is read — and an admin of ANOTHER
///     family writes nothing here.
///
/// One throwaway family: the NULL-bound call reaches every future day the
/// family has, which would be every other suite's days in the shared one.
void handoffRangeTests(GateFixture fx) {
  const sixThirtyPm = '18:30:00';
  const sevenThirtyAm = '07:30:00';

  ThrowawayFamily? family;
  Future<ThrowawayFamily> fam() async =>
      family ??= await fx.createFamily('u55-handoff');

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

  Future<Map<String, dynamic>> setRange(
          SupabaseClient who, DateTime from, DateTime? to, String time) async =>
      Map<String, dynamic>.from(await who.rpc<dynamic>('set_handoff_time_range',
          params: {
            'p_from': isoDate(from),
            'p_to': to == null ? null : isoDate(to),
            'p_time': time,
          }) as Map);

  /// Raw rows, by ISO date — `handoff_time_backup` is not in the client model.
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

  Future<List<ActivityLog>> logsOfBatch(int familyId, String batchId) async => [
        for (final row in await fx.service
            .from('activity_logs')
            .select()
            .eq('family_id', familyId)
            .eq('context->>batch_id', batchId))
          ActivityLog.fromJson(row)
      ];

  /// The member asks for the admin's day: frozen for everyone.
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

  group('HandoffRangeTests', () {
    test('a non-admin is refused, even over an empty range', () async {
      final f = await fam();
      final from = addDays(today(), 170);
      await expectRejected(
        () => setRange(f.member, from, addDays(from, 3), sixThirtyPm),
        contains: 'Só um administrador define o horário de troca',
      );
    });

    test('only future transition days without a time are written; a set '
        'time, a frozen day and the past are kept, with the counts to match',
        () async {
      final f = await fam();
      final a = f.adminProfile.id;
      final m = f.memberProfile.id;
      final from = addDays(today(), 100);
      final past = addDays(today(), -5);

      // A A M M A A M M A — transitions at 0 (no D-1), 2, 4, 6 and 8.
      final pattern = [a, a, m, m, a, a, m, m, a];
      final days = <CareSchedule>[
        for (var i = 0; i < pattern.length; i++)
          await seedDay(f.admin, pattern[i], addDays(from, i),
              handoffTime: i == 4 ? sevenThirtyAm : null),
      ];
      await freeze(f, days[8]);
      // A past transition with no time: the floor is today for every tier.
      await seedDay(fx.service, a, past);

      final to = addDays(from, pattern.length - 1);
      final result = await setRange(f.admin, past, to, sixThirtyPm);
      expect(result['updated'], 3);
      expect(result['kept_existing'], 1);
      expect(result['kept_frozen'], 1);
      expect(result['batch_id'], isA<String>());

      final after = await rowsIn(f.familyId, from, to);
      String? timeOf(int i) =>
          after[isoDate(days[i].scheduleDate)]!['handoff_time'] as String?;
      String? backupOf(int i) => after[isoDate(days[i].scheduleDate)]![
          'handoff_time_backup'] as String?;
      for (final i in [0, 2, 6]) {
        expect(timeOf(i), sixThirtyPm, reason: 'transition $i');
      }
      expect(timeOf(4), sevenThirtyAm, reason: 'a set time is never replaced');
      expect(timeOf(8), isNull, reason: 'the frozen day is spared');
      for (final i in [1, 3, 5, 7]) {
        expect(timeOf(i), isNull, reason: 'non-transition $i');
        // Not touched at all: nothing parked for a later transition.
        expect(backupOf(i), isNull, reason: 'non-transition $i');
      }
      final pastRow = (await rowsIn(f.familyId, past, past))[isoDate(past)]!;
      expect(pastRow['handoff_time'], isNull);

      // One stamp, one kind, one UPDATE per written day — and nothing else:
      // the T-45 cascade stays silent, since no responsible changed.
      final logs = await logsOfBatch(f.familyId, result['batch_id'] as String);
      expect(logs, hasLength(3));
      expect(logs.every((l) => l.action == 'UPDATE'), isTrue);
      expect(logs.every((l) => l.context?.batchKind == 'handoff_range'), isTrue);
      expect(logs.map((l) => isoDate(l.affectedDate)).toSet(), {
        for (final i in [0, 2, 6]) isoDate(days[i].scheduleDate),
      });
    });

    test('with no upper bound it reaches every future transition day',
        () async {
      final f = await fam();
      final far = addDays(today(), 150);
      await seedDay(f.admin, f.memberProfile.id, far);

      final result = await setRange(f.admin, today(), null, sixThirtyPm);
      expect(result['updated'], greaterThanOrEqualTo(1));
      final row = (await rowsIn(f.familyId, far, far))[isoDate(far)]!;
      expect(row['handoff_time'], sixThirtyPm);
    });

    test("an admin of another family writes nothing in this one", () async {
      final f = await fam();
      final other = await fx.createFamily('u55-other');
      final day = addDays(today(), 160);
      await seedDay(f.admin, f.adminProfile.id, day);

      final result = await setRange(other.admin, today(), null, sixThirtyPm);
      expect(result['updated'], 0);
      final row = (await rowsIn(f.familyId, day, day))[isoDate(day)]!;
      expect(row['handoff_time'], isNull);
    });

    test('a missing time and an inverted range are refused', () async {
      final f = await fam();
      final from = addDays(today(), 120);
      await expectRejected(
        () => f.admin.rpc<dynamic>('set_handoff_time_range', params: {
          'p_from': isoDate(from),
          'p_to': null,
          'p_time': null,
        }),
        contains: 'Informe o horário da troca',
      );
      await expectRejected(
        () => setRange(f.admin, from, addDays(from, -1), sixThirtyPm),
        contains: 'Intervalo de datas inválido',
      );
    });
  });
}
