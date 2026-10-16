import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-88 (PR 2) — "baixa o Entrelares, te convidei": the parent opens the app,
/// founds a family of their own, and the invitation then answers "este e-mail
/// já possui cadastro". The owner's decision (04/10/2026): a founder whose
/// VERIFIED e-mail has an open invitation, alone in a family with nothing
/// planned, is offered the way in — and the empty family is discarded.
///
/// Pinned on the outputs (`profiles`, `families`, `family_invitations`):
/// * the offer reaches exactly that founder, and nobody else;
/// * accepting moves the founder into the inviting family with the invited
///   role, discards the empty family and keeps the session's account;
/// * a family with anything in it is never discarded;
/// * an invitation already accepted says so, apart from unusable ones.
void pendingInvitationOfferTests(GateFixture fx) {
  group('F-88 · pending invitation offer', () {
    late ThrowawayFamily inviting;
    var families = 0;

    Future<String> invite(String email) => GateFixture.createInvitation(
        inviting.admin, email, fx.roleId('father'));

    // One inviting family per test: each invitation holds a seat, and the
    // caregiver cap would otherwise refuse the fourth test's.
    setUp(() async {
      inviting = await fx.createFamily('f88inv${families++}');
      // A third caregiver needs the Premium seats.
      await fx.service.from('families').update({
        'comp_premium_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', inviting.familyId);
    });

    test('the offer reaches a solo founder whose e-mail was invited', () async {
      // The real order: the ex invites first, then the parent opens the
      // app and founds a family of their own.
      final token = await invite(fx.testEmail('f88a-solo'));
      final solo = await fx.createSoloFounder('f88a');

      final rows = await solo.client.rpc<dynamic>('my_pending_invitation')
          as List;
      expect(rows, hasLength(1));
      expect(rows.single['token'], token);
      expect(rows.single['family_name'], isNotEmpty);
      expect(rows.single['inviter_name'], inviting.adminProfile.fullName);

      // A member of a family that has someone else is offered nothing.
      final none =
          await inviting.member.rpc<dynamic>('my_pending_invitation') as List;
      expect(none, isEmpty);
    });

    test('accepting moves the founder in and discards the empty family',
        () async {
      // The real order: the ex invites first, then the parent opens the
      // app and founds a family of their own.
      final token = await invite(fx.testEmail('f88b-solo'));
      final solo = await fx.createSoloFounder('f88b');
      final oldFamily = solo.profile.familyId!;

      await solo.client.rpc<dynamic>('join_invitation_from_empty_family',
          params: {
            'p_token': token,
            'p_policy_version': PolicyVersions.current,
          });

      final me = (await fx.service
              .from('profiles')
              .select('family_id, role_id, user_id, left_at')
              .eq('email', solo.email)
              .isFilter('left_at', null))
          .single;
      expect(me['family_id'], inviting.familyId);
      expect(me['role_id'], fx.roleId('father'));
      expect(me['user_id'], isNotNull, reason: 'the session account survives');
      expect(
          await fx.service.from('families').select('id').eq('id', oldFamily),
          isEmpty,
          reason: 'the empty family is discarded');
      final inv = (await fx.service
              .from('family_invitations')
              .select('accepted_at')
              .eq('token', token))
          .single;
      expect(inv['accepted_at'], isNotNull);

      // The same session now reads its new family.
      final family = await solo.client.from('families').select('id');
      expect(family.single['id'], inviting.familyId);
    });

    test('a family with a planned day is never discarded', () async {
      // The real order: the ex invites first, then the parent opens the
      // app and founds a family of their own.
      final token = await invite(fx.testEmail('f88c-solo'));
      final solo = await fx.createSoloFounder('f88c');
      await solo.client.from('care_schedules').insert({
        'schedule_date': isoDate(fx.nextFutureDate()),
        'scheduled_parent_id': solo.profile.id,
      });

      expect(
          await solo.client.rpc<dynamic>('my_pending_invitation') as List,
          isEmpty);
      await expectRejected(
          () => solo.client.rpc<dynamic>('join_invitation_from_empty_family',
                  params: {
                    'p_token': token,
                    'p_policy_version': PolicyVersions.current,
                  }),
          contains: 'não pode ser descartada');
      final me = (await fx.service
              .from('profiles')
              .select('family_id')
              .eq('id', solo.profile.id))
          .single;
      expect(me['family_id'], solo.profile.familyId);
    });

    test('an accepted invitation says so; others stay indistinguishable',
        () async {
      // The real order: the ex invites first, then the parent opens the
      // app and founds a family of their own.
      final token = await invite(fx.testEmail('f88d-solo'));
      final solo = await fx.createSoloFounder('f88d');
      Future<String> status(String t) async =>
          await fx.newAnonClient().rpc<dynamic>('invite_token_status',
              params: {'p_token': t}) as String;

      expect(await status(token), 'pending');
      await solo.client.rpc<dynamic>('join_invitation_from_empty_family',
          params: {
            'p_token': token,
            'p_policy_version': PolicyVersions.current,
          });
      expect(await status(token), 'accepted');
      expect(await status('00000000-0000-4000-8000-000000000000'), 'unusable');
    });
  });
}
