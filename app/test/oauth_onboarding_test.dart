// F-57 — the social-login surfaces: the fail-closed Google button, the
// onboarding screen both ways (founder and invitation claim, S-11 migration
// included), and the profile screen's password-card swap for a password-less
// session.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/invite_info.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_app/screens/login_screen.dart';
import 'package:entrelares_app/screens/oauth_onboarding_screen.dart';
import 'package:entrelares_app/screens/profile_screen.dart';
import 'package:entrelares_app/screens/register_screen.dart';
import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

final pt = Localization(AppLanguage.ptBr);

Widget wrap(Widget child) => AppL10n(
      l: pt,
      setLanguage: (_) async {},
      child: MaterialApp(home: child),
    );

Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<void> pumpOnboarding(
  WidgetTester tester,
  FakeCustodyDataSource ds,
  SharedPreferences prefs, {
  Future<void> Function()? onCompleted,
  Future<void> Function()? onSignOut,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(OauthOnboardingScreen(
    dataSource: ds,
    prefs: prefs,
    onSignOut: onSignOut ?? () async {},
    onCompleted: onCompleted ?? () async {},
  )));
  await tester.pumpAndSettle();
}

void main() {
  group('LoginScreen — the fail-closed Google button', () {
    Future<void> pumpLogin(WidgetTester tester,
        {Future<bool>? googleEnabled}) async {
      final prefs = await prefsWith({});
      await tester.pumpWidget(wrap(LoginScreen(
        onSignIn: (_, _) async {},
        onForgotPassword: () {},
        onSignUp: () {},
        prefs: prefs,
        googleEnabled: googleEnabled,
        onSignInWithGoogle: googleEnabled == null ? null : () async {},
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('appears only when GoTrue says the provider exists',
        (tester) async {
      await pumpLogin(tester, googleEnabled: Future.value(true));
      expect(find.text(pt[KApp.authGoogle]), findsOneWidget);
    });

    testWidgets('a disabled provider leaves the screen exactly as before',
        (tester) async {
      await pumpLogin(tester, googleEnabled: Future.value(false));
      expect(find.text(pt[KApp.authGoogle]), findsNothing);
    });

    testWidgets('absent wiring (pre-F-57 callers) shows nothing',
        (tester) async {
      await pumpLogin(tester);
      expect(find.text(pt[KApp.authGoogle]), findsNothing);
    });
  });

  // The ORDER is the feature, not decoration: the Google button exists so
  // nobody has to invent a password, and the escape hatch exists so a wrong
  // account is caught before the form is filled. Both lose their point if they
  // drift back down the column, and nothing else in the tree would notice.
  group('F-57 placement (owner, 27/08/2026)', () {
    double dyOf(WidgetTester tester, Finder f) =>
        tester.getTopLeft(f).dy;

    testWidgets('register: Google sits ABOVE the password fields',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final ds = FakeCustodyDataSource(members: const [], days: const []);
      await tester.pumpWidget(wrap(RegisterScreen(
        dataSource: ds,
        onSignIn: (_, _) async {},
        onBackToLogin: () {},
        googleEnabled: Future.value(true),
        onSignInWithGoogle: ({String? inviteToken}) async {},
      )));
      await tester.pumpAndSettle();

      final google = dyOf(tester, find.text(pt[KApp.authGoogle]));
      final email = dyOf(
          tester, find.widgetWithText(TextField, pt[K.commonEmail]));
      final password = dyOf(
          tester, find.widgetWithText(TextField, pt[K.commonPassword]));

      expect(google, greaterThan(email),
          reason: 'the button follows the e-mail field');
      expect(google, lessThan(password),
          reason: 'a password offered first is a password already invented — '
              'everything below the button is the secondary path');
    });

    testWidgets('onboarding: account identity and the way out, under the name',
        (tester) async {
      final ds = FakeCustodyDataSource(members: const [], days: const [])
        ..displayName = 'Conta Errada'
        ..sessionEmailValue = 'a.errada@gmail.com';
      final prefs = await prefsWith({});
      await pumpOnboarding(tester, ds, prefs);

      final name = dyOf(
          tester, find.widgetWithText(TextField, pt[K.registerFullName]));
      final signedInAs = dyOf(
          tester, find.text(pt.format(KApp.onbSignedInAs, ['a.errada@gmail.com'])));
      final switchAccount = dyOf(tester, find.text(pt[KApp.onbSwitchAccount]));
      final cta =
          dyOf(tester, find.widgetWithText(FilledButton, pt[KApp.onbFounderCta]));

      // The address is the recognition, so it comes with the escape hatch and
      // both come before any of the form is worth filling.
      expect(signedInAs, greaterThan(name));
      expect(switchAccount, greaterThan(signedInAs));
      expect(switchAccount, lessThan(cta),
          reason: 'leaving must be possible before the form is filled');
    });

    testWidgets('onboarding: no session e-mail renders no line at all',
        (tester) async {
      final ds = FakeCustodyDataSource(members: const [], days: const []);
      final prefs = await prefsWith({});
      await pumpOnboarding(tester, ds, prefs);

      expect(find.textContaining('Conectado como'), findsNothing);
      // The way out survives its absence — it never depended on the address.
      expect(find.text(pt[KApp.onbSwitchAccount]), findsOneWidget);
    });
  });

  group('OauthOnboardingScreen — founder', () {
    testWidgets('creates the family through the RPC, consent-gated',
        (tester) async {
      var completed = false;
      final ds = FakeCustodyDataSource(members: const [], days: const [])
        ..displayName = 'Ana do Google';
      final prefs = await prefsWith({});
      await pumpOnboarding(tester, ds, prefs,
          onCompleted: () async => completed = true);

      // Prefilled from the provider's display name.
      expect(find.widgetWithText(TextField, 'Ana do Google'), findsOneWidget);
      expect(find.text(pt[KApp.onbFounderTitle]), findsOneWidget);

      // F-18 shape: the checkbox is the gate, so the CTA starts disabled.
      final cta = find.widgetWithText(FilledButton, pt[KApp.onbFounderCta]);
      expect(tester.widget<FilledButton>(cta).onPressed, isNull);

      await tester.enterText(
          find.widgetWithText(TextField, pt[K.registerFamilyName]),
          'Família Teste');
      await tester.tap(find.text('👩 Mãe'));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();

      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(ds.onboardings, hasLength(1));
      expect(ds.onboardings.single['role'], 'mother');
      expect(ds.onboardings.single['familyName'], 'Família Teste');
      expect(completed, isTrue);
    });

    testWidgets('a missing role refuses with the register form sentence',
        (tester) async {
      final ds = FakeCustodyDataSource(members: const [], days: const []);
      final prefs = await prefsWith({});
      await pumpOnboarding(tester, ds, prefs);

      await tester.enterText(
          find.widgetWithText(TextField, pt[K.registerFullName]), 'Ana');
      await tester.enterText(
          find.widgetWithText(TextField, pt[K.registerFamilyName]),
          'Família Teste');
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(FilledButton, pt[KApp.onbFounderCta]));
      await tester.pumpAndSettle();

      expect(find.text(pt[K.registerErrorRoleRequired]), findsOneWidget);
      expect(ds.onboardings, isEmpty);
    });

    testWidgets("the server's own refusal is shown verbatim", (tester) async {
      final ds = FakeCustodyDataSource(members: const [], days: const [])
        ..onboardingRefusalMessage =
            'Versão da política desatualizada (enviada: x, vigente: y). '
                'Atualize o aplicativo.';
      final prefs = await prefsWith({});
      await pumpOnboarding(tester, ds, prefs);

      await tester.enterText(
          find.widgetWithText(TextField, pt[K.registerFullName]), 'Ana');
      await tester.enterText(
          find.widgetWithText(TextField, pt[K.registerFamilyName]),
          'Família Teste');
      await tester.tap(find.text('👩 Mãe'));
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester
          .tap(find.widgetWithText(FilledButton, pt[KApp.onbFounderCta]));
      await tester.pumpAndSettle();

      expect(find.textContaining('Versão da política desatualizada'),
          findsOneWidget);
    });
  });

  group('OauthOnboardingScreen — invitation claim', () {
    const invite = InviteInfo(
      invitedEmail: 'ana@example.com',
      familyName: 'Família Silva',
      inviterName: 'Bruno',
      roleName: 'aunt',
    );
    const token = '11111111-2222-3333-4444-555555555555';

    testWidgets('claims through the stashed token', (tester) async {
      var completed = false;
      final ds = FakeCustodyDataSource(members: const [], days: const [])
        ..inviteInfo = invite;
      final prefs = await prefsWith(
          {OauthOnboardingScreen.pendingInviteTokenKey: token});
      await pumpOnboarding(tester, ds, prefs,
          onCompleted: () async => completed = true);

      expect(find.text(pt[K.registerInvitedTitle]), findsOneWidget);
      // The invitation carries family and role — no fields for them.
      expect(find.widgetWithText(TextField, pt[K.registerFamilyName]),
          findsNothing);

      await tester.enterText(
          find.widgetWithText(TextField, pt[K.registerFullName]), 'Ana');
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, pt[KApp.onbClaimCta]));
      await tester.pumpAndSettle();

      expect(ds.claims, hasLength(1));
      expect(ds.claims.single['token'], token);
      expect(ds.claims.single['confirmMigration'], false);
      expect(completed, isTrue);
      // Used up: the stash must not survive the claim.
      expect(prefs.getString(OauthOnboardingScreen.pendingInviteTokenKey),
          isNull);
    });

    testWidgets('the S-11 migration question is asked, then confirmed',
        (tester) async {
      final ds = FakeCustodyDataSource(members: const [], days: const [])
        ..inviteInfo = invite
        ..claimResult = const InviteeNeedsMigration('Família Antiga');
      final prefs = await prefsWith(
          {OauthOnboardingScreen.pendingInviteTokenKey: token});
      await pumpOnboarding(tester, ds, prefs);

      await tester.enterText(
          find.widgetWithText(TextField, pt[K.registerFullName]), 'Ana');
      await tester.tap(find.byType(Checkbox));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, pt[KApp.onbClaimCta]));
      await tester.pumpAndSettle();

      expect(find.text(pt[K.registerMigrationTitle]), findsOneWidget);
      expect(find.textContaining('Família Antiga'), findsOneWidget);

      ds.claimResult = const InviteeRegistered();
      await tester.tap(
          find.widgetWithText(FilledButton, pt[K.registerMigrationConfirm]));
      await tester.pumpAndSettle();

      expect(ds.claims, hasLength(2));
      expect(ds.claims.last['confirmMigration'], true);
    });

    testWidgets('a dead token falls back to the founder form, not a wall',
        (tester) async {
      final ds = FakeCustodyDataSource(members: const [], days: const []);
      // No inviteInfo → every token resolves invalid.
      final prefs = await prefsWith(
          {OauthOnboardingScreen.pendingInviteTokenKey: token});
      await pumpOnboarding(tester, ds, prefs);

      expect(find.text(pt[KApp.onbFounderTitle]), findsOneWidget);
      expect(find.text(pt[K.registerInviteInvalidBody]), findsOneWidget);
    });
  });

  group('ProfileScreen — sign-in method (the U-21 slice F-57 needs)', () {
    const me = Member(
      id: 1,
      fullName: 'Ana Souza',
      userId: 'u1',
      isAdmin: true,
      roleId: 1,
      email: 'ana@example.com',
    );

    Future<void> pumpProfile(
        WidgetTester tester, FakeCustodyDataSource ds) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(ProfileScreen(
        dataSource: ds,
        sudo: SudoService(ds),
        deliverExport: (_, _) async {},
      )));
      await tester.pumpAndSettle();
    }

    FakeCustodyDataSource source() =>
        FakeCustodyDataSource(members: const [me], days: const [])
          ..family = const Family(id: 7, name: 'Souza', plan: 'free')
          ..roles = const [Role(id: 1, roleName: 'mother')];

    testWidgets('a Google-only session sees its method, never a password form',
        (tester) async {
      final ds = source()..providers = ['google'];
      await pumpProfile(tester, ds);

      expect(find.text(pt[KApp.profLoginMethod]), findsOneWidget);
      expect(find.text(pt[KApp.profLoginMethodGoogle]), findsOneWidget);
      expect(find.text(pt[K.profChangePassword]), findsNothing);
      expect(find.text(pt[K.profResetByEmail]), findsNothing);
    });

    testWidgets('a password session keeps the password card unchanged',
        (tester) async {
      await pumpProfile(tester, source());

      expect(find.text(pt[K.profSectionPassword]), findsOneWidget);
      expect(find.text(pt[K.profChangePassword]), findsOneWidget);
      expect(find.text(pt[KApp.profLoginMethod]), findsNothing);
    });
  });
}
