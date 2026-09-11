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
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/invite_info.dart';
import 'package:entrelares_app/screens/register_screen.dart';
import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

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
}) async {
  final l = Localization(AppLanguage.ptBr);
  await tester.enterText(
      find.widgetWithText(TextField, l[K.registerFullName]), name);
  await tester.enterText(
      find.widgetWithText(TextField, l[K.commonPassword]), password);
  await tester.enterText(
      find.widgetWithText(TextField, l[K.commonConfirmPassword]), password);
  await tester.pump();
}

Future<void> acceptTerms(WidgetTester tester) =>
    tapVisible(tester, find.byType(Checkbox));

/// "Criar conta" is BOTH the heading and the submit label in PT-BR, so the
/// button is always addressed through its widget type.
Finder submitButton(Localization l) =>
    find.widgetWithText(FilledButton, l[K.registerSubmit]);

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('founder branch', () {
    testWidgets('offers the family name and the 21-role grid', (tester) async {
      await pumpRegister(tester, dataSource: source());

      expect(find.text(l[K.registerCreateSubtitle]), findsOne);
      expect(
          find.widgetWithText(TextField, l[K.registerFamilyName]), findsOne);
      expect(find.byType(ChoiceChip), findsNWidgets(RoleCatalog.all.length));
      expect(find.widgetWithText(ChoiceChip, '👩 Mãe'), findsOne);
    });

    testWidgets('shows the A-1.1 awareness declaration', (tester) async {
      await pumpRegister(tester, dataSource: source());

      expect(find.text(ConsentDeclarations.creator), findsOne);
      expect(find.text(ConsentDeclarations.invitee), findsNothing);
    });

    testWidgets('the submit button is dead until consent is given',
        (tester) async {
      await pumpRegister(tester, dataSource: source());

      final button = tester.widget<FilledButton>(submitButton(l));
      expect(button.onPressed, isNull);

      await acceptTerms(tester);

      final enabled = tester.widget<FilledButton>(submitButton(l));
      expect(enabled.onPressed, isNotNull);
    });

    testWidgets('refuses a form with no role, in the web\'s order',
        (tester) async {
      final ds = source();
      await pumpRegister(tester, dataSource: ds);
      await fillCommonFields(tester);
      await tester.enterText(
          find.widgetWithText(TextField, l[K.commonEmail]), 'ana@example.com');
      await tester.enterText(
          find.widgetWithText(TextField, l[K.registerFamilyName]), 'Souza');
      await acceptTerms(tester);

      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      expect(find.text(l[K.registerErrorRoleRequired]), findsOne);
      expect(ds.signUps, isEmpty, reason: 'nothing may reach the server');
    });

    testWidgets('a complete form signs up and lands on "confirm your e-mail"',
        (tester) async {
      final ds = source();
      await pumpRegister(tester, dataSource: ds);
      await fillCommonFields(tester, name: 'Ana Souza');
      await tester.enterText(
          find.widgetWithText(TextField, l[K.commonEmail]), 'ana@example.com');
      await tester.enterText(
          find.widgetWithText(TextField, l[K.registerFamilyName]), 'Souza');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, '👩 Mãe'));
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

    testWidgets('a refusal is translated and the form stays put',
        (tester) async {
      final ds = source()..signUpFailureKey = K.authErrAlreadyRegistered;
      await pumpRegister(tester, dataSource: ds);
      await fillCommonFields(tester, name: 'Ana Souza');
      await tester.enterText(
          find.widgetWithText(TextField, l[K.commonEmail]), 'ana@example.com');
      await tester.enterText(
          find.widgetWithText(TextField, l[K.registerFamilyName]), 'Souza');
      await tapVisible(tester, find.widgetWithText(ChoiceChip, '👩 Mãe'));
      await acceptTerms(tester);

      await tapVisible(tester, submitButton(l));
      await tester.pumpAndSettle();

      expect(find.text(l[K.authErrAlreadyRegistered]), findsOne);
      expect(find.text(l[K.registerConfirmEmailTitle]), findsNothing);
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

      expect(find.text(ConsentDeclarations.creatorEn), findsOne);
      expect(find.widgetWithText(ChoiceChip, '👩 Mother'), findsOne);
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
