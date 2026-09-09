import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-56 — the PENDING member: a profile with no auth user, authored by the
/// admin, that the family plans around until the person joins.
///
/// The state is the pair (`user_id`, `left_at`): NULL + NULL is pending, NULL
/// + set is the S-11 tombstone, present + NULL is active. Every rule here is a
/// predicate that used to say `user_id IS NOT NULL` and now has to say WHICH
/// of the two NULL states it means — seats, colours, the join announcement,
/// the swap counterpart, the admin bit, the auto-approval fan-out.
///
/// Every scenario runs in its own throwaway family: adding placeholders to the
/// shared family would move its seat count under every other suite.
void pendingMemberTests(GateFixture fx) {
  Future<Member> profileById(int id) async => Member.fromJson(
      (await fx.service.from('profiles').select().eq('id', id)).single);

  Future<List<Member>> profilesOf(SupabaseClient who) async => [
        for (final row in await who.from('profiles').select())
          Member.fromJson(row)
      ];

  Map<String, dynamic> rowOf(dynamic result) => result is List
      ? Map<String, dynamic>.from(result.first as Map)
      : Map<String, dynamic>.from(result as Map);

  Future<Map<String, dynamic>> addPending(
    SupabaseClient admin,
    String name, {
    String? email,
    String role = 'grandmother',
  }) async =>
      rowOf(await admin.rpc<dynamic>('add_pending_member', params: {
        'p_full_name': name,
        'p_role_id': fx.roleId(role),
        'p_email': ?email,
      }));

  Future<int> addPendingId(SupabaseClient admin, String name) async =>
      (await addPending(admin, name))['profile_id'] as int;

  Future<void> setPlan(int familyId, String plan) => fx.service.rpc<dynamic>(
      'set_family_plan', params: {'p_family_id': familyId, 'p_plan': plan});

  /// What an ANONYMOUS visitor sees for [token] — empty once it is dead.
  Future<List<InviteInfo>> inviteInfo(String token) async {
    final anon = fx.newAnonClient();
    try {
      final result = await anon
          .rpc<dynamic>('get_invite_info', params: {'p_token': token});
      return [
        if (result is List)
          for (final row in result)
            InviteInfo.fromJson(Map<String, dynamic>.from(row as Map))
      ];
    } finally {
      await anon.dispose();
    }
  }

  Future<FamilyInvitation> invitationByToken(String token) async =>
      FamilyInvitation.fromJson((await fx.service
              .from('family_invitations')
              .select()
              .eq('token', token))
          .single);

  Future<List<Map<String, dynamic>>> notificationsFor(int profileId,
          {String? type}) async =>
      [
        for (final row in await fx.service
            .from('notifications')
            .select()
            .eq('recipient_profile_id', profileId))
          if (type == null || row['type'] == type)
            Map<String, dynamic>.from(row)
      ];

  String? nameParam(Map<String, dynamic> notification) =>
      (notification['params'] as Map?)?['name'] as String?;

  group('PendingMemberTests', () {
    test('an admin adds a placeholder: no account, its own colour, invited by '
        'construction, visible to the family only', () async {
      final fam = await fx.createFamily('f56-add');

      final id = await addPendingId(fam.admin, 'E2E Pending One');

      // The NON-admin member reads it through RLS like any family row.
      final seen = (await profilesOf(fam.member)).firstWhere((m) => m.id == id);
      expect(seen.userId, isNull);
      expect(seen.leftAt, isNull);
      expect(seen.isPendingMember, isTrue);
      expect(seen.isActiveMember, isFalse);
      expect(seen.isAdmin, isFalse);
      expect(seen.email, isNull, reason: 'the placeholder carries no e-mail');
      expect(seen.roleId, fx.roleId('grandmother'));
      expect(seen.joinedViaInvite, isTrue,
          reason: 'S-15: the claim shows the INVITEE declaration');
      expect(seen.colorSlot, isNotNull);
      expect(seen.colorSlot, isNot(fam.adminProfile.colorSlot));
      expect(seen.colorSlot, isNot(fam.memberProfile.colorSlot));

      // Another family never sees it.
      final seenByB = await profilesOf(fx.founderB);
      expect(seenByB.map((m) => m.id), isNot(contains(id)));

      // Nobody "joined": the announcement waits for the claim.
      final joined = await notificationsFor(fam.adminProfile.id,
          type: 'member_joined');
      expect(joined.where((n) => nameParam(n) == 'E2E Pending One'), isEmpty);

      // Admin only, and a real name.
      await expectRejected(
        () => fam.member.rpc<dynamic>('add_pending_member', params: {
          'p_full_name': 'E2E Not Allowed',
          'p_role_id': fx.roleId('grandmother'),
        }),
        contains: 'administradores',
      );
      await expectRejected(
        () => addPending(fam.admin, 'X'),
        contains: 'entre 2 e 80',
      );
    });

    test('a placeholder holds a seat and a colour', () async {
      final fam = await fx.createFamily('f56-seat');

      // F-37: the third seat is Premium — for a placeholder too.
      await setPlan(fam.familyId, 'free');
      await expectRejected(
        () => addPending(fam.admin, 'E2E Blocked'),
        contains: 'Premium',
      );

      await setPlan(fam.familyId, 'premium');
      final third = await addPendingId(fam.admin, 'E2E Seat Three');
      final fourth = await addPendingId(fam.admin, 'E2E Seat Four');
      await expectRejected(
        () => addPending(fam.admin, 'E2E Seat Five'),
        contains: 'limite de 4',
      );

      // A legacy invitation counts the placeholders as seats as well.
      await expectRejected(
        () => GateFixture.createInvitation(
            fam.admin, fx.testEmail('f56-seat-legacy'), fx.roleId('aunt')),
        contains: 'limite de 4',
      );

      // Four people, four colours — no placeholder shares one.
      final slots = {
        fam.adminProfile.colorSlot,
        fam.memberProfile.colorSlot,
        (await profileById(third)).colorSlot,
        (await profileById(fourth)).colorSlot,
      };
      expect(slots, {1, 2, 3, 4});
    });

    test('a placeholder is assignable to a day but never a swap counterpart',
        () async {
      final fam = await fx.createFamily('f56-day');
      final pending = await addPendingId(fam.admin, 'E2E Pending Day');

      // The whole point: the admin plans the other parent's days.
      final theirDay = fx.nextFutureDate();
      await fam.admin.from('care_schedules').insert({
        'schedule_date': isoDate(theirDay),
        'scheduled_parent_id': pending,
      });
      expect((await readDay(fam.admin, theirDay)).scheduledParentId, pending);

      // Scenario B on their day: the target would be the placeholder.
      await expectRejected(
        () => fam.member.from('swap_requests').insert({
          'schedule_date': isoDate(theirDay),
          'requesting_profile_id': fam.memberProfile.id,
          'target_profile_id': pending,
          'proposed_actual_parent_id': fam.memberProfile.id,
          'status': 'pending',
        }),
        contains: 'ainda não entrou',
      );

      // Scenario A on my own day: the placeholder as the PROPOSED parent is
      // refused too, even with an active target on the row.
      final myDay = fx.nextFutureDate();
      await fam.admin.from('care_schedules').insert({
        'schedule_date': isoDate(myDay),
        'scheduled_parent_id': fam.memberProfile.id,
      });
      await expectRejected(
        () => fam.member.from('swap_requests').insert({
          'schedule_date': isoDate(myDay),
          'requesting_profile_id': fam.memberProfile.id,
          'target_profile_id': fam.adminProfile.id,
          'proposed_actual_parent_id': pending,
          'status': 'pending',
        }),
        contains: 'ainda não entrou',
      );
    });

    test('a departed member cannot be a swap counterpart either', () async {
      // The gap this rule closes: nothing checked the counterpart before.
      final fam = await fx.createFamily('f56-left');
      final day = fx.nextFutureDate();
      await fam.admin.from('care_schedules').insert({
        'schedule_date': isoDate(day),
        'scheduled_parent_id': fam.adminProfile.id,
      });

      await fx.elevate(fam.memberProfile);
      await fam.member.rpc<dynamic>('request_account_deletion');

      await expectRejected(
        () => fam.admin.from('swap_requests').insert({
          'schedule_date': isoDate(day),
          'requesting_profile_id': fam.adminProfile.id,
          'target_profile_id': fam.memberProfile.id,
          'proposed_actual_parent_id': fam.memberProfile.id,
          'status': 'pending',
        }),
        contains: 'saiu da família',
      );
    });

    test('a placeholder cannot be made admin', () async {
      final fam = await fx.createFamily('f56-adm');
      final pending = await addPendingId(fam.admin, 'E2E Pending Admin');

      // Elevated on purpose, so the call reaches the F-56 guard rather than
      // stopping at the sudo gate.
      await fx.elevate(fam.adminProfile);
      await expectRejected(
        () => fam.admin.rpc<dynamic>('set_member_admin', params: {
          'p_profile_id': pending,
          'p_is_admin': true,
        }),
        contains: 'ainda não entrou',
      );
      expect((await profileById(pending)).isAdmin, isFalse);
    });

    test('the invitation carries the placeholder: name shown, resend keeps '
        'the identity, and the claim attaches to the SAME profile', () async {
      final fam = await fx.createFamily('f56-claim');
      final email = fx.testEmail('f56-claim');

      final born = await addPending(fam.admin, 'E2E Placeholder',
          email: email, role: 'aunt');
      final pending = born['profile_id'] as int;
      final token1 = born['token'] as String;
      expect(born['invitation_id'], isNotNull,
          reason: 'with an e-mail the invitation goes out at once');
      expect((await invitationByToken(token1)).profileId, pending);

      // The visitor sees the name the admin gave them.
      final info = await inviteInfo(token1);
      expect(info, hasLength(1));
      expect(info.single.inviteeName, 'E2E Placeholder');
      expect(info.single.roleName, 'aunt');

      // Resend: a new row for the same profile, the old token dead.
      final resent = rowOf(await fam.admin.rpc<dynamic>('create_invitation',
          params: {
            'p_email': email,
            'p_role_id': fx.roleId('aunt'),
            'p_profile_id': pending,
          }));
      final token2 = resent['token'] as String;
      expect(await inviteInfo(token1), isEmpty);
      expect((await invitationByToken(token2)).profileId, pending);

      // A day planned BEFORE the person exists.
      final day = fx.nextFutureDate();
      await fam.admin.from('care_schedules').insert({
        'schedule_date': isoDate(day),
        'scheduled_parent_id': pending,
      });
      final before = await profileById(pending);
      final seatsBefore =
          (await profilesOf(fam.admin)).where((m) => !m.hasLeft).length;

      // The claim, through the register-invitee shape (handle_new_user).
      final uid = await fx.createInvitedUser(email, token2,
          fullName: 'E2E Claimed');

      final claimed = await profileById(pending);
      expect(claimed.userId, uid, reason: 'the SAME row, now with an account');
      expect(claimed.email, email);
      expect(claimed.fullName, 'E2E Claimed',
          reason: 'the name the person typed wins over the admin\'s');
      expect(claimed.colorSlot, before.colorSlot, reason: 'colour is the seat');
      expect(claimed.roleId, fx.roleId('aunt'));
      expect(claimed.isActiveMember, isTrue);
      expect(claimed.isAdmin, isFalse);
      expect(claimed.joinedViaInvite, isTrue);
      expect(claimed.consentPolicyVersion, PolicyVersions.current,
          reason: 'S-13: consent stamped at the claim');

      // Nothing was duplicated, and the day survived as theirs.
      expect((await profilesOf(fam.admin)).where((m) => !m.hasLeft).length,
          seatsBefore);
      expect((await readDay(fam.admin, day)).scheduledParentId, pending);
      expect((await invitationByToken(token2)).acceptedAt, isNotNull);

      // NOW the family hears about it.
      final joined = await notificationsFor(fam.adminProfile.id,
          type: 'member_joined');
      expect(joined.where((n) => nameParam(n) == 'E2E Claimed'), isNotEmpty);

      // And swaps unlock on the very day that was planned for the placeholder.
      await fam.admin.from('swap_requests').insert({
        'schedule_date': isoDate(day),
        'requesting_profile_id': fam.adminProfile.id,
        'target_profile_id': pending,
        'proposed_actual_parent_id': fam.adminProfile.id,
        'status': 'pending',
      });
      await fx.service
          .from('swap_requests')
          .delete()
          .eq('family_id', fam.familyId)
          .eq('schedule_date', isoDate(day));
    });

    test('the OAuth claim attaches to the placeholder too', () async {
      final fam = await fx.createFamily('f56-oauth');
      final email = await fx.createOauthUser('f56-oauth');
      final client = await fx.signIn(email);
      final uid = client.auth.currentUser!.id;

      final born =
          await addPending(fam.admin, 'E2E OAuth Placeholder', email: email);
      final pending = born['profile_id'] as int;

      await fx.service.rpc<dynamic>('claim_invitation_for_user', params: {
        'p_user_id': uid,
        'p_full_name': 'E2E OAuth Claimed',
        'p_token': born['token'],
        'p_policy_version': PolicyVersions.current,
      });

      final claimed = await profileById(pending);
      expect(claimed.userId, uid);
      expect(claimed.familyId, fam.familyId);
      expect(claimed.fullName, 'E2E OAuth Claimed');
      expect(claimed.email, email);
      expect(claimed.consentPolicyVersion, PolicyVersions.current);

      // The session is a member now: it reads its family.
      final mine = await profilesOf(client);
      expect(mine.map((m) => m.id), contains(fam.adminProfile.id));
    });

    test('removing a placeholder: deleted without history, frozen with it',
        () async {
      final fam = await fx.createFamily('f56-rm');

      // (a) Never planned → the row goes; its invitation is revoked and
      // detached (FK ON DELETE SET NULL).
      final emailA = fx.testEmail('f56-rm-a');
      final bornA =
          await addPending(fam.admin, 'E2E Remove Plain', email: emailA);
      final idA = bornA['profile_id'] as int;
      final tokenA = bornA['token'] as String;

      await fam.admin
          .rpc<dynamic>('remove_pending_member', params: {'p_profile_id': idA});

      expect(await fx.service.from('profiles').select().eq('id', idA), isEmpty);
      final invA = await invitationByToken(tokenA);
      expect(invA.revokedAt, isNotNull);
      expect(invA.profileId, isNull);

      // (b) With a past day → S-11 tombstone: future cleared, past kept,
      // seat and colour freed.
      final idB = await addPendingId(fam.admin, 'E2E Remove History');
      final slotB = (await profileById(idB)).colorSlot;

      final future = fx.nextFutureDate();
      await fam.admin.from('care_schedules').insert({
        'schedule_date': isoDate(future),
        'scheduled_parent_id': idB,
      });
      final past = addDays(today(), -40);
      await fx.service.from('care_schedules').insert({
        'schedule_date': isoDate(past),
        'scheduled_parent_id': idB,
      });

      await fam.admin
          .rpc<dynamic>('remove_pending_member', params: {'p_profile_id': idB});

      final frozen = await profileById(idB);
      expect(frozen.hasLeft, isTrue);
      expect(frozen.userId, isNull);
      expect(frozen.fullName, 'E2E Remove History',
          reason: 'the name stays on the history');
      expect(
          await fx.service
              .from('care_schedules')
              .select()
              .eq('family_id', fam.familyId)
              .eq('schedule_date', isoDate(future)),
          isEmpty);
      final kept = await fx.service
          .from('care_schedules')
          .select()
          .eq('family_id', fam.familyId)
          .eq('schedule_date', isoDate(past));
      expect(kept.single['scheduled_parent_id'], idB);

      // The next placeholder inherits the freed colour (and the seat).
      final idC = await addPendingId(fam.admin, 'E2E Remove Next');
      expect((await profileById(idC)).colorSlot, slotB);

      // A frozen placeholder is frozen like any tombstone.
      await expectRejected(
        () => fam.admin.from('care_schedules').insert({
          'schedule_date': isoDate(fx.nextFutureDate()),
          'scheduled_parent_id': idB,
        }),
        contains: 'saiu da família',
      );

      // Only placeholders leave through here.
      await expectRejected(
        () => fam.admin.rpc<dynamic>('remove_pending_member',
            params: {'p_profile_id': fam.memberProfile.id}),
        contains: 'ainda não entrou',
      );
    });

    test('the auto-approval fan-out skips a placeholder', () async {
      final fam = await fx.createFamily('f56-fanout');
      final pending = await addPendingId(fam.admin, 'E2E Fanout Pending');

      // An expired request between the two ACTIVE members (F-24: > 48 h past
      // the day's midnight in São Paulo), seeded as the system would find it.
      final date = addDays(today(), -5);
      final schedule = (await fx.service
              .from('care_schedules')
              .insert({
                'schedule_date': isoDate(date),
                'scheduled_parent_id': fam.adminProfile.id,
              })
              .select())
          .single;
      await fx.service.from('swap_requests').insert({
        'schedule_date': isoDate(date),
        'schedule_id': schedule['id'],
        'requesting_profile_id': fam.memberProfile.id,
        'target_profile_id': fam.adminProfile.id,
        'proposed_actual_parent_id': fam.memberProfile.id,
        'status': 'pending',
      });

      await fx.service.rpc<dynamic>('auto_approve_expired');

      expect(await notificationsFor(pending), isEmpty,
          reason: 'no session to read it in');
      expect(await notificationsFor(fam.adminProfile.id, type: 'auto_approved'),
          isNotEmpty,
          reason: 'the involved parties still get theirs');
    });

    // ── F-62: a LEGACY invitation gets its placeholder ─────────────────────

    /// The F-37 arithmetic as the RPCs compute it: seats held by everyone
    /// still in the family, plus open placeholder-less invitations that have
    /// not expired. The attach must never move this number for a valid
    /// invitation — that is the "aritmética honesta" the owner chose.
    Future<int> seatsTakenOf(int familyId) async {
      final seated = await fx.service
          .from('profiles')
          .select('id')
          .eq('family_id', familyId)
          .isFilter('left_at', null);
      final legacy = await fx.service
          .from('family_invitations')
          .select('id')
          .eq('family_id', familyId)
          .isFilter('profile_id', null)
          .isFilter('accepted_at', null)
          .isFilter('revoked_at', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String());
      return seated.length + legacy.length;
    }

    Future<int> attach(SupabaseClient who, int invitationId, String name) async =>
        (await who.rpc<dynamic>('attach_pending_member', params: {
          'p_invitation_id': invitationId,
          'p_full_name': name,
        }) as num)
            .toInt();

    /// The two-argument call every pre-F-56 client still makes.
    Future<FamilyInvitation> legacyInvitation(
            ThrowawayFamily fam, String email) async =>
        invitationByToken(await GateFixture.createInvitation(
            fam.admin, email, fx.roleId('aunt')));

    test('F-62: a legacy invitation gets its placeholder — same token, name '
        'shown, assignable, the claim lands on that profile', () async {
      final fam = await fx.createFamily('f62-attach');
      final email = fx.testEmail('f62-attach');

      final legacy = await legacyInvitation(fam, email);
      expect(legacy.profileId, isNull, reason: 'the pre-F-56 shape');
      expect((await inviteInfo(legacy.token)).single.inviteeName, isNull);
      final seatsBefore = await seatsTakenOf(fam.familyId);

      final id = await attach(fam.admin, legacy.id, 'E2E Attached');

      // The SAME row now names a placeholder; the token never changed.
      final after = await invitationByToken(legacy.token);
      expect(after.id, legacy.id);
      expect(after.profileId, id);
      expect(after.revokedAt, isNull);
      final info = await inviteInfo(legacy.token);
      expect(info.single.inviteeName, 'E2E Attached');
      expect(info.single.roleName, 'aunt');

      // The placeholder is one add_pending_member would have made.
      final placeholder = await profileById(id);
      expect(placeholder.isPendingMember, isTrue);
      expect(placeholder.roleId, fx.roleId('aunt'),
          reason: 'the invitation\'s role');
      expect(placeholder.email, isNull,
          reason: 'the e-mail stays on the invitation (LGPD, F-56)');
      expect(placeholder.colorSlot, isNotNull);
      expect(placeholder.joinedViaInvite, isTrue);

      // The seat moved from the invitation to the placeholder: no double count.
      expect(await seatsTakenOf(fam.familyId), seatsBefore);

      // Once is enough.
      await expectRejected(
        () => attach(fam.admin, legacy.id, 'E2E Twice'),
        contains: 'já está ligado',
      );

      // The whole point: a day planned for them before they exist …
      final day = fx.nextFutureDate();
      await fam.admin.from('care_schedules').insert({
        'schedule_date': isoDate(day),
        'scheduled_parent_id': id,
      });

      // … and the link they already hold attaches the account to THAT row.
      final uid = await fx.createInvitedUser(email, legacy.token,
          fullName: 'E2E Attached Claimed');
      final claimed = await profileById(id);
      expect(claimed.userId, uid);
      expect(claimed.fullName, 'E2E Attached Claimed');
      expect(claimed.colorSlot, placeholder.colorSlot);
      expect((await readDay(fam.admin, day)).scheduledParentId, id);
      expect((await invitationByToken(legacy.token)).acceptedAt, isNotNull);
      expect(await seatsTakenOf(fam.familyId), seatsBefore);
    });

    test('F-62: the refusals — non-admin, accepted, revoked, another '
        'family\'s, a bad name', () async {
      final fam = await fx.createFamily('f62-refuse');

      final legacy = await legacyInvitation(fam, fx.testEmail('f62-refuse'));
      await expectRejected(
        () => attach(fam.member, legacy.id, 'E2E Not Admin'),
        contains: 'administradores',
      );
      await expectRejected(
        () => attach(fam.admin, legacy.id, 'X'),
        contains: 'entre 2 e 80',
      );
      // Family B's founder is an admin — of the wrong family.
      await expectRejected(
        () => attach(fx.founderB, legacy.id, 'E2E Wrong Family'),
        contains: 'não encontrado',
      );

      // The member's own invitation was accepted when the family was built.
      final accepted = FamilyInvitation.fromJson((await fx.service
              .from('family_invitations')
              .select()
              .eq('family_id', fam.familyId)
              .not('accepted_at', 'is', null))
          .first);
      await expectRejected(
        () => attach(fam.admin, accepted.id, 'E2E Accepted'),
        contains: 'já foi aceito',
      );

      await fam.admin.rpc<dynamic>('revoke_invitation',
          params: {'p_invitation_id': legacy.id});
      await expectRejected(
        () => attach(fam.admin, legacy.id, 'E2E Revoked'),
        contains: 'revogado',
      );

      // Nothing was created by any of them.
      expect(
          (await profilesOf(fam.admin)).where((m) => m.isPendingMember), isEmpty);
    });

    test('F-62: a VALID invitation attaches with no gate even after a '
        'downgrade; an EXPIRED one is a new seat and goes through it',
        () async {
      final fam = await fx.createFamily('f62-seat');

      // Two legacy invitations issued on Premium: seats 3 and 4.
      await setPlan(fam.familyId, 'premium');
      final valid = await legacyInvitation(fam, fx.testEmail('f62-seat-v'));
      final expired = await legacyInvitation(fam, fx.testEmail('f62-seat-x'));
      await fx.service.from('family_invitations').update({
        'expires_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 1))
            .toIso8601String(),
      }).eq('id', expired.id);
      expect(await seatsTakenOf(fam.familyId), 3,
          reason: 'the expired one holds no seat');

      // Back on free: the valid invitation's seat is already the family's,
      // so attaching it changes nothing and is never refused.
      await setPlan(fam.familyId, 'free');
      await attach(fam.admin, valid.id, 'E2E Seat Valid');
      expect(await seatsTakenOf(fam.familyId), 3);

      // The expired one would be a NEW seat: the F-37 gate speaks.
      await expectRejected(
        () => attach(fam.admin, expired.id, 'E2E Seat Expired'),
        contains: 'Premium',
      );
      expect((await invitationByToken(expired.token)).profileId, isNull);

      // With room for it, it attaches — and outlives its dead token.
      await setPlan(fam.familyId, 'premium');
      final id = await attach(fam.admin, expired.id, 'E2E Seat Expired');
      expect((await invitationByToken(expired.token)).profileId, id);
      expect(await seatsTakenOf(fam.familyId), 4);
      expect(await inviteInfo(expired.token), isEmpty,
          reason: 'expired stays expired — a resend renews the link');
    });
  });
}
