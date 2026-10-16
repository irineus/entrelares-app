import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-07 (PR 5b) — a swap's notification names its child, stamped by ONE
/// trigger (`stamp_notification_child`) for every writer: `params.child` and
/// the `" · name"` suffix on the stored PT-BR title. A single-plan family's
/// requests have no lane, so their notifications are untouched.
void notificationChildTests(GateFixture fx) {
  const agendaFlag = 'feature.child_agenda';

  group('F-07 · the notification names the child', () {
    late ThrowawayFamily fam;
    late String agendaBefore;
    late int childA;

    Future<int> insertDay(DateTime d, {int? child}) async => (await fam.admin
            .from('care_schedules')
            .insert({
              'schedule_date': isoDate(d),
              'scheduled_parent_id': fam.adminProfile.id,
              'child_id': ?child,
            })
            .select('id'))
        .single['id'] as int;

    Future<int> openSwap(DateTime d, int scheduleId) async => (await fam.member
            .from('swap_requests')
            .insert({
              'schedule_date': isoDate(d),
              'schedule_id': scheduleId,
              'requesting_profile_id': fam.memberProfile.id,
              'target_profile_id': fam.adminProfile.id,
              'previous_actual_parent_id': null,
              'proposed_actual_parent_id': fam.memberProfile.id,
              'status': 'pending',
            })
            .select('id'))
        .single['id'] as int;

    /// What the app's composer writes for the approver — minimal return, as
    /// the client does (RLS hides the other member's row).
    Future<Map<String, dynamic>> notify(int swapId) async {
      await fam.member.from('notifications').insert({
        'recipient_profile_id': fam.adminProfile.id,
        'type': 'swap_requested',
        'title': 'Nova solicitação de troca',
        'message': 'mensagem',
        'params': {'date': '2026-10-12', 'name': 'E2E'},
        'swap_request_id': swapId,
        'is_read': false,
      });
      return (await fx.service
              .from('notifications')
              .select('title, params')
              .eq('swap_request_id', swapId))
          .single;
    }

    setUpAll(() async {
      agendaBefore = await readFlag(fx, agendaFlag);
      await writeFlag(fx, agendaFlag, 'true');
      fam = await fx.createFamily('f07notif');
      await fx.service.from('families').update({
        'comp_premium_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', fam.familyId);
      childA = await fam.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Lia'}) as int;
    });

    tearDownAll(() async => writeFlag(fx, agendaFlag, agendaBefore));

    test('a single plan: the notification is untouched', () async {
      final d = fx.nextFutureDate();
      final row = await notify(await openSwap(d, await insertDay(d)));
      expect(row['title'], 'Nova solicitação de troca');
      expect((row['params'] as Map).containsKey('child'), isFalse);
    });

    test("a child's lane: params.child and the heading's suffix", () async {
      await fam.admin
          .rpc<dynamic>('add_child', params: {'p_first_name': 'Theo'});
      await fx.service
          .from('families')
          .update({'schedule_mode': 'per_child'}).eq('id', fam.familyId);
      final d = fx.nextFutureDate();
      final row =
          await notify(await openSwap(d, await insertDay(d, child: childA)));
      expect(row['title'], 'Nova solicitação de troca · Lia');
      expect((row['params'] as Map)['child'], 'Lia');
      expect((row['params'] as Map)['date'], '2026-10-12',
          reason: "the writer's own params survive the stamp");
    });
  });
}
