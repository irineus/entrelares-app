// `/register` — the two branches and the four states around them.
//
// The branch is decided by ONE thing (an invite token in the URL), and almost
// every difference on screen follows from it: the founder names a family and
// picks a role and ends on "confirm your e-mail"; the invitee gets a read-only
// address, no family/role, and is signed straight in.
//
// The consent block is asserted per branch on purpose — the S-15 declaration
// differs, and showing the founder's text to an invitee would be a legal
// defect, not a cosmetic one.
import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:entrelares_db_contracts/models/invite_info.dart';
import 'package:entrelares_app/screens/register_screen.dart';
import 'package:entrelares_app/services/analytics_service.dart';
import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/role_picker.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource, ana, bruno;

const validToken = '11111111-2222-3333-4444-555555555555';

const invite = InviteInfo(
  familyName: 'Souza',
  inviterName: 'Ana Souza',
  invitedEmail: 'bruno@example.com',
  roleName: 'father',
);

FakeCustodyDataSource source() =>
    FakeCustodyDataSource(members: const [ana, bruno], days: []);

Future<void> pumpRegister(
  WidgetTester tester, {
  required FakeCustodyDataSource dataSource,
  String? inviteToken,
  AppLanguage language = AppLanguage.ptBr,
  List<String>? signIns,
  VoidCallback? onBackToLogin,
  AnalyticsService? analytics,
}) async {
  // The founder form (21 role chips + consent block) is far taller than the
  // 800px default surface. Giving the test a tall viewport keeps every control
  // hit-testable, so a missed tap means a real defect rather than a scroll.
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(AppL10n(
    l: Localization(language),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: RegisterScreen(
        dataSource: dataSource,
        analytics: analytics,
        inviteToken: inviteToken,
        onSignIn: (email, password) async => signIns?.add(email),
        onBackToLogin: onBackToLogin ?? () {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The form is taller than the test surface, so anything tapped has to be
/// scrolled to first — `enterText` does not need it, taps do.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> fillCommonFields(
  WidgetTester tester, {
  String name = 'Bruno Souza',
  String password = 'segredo123',
  AppLanguage language = AppLanguage.ptBr,
}) async {
  final l = Localization(language);
  await tester.enterText(
      find.widgetWithText(TextField, l[K.registerFullName]), name);
  await tester.enterText(
      find.widgetWithText(TextField, l[K.commonPassword]), password);
  await tester.enterText(
      find.widgetWithText(TextField, l[K.commonConfirmPassword]), password);
  await tester.pump();
}

/// U-44 — the founder's first step, filled and left: what every family-step
/// test starts from.
Future<void> goToFamilyStep(
  WidgetTester tester, {
  String name = 'Ana Souza',
  String email = 'ana@example.com',
  AppLanguage language = AppLanguage.ptBr,
}) async {
  final l = Localization(language);
  await fillCommonFields(tester, name: name, language: language);
  await tester.enterText(find.widgetWithText(TextField, l[K.commonEmail]), email);
  await tapVisible(tester, continueButton(l));
  await tester.pumpAndSettle();
}

Finder continueButton(Localization l) =>
    find.widgetWithText(FilledButton, l[KApp.signupContinue]);

Finder backButton(Localization l) =>
    find.widgetWithText(TextButton, l[KApp.signupBack]);

Future<void> acceptTerms(WidgetTester tester) =>
    tapVisible(tester, find.byType(Checkbox));

/// "Criar conta" is BOTH the heading and the submit label in PT-BR, so the
/// button is always addressed through its widget type.
Finder submitButton(Localization l) =>
    find.widgetWithText(FilledButton, l[K.registerSubmit]);

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('founder branch — step 1, the account (U-44)', () {
    testWidgets('asks who you are, and nothing about the family yet',
        (tester) async {
      await pumpRegister(tester, dataSource: source());

      expect(find.text(l[K.registerCreateSubtitle]), findsOne);
      expect(find.text('Passo 1 de 2 · Sua conta'), findsOne);
      expect(find.widgetWithText(TextField, l[K.registerFullName]), findsOne);
      expect(find.widgetWithText(TextField, l[K.commonEmail]), findsOne);
      expect(find.widgetWithText(TextField, l[K.commonPassword]), findsOne);
      expect(
          find.widgetWithText(TextField, l[K.registerFamilyName]), findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(Checkbox), findsNothing,
          reason: 'consent is signed on the step that creates the family');
      expect(continueButton(l), findsOne);
    });

    testWidgets('Continuar refuses the account step in the form\'s own order',
        (tester) async {
      final ds = source();
      await pumpRegister(tester, dataSource: ds);
      await fillCommonFields(tester, password: 'curta');
      await tester.enterText(
          find.widgetWithText(TextField, l[K.commonEmail]), 'ana@example.com');

      await tapVisible(tester, continueButton(l));
      await tester.pumpAndSettle();

      expect(find.text(l[K.registerErrorPasswordShort]), findsOne);
      expect(
          find.widgetWithText(TextField, l[K.registerFamilyName]), findsNothing);
      expect(ds.signUps, isEmpty);
    });

    testWidgets('a valid account moves on without touching the server',
        (tester) async {
      final ds = source();
      await pumpRegister(tester, dataSource: ds);
      await goToFamilyStep(tester);

      expect(find.text('Passo 2 de 2 · Sua família'), findsOne);
      expect(find.widgetWithText(TextField, l[K.registerFamilyName]), findsOne);
      expect(ds.signUps, isEmpty);
    });

    testWidgets('reaching the family step is counted once, by name only',
        (tester) async {
      final sent = <http.Request>[];
      final analytics = AnalyticsService(
        websiteId: 'site-1',
        host: 'https://cloud.umami.is',
        hostname: 'app.entrelares.app',
        client: MockClient((request) async {
          sent.add(request);
          return http.Response('', 200);
        }),
      );
      await pumpRegister(tester, dataSource: source(), analytics: analytics);

      await goToFamilyStep(tester);
      await tapVisible(tester, backButton(l));
      await tester.pumpAndSettle();
      await tapVisible(tester, continueButton(l));
      await tester.pumpAndSettle();

      final events = [
        for (final request in sent)
          (jsonDecode(request.body) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>
      ].where((p) => p['name'] == 'signup_step').toList();
      expect(events, hasLength(1));
      expect(events.single['data'], {'step': 'family'});
    });
  });

  group('founder branch — step 2, the family (U-44)', () {
    testWidgets('offers the family name, six roles and "Outro…"',
        (tester) async {
      await pumpRegister(tester, dataSource: source());
      await goToFamilyStep(tester);

      expect(find.byType(ChoiceChip),
          findsNWidgets(RoleCatalog.signUpShortlist.length));
      for (final label in ['Pai', 'Mãe', 'Avô', 'Avó', 'Padrasto', 'Madrasta']) {
        expect(find.widgetWithText(ChoiceChip, label), findsOne);
      }
      expect(find.widgetWithText(ChoiceChip, 'Tio'), findsNothing);
      expect(find.byKey(RolePicker.otherKey), findsOne);
    });

    testWidgets('shows the A-1.1 awareness declaration', (tester) async {
      await pumpRegister(tester, dataSource: source());
      await goToFamilyStep(tester);

      expect(find.text(ConsentDeclarations.creator), findsOne);
      expect(find.text(ConsentDeclarations.invitee), findsNothing);
    });

    testWidgets('the submit button is dead until consent is given',
        (tester) async {
      await pumpRegister(tester, dataSource: source());
      await goToFamilyStep(tester);

      final button = tester.widget<FilledButton>(submitButton(l));
      expect(button.onPressed, isNull);

      await acceptTerms(tester);

      final enabled = tester.widget<FilledButton>(submitButton(l));
      expect(enabled.onPressed, isNotNull);
    });

    testWidgets('refuses a form with no role, and stays on the family step',
        (tester) async {
      final ds = source();
      await pumpRegister(tester, dataSource: ds);
      await goToFamilyStep(tester);
      await tester.enterText(
          find.widgetWithText(TextField, l[K.registerFamilyName]), 'Souza');
      await acceptTerms(tester);

      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      expect(find.text(l[K.registerErrorRoleRequired]), findsOne);
      expect(find.widgetWithText(TextField, l[K.registerFamilyName]), findsOne);
      expect(ds.signUps, isEmpty, reason: 'nothing may reach the server');
    });

    testWidgets('a complete form signs up and lands on "confirm your e-mail"',
        (tester) async {
      final ds = source();
      await pumpRegister(tester, dataSource: ds);
      await goToFamilyStep(tester);
      await tester.enterText(
          find.widgetWithText(TextField, l[K.registerFamilyName]), 'Souza');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Mãe'));
      await acceptTerms(tester);

      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      expect(ds.signUps, hasLength(1));
      expect(ds.signUps.single['role'], 'mother');
      expect(ds.signUps.single['familyName'], 'Souza');
      expect(ds.signUps.single['language'], AppLanguage.ptBrCode);
      expect(find.text(l[K.registerConfirmEmailTitle]), findsOne);
      expect(find.textContaining('ana@example.com'), findsOne);
    });

    testWidgets('a role behind "Outro…" is two taps and stays on screen',
        (tester) async {
      final ds = source();
      await pumpRegister(tester, dataSource: ds);
      await goToFamilyStep(tester);
      await tester.enterText(
          find.widgetWithText(TextField, l[K.registerFamilyName]), 'Souza');

      await tapVisible(tester, find.byKey(RolePicker.otherKey));
      await tester.pumpAndSettle();
      expect(find.text(Localization(AppLanguage.ptBr)[KApp.roleOtherTitle]),
          findsOne);
      expect(find.byType(ListTile), findsNWidgets(RoleCatalog.others.length));
      await tester.tap(find.widgetWithText(ListTile, 'Tio'));
      await tester.pumpAndSettle();

      final picked =
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Tio'));
      expect(picked.selected, isTrue);

      await acceptTerms(tester);
      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      expect(ds.signUps.single['role'], 'uncle');
    });

    testWidgets('an address GoTrue refuses sends the person back to step 1, '
        'with the answers of step 2 kept', (tester) async {
      final ds = source()..signUpFailureKey = K.authErrAlreadyRegistered;
      await pumpRegister(tester, dataSource: ds);
      await goToFamilyStep(tester);
      await tester.enterText(
          find.widgetWithText(TextField, l[K.registerFamilyName]), 'Souza');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Mãe'));
      await acceptTerms(tester);

      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      expect(find.text(l[K.authErrAlreadyRegistered]), findsOne);
      expect(find.text('Passo 1 de 2 · Sua conta'), findsOne);
      expect(find.text(l[K.registerConfirmEmailTitle]), findsNothing);

      await tapVisible(tester, continueButton(l));
      await tester.pumpAndSettle();

      expect(find.text('Souza'), findsOne);
      expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Mãe'))
              .selected,
          isTrue);
    });

    testWidgets('a refusal that is not about the account keeps step 2',
        (tester) async {
      final ds = source()..signUpFailureKey = K.authErrRateLimited;
      await pumpRegister(tester, dataSource: ds);
      await goToFamilyStep(tester);
      await tester.enterText(
          find.widgetWithText(TextField, l[K.registerFamilyName]), 'Souza');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, 'Mãe'));
      await acceptTerms(tester);

      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      expect(find.text(l[K.authErrRateLimited]), findsOne);
      expect(find.text('Passo 2 de 2 · Sua família'), findsOne);
    });

    testWidgets('Voltar returns to the account with everything typed kept',
        (tester) async {
      await pumpRegister(tester, dataSource: source());
      await goToFamilyStep(tester);

      await tapVisible(tester, backButton(l));
      await tester.pumpAndSettle();

      expect(find.text('Passo 1 de 2 · Sua conta'), findsOne);
      expect(find.text('ana@example.com'), findsOne);
    });

    testWidgets('the system back on step 2 goes to step 1, not out of the form',
        (tester) async {
      await pumpRegister(tester, dataSource: source());
      await goToFamilyStep(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text('Passo 1 de 2 · Sua conta'), findsOne);
      expect(find.text('ana@example.com'), findsOne);
    });
  });

  group('invited branch', () {
    testWidgets('resolves the token and greets with inviter, family and role',
        (tester) async {
      final ds = source()..inviteInfo = invite;
      await pumpRegister(tester, dataSource: ds, inviteToken: validToken);

      expect(find.text(l[K.registerInvitedTitle]), findsOne);
      expect(find.textContaining('Ana Souza'), findsOne);
      expect(find.textContaining('Souza'), findsWidgets);
      expect(find.textContaining('Pai'), findsOne);
    });

    testWidgets('hides the family name and the role grid', (tester) async {
      final ds = source()..inviteInfo = invite;
      await pumpRegister(tester, dataSource: ds, inviteToken: validToken);

      expect(find.widgetWithText(TextField, l[K.registerFamilyName]),
          findsNothing);
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('prefills the address read-only — the trigger refuses any other',
        (tester) async {
      final ds = source()..inviteInfo = invite;
      await pumpRegister(tester, dataSource: ds, inviteToken: validToken);

      final field = tester
          .widget<TextField>(find.widgetWithText(TextField, l[K.commonEmail]));
      expect(field.controller?.text, 'bruno@example.com');
      expect(field.readOnly, isTrue);
    });

    testWidgets('shows the A-1.2 confidentiality declaration', (tester) async {
      final ds = source()..inviteInfo = invite;
      await pumpRegister(tester, dataSource: ds, inviteToken: validToken);

      expect(find.text(ConsentDeclarations.invitee), findsOne);
      expect(find.text(ConsentDeclarations.creator), findsNothing);
    });

    testWidgets('registers and signs straight in (U-17 auto-confirm)',
        (tester) async {
      final ds = source()..inviteInfo = invite;
      final signIns = <String>[];
      await pumpRegister(tester,
          dataSource: ds, inviteToken: validToken, signIns: signIns);
      await fillCommonFields(tester);
      await acceptTerms(tester);

      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      expect(ds.inviteeRegistrations, hasLength(1));
      expect(ds.inviteeRegistrations.single['confirmMigration'], isFalse);
      expect(signIns, ['bruno@example.com']);
    });

    testWidgets('a dead token shows the invalid-invitation dead end',
        (tester) async {
      // inviteInfo left null — unknown, accepted, revoked and expired all land
      // here, and the screen must not tell them apart.
      await pumpRegister(tester,
          dataSource: source(), inviteToken: validToken);

      expect(find.text(l[K.registerInviteInvalidTitle]), findsOne);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a malformed token never reaches the server', (tester) async {
      await pumpRegister(tester,
          dataSource: source()..inviteInfo = invite, inviteToken: 'nonsense');

      expect(find.text(l[K.registerInviteInvalidTitle]), findsOne);
    });

    testWidgets('the server\'s own refusal text is shown verbatim',
        (tester) async {
      final ds = source()
        ..inviteInfo = invite
        ..inviteeResult = const InviteeFailed(
            'Este e-mail já possui cadastro. Faça login ou recupere a senha.');
      await pumpRegister(tester, dataSource: ds, inviteToken: validToken);
      await fillCommonFields(tester);
      await acceptTerms(tester);

      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      expect(
          find.text(
              'Este e-mail já possui cadastro. Faça login ou recupere a senha.'),
          findsOne);
    });
  });

  group('S-11 cross-family migration', () {
    testWidgets('asks before deleting the previous registration',
        (tester) async {
      final ds = source()
        ..inviteInfo = invite
        ..inviteeResult = const InviteeNeedsMigration('Lima');
      final signIns = <String>[];
      await pumpRegister(tester,
          dataSource: ds, inviteToken: validToken, signIns: signIns);
      await fillCommonFields(tester);
      await acceptTerms(tester);

      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      expect(find.text(l[K.registerMigrationTitle]), findsOne);
      expect(find.textContaining('Lima'), findsOne);
      expect(signIns, isEmpty, reason: 'nothing happened yet — it is a question');
    });

    testWidgets('confirming retries with the migration flag set',
        (tester) async {
      final ds = source()
        ..inviteInfo = invite
        ..inviteeResult = const InviteeNeedsMigration('Lima');
      await pumpRegister(tester, dataSource: ds, inviteToken: validToken);
      await fillCommonFields(tester);
      await acceptTerms(tester);
      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      ds.inviteeResult = const InviteeRegistered();
      await tapVisible(tester,
          find.widgetWithText(FilledButton, l[K.registerMigrationConfirm]));
      await tester.pumpAndSettle();

      expect(ds.inviteeRegistrations, hasLength(2));
      expect(ds.inviteeRegistrations.last['confirmMigration'], isTrue);
    });

    testWidgets('cancelling returns to the form with nothing done',
        (tester) async {
      final ds = source()
        ..inviteInfo = invite
        ..inviteeResult = const InviteeNeedsMigration('Lima');
      await pumpRegister(tester, dataSource: ds, inviteToken: validToken);
      await fillCommonFields(tester);
      await acceptTerms(tester);
      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      await tapVisible(
          tester, find.widgetWithText(TextButton, l[K.commonCancel]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.registerInvitedTitle]), findsOne);
      expect(ds.inviteeRegistrations, hasLength(1));
    });
  });

  group('U-13', () {
    testWidgets('an English session renders the English declaration and roles',
        (tester) async {
      await pumpRegister(tester,
          dataSource: source(), language: AppLanguage.en);
      await goToFamilyStep(tester, language: AppLanguage.en);

      expect(find.text('Step 2 of 2 · Your family'), findsOne);
      expect(find.text(ConsentDeclarations.creatorEn), findsOne);
      expect(find.widgetWithText(ChoiceChip, 'Mother'), findsOne);
      // The courtesy notice only exists for the English reader — the binding
      // text is the Portuguese one.
      expect(find.text(Localization(AppLanguage.en)[K.registerConsentBindingNotice]),
          findsOne);
    });

    testWidgets('the PT-BR session shows no binding notice (it is empty)',
        (tester) async {
      await pumpRegister(tester, dataSource: source());

      expect(l[K.registerConsentBindingNotice], isEmpty);
    });
  });
}
