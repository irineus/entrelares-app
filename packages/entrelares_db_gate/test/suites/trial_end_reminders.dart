import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_billing.dart';

/// F-77 — `trial_end_reminders_due()`: a family whose Premium trial is running
/// out is told so at D-7, at D-1 and once after it ended — only its admins,
/// never a family that already pays, never twice for the same end, and never an
/// "ended" that no D-7/D-1 announced (no backfill, owner 02/10/2026).
///
/// The cron calls the function itself; these call it through the service
/// client, always scoped to the test's own family (`p_family_id`) — the
/// unscoped call stamps and notifies every family on the stack.
void trialEndReminderTests(GateFixture fx) {
  final billing = Billing(fx);

  /// São Paulo's calendar day (fixed UTC-3, like the RPC's timezone).
  DateTime spToday() {
    final sp = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return DateTime(sp.year, sp.month, sp.day);
  }

  /// Noon in São Paulo [n] days from today, as a UTC instant — far from any
  /// midnight, so the SP day the RPC computes is unambiguous.
  DateTime noonIn(int n) {
    final t = spToday();
    return DateTime.utc(t.year, t.month, t.day + n, 15);
  }

  String ddmmyyyy(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> trialEndsAt(ThrowawayFamily fam, DateTime instant) =>
      fx.service
          .from('families')
          .update({'trial_ends_at': instant.toIso8601String()}).eq(
              'id', fam.familyId);

  Future<List<Map<String, dynamic>>> run(ThrowawayFamily fam) async {
    final rows = await fx.service.rpc<dynamic>('trial_end_reminders_due',
        params: {'p_family_id': fam.familyId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> notices(int profileId) async =>
      (await fx.service
              .from('notifications')
              .select()
              .eq('recipient_profile_id', profileId)
              .eq('type', 'premium_trial')
              .order('id', ascending: true))
          .cast<Map<String, dynamic>>();

  group('TrialEndReminderTests', () {
    test('D-7: the admin is told in-app, the non-admin member is not',
        () async {
      final fam = await fx.createFamily('te7');
      final end = noonIn(5);
      await trialEndsAt(fam, end);

      final due = await run(fam);

      expect(due.map((r) => r['profile_id']).toList(), [fam.adminProfile.id]);
      expect(due.single['stage'], 'd7');
      expect(due.single['trial_end'], isoDate(end));

      final n = await notices(fam.adminProfile.id);
      expect(n, hasLength(1));
      expect(n.single['params'], {'kind': 'ending', 'date': isoDate(end)});
      // The stored PT-BR sentence is the catalog's, byte for byte (U-13).
      expect(n.single['title'], 'A avaliação Premium termina em breve');
      expect(
          n.single['message'],
          'A avaliação Premium da família vai até ${ddmmyyyy(end)}. '
          'Para continuar com o Premium depois dessa data, veja o plano.');
      expect(await notices(fam.memberProfile.id), isEmpty,
          reason: 'only an admin can subscribe, on either rail');
    });

    test('every admin is told when the family has two', () async {
      final fam = await fx.createFamily('te-2adm');
      await fx.service
          .from('profiles')
          .update({'is_admin': true}).eq('id', fam.memberProfile.id);
      await trialEndsAt(fam, noonIn(6));

      final due = await run(fam);
      expect(due.map((r) => r['profile_id']).toSet(),
          {fam.adminProfile.id, fam.memberProfile.id});
    });

    test('a re-run the same day sends nothing new', () async {
      final fam = await fx.createFamily('te-rerun');
      await trialEndsAt(fam, noonIn(4));

      await run(fam);
      expect(await run(fam), isEmpty);
      expect(await notices(fam.adminProfile.id), hasLength(1));
    });

    test('D-1 follows the D-7, and a D-7 never comes after the D-1', () async {
      final fam = await fx.createFamily('te1');
      // The end is tomorrow: D-1. A first sighting inside the last day gets
      // the D-1 only — never a late D-7 on top of it.
      await trialEndsAt(fam, noonIn(1));
      expect((await run(fam)).map((r) => r['stage']).toSet(), {'d1'});
      expect(await run(fam), isEmpty);
      expect(await notices(fam.adminProfile.id), hasLength(1));
    });

    test('the end later today is still D-1, not ended', () async {
      final fam = await fx.createFamily('te-today');
      await trialEndsAt(
          fam, DateTime.now().toUtc().add(const Duration(minutes: 30)));
      expect((await run(fam)).map((r) => r['stage']).toSet(), {'d1'});
    });

    test('after an announced end, "ended" is told once', () async {
      final fam = await fx.createFamily('te-end');
      final end = noonIn(-1);
      await trialEndsAt(fam, end);
      // The D-1 of THIS end went out while the trial still ran.
      await fx.service.from('trial_end_reminders').insert({
        'family_id': fam.familyId,
        'trial_ends_at': end.toIso8601String(),
        'stage': 'd1',
      });

      final due = await run(fam);
      expect(due.map((r) => r['stage']).toSet(), {'ended'});
      final n = await notices(fam.adminProfile.id);
      expect(n.single['params'], {'kind': 'ended', 'date': isoDate(end)});
      expect(n.single['title'], 'A avaliação Premium terminou');
      expect(
          n.single['message'],
          'A avaliação Premium da família terminou em ${ddmmyyyy(end)}. '
          'A família segue no plano gratuito, e o Premium pode ser assinado a '
          'qualquer momento.');

      expect(await run(fam), isEmpty);
    });

    test('no backfill: an end nobody announced is never told', () async {
      final fam = await fx.createFamily('te-nobf');
      await trialEndsAt(fam, noonIn(-2));

      expect(await run(fam), isEmpty);
      expect(await notices(fam.adminProfile.id), isEmpty);
    });

    test('far from the end, nothing is sent', () async {
      final fam = await fx.createFamily('te-far');
      await trialEndsAt(fam, noonIn(8));

      expect(await run(fam), isEmpty);
    });

    test('a moved end is a new end: told again from its own D-7', () async {
      final fam = await fx.createFamily('te-move');
      await trialEndsAt(fam, noonIn(3));
      expect((await run(fam)).single['stage'], 'd7');

      final moved = noonIn(6);
      await trialEndsAt(fam, moved);
      final again = await run(fam);
      expect(again.single['stage'], 'd7');
      expect(again.single['trial_end'], isoDate(moved));
      expect(await notices(fam.adminProfile.id), hasLength(2));
    });

    test('a family that pays on either rail is told nothing', () async {
      // Store rail (Play's own free trial included) and the web rail's
      // confirmed payment both land on `plan = premium`.
      final paid = await fx.createFamily('te-paid');
      await trialEndsAt(paid, noonIn(4));
      await billing.setPlan(paid.familyId, 'premium');
      // `set_family_plan('premium')` keeps the trial column; the plan is what
      // excludes.
      await trialEndsAt(paid, noonIn(4));
      expect(await run(paid), isEmpty);

      // F-46: paying DURING the trial keeps `plan = free` until the paid
      // cycle starts — the subscription row is what says it chose.
      for (final status in ['active', 'scheduled', 'overdue']) {
        final fam = await fx.createFamily('te-sub-$status');
        await trialEndsAt(fam, noonIn(4));
        await billing.seed(fam.familyId, 'f77-$status', status: status);
        expect(await run(fam), isEmpty, reason: 'subscription $status');
        await fx.deleteSubscriptionSeed('sub_e2e_f77-$status');
      }
    });

    test('a checkout started and never paid is still told', () async {
      final fam = await fx.createFamily('te-pend');
      await trialEndsAt(fam, noonIn(4));
      await billing.seed(fam.familyId, 'f77-pending');

      expect((await run(fam)).single['stage'], 'd7');
      await fx.deleteSubscriptionSeed('sub_e2e_f77-pending');
    });

    test('a family with a pending deletion request is told nothing', () async {
      final fam = await fx.createFamily('te-del');
      await fx.service.from('family_deletion_requests').insert({
        'family_id': fam.familyId,
        'requested_by': fam.adminProfile.id,
        'scheduled_for':
            DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
      });
      await trialEndsAt(fam, noonIn(4));

      expect(await run(fam), isEmpty);
    });

    test('a departed admin is not told, and no reader means no stamp',
        () async {
      final fam = await fx.createFamily('te-gone');
      await fx.service
          .from('profiles')
          .update({'left_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', fam.adminProfile.id);
      await trialEndsAt(fam, noonIn(4));

      expect(await run(fam), isEmpty);
      final ledger = await fx.service
          .from('trial_end_reminders')
          .select()
          .eq('family_id', fam.familyId);
      expect(ledger, isEmpty,
          reason: 'an admin who claims the seat later must still be told');
    });

    test('one family\'s end never reaches another family', () async {
      final a = await fx.createFamily('te-iso-a');
      final b = await fx.createFamily('te-iso-b');
      await trialEndsAt(a, noonIn(4));
      await trialEndsAt(b, noonIn(4));

      await run(a);

      expect(await notices(a.adminProfile.id), hasLength(1));
      expect(await notices(b.adminProfile.id), isEmpty);
    });

    test('no client can run the job or read its ledger', () async {
      final fam = await fx.createFamily('te-rls');
      await trialEndsAt(fam, noonIn(4));

      await expectLater(
          fam.admin.rpc<dynamic>('trial_end_reminders_due',
              params: {'p_family_id': fam.familyId}),
          throwsA(anything));
      expect(await notices(fam.adminProfile.id), isEmpty,
          reason: 'the refused call must not have written anything');

      await run(fam);
      List<dynamic> seen;
      try {
        seen = await fam.admin.from('trial_end_reminders').select();
      } catch (_) {
        seen = const [];
      }
      expect(seen, isEmpty);
    });
  });
}
