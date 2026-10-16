import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-99 — only the two ends of a handoff (or an admin) change its time.
///
/// Owner, 05/10/2026: RESTRICT. The day's planned or real carer and the
/// previous day's effective carer may change `handoff_time`; an admin may
/// (F-81 tells the parents); anyone else is refused with `HANDOFF_PARTY:`.
/// The wizard's INSERT and the system paths are unchanged.
void handoffPartyTests(GateFixture fx) {
  group('F-99 · who changes a handoff time', () {
    /// D-1 the member's, D the founder's: D is a transition, its ends are the
    /// founder (the day) and the member (D-1).
    Future<int> transition() async {
      final dates = fx.nextFutureDates(2);
      await fx.founder.from('care_schedules').insert([
        {'schedule_date': isoDate(dates[0]), 'scheduled_parent_id': fx.memberProfile.id},
        {
          'schedule_date': isoDate(dates[1]),
          'scheduled_parent_id': fx.founderProfile.id,
          'handoff_time': '18:00:00',
        },
      ]);
      return (await readDay(fx.founder, dates[1])).id;
    }

    Future<String?> timeOf(int id) async =>
        (await readDayById(fx.service, id)).handoffTime;

    /// The client's full-row UPDATE (T-35 echo) with a new time.
    Future<void> setTime(SupabaseClient who, int id, String time) async {
      final day = await readDayById(fx.service, id);
      await saveDay(who, day.copyWith(handoffTime: time));
    }

    test('a third caregiver, at neither end, is refused', () async {
      await fx.ensureThirdMember();
      final third = await fx.ensureThirdClient();
      final id = await transition();
      await expectRejected(
          () => setTime(third, id, '19:30:00'),
          contains: 'HANDOFF_PARTY');
      expect(await timeOf(id), startsWith('18:00'));
    });

    test('the end that hands over (D-1) may change it', () async {
      final id = await transition();
      await setTime(fx.member, id, '19:30:00');
      expect(await timeOf(id), startsWith('19:30'));
    });

    test('an admin may change it on a day that is not theirs', () async {
      // D-1 and D are the member's and the third's: the founder (admin) is
      // at neither end and still passes.
      final third = await fx.ensureThirdMember();
      final dates = fx.nextFutureDates(2);
      await fx.founder.from('care_schedules').insert([
        {'schedule_date': isoDate(dates[0]), 'scheduled_parent_id': fx.memberProfile.id},
        {
          'schedule_date': isoDate(dates[1]),
          'scheduled_parent_id': third.id,
          'handoff_time': '18:00:00',
        },
      ]);
      final id = (await readDay(fx.founder, dates[1])).id;
      await setTime(fx.founder, id, '08:15:00');
      expect(await timeOf(id), startsWith('08:15'));
    });
  });
}
