import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-94 — an unanswered swap request is told on the EVE of its day.
///
/// Owner, 05/10/2026: push + in-app at 19:00 (São Paulo) of the day before,
/// to whoever must answer, once per request, only while it is pending; a
/// request created after that 19:00 gets none. `swap_eve_reminders_due(p_now)`
/// is what the 19:00 cron runs; the gate hands it the instant to judge, so
/// the dates stay the allocator's (ten days out and beyond) and nothing here
/// depends on the hour the gate happens to run.
void swapEveReminderTests(GateFixture fx) {
  group('F-94 · eve reminder', () {
    late ThrowawayFamily fam;

    setUpAll(() async {
      fam = await fx.createFamily('f94eve');
    });

    Future<Map<String, dynamic>> plan(DateTime date) async => (await fam.admin
            .from('care_schedules')
            .insert({
              'schedule_date': isoDate(date),
              'scheduled_parent_id': fam.adminProfile.id,
            })
            .select())
        .single;

    /// The admin asks the member to keep the admin's day — the member answers.
    Future<int> request(Map<String, dynamic> day) async => (await fam.admin
            .from('swap_requests')
            .insert({
              'schedule_date': day['schedule_date'],
              'schedule_id': day['id'],
              'requesting_profile_id': fam.adminProfile.id,
              'target_profile_id': fam.memberProfile.id,
              'previous_actual_parent_id': null,
              'proposed_actual_parent_id': fam.memberProfile.id,
              'status': 'pending',
            })
            .select('id'))
        .single['id'] as int;

    /// 19:30 in São Paulo (UTC-3) on the eve of [day] — just after the cron.
    String eveOf(DateTime day) {
      final eve = DateTime.utc(day.year, day.month, day.day - 1, 22, 30);
      return eve.toIso8601String();
    }

    Future<List<int>> run(String pNow) async => [
          for (final r in (await fx.service.rpc<dynamic>(
              'swap_eve_reminders_due',
              params: {'p_now': pNow})) as List)
            (r as Map)['swap_request_id'] as int
        ];

    Future<List<Map<String, dynamic>>> eveNotices(int requestId) async =>
        (await fx.service
                .from('notifications')
                .select()
                .eq('swap_request_id', requestId)
                .eq('type', 'auto_reminder'))
            .cast<Map<String, dynamic>>()
            .where((n) => (n['params'] as Map?)?['kind'] == 'eve')
            .toList();

    test('the target is told at 19:00 of the eve, once, with the requester '
        'and the day', () async {
      final date = fx.nextFutureDate();
      final id = await request(await plan(date));

      expect(await run(eveOf(date)), contains(id));
      final sent = await eveNotices(id);
      expect(sent, hasLength(1));
      final n = sent.single;
      expect(n['recipient_profile_id'], fam.memberProfile.id);
      expect((n['params'] as Map)['date'], isoDate(date));
      expect((n['params'] as Map)['name'], isNotEmpty);
      expect(n['title'], 'Pedido para amanhã sem resposta');
      expect(n['message'], contains('para amanhã'));

      // Once per request: the cron running again (or late) sends nothing.
      expect(await run(eveOf(date)), isNot(contains(id)));
      expect(await eveNotices(id), hasLength(1));
    });

    test('only the eve: two days before, nothing', () async {
      final date = fx.nextFutureDate();
      final id = await request(await plan(date));
      final early = DateTime.utc(date.year, date.month, date.day - 2, 22, 30)
          .toIso8601String();
      expect(await run(early), isNot(contains(id)));
      expect(await eveNotices(id), isEmpty);
    });

    test('an answered request is not reminded', () async {
      final date = fx.nextFutureDate();
      final id = await request(await plan(date));
      await fam.member.rpc<dynamic>('reject_swap_request',
          params: {'p_id': id, 'p_reason': null, 'p_notifications': []});
      expect(await run(eveOf(date)), isNot(contains(id)));
      expect(await eveNotices(id), isEmpty);
    });

    test('nobody but the service role runs it', () async {
      await expectRejected(() => fam.admin.rpc<dynamic>(
          'swap_eve_reminders_due',
          params: {'p_now': DateTime.now().toUtc().toIso8601String()}));
      await expectRejected(
          () => fam.admin.from('swap_eve_reminders').select('swap_request_id'));
    });
  });
}
