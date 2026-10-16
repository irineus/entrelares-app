import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// S-25 — answering a swap is ONE server transaction, and the target of an
/// open request may write the answer and nothing else.
///
/// The approver's phone used to run four separate writes (the day, the
/// status, the notifications, the e-mail): two people answering at once left
/// the day showing the swap under a request reading "cancelada", a dropped
/// connection left a half-applied answer, and a batch could not be re-run.
/// And while a request was pending, being its target opened S-09, the
/// past-day rule and the delete rules wholesale.
///
/// What this suite pins, on the outputs (`care_schedules`, `swap_requests`,
/// `notifications`), never on the function's text:
/// * an approval applies exactly the proposal, closes the request and inserts
///   only the notices that belong to it — and a retry changes nothing;
/// * approve × cancel at the same instant ends in ONE coherent state;
/// * through PostgREST the target can still write exactly the proposal (the
///   Android builds in Production do that), and nothing else;
/// * a revert's approval restores the day on the server.
void swapAnswerTests(GateFixture fx) {
  group('S-25 · swap answers', () {
    late ThrowawayFamily fam;
    late ThrowawayFamily other;

    Future<Map<String, dynamic>> plan(DateTime date) async => (await fam.admin
            .from('care_schedules')
            .insert({
              'schedule_date': isoDate(date),
              'scheduled_parent_id': fam.adminProfile.id,
              'notes': 'S-25 base',
            })
            .select())
        .single;

    /// The member asks to take the admin's day — the admin is the target.
    Future<int> request(Map<String, dynamic> day) async => (await fam.member
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
            .select('id'))
        .single['id'] as int;

    Future<Map<String, dynamic>> requestRow(int id) async =>
        (await fx.service.from('swap_requests').select().eq('id', id)).single;

    Future<Map<String, dynamic>> dayRow(int id) async =>
        (await fx.service.from('care_schedules').select().eq('id', id)).single;

    Future<List<Map<String, dynamic>>> notices(int requestId) async =>
        (await fx.service
                .from('notifications')
                .select()
                .eq('swap_request_id', requestId))
            .cast<Map<String, dynamic>>();

    Map<String, dynamic> draft(int recipient, String type) => {
          'recipient_profile_id': recipient,
          'type': type,
          'title': 'S-25 $type',
          'message': 'S-25 mensagem',
          'params': {'date': '2026-10-05'},
        };

    Future<dynamic> rpc(SupabaseClient who, String name,
            Map<String, dynamic> params) =>
        who.rpc<dynamic>(name, params: params);

    setUpAll(() async {
      fam = await fx.createFamily('s25ans');
      other = await fx.createFamily('s25oth');
    });

    test('an approval applies exactly the proposal, closes the request and '
        'inserts only its own notices; a retry changes nothing', () async {
      final day = await plan(fx.nextFutureDate());
      final id = await request(day);

      final result = await rpc(fam.admin, 'approve_swap_request', {
        'p_id': id,
        'p_note': '  combinado  ',
        'p_notifications': [
          draft(fam.memberProfile.id, 'swap_approved'),
          draft(fam.adminProfile.id, 'swap_approved_self'),
          // Not this answer's type, and not this family: both dropped.
          draft(fam.memberProfile.id, 'billing'),
          draft(other.adminProfile.id, 'swap_approved'),
        ],
      }) as Map;
      expect(result['status'], 'approved');
      expect(result['changed'], isTrue);

      final after = await dayRow(day['id'] as int);
      expect(after['actual_parent_id'], fam.memberProfile.id);
      expect(after['scheduled_parent_id'], fam.adminProfile.id);
      expect(after['notes'], 'S-25 base');
      final req = await requestRow(id);
      expect(req['status'], 'approved');
      expect(req['approval_note'], 'combinado');
      expect(req['resolved_by'], 'user');
      expect(req['resolved_at'], isNotNull);

      final sent = await notices(id);
      expect({for (final n in sent) '${n['recipient_profile_id']}:${n['type']}'},
          {'${fam.memberProfile.id}:swap_approved',
           '${fam.adminProfile.id}:swap_approved_self'});

      final again = await rpc(fam.admin, 'approve_swap_request',
          {'p_id': id, 'p_notifications': [draft(fam.memberProfile.id, 'swap_approved')]}) as Map;
      expect(again['changed'], isFalse, reason: 'a retried batch completes');
      expect(await notices(id), hasLength(2), reason: 'and sends nothing twice');
    });

    test('only the target answers, only the requester cancels', () async {
      final day = await plan(fx.nextFutureDate());
      final id = await request(day);
      await expectRejected(
          () => rpc(fam.member, 'approve_swap_request', {'p_id': id}),
          contains: 'Só quem recebeu');
      await expectRejected(
          () => rpc(fam.admin, 'cancel_swap_request', {'p_id': id}),
          contains: 'Só quem fez');
      await expectRejected(
          () => rpc(other.admin, 'reject_swap_request', {'p_id': id}),
          contains: 'não encontrada');
      expect((await requestRow(id))['status'], 'pending');
    });

    test('a request answered otherwise refuses the late answer', () async {
      final day = await plan(fx.nextFutureDate());
      final id = await request(day);
      final cancelled = await rpc(fam.member, 'cancel_swap_request', {
        'p_id': id,
        'p_notifications': [draft(fam.adminProfile.id, 'swap_cancelled')],
      }) as Map;
      expect(cancelled['status'], 'cancelled');
      await expectRejected(
          () => rpc(fam.admin, 'approve_swap_request', {'p_id': id}),
          contains: 'não está mais pendente');
      expect((await dayRow(day['id'] as int))['actual_parent_id'], isNull);
    });

    test('approve and cancel at the same instant end in ONE state', () async {
      final day = await plan(fx.nextFutureDate());
      final id = await request(day);

      final outcomes = await Future.wait([
        rpc(fam.admin, 'approve_swap_request', {'p_id': id})
            .then((_) => 'approved', onError: (Object e) => 'lost: $e'),
        rpc(fam.member, 'cancel_swap_request', {'p_id': id})
            .then((_) => 'cancelled', onError: (Object e) => 'lost: $e'),
      ]);
      final winners = outcomes.where((o) => !o.startsWith('lost')).toList();
      expect(winners, hasLength(1), reason: '$outcomes');

      final req = await requestRow(id);
      final actual = (await dayRow(day['id'] as int))['actual_parent_id'];
      if (req['status'] == 'approved') {
        expect(actual, fam.memberProfile.id);
      } else {
        expect(req['status'], 'cancelled');
        expect(actual, isNull, reason: 'a cancelled request never swaps the day');
      }
    });

    test('while pending, the target writes the proposal and nothing else',
        () async {
      final day = await plan(fx.nextFutureDate());
      final id = await request(day);
      final dayId = day['id'] as int;

      Future<void> write(Map<String, dynamic> change) async {
        final current = await readDayById(fam.admin, dayId);
        final json = current.toUpdateJson()..addAll(change);
        await fam.admin.from('care_schedules').update(json).eq('id', dayId);
      }

      const refusal = 'só pode aplicar o que foi pedido';
      // Another real carer than the proposal.
      await expectRejected(
          () => write({'actual_parent_id': fam.adminProfile.id}),
          contains: refusal);
      // The proposal plus a change of the planned carer, or of the note.
      await expectRejected(
          () => write({
                'actual_parent_id': fam.memberProfile.id,
                'scheduled_parent_id': fam.memberProfile.id,
              }),
          contains: refusal);
      await expectRejected(
          () => write({
                'actual_parent_id': fam.memberProfile.id,
                'notes': 'reescrito pelo alvo',
              }),
          contains: refusal);
      // Delete.
      await expectRejected(
          () => fam.admin.from('care_schedules').delete().eq('id', dayId),
          contains: refusal);
      final untouched = await dayRow(dayId);
      expect(untouched['actual_parent_id'], isNull);
      expect(untouched['notes'], 'S-25 base');

      // The Android builds in Production: exactly the proposal, then the
      // status — still works.
      await write({'actual_parent_id': fam.memberProfile.id});
      await fam.admin
          .from('swap_requests')
          .update({'status': 'approved'}).eq('id', id);
      expect((await dayRow(dayId))['actual_parent_id'], fam.memberProfile.id);
      expect((await requestRow(id))['status'], 'approved');
    });

    test("a revert's approval restores the day on the server", () async {
      final day = await plan(fx.nextFutureDate());
      final id = await request(day);
      await rpc(fam.admin, 'approve_swap_request', {'p_id': id});
      final dayId = day['id'] as int;
      expect((await dayRow(dayId))['actual_parent_id'], fam.memberProfile.id);

      // The admin asks to undo; the member (the swap's real carer) answers.
      final revertId = (await fam.admin
              .from('swap_requests')
              .insert({
                'schedule_date': day['schedule_date'],
                'schedule_id': dayId,
                'requesting_profile_id': fam.adminProfile.id,
                'target_profile_id': fam.memberProfile.id,
                'previous_actual_parent_id': fam.memberProfile.id,
                'proposed_actual_parent_id': fam.adminProfile.id,
                'status': 'revert_pending',
              })
              .select('id'))
          .single['id'] as int;

      // While it is open, the member cannot rewrite the day another way.
      final current = await readDayById(fam.member, dayId);
      await expectRejected(
          () => fam.member
              .from('care_schedules')
              .update(current.toUpdateJson()
                ..['scheduled_parent_id'] = fam.memberProfile.id)
              .eq('id', dayId),
          contains: 'só pode aplicar o que foi pedido');

      final result = await rpc(fam.member, 'approve_swap_request', {
        'p_id': revertId,
        'p_notifications': [draft(fam.adminProfile.id, 'revert_approved')],
      }) as Map;
      expect(result['status'], 'revert_approved');
      // No pre-edit snapshot on this request: the swap is cleared, the plan
      // stays.
      final restored = await dayRow(dayId);
      expect(restored['actual_parent_id'], isNull);
      expect(restored['scheduled_parent_id'], fam.adminProfile.id);
      expect(await notices(revertId), hasLength(1));
    });

    test('a rejection keeps the day and carries the reason', () async {
      final day = await plan(fx.nextFutureDate());
      final id = await request(day);
      final result = await rpc(fam.admin, 'reject_swap_request', {
        'p_id': id,
        'p_reason': 'não dá',
        'p_notifications': [draft(fam.memberProfile.id, 'swap_rejected')],
      }) as Map;
      expect(result['status'], 'rejected');
      final req = await requestRow(id);
      expect(req['rejection_reason'], 'não dá');
      expect((await dayRow(day['id'] as int))['actual_parent_id'], isNull);
      expect(await notices(id), hasLength(1));
    });
  });
}
