import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-50 (PR 1) — the Visualizador, where it is actually enforced.
///
/// * **dark** — with `feature.viewers` off no viewer invitation is accepted;
/// * **its own caps** — `free_viewers` / `max_viewers`, outside the caregiver
///   seats, and the invitation says what the person is invited as;
/// * **no colour, no admin, no day, no swap** — and it WRITES NOTHING: one
///   guard on every table of the plan, whatever the path;
/// * **the negotiation stays between the parties** — a viewer reads no swap;
/// * **informative notifications only** — the filter at the table;
/// * **promotion one way** — a caregiver seat and a colour; never back;
/// * **exit is a complete delete**.
void viewerTests(GateFixture fx) {
  const flag = 'feature.viewers';
  final today = saoPauloToday();

  Future<Map<String, dynamic>> profileRow(int id) async => (await fx.service
          .from('profiles')
          .select()
          .eq('id', id)
          .limit(1))
      .single;

  Future<String> inviteViewer(SupabaseClient admin, String email) async {
    final rows = await admin.rpc<dynamic>('create_viewer_invitation',
        params: {'p_email': email, 'p_role_id': fx.roleId('grandmother')});
    return (rows as List).single['token'] as String;
  }

  group('F-50 · viewer', () {
    late ThrowawayFamily fam;
    late String flagBefore;
    late String viewerEmail;
    late SupabaseClient viewer;
    late Member viewerProfile;

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
      fam = await fx.createFamily('f50vw');
      await fx.service.from('families').update({
        'plan': 'free',
        'trial_ends_at': null,
        'comp_premium_at': null,
      }).eq('id', fam.familyId);
    });

    tearDownAll(() async => writeFlag(fx, flag, flagBefore));

    test('with the flag OFF no viewer invitation is accepted', () async {
      await writeFlag(fx, flag, 'false');
      try {
        await expectRejected(
            () => inviteViewer(fam.admin, fx.testEmail('f50off')),
            contains: 'ainda não está disponível');
      } finally {
        await writeFlag(fx, flag, 'true');
      }
    });

    test('a member who is not admin cannot invite a viewer', () async {
      await expectRejected(
          () => inviteViewer(fam.member, fx.testEmail('f50nadm')),
          contains: 'Somente administradores');
    });

    test('the invitation says "viewer", and joining makes a viewer', () async {
      viewerEmail = fx.testEmail('f50viewer');
      final token = await inviteViewer(fam.admin, viewerEmail);
      final info = await fx.newAnonClient().rpc<dynamic>('get_invite_info',
          params: {'p_token': token});
      expect((info as List).single['member_type'], 'viewer');

      // A free family with two caregivers is FULL for caregivers — the viewer
      // still joins: it takes no caregiver seat.
      await fx.createInvitedUser(viewerEmail, token, fullName: 'E2E Vó Viewer');
      viewer = await fx.signIn(viewerEmail);
      final row = (await fx.service
              .from('profiles')
              .select()
              .eq('family_id', fam.familyId)
              .eq('email', viewerEmail)
              .limit(1))
          .single;
      viewerProfile = Member.fromJson(row);
      expect(row['membership_type'], 'viewer');
      expect(row['color_slot'], isNull);
      expect(row['is_admin'], isFalse);
      expect(
          await fx.service
              .rpc<dynamic>('seat_count', params: {'p_family_id': fam.familyId}),
          2);
    });

    test('the free plan has its viewer cap; the second invitation is refused',
        () async {
      await expectRejected(
          () => inviteViewer(fam.admin, fx.testEmail('f50second')),
          contains: 'visualizador(es)');
    });

    test('a viewer writes nothing — days, agenda, avisos, relatos, swaps',
        () async {
      await expectRejected(
          () => viewer.from('care_schedules').insert({
                'family_id': fam.familyId,
                'schedule_date': isoDate(addDays(today, 3)),
                'scheduled_parent_id': fam.adminProfile.id,
              }),
          contains: 'Visualizadores acompanham');
      await expectRejected(
          () => viewer.from('swap_requests').insert({
                'requesting_profile_id': viewerProfile.id,
                'target_profile_id': fam.adminProfile.id,
                'schedule_date': isoDate(addDays(today, 3)),
                'proposed_actual_parent_id': fam.adminProfile.id,
              }),
          contains: 'Visualizadores acompanham');
      await expectRejected(
          () => viewer.rpc<dynamic>('rename_family', params: {'p_name': 'x'}));
    });

    test('a viewer is never on a day, and never a swap party', () async {
      await expectRejected(
          () => fx.service.from('care_schedules').insert({
                'family_id': fam.familyId,
                'schedule_date': isoDate(addDays(today, 4)),
                'scheduled_parent_id': viewerProfile.id,
              }),
          contains: 'não pode ser responsável por um dia');

      await fx.service.from('care_schedules').insert({
        'family_id': fam.familyId,
        'schedule_date': isoDate(addDays(today, 5)),
        'scheduled_parent_id': fam.adminProfile.id,
      });
      await expectRejected(
          () => fam.member.from('swap_requests').insert({
                'requesting_profile_id': fam.memberProfile.id,
                'target_profile_id': viewerProfile.id,
                'schedule_date': isoDate(addDays(today, 5)),
                'proposed_actual_parent_id': fam.memberProfile.id,
              }),
          contains: 'não participa de trocas');
    });

    test('a viewer reads the plan, but no swap', () async {
      final days = await viewer
          .from('care_schedules')
          .select('id')
          .eq('schedule_date', isoDate(addDays(today, 5)));
      expect(days, hasLength(1));

      await fam.member.from('swap_requests').insert({
        'requesting_profile_id': fam.memberProfile.id,
        'target_profile_id': fam.adminProfile.id,
        'schedule_date': isoDate(addDays(today, 5)),
        'proposed_actual_parent_id': fam.memberProfile.id,
        'request_message': 'entre nós',
      });
      expect(await fam.admin.from('swap_requests').select('id'), isNotEmpty);
      expect(await viewer.from('swap_requests').select('id'), isEmpty);
    });

    test('a viewer is never admin, and never moves its own category',
        () async {
      await fx.elevate(fam.adminProfile);
      await expectRejected(
          () => fam.admin.rpc<dynamic>('set_member_admin', params: {
                'p_profile_id': viewerProfile.id,
                'p_is_admin': true,
              }),
          contains: 'visualizador não pode ser administrador');
      await expectRejected(
          () => viewer
              .from('profiles')
              .update({'membership_type': 'full'}).eq('id', viewerProfile.id),
          contains: 'Só o administrador promove');
    });

    test('only informative notifications reach a viewer', () async {
      Future<void> send(String type) =>
          fx.service.from('notifications').insert({
            'recipient_profile_id': viewerProfile.id,
            'type': type,
            'title': 't',
            'message': 'm',
            'params': {'date': isoDate(today)},
          });
      await send('swap_requested');
      await send('family_deletion');
      await send('plan_ending');
      await send('swap_family_info');
      final types = (await fx.service
              .from('notifications')
              .select('type')
              .eq('recipient_profile_id', viewerProfile.id))
          .map((n) => n['type'])
          .toSet();
      expect(types, containsAll(['plan_ending', 'swap_family_info']));
      expect(types, isNot(contains('swap_requested')));
      expect(types, isNot(contains('family_deletion')));
    });

    test('promotion needs a caregiver seat: refused on a full free family',
        () async {
      await expectRejected(
          () => fam.admin.rpc<dynamic>('promote_member_to_full',
              params: {'p_profile_id': viewerProfile.id}),
          contains: 'plano gratuito');
    });

    test('Premium: promotion gives a seat and a colour; there is no way back',
        () async {
      await fx.service
          .from('families')
          .update({'comp_premium_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', fam.familyId);
      await fam.admin.rpc<dynamic>('promote_member_to_full',
          params: {'p_profile_id': viewerProfile.id});
      final row = await profileRow(viewerProfile.id);
      expect(row['membership_type'], 'full');
      expect(row['color_slot'], isNotNull);
      await expectRejected(
          () => fx.service
              .from('profiles')
              .update({'membership_type': 'viewer'}).eq('id', viewerProfile.id),
          contains: 'não vira visualizador');
    });

    test('exit is a complete delete — by the admin, or by the viewer itself',
        () async {
      // Premium now: room for two more viewers.
      final byAdminEmail = fx.testEmail('f50rm');
      await fx.createInvitedUser(
          byAdminEmail, await inviteViewer(fam.admin, byAdminEmail),
          fullName: 'E2E Viewer Removed');
      final removed = (await fx.service
              .from('profiles')
              .select('id')
              .eq('email', byAdminEmail)
              .limit(1))
          .single['id'] as int;
      expect(
          await fam.admin
              .rpc<dynamic>('remove_viewer', params: {'p_profile_id': removed}),
          'deleted');
      expect(
          await fx.service.from('profiles').select('id').eq('id', removed),
          isEmpty);

      final selfEmail = fx.testEmail('f50self');
      await fx.createInvitedUser(
          selfEmail, await inviteViewer(fam.admin, selfEmail),
          fullName: 'E2E Viewer Leaves');
      final leaver = await fx.signIn(selfEmail);
      final leaverRow = (await fx.service
              .from('profiles')
              .select()
              .eq('email', selfEmail)
              .limit(1))
          .single;
      await expectRejected(() => leaver.rpc<dynamic>('leave_family_as_viewer'),
          contains: 'ELEVATION_REQUIRED');
      await fx.elevate(Member.fromJson(leaverRow));
      expect(await leaver.rpc<dynamic>('leave_family_as_viewer'), 'deleted');
      expect(
          await fx.service
              .from('profiles')
              .select('id')
              .eq('id', leaverRow['id'] as int),
          isEmpty);
    });
  });
}
