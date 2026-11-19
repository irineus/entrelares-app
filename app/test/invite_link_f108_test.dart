// F-108 — inviting the other caregiver by LINK, without their e-mail.
//
// The activation reading behind it (19/11/2026): 8 of 16 new families added
// the other caregiver and 6 of them stopped at a pending member with no
// e-mail — no invitation existed, so there was no link to send, and the
// checklist ticked "Convidar" anyway. These tests pin the app half:
//
// * with `feature.invite_link` on, adding a caregiver leaves with a link on
//   the share sheet, e-mail or not; a pending member with no invitation gets
//   a card whose one primary is "Compartilhar convite";
// * a link invitation's card never says "E-mail não enviado";
// * the invitee's e-mail is unlocked for a caregiver invitation, and an
//   address other than the invitation's signs up through the confirmation
//   (the seat is taken when it is confirmed — PR 1's trigger);
// * with the flag OFF nothing changes — the Android build in Production still
//   locks the sign-up to the invitation's address.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:entrelares_db_contracts/models/family_invitation.dart';
import 'package:entrelares_db_contracts/models/invite_info.dart';
import 'package:entrelares_app/screens/family_screen.dart';
import 'package:entrelares_app/screens/oauth_onboarding_screen.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;
import 'family_page_test.dart' as fam;
import 'register_test.dart' as reg;

const _linkOn = {'feature.invite_link': 'true'};
const _token = '11111111-2222-3333-4444-555555555555';

/// A caregiver invitation for a pending member — claimable by whoever holds
/// the token. [email] empty is a link.
InviteInfo _caregiverInvite({String email = ''}) => InviteInfo(
      familyName: 'Souza',
      inviterName: 'Ana Souza',
      invitedEmail: email,
      roleName: 'father',
      inviteeName: 'Bruno',
    );

