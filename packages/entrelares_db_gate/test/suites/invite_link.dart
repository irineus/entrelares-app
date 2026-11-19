import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// F-108 — invite the other caregiver by LINK, without their e-mail.
///
/// Owner's decisions (19/11/2026), pinned on the outputs (`profiles`,
/// `family_invitations`, `notifications`, `auth.users` through the Admin API):
/// * a caregiver invitation for a placeholder is claimable by WHOEVER holds
///   the token — single use, 7 days, revoked/expired refused; the admin hears
///   it (`member_joined`);
/// * the e-mail the admin typed is delivery only: another address claims it;
/// * an UNCONFIRMED address other than the invitation's gets the account and
///   no seat; the seat is taken when the address is confirmed — a typo never
///   holds the placeholder, and someone else may claim meanwhile;
/// * a link is born only for a placeholder and only with `feature.invite_link`
///   on; sharing again returns the same link, and an e-mail typed later
///   attaches to that same row;
/// * viewer and legacy (no placeholder) invitations stay e-mail-bound;
/// * F-88 by the token: a solo founder of an empty family who opens a link is
///   offered it and joins.
void inviteLinkTests(GateFixture fx) {
  const flag = 'feature.invite_link';

  Map<String, dynamic> rowOf(dynamic result) => result is List
      ? Map<String, dynamic>.from(result.first as Map)
      : Map<String, dynamic>.from(result as Map);

  Future<int> addPending(SupabaseClient admin, String name, {String? email}) async =>
      rowOf(await admin.rpc<dynamic>('add_pending_member', params: {
        'p_full_name': name,
        'p_role_id': fx.roleId('father'),
        'p_email': ?email,
      }))['profile_id'] as int;

  Future<Map<String, dynamic>> invite(SupabaseClient admin, int profileId,
          {String? email}) async =>
      rowOf(await admin.rpc<dynamic>('create_invitation', params: {
        'p_email': email,
        'p_role_id': fx.roleId('father'),
        'p_profile_id': profileId,
      }));

  Future<Map<String, dynamic>> invitationRow(String token) async =>
      Map<String, dynamic>.from((await fx.service
              .from('family_invitations')
              .select()
              .eq('token', token))
          .single);

  Future<Map<String, dynamic>> profileRow(int id) async => Map<String,
          dynamic>.from(
      (await fx.service.from('profiles').select().eq('id', id)).single);

  Future<List<Map<String, dynamic>>> profilesOfUser(String uid) async => [
        for (final row
            in await fx.service.from('profiles').select().eq('user_id', uid))
          Map<String, dynamic>.from(row)
      ];

  Future<String?> tokenOfPlaceholder(int profileId) async {
    final rows = await fx.service
        .from('family_invitations')
        .select('token')
        .eq('profile_id', profileId)
        .isFilter('accepted_at', null)
        .isFilter('revoked_at', null);
    return rows.isEmpty ? null : rows.first['token'] as String;
  }

  group('F-108 · invitation by link', () {
    late String flagBefore;
    var families = 0;
    late ThrowawayFamily fam;

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
    });
    tearDownAll(() => writeFlag(fx, flag, flagBefore));

    // One family per test: each placeholder holds the third seat (the
    // throwaway family is inside its trial, so Premium seats are open).
    setUp(() async => fam = await fx.createFamily('f108-${families++}'));

    test('with the flag off a link is refused; an e-mail still invites',
        () async {
      final pending = await addPending(fam.admin, 'E2E Pai Off');
      await writeFlag(fx, flag, 'false');
      try {
        await expectRejected(() => invite(fam.admin, pending),
            contains: 'Informe o e-mail');
        final viaEmail =
            await invite(fam.admin, pending, email: fx.testEmail('f108-off'));
        expect(viaEmail['token'], isNotNull);
      } finally {
        await writeFlag(fx, flag, 'true');
      }
    });

    test('a link needs a placeholder, and sharing again returns the same one',
        () async {
      await expectRejected(
          () => fam.admin.rpc<dynamic>('create_invitation', params: {
                'p_email': null,
                'p_role_id': fx.roleId('father'),
              }),
          contains: 'Informe o e-mail');

      final pending = await addPending(fam.admin, 'E2E Pai Link');
      final first = await invite(fam.admin, pending);
      final again = await invite(fam.admin, pending);
      expect(again['token'], first['token'],
          reason: 'sharing again never kills the link already in a chat');

      final row = await invitationRow(first['token'] as String);
      expect(row['email'], isNull);
      expect(row['email_sent_at'], isNull);
      expect(row['profile_id'], pending);
      expect(row['member_type'], 'full');

      // The CHECK: no address only for a caregiver placeholder.
      await expectRejected(() => fx.service.from('family_invitations').insert({
            'family_id': fam.familyId,
            'email': null,
            'role_id': fx.roleId('father'),
            'invited_by': fam.adminProfile.id,
          }));
    });

    test('an e-mail typed after the link rides the same token', () async {
      final pending = await addPending(fam.admin, 'E2E Pai Depois');
      final link = await invite(fam.admin, pending);
      final email = fx.testEmail('f108-later');
      final mailed = await invite(fam.admin, pending, email: email);
      expect(mailed['token'], link['token']);
      final row = await invitationRow(link['token'] as String);
      expect(row['email'], email.toLowerCase());
      expect(row['revoked_at'], isNull);
    });

    test('whoever holds the link claims the placeholder, once', () async {
      final pending = await addPending(fam.admin, 'E2E Pai Qualquer');
      final token = (await invite(fam.admin, pending))['token'] as String;

      final uid = await fx.createInvitedUser(
          fx.testEmail('f108-anyone'), token,
          fullName: 'E2E Bruno');

      final placeholder = await profileRow(pending);
      expect(placeholder['user_id'], uid,
          reason: 'the claim is an UPDATE of the placeholder (F-56)');
      expect(placeholder['full_name'], 'E2E Bruno');
      expect((await invitationRow(token))['accepted_at'], isNotNull);

      final joined = await fx.service
          .from('notifications')
          .select('type, params')
          .eq('recipient_profile_id', fam.adminProfile.id)
          .eq('type', 'member_joined');
      expect(joined, isNotEmpty, reason: 'the admin hears who joined');

      // Single use: the same link refuses a second person.
      await expectRejected(() => fx.createInvitedUser(
          fx.testEmail('f108-second'), token,
          fullName: 'E2E Second'));
    });

    test("the admin's e-mail is delivery only: another address claims it",
        () async {
      final pending = await addPending(fam.admin, 'E2E Pai Outro Google',
          email: fx.testEmail('f108-typed'));
      final token = (await tokenOfPlaceholder(pending))!;

      final uid = await fx.createInvitedUser(
          fx.testEmail('f108-other-google'), token,
          fullName: 'E2E Outro Endereço');
      expect((await profileRow(pending))['user_id'], uid);
    });

    test('an unconfirmed other address waits; confirming takes the seat',
        () async {
      final pending = await addPending(fam.admin, 'E2E Pai Confirma');
      final token = (await invite(fam.admin, pending))['token'] as String;

      final uid = await fx.createUnconfirmedInvitedUser(
          fx.testEmail('f108-confirm'), token,
          fullName: 'E2E Confirma');
      expect(await profilesOfUser(uid), isEmpty,
          reason: 'no profile before the address is proven');
      expect((await profileRow(pending))['user_id'], isNull);
      expect((await invitationRow(token))['accepted_at'], isNull);

      await fx.confirmUser(uid);

      expect((await profileRow(pending))['user_id'], uid,
          reason: 'claim_invitation_on_confirm took the placeholder');
      expect((await invitationRow(token))['accepted_at'], isNotNull);
    });

    test('a typo never holds the seat: another person claims meanwhile, and '
        'the late confirmation leaves a profile-less account', () async {
      final pending = await addPending(fam.admin, 'E2E Pai Typo');
      final token = (await invite(fam.admin, pending))['token'] as String;

      final typo = await fx.createUnconfirmedInvitedUser(
          fx.testEmail('f108-typo'), token,
          fullName: 'E2E Typo');
      final real = await fx.createInvitedUser(
          fx.testEmail('f108-real'), token,
          fullName: 'E2E Real');
      expect((await profileRow(pending))['user_id'], real);

      // The confirmation itself must never fail because the claim cannot run.
      await fx.confirmUser(typo);
      expect(await profilesOfUser(typo), isEmpty);
      expect((await profileRow(pending))['user_id'], real);
    });

    test('a revoked or expired link is refused', () async {
      final pending = await addPending(fam.admin, 'E2E Pai Morto');
      final token = (await invite(fam.admin, pending))['token'] as String;

      await fx.service.from('family_invitations').update({
        'expires_at':
            DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String(),
      }).eq('token', token);
      await expectRejected(() => fx.createInvitedUser(
          fx.testEmail('f108-expired'), token,
          fullName: 'E2E Expirado'));

      final fresh = (await invite(fam.admin, pending))['token'] as String;
      expect(fresh, isNot(token), reason: 'an expired link is replaced');
      await fx.service.from('family_invitations').update({
        'revoked_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('token', fresh);
      await expectRejected(() => fx.createInvitedUser(
          fx.testEmail('f108-revoked'), fresh,
          fullName: 'E2E Revogado'));
      expect((await profileRow(pending))['user_id'], isNull);
    });

    test('viewer and legacy invitations stay bound to their address',
        () async {
      final viewerToken = rowOf(await fam.admin.rpc<dynamic>(
          'create_viewer_invitation', params: {
        'p_email': fx.testEmail('f108-viewer'),
        'p_role_id': fx.roleId('grandmother'),
      }))['token'] as String;
      await expectRejected(() => fx.createInvitedUser(
          fx.testEmail('f108-viewer-thief'), viewerToken,
          fullName: 'E2E Viewer Thief'));

      final legacyToken = await GateFixture.createInvitation(
          fam.admin, fx.testEmail('f108-legacy'), fx.roleId('aunt'));
      await expectRejected(() => fx.createInvitedUser(
          fx.testEmail('f108-legacy-thief'), legacyToken,
          fullName: 'E2E Legacy Thief'));
    });

    test('F-88 by the token: a solo founder is offered the link and joins',
        () async {
      final pending = await addPending(fam.admin, 'E2E Pai Solo');
      final token = (await invite(fam.admin, pending))['token'] as String;
      final solo = await fx.createSoloFounder('f108-solo');
      final oldFamily = solo.profile.familyId!;

      final offer = await solo.client.rpc<dynamic>('invitation_offer_for_token',
          params: {'p_token': token}) as List;
      expect(offer, hasLength(1));
      expect(offer.single['inviter_name'], fam.adminProfile.fullName);

      // A member of a family with someone else is offered nothing.
      final none = await fam.member.rpc<dynamic>('invitation_offer_for_token',
          params: {'p_token': token}) as List;
      expect(none, isEmpty);

      await solo.client.rpc<dynamic>('join_invitation_from_empty_family',
          params: {
            'p_token': token,
            'p_policy_version': PolicyVersions.current,
          });

      final placeholder = await profileRow(pending);
      expect(placeholder['user_id'], solo.profile.userId,
          reason: 'the session account takes the placeholder');
      expect(
          await fx.service.from('families').select('id').eq('id', oldFamily),
          isEmpty,
          reason: 'the empty family is discarded');
    });
  });
}
