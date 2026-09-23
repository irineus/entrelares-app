import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

/// F-70 — `plan_end_reminders_due()`: a family whose plan runs out is told
/// so, at D-30, at D-7 and once after it ended, and never twice for the same
/// end. The Edge Function is a thin wrapper that only sends the e-mail twins,
/// so these call the RPC directly through the service client — always scoped
/// to the test's own throwaway family (`p_family_id`), because the unscoped
/// call stamps and notifies every family in the shared dev project.
///
/// Days are seeded relative to São Paulo's today — the RPC's clock — and the
/// service client bypasses the day-protection trigger, which is what makes a
/// past day seedable at all.
void planEndReminderTests(GateFixture fx) {
  /// São Paulo's calendar day (fixed UTC-3, like the RPC's timezone).
  DateTime spToday() {
    final sp = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return DateTime(sp.year, sp.month, sp.day);
  }

  DateTime inDays(int n) {
    final t = spToday();
    return DateTime(t.year, t.month, t.day + n);
  }

  Future<void> plan(ThrowawayFamily fam, List<DateTime> days) async {
    await fx.service.from('care_schedules').insert([
      for (final d in days)
        {
          'schedule_date': isoDate(d),
          'scheduled_parent_id': fam.adminProfile.id,
        }
    ]);
  }

  Future<List<Map<String, dynamic>>> run(ThrowawayFamily fam) async {
    final rows = await fx.service.rpc<dynamic>('plan_end_reminders_due',
        params: {'p_family_id': fam.familyId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> notices(int profileId) async =>
      (await fx.service
              .from('notifications')
              .select()
              .eq('recipient_profile_id', profileId)
              .eq('type', 'plan_ending')
              .order('id'))
          .cast<Map<String, dynamic>>();

  group('PlanEndReminderTests', () {
    test('D-30: every active member is told in-app, with no e-mail', () async {
      final fam = await fx.createFamily('pe30');
      final last = inDays(25);
      await plan(fam, [inDays(3), last]);

      final due = await run(fam);

      expect(due, hasLength(2));
      expect(due.map((r) => r['profile_id']).toSet(),
          {fam.adminProfile.id, fam.memberProfile.id});
      expect(due.every((r) => r['stage'] == 'd30'), isTrue);
      expect(due.every((r) => r['send_email'] == false), isTrue,
          reason: 'the e-mail twin is for D-7 and ended only');

      for (final p in [fam.adminProfile, fam.memberProfile]) {
        final n = await notices(p.id);
        expect(n, hasLength(1));
        expect(n.single['params'], {'kind': 'ending', 'date': isoDate(last)});
        // The stored PT-BR sentence is the catalog's, byte for byte (U-13).
        expect(n.single['title'], 'O planejamento termina em breve');
        expect(
            n.single['message'],
            'O planejamento da família vai até '
            '${last.day.toString().padLeft(2, '0')}/'
            '${last.month.toString().padLeft(2, '0')}/${last.year}. '
            'Planeje os próximos meses.');
      }
    });

    test('a re-run the same day sends nothing new', () async {
      final fam = await fx.createFamily('pe-rerun');
      await plan(fam, [inDays(20)]);

      await run(fam);
      expect(await run(fam), isEmpty);
      expect(await run(fam), isEmpty);

      expect(await notices(fam.adminProfile.id), hasLength(1));
    });

    test('D-7 asks for the e-mail, and a family first seen inside the last '
        'week gets no late D-30', () async {
      final fam = await fx.createFamily('pe7');
      await plan(fam, [inDays(5)]);

      final due = await run(fam);
      expect(due.map((r) => r['stage']).toSet(), {'d7'});
      expect(due.every((r) => r['send_email'] == true), isTrue);

      expect(await run(fam), isEmpty);
      expect(await notices(fam.adminProfile.id), hasLength(1));
    });

    test('the last day being today is still D-7, not ended', () async {
      final fam = await fx.createFamily('pe-today');
      await plan(fam, [inDays(0)]);

      final due = await run(fam);
      expect(due.map((r) => r['stage']).toSet(), {'d7'});
    });

    test('a plan that already ended is told once, with the e-mail', () async {
      final fam = await fx.createFamily('pe-end');
      final last = inDays(-12);
      await plan(fam, [inDays(-20), last]);

      final due = await run(fam);
      expect(due.map((r) => r['stage']).toSet(), {'ended'});
      expect(due.every((r) => r['send_email'] == true), isTrue);
      final n = await notices(fam.memberProfile.id);
      expect(n.single['params'], {'kind': 'ended', 'date': isoDate(last)});
      expect(n.single['title'], 'O planejamento terminou');

      expect(await run(fam), isEmpty);
    });

    test('far from the end, nothing is sent', () async {
      final fam = await fx.createFamily('pe-far');
      await plan(fam, [inDays(31)]);

      expect(await run(fam), isEmpty);
      expect(await notices(fam.adminProfile.id), isEmpty);
    });

    test('a family that never planned is not this trigger', () async {
      final fam = await fx.createFamily('pe-none');
      expect(await run(fam), isEmpty);
    });

    test('planning further moves the end: the old D-7 never comes, the new '
        'cycle starts at its own D-30', () async {
      final fam = await fx.createFamily('pe-ext');
      await plan(fam, [inDays(20)]);
      expect((await run(fam)).map((r) => r['stage']).toSet(), {'d30'});

      // The family plans on; the end is now 60 days away — nothing to say.
      await plan(fam, [inDays(60)]);
      expect(await run(fam), isEmpty);

      // It plans only a little further instead: a NEW end inside 30 days is
      // a new plan end, told once more.
      final fam2 = await fx.createFamily('pe-ext2');
      await plan(fam2, [inDays(20)]);
      await run(fam2);
      final newLast = inDays(28);
      await plan(fam2, [newLast]);
      final again = await run(fam2);
      expect(again.map((r) => r['plan_end']).toSet(), {isoDate(newLast)});
      expect(await notices(fam2.adminProfile.id), hasLength(2));
    });

    test('a departed member and a pending placeholder are not told', () async {
      final fam = await fx.createFamily('pe-who');
      await fx.service.rpc<dynamic>('set_family_plan',
          params: {'p_family_id': fam.familyId, 'p_plan': 'premium'});
      final pending = await fam.admin.rpc<dynamic>('add_pending_member',
          params: {'p_full_name': 'Vó Pendente', 'p_role_id': fx.roleId('grandmother')});
      final pendingId = ((pending is List ? pending.first : pending)
          as Map)['profile_id'] as int;
      await fx.service
          .from('profiles')
          .update({'left_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', fam.memberProfile.id);
      await plan(fam, [inDays(10)]);

      final due = await run(fam);

      expect(due.map((r) => r['profile_id']).toList(), [fam.adminProfile.id]);
      expect(await notices(fam.memberProfile.id), isEmpty);
      expect(await notices(pendingId), isEmpty);
    });

    test('a family with a pending deletion request is told nothing', () async {
      final fam = await fx.createFamily('pe-del');
      await fx.service.from('family_deletion_requests').insert({
        'family_id': fam.familyId,
        'requested_by': fam.adminProfile.id,
        'scheduled_for':
            DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
      });
      await plan(fam, [inDays(10)]);

      expect(await run(fam), isEmpty);
      expect(await notices(fam.memberProfile.id), isEmpty);
    });

    test('one family\'s end never reaches another family', () async {
      final a = await fx.createFamily('pe-iso-a');
      final b = await fx.createFamily('pe-iso-b');
      await plan(a, [inDays(10)]);
      await plan(b, [inDays(10)]);

      await run(a);

      expect(await notices(a.adminProfile.id), hasLength(1));
      expect(await notices(b.adminProfile.id), isEmpty);
      expect(await notices(b.memberProfile.id), isEmpty);
    });

    test('no client can run the job or read its ledger', () async {
      final fam = await fx.createFamily('pe-rls');
      await plan(fam, [inDays(10)]);

      await expectLater(
          fam.admin.rpc<dynamic>('plan_end_reminders_due',
              params: {'p_family_id': fam.familyId}),
          throwsA(anything));
      expect(await notices(fam.adminProfile.id), isEmpty,
          reason: 'the refused call must not have written anything');

      // The job runs, so the ledger holds this family's row — and the
      // family's own session still cannot see it (no grant, no policy).
      await run(fam);
      List<dynamic> seen;
      try {
        seen = await fam.admin.from('plan_end_reminders').select();
      } catch (_) {
        seen = const [];
      }
      expect(seen, isEmpty);
    });
  });
}