FamilyInvitation _link({int profileId = 6, bool expired = false}) =>
    FamilyInvitation(
      id: 77,
      email: '',
      roleId: 2,
      token: _token,
      expiresAt: expired
          ? DateTime.now().toUtc().subtract(const Duration(days: 1))
          : DateTime.now().toUtc().add(const Duration(days: 6)),
      profileId: profileId,
    );

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('F-108 · Família', () {
    testWidgets('adding a caregiver without an e-mail creates the link and '
        'opens the share sheet', (tester) async {
      final ds = fam.source(plan: 'premium', settings: _linkOn);
      final shared = <String>[];
      final funnel = fam.FakeFunnel();
      await fam.pumpFamily(tester, ds,
          onShareInvite: (m) async => shared.add(m),
          analytics: funnel.service);

      expect(find.text(l[KApp.famAddAndShare]), findsOne);
      expect(find.text(l[KApp.famAddWithoutInvite]), findsNothing);

      await fam.enterInviteName(tester, l);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Mãe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[KApp.famAddAndShare]));
      await tester.pumpAndSettle();

      expect(ds.addedPending.single['email'], isNull);
      expect(ds.createdInvitations, [
        {'email': null, 'roleId': 1, 'profileId': 501}
      ]);
      expect(ds.mailedInvitations, isEmpty,
          reason: 'a link has no address to mail');
      expect(shared, hasLength(1));
      expect(shared.single, contains('/register?invite='));
      await tester.pump(const Duration(milliseconds: 50));
      expect(funnel.dataOf(AnalyticsEvents.inviteSent), {'email': 'link'});
    });

    testWidgets('with an e-mail typed the message goes out AND the share '
        'sheet opens', (tester) async {
      final ds = fam.source(plan: 'premium', settings: _linkOn);
      final shared = <String>[];
      await fam.pumpFamily(tester, ds,
          onShareInvite: (m) async => shared.add(m));

      await fam.enterInviteName(tester, l);
      await tester.enterText(
          find.widgetWithText(TextField, l[K.commonEmail]), 'vovo@example.com');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Mãe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.famSendInvite]));
      await tester.pumpAndSettle();

      // add_pending_member issued the invitation (42) with the address.
      expect(ds.createdInvitations, isEmpty);
      expect(ds.mailedInvitations, [42]);
      expect(shared.single, contains('born-0000-0000-0000-000000000042'));
    });

    testWidgets('a pending member with no invitation gets the card with '
        '"Compartilhar convite"', (tester) async {
      final ds = fam.source(
          members: const [fam.admin, fam.pending],
          plan: 'premium',
          settings: _linkOn);
      final shared = <String>[];
      await fam.pumpFamily(tester, ds,
          onShareInvite: (m) async => shared.add(m));

      expect(find.byKey(const ValueKey('uninvited-6')), findsOne);
      expect(find.text(l[KApp.famNoInviteBadge]), findsOne);

      await tester.ensureVisible(find.byKey(const ValueKey('share-invite-6')));
      await tester.tap(find.byKey(const ValueKey('share-invite-6')));
      await tester.pumpAndSettle();

      expect(ds.createdInvitations, [
        {'email': null, 'roleId': 2, 'profileId': 6}
      ]);
      expect(shared.single, contains('renewed-0000-0000-0000-000000000042'));
      // The card becomes the invitation's: a link, never "não enviado".
      expect(find.byKey(const ValueKey('uninvited-6')), findsNothing);
      expect(find.text(l[KApp.famInviteLinkLabel]), findsOne);
      expect(find.text(l[KApp.famInviteLinkBadge]), findsOne);
      expect(find.text(l[KApp.famInviteEmailUnsentBadge]), findsNothing);
    });

    testWidgets('the member ⋮ puts the link first and the e-mail second',
        (tester) async {
      final ds = fam.source(
          members: const [fam.admin, fam.pending],
          plan: 'premium',
          settings: _linkOn);
      await fam.pumpFamily(tester, ds, onShareInvite: (_) async {});

      await fam.openMenu(tester, FamilyScreen.memberMenuKey(6));
      expect(find.text(l[KApp.famShareInvite]), findsWidgets);
      expect(find.text(l[KApp.famInviteByEmail]), findsOne);
      expect(find.text(l[KApp.famPendingInvite]), findsNothing);
    });

    testWidgets('a live link offers "Convidar por e-mail" on the same token '
        'and no "Reenviar"', (tester) async {
      final ds = fam.source(
          members: const [fam.admin, fam.pending],
          invitations: [_link()],
          plan: 'premium',
          settings: _linkOn);
      await fam.pumpFamily(tester, ds, onShareInvite: (_) async {});

      expect(find.text(l[KApp.famInviteLinkLabel]), findsOne);
      expect(find.byKey(const ValueKey('uninvited-6')), findsNothing);

      await fam.openMenu(tester, FamilyScreen.invitationMenuKey(77));
      expect(find.text(l[K.famResendInvite]), findsNothing);
      await tester.tap(find.text(l[KApp.famInviteByEmail]));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.widgetWithText(TextField, l[K.commonEmail]).last,
          'eva@example.com');
      await tester.tap(find.text(l[K.famSendInvite]).last);
      await tester.pumpAndSettle();

      expect(ds.createdInvitations, [
        {'email': 'eva@example.com', 'roleId': 2, 'profileId': 6}
      ]);
      expect(ds.invitations.single.token, _token,
          reason: 'the address lands on the link already shared');
      expect(ds.mailedInvitations, [77]);
    });

    testWidgets('an expired link shares a new one and mails nothing',
        (tester) async {
      final ds = fam.source(
          members: const [fam.admin, fam.pending],
          invitations: [_link(expired: true)],
          plan: 'premium',
          settings: _linkOn);
      final shared = <String>[];
      await fam.pumpFamily(tester, ds,
          onShareInvite: (m) async => shared.add(m));

      await tester.ensureVisible(find.text(l[KApp.famShareAgain]));
      await tester.tap(find.text(l[KApp.famShareAgain]));
      await tester.pumpAndSettle();

      expect(ds.createdInvitations.single['email'], '');
      expect(ds.mailedInvitations, isEmpty);
      expect(shared.single, contains('renewed-0000-0000-0000-000000000042'));
      expect(find.text(l[K.famInviteRenewedEmailFailed]), findsNothing);
    });

    testWidgets('no share sheet (desktop browser) copies the link instead of '
        'failing the add', (tester) async {
      final ds = fam.source(plan: 'premium', settings: _linkOn);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await fam.pumpFamily(tester, ds,
          onShareInvite: (_) async => throw Exception('canShare() is false'));

      await fam.enterInviteName(tester, l);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Mãe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[KApp.famAddAndShare]));
      await tester.pumpAndSettle();

      expect(copied, contains('/register?invite='));
      expect(find.text(l[K.errSaveFailed]), findsNothing);
      expect(ds.addedPending, hasLength(1));
    });

    testWidgets('with the flag OFF the F-56 flow is untouched', (tester) async {
      final ds = fam.source(
          members: const [fam.admin, fam.pending], plan: 'premium');
      final shared = <String>[];
      await fam.pumpFamily(tester, ds,
          onShareInvite: (m) async => shared.add(m));

      expect(find.byKey(const ValueKey('uninvited-6')), findsNothing);
      expect(find.text(l[KApp.famAddWithoutInvite]), findsOne);

      await fam.enterInviteName(tester, l);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Mãe'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[KApp.famAddWithoutInvite]));
      await tester.pumpAndSettle();

      expect(ds.createdInvitations, isEmpty);
      expect(shared, isEmpty);
    });
  });

  group('F-108 · /register?invite=', () {
    testWidgets('a link unlocks the e-mail and signs up through the '
        'confirmation', (tester) async {
      final ds = reg.source()..inviteInfo = _caregiverInvite();
      final signIns = <String>[];
      await reg.pumpRegister(tester,
          dataSource: ds, inviteToken: _token, signIns: signIns);

      final field = tester.widget<TextField>(
          find.widgetWithText(TextField, l[K.commonEmail]));
      expect(field.readOnly, isFalse);
      expect(find.text(l[KApp.registerInviteEmailHelper]), findsOne);

      await reg.fillCommonFields(tester);
      await tester.enterText(find.widgetWithText(TextField, l[K.commonEmail]),
          'bruno.pessoal@example.com');
      await reg.acceptTerms(tester);
      await reg.tapVisible(tester, reg.submitButton(l));
      await tester.pumpAndSettle();

      expect(ds.inviteeRegistrations, isEmpty,
          reason: 'never pre-confirm an address nobody proved');
      expect(ds.inviteeSignUps, [
        {
          'email': 'bruno.pessoal@example.com',
          'fullName': 'Bruno Souza',
          'inviteToken': _token,
          'language': 'pt-BR',
        }
      ]);
      expect(signIns, isEmpty);
      expect(find.text(l[K.registerConfirmEmailTitle]), findsOne);
      expect(find.byKey(const ValueKey('register-invite-confirm-joins')),
          findsOne);
    });

    testWidgets("the invitation's own address keeps the pre-confirmed path",
        (tester) async {
      final ds = reg.source()
        ..inviteInfo = _caregiverInvite(email: 'bruno@example.com');
      final signIns = <String>[];
      await reg.pumpRegister(tester,
          dataSource: ds, inviteToken: _token, signIns: signIns);

      await reg.fillCommonFields(tester);
      await reg.acceptTerms(tester);
      await reg.tapVisible(tester, reg.submitButton(l));
      await tester.pumpAndSettle();

      expect(ds.inviteeRegistrations, hasLength(1));
      expect(ds.inviteeSignUps, isEmpty);
      expect(signIns, ['bruno@example.com']);
    });

    testWidgets('a viewer invitation stays bound to its address',
        (tester) async {
      final ds = reg.source()
        ..inviteInfo = const InviteInfo(
          familyName: 'Souza',
          inviterName: 'Ana Souza',
          invitedEmail: 'vovo@example.com',
          roleName: 'grandmother',
          memberType: 'viewer',
        );
      await reg.pumpRegister(tester, dataSource: ds, inviteToken: _token);

      final field = tester.widget<TextField>(
          find.widgetWithText(TextField, l[K.commonEmail]));
      expect(field.readOnly, isTrue);
      expect(find.text(l[KApp.registerInviteEmailHelper]), findsNothing);
    });
  });

  group('F-108 · Google onboarding', () {
    testWidgets('a caregiver invitation takes any Google address — no '
        'mismatch banner', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ds = FakeCustodyDataSource(members: const [], days: const [])
        ..inviteInfo = _caregiverInvite(email: 'bruno@example.com')
        ..sessionEmailValue = 'bruno.outro@example.com';
      await tester.binding.setSurfaceSize(const Size(800, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(AppL10n(
        l: l,
        setLanguage: (_) async {},
        child: MaterialApp(
          home: OauthOnboardingScreen(
            dataSource: ds,
            prefs: prefs,
            initialInviteToken: _token,
            onSignOut: () async {},
            onCompleted: () async {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text(l[K.registerInvitedTitle]), findsOne);
      expect(find.byKey(const ValueKey('invite-email-mismatch')), findsNothing);
    });
  });
}
