import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

/// F-78 — `unplanned_family_nudges_due()`: a family with no planned day in
/// any lane, `onboarding.unplanned_nudge_hours` (48 by default) after it was
/// created, hears once that the first month is still to plan. Push + in-app,
/// as a third `kind` of F-70's `plan_ending`; once per family, ever.
///
/// The fixture's families are born now, so each test backdates `created_at`
/// through the service client; every call is scoped to the test's family.
void unplannedNudgeTests(GateFixture fx) {
  DateTime spToday() {
    final sp = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return DateTime(sp.year, sp.month, sp.day);
  }

  Future<void> createdHoursAgo(ThrowawayFamily fam, int hours) => fx.service
      .from('families')
      .update({
        'created_at': DateTime.now()
            .toUtc()
            .subtract(Duration(hours: hours))
            .toIso8601String()
      })
      .eq('id', fam.familyId);

  Future<List<Map<String, dynamic>>> run(ThrowawayFamily fam) async {
    final rows = await fx.service.rpc<dynamic>('unplanned_family_nudges_due',
        params: {'p_family_id': fam.familyId});
    return (rows as List).cast<Map<String, dynamic>>();
  }

  Future<List<Map<String, dynamic>>> nudges(int profileId) async =>
      (await fx.service
              .from('notifications')
              .select()
              .eq('recipient_profile_id', profileId)
              .eq('type', 'plan_ending')
              .order('id', ascending: true))
          .cast<Map<String, dynamic>>();

  group('UnplannedNudgeTests', () {
    test('a family with no planned day after 48 h: every member with an '
        'account is told once, in the catalog\'s words', () async {
      final fam = await fx.createFamily('un-told');
      await createdHoursAgo(fam, 72);

      final due = await run(fam);

      expect(due.map((r) => r['profile_id']).toSet(),
          {fam.adminProfile.id, fam.memberProfile.id});
      for (final p in [fam.adminProfile, fam.memberProfile]) {
        final n = await nudges(p.id);
        expect(n, hasLength(1));
        expect(n.single['params'],
            {'kind': 'unplanned', 'date': isoDate(spToday())});
        expect(n.single['title'], 'Falta planejar o primeiro mês');
        expect(
            n.single['message'],
            'O calendário da família ainda não tem nenhum dia planejado. '
            'Comece pelo primeiro mês.');
      }

      expect(await run(fam), isEmpty, reason: 'once per family, ever');
      expect(await nudges(fam.adminProfile.id), hasLength(1));
    });

    test('a family younger than the window hears nothing yet', () async {
      final fam = await fx.createFamily('un-young');
      await createdHoursAgo(fam, 20);

      expect(await run(fam), isEmpty);
      expect(await nudges(fam.adminProfile.id), isEmpty);
    });

    test('one planned day is enough to stay quiet', () async {
      final fam = await fx.createFamily('un-planned');
      await createdHoursAgo(fam, 72);
      await fx.service.from('care_schedules').insert({
        'schedule_date': isoDate(spToday()),
        'scheduled_parent_id': fam.adminProfile.id,
      });

      expect(await run(fam), isEmpty);
    });

    test('a departed member is not told, and a family with no reader is '
        'not stamped', () async {
      final fam = await fx.createFamily('un-gone');
      await createdHoursAgo(fam, 72);
      final now = DateTime.now().toUtc().toIso8601String();
      await fx.service
          .from('profiles')
          .update({'left_at': now}).eq('id', fam.memberProfile.id);

      expect((await run(fam)).map((r) => r['profile_id']).toList(),
          [fam.adminProfile.id]);
      expect(await nudges(fam.memberProfile.id), isEmpty);

      final empty = await fx.createFamily('un-noreader');
      await createdHoursAgo(empty, 72);
      await fx.service.from('profiles').update({'left_at': now}).inFilter(
          'id', [empty.adminProfile.id, empty.memberProfile.id]);
      expect(await run(empty), isEmpty);
      final ledger = await fx.service
          .from('unplanned_family_nudges')
          .select()
          .eq('family_id', empty.familyId);
      expect(ledger, isEmpty);
    });

    test('a family with a pending deletion request is told nothing', () async {
      final fam = await fx.createFamily('un-del');
      await createdHoursAgo(fam, 72);
      await fx.service.from('family_deletion_requests').insert({
        'family_id': fam.familyId,
        'requested_by': fam.adminProfile.id,
        'scheduled_for':
            DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
      });

      expect(await run(fam), isEmpty);
    });

    test('one family\'s nudge never reaches another family', () async {
      final a = await fx.createFamily('un-iso-a');
      final b = await fx.createFamily('un-iso-b');
      await createdHoursAgo(a, 72);
      await createdHoursAgo(b, 72);

      await run(a);

      expect(await nudges(a.adminProfile.id), hasLength(1));
      expect(await nudges(b.adminProfile.id), isEmpty);
    });

    test('no client can run the job or read its ledger', () async {
      final fam = await fx.createFamily('un-rls');
      await createdHoursAgo(fam, 72);

      await expectLater(
          fam.admin.rpc<dynamic>('unplanned_family_nudges_due',
              params: {'p_family_id': fam.familyId}),
          throwsA(anything));
      expect(await nudges(fam.adminProfile.id), isEmpty);

      await run(fam);
      List<dynamic> seen;
      try {
        seen = await fam.admin.from('unplanned_family_nudges').select();
      } catch (_) {
        seen = const [];
      }
      expect(seen, isEmpty);
    });
  });
}
