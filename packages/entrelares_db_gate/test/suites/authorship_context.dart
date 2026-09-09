import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-61 — `activity_logs.context`: the audit trigger stamps, at the instant of
/// every calendar write, whether the assigned parents had an account and
/// whether the write went through only on the admin's authority.
///
/// Why these are gate tests and not unit tests: the stamp is a FACT about the
/// database at write time. The client renders it and must never compute it —
/// after the claim the profile id is the same, so nothing on the client side
/// could tell the two moments apart. Each case here drives the real write
/// path (PostgREST as the family's own sessions) and reads the row the trigger
/// left behind.
///
/// Every scenario runs in its own throwaway family: a placeholder moves the
/// shared family's seat count under every other suite.
void authorshipContextTests(GateFixture fx) {
  Future<int> addPending(SupabaseClient admin, String name) async {
    final result = await admin.rpc<dynamic>('add_pending_member', params: {
      'p_full_name': name,
      'p_role_id': fx.roleId('grandmother'),
    });
    final row = result is List
        ? Map<String, dynamic>.from(result.first as Map)
        : Map<String, dynamic>.from(result as Map);
    return row['profile_id'] as int;
  }

  Future<CareSchedule> seedDay(
      SupabaseClient creator, int scheduledParentId, DateTime date) async {
    final rows = await creator.from('care_schedules').insert({
      'schedule_date': isoDate(date),
      'scheduled_parent_id': scheduledParentId,
    }).select();
    return CareSchedule.fromJson(rows.single);
  }

  /// The trail of one day, oldest first — read with the service client so a
  /// DELETE row (schedule_id NULL) is found by date like the others.
  Future<List<ActivityLog>> trailOf(int familyId, DateTime date) async => [
        for (final row in await fx.service
            .from('activity_logs')
            .select()
            .eq('family_id', familyId)
            .eq('affected_date', isoDate(date))
            .order('created_at', ascending: true))
          ActivityLog.fromJson(row)
      ];

  group('AuthorshipContextTests', () {
    test('a day planned for a placeholder is stamped "no account", and the '
        'stamp survives the claim', () async {
      final fam = await fx.createFamily('f61-pending');
      final pending = await addPending(fam.admin, 'E2E F61 Pending');
      final date = fx.nextFutureDate();

      await seedDay(fam.admin, pending, date);

      final insert = (await trailOf(fam.familyId, date)).single;
      expect(insert.action, 'INSERT');
      expect(insert.performedById, fam.adminProfile.id);
      final ctx = insert.context;
      expect(ctx, isNotNull, reason: 'the trigger stamps every write');
      expect(ctx!.scheduledParentHasAccount, isFalse);
      expect(ctx.actualParentHasAccount, isNull, reason: 'no real parent set');
      expect(ctx.actorIsAdmin, isTrue);
      expect(ctx.adminOverride, isFalse,
          reason: 'planning a day is not an admin-only power');

      // The claim attaches an account to the SAME profile id (F-56). The
      // record must keep saying what was true when the day was written.
      final email = fx.testEmail('f61-claim');
      final invitation = await fam.admin.rpc<dynamic>('create_invitation',
          params: {
            'p_email': email,
            'p_role_id': fx.roleId('grandmother'),
            'p_profile_id': pending,
          });
      final token = (invitation is List
          ? (invitation.first as Map)['token']
          : (invitation as Map)['token']) as String;
      await fx.createInvitedUser(email, token, fullName: 'E2E F61 Claimed');

      final after = (await trailOf(fam.familyId, date)).single;
      expect(after.context!.scheduledParentHasAccount, isFalse,
          reason: 'append-only: the claim rewrites nothing');

      // And a write made AFTER the claim says the person now has an account.
      final later = fx.nextFutureDate();
      await seedDay(fam.admin, pending, later);
      expect((await trailOf(fam.familyId, later)).single.context!
          .scheduledParentHasAccount, isTrue);
    });

    test('a day planned for an active member by a non-admin: account yes, '
        'admin no, override no', () async {
      final fam = await fx.createFamily('f61-active');
      final date = fx.nextFutureDate();

      await seedDay(fam.member, fam.memberProfile.id, date);

      final ctx = (await trailOf(fam.familyId, date)).single.context!;
      expect(ctx.scheduledParentHasAccount, isTrue);
      expect(ctx.actorIsAdmin, isFalse);
      expect(ctx.adminOverride, isFalse);
    });

    test("the admin's direct change of the planned parent (S-09) is stamped "
        'as an override', () async {
      final fam = await fx.createFamily('f61-s09');
      final date = fx.nextFutureDate();
      final day = await seedDay(fam.member, fam.memberProfile.id, date);

      final fresh = await readDayById(fam.admin, day.id);
      await saveDay(
          fam.admin, fresh.copyWith(scheduledParentId: fam.adminProfile.id));

      final trail = await trailOf(fam.familyId, date);
      expect(trail.map((l) => l.action), ['INSERT', 'UPDATE']);
      final update = trail.last.context!;
      expect(update.adminOverride, isTrue);
      expect(update.actorIsAdmin, isTrue);
      expect(update.scheduledParentHasAccount, isTrue);

      // An admin editing something any member may edit is NOT an override:
      // the note changes, the parents stay.
      final again = await readDayById(fam.admin, day.id);
      await saveDay(fam.admin, again.copyWith(notes: 'levar mochila'));
      expect((await trailOf(fam.familyId, date)).last.context!.adminOverride,
          isFalse);
    });

    test('clearing an assigned day is stamped as an override, reading the '
        'assignee from the row that went', () async {
      final fam = await fx.createFamily('f61-clear');
      final pending = await addPending(fam.admin, 'E2E F61 Cleared');
      final date = fx.nextFutureDate();
      final day = await seedDay(fam.admin, pending, date);

      await fam.admin.from('care_schedules').delete().eq('id', day.id);

      final gone = (await trailOf(fam.familyId, date)).last;
      expect(gone.action, 'DELETE');
      expect(gone.newData, isNull);
      expect(gone.context!.adminOverride, isTrue);
      expect(gone.context!.scheduledParentHasAccount, isFalse,
          reason: 'the DELETE still records who the day named');
    });

    test('PR 2: the invitation log names the placeholder it was issued for; '
        'a legacy one carries only the e-mail', () async {
      final fam = await fx.createFamily('f61-invlog');
      final pending = await addPending(fam.admin, 'E2E F61 Invited');
      final email = fx.testEmail('f61-invlog');

      await fam.admin.rpc<dynamic>('create_invitation', params: {
        'p_email': email,
        'p_role_id': fx.roleId('grandmother'),
        'p_profile_id': pending,
      });
      final legacyEmail = fx.testEmail('f61-invlog-legacy');
      await GateFixture.createInvitation(
          fam.admin, legacyEmail, fx.roleId('aunt'));

      final rows = [
        for (final row in await fx.service
            .from('account_logs')
            .select()
            .eq('family_id', fam.familyId)
            .eq('action', 'invitation_created'))
          AccountLog.fromJson(row)
      ];
      final forPending = rows.singleWhere((r) => r.newValue == email);
      expect(forPending.targetProfileId, pending);
      expect(forPending.actorProfileId, fam.adminProfile.id);
      final legacy = rows.singleWhere((r) => r.newValue == legacyEmail);
      expect(legacy.targetProfileId, isNull,
          reason: 'no placeholder behind it — the e-mail is all there is');
    });

    test('an admin applying an approval as the workflow TARGET is not an '
        'override; the auto-approval has no actor at all', () async {
      final fam = await fx.createFamily('f61-target');
      final date = fx.nextFutureDate();
      final day = await seedDay(fam.admin, fam.adminProfile.id, date);

      // The member asks for the admin's day — the admin is the target.
      final request = SwapRequest.fromJson((await fam.member
              .from('swap_requests')
              .insert({
                'schedule_date': isoDate(date),
                'schedule_id': day.id,
                'requesting_profile_id': fam.memberProfile.id,
                'target_profile_id': fam.adminProfile.id,
                'previous_actual_parent_id': null,
                'proposed_actual_parent_id': fam.memberProfile.id,
                'status': 'pending',
              })
              .select())
          .single);

      // The approve flow, verbatim: the target applies the calendar change
      // with a full-row update, then resolves the request.
      final fresh = await readDayById(fam.admin, day.id);
      await saveDay(fam.admin,
          fresh.copyWith(actualParentId: request.proposedActualParentId));
      await fam.admin.from('swap_requests').update({
        'status': 'approved',
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', request.id);

      final applied = (await trailOf(fam.familyId, date)).last.context!;
      expect(applied.adminOverride, isFalse,
          reason: 'inside the two-party workflow, not on admin authority');
      expect(applied.actorIsAdmin, isTrue);
      expect(applied.actualParentHasAccount, isTrue);

      // A system write (service_role) has no actor: both actor facts are
      // absent, not false.
      final systemDate = fx.nextFutureDate();
      await fx.service.from('care_schedules').insert({
        'schedule_date': isoDate(systemDate),
        'scheduled_parent_id': fam.memberProfile.id,
        'family_id': fam.familyId,
      });
      final system = (await trailOf(fam.familyId, systemDate)).single;
      expect(system.performedById, isNull);
      expect(system.context!.actorIsAdmin, isNull);
      expect(system.context!.adminOverride, isNull);
      expect(system.context!.scheduledParentHasAccount, isTrue);
    });
  });
}
