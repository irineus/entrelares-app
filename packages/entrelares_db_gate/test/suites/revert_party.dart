import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// S-26 — a revert is opened only by the day's planned or actual carer.
///
/// F-28 forbade scenario C on swaps and nothing forbade it on reverts: a third
/// caregiver could undo an approved swap between two other people, with the
/// planned parent as the approver, and the actual carer lost the day without
/// being asked. The database refuses it now (`enforce_revert_party`).
void revertPartyTests(GateFixture fx) {
  group('S-26 · who may open a revert', () {
    /// The founder's day, swapped (approved) to the member.
    Future<CareSchedule> swappedDay() async {
      final date = fx.nextFutureDate();
      await fx.founder.from('care_schedules').insert({
        'schedule_date': isoDate(date),
        'scheduled_parent_id': fx.founderProfile.id,
      });
      final day = await readDay(fx.founder, date);
      final id = (await fx.member
              .from('swap_requests')
              .insert({
                'schedule_date': isoDate(date),
                'schedule_id': day.id,
                'requesting_profile_id': fx.memberProfile.id,
                'target_profile_id': fx.founderProfile.id,
                'previous_actual_parent_id': null,
                'proposed_actual_parent_id': fx.memberProfile.id,
                'status': 'pending',
              })
              .select('id'))
          .single['id'] as int;
      await fx.founder.rpc<dynamic>('approve_swap_request', params: {'p_id': id});
      final swapped = await readDayById(fx.service, day.id);
      expect(swapped.actualParentId, fx.memberProfile.id);
      return swapped;
    }

    Map<String, dynamic> revert(CareSchedule day, int requester, int target) => {
          'schedule_date': isoDate(day.scheduleDate),
          'schedule_id': day.id,
          'requesting_profile_id': requester,
          'target_profile_id': target,
          'previous_actual_parent_id': fx.memberProfile.id,
          'proposed_actual_parent_id': fx.founderProfile.id,
          'status': 'revert_pending',
        };

    test('a third caregiver is refused — the swap is not theirs', () async {
      final third = await fx.ensureThirdMember();
      final thirdClient = await fx.ensureThirdClient();
      final day = await swappedDay();

      await expectRejected(
          () => thirdClient
              .from('swap_requests')
              .insert(revert(day, third.id, fx.founderProfile.id)),
          contains: 'desfazer a troca');
      final open = await fx.service
          .from('swap_requests')
          .select('id')
          .eq('schedule_id', day.id)
          .eq('status', 'revert_pending');
      expect(open, isEmpty);
    });

    test('the actual carer may ask — and so may the planned one', () async {
      final day = await swappedDay();
      final byActual = (await fx.member
              .from('swap_requests')
              .insert(revert(day, fx.memberProfile.id, fx.founderProfile.id))
              .select('id'))
          .single['id'] as int;
      await fx.member
          .rpc<dynamic>('cancel_swap_request', params: {'p_id': byActual});

      final byPlanned = (await fx.founder
              .from('swap_requests')
              .insert(revert(day, fx.founderProfile.id, fx.memberProfile.id))
              .select('id'))
          .single['id'] as int;
      await fx.founder
          .rpc<dynamic>('cancel_swap_request', params: {'p_id': byPlanned});
    });
  });
}
