// F-66 — a Google-only account sets a first password from the profile.
//
// What is pinned: the action exists only where the SERVER said there is no
// password (never on an unanswered question, never beside a password); the
// sheet sets, with no current-password field and no reset door; the write
// runs behind the S-10 sudo, whose e-mailed code (S-21) is the proof such an
// account gives — the gate is not weakened; and afterwards the page asks the
// server again, so the password door and the Senha card appear at once.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_app/screens/profile_screen.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

final pt = Localization(AppLanguage.ptBr);
const setKey = ValueKey('profile-set-password');

const me = Member(
  id: 1,
  fullName: 'Ana Souza',
  userId: 'u1',
  isAdmin: true,
  roleId: 1,
  email: 'ana@gmail.com',
);

FakeCustodyDataSource googleOnly({bool? hasPassword = false}) =>
    FakeCustodyDataSource(members: const [me], days: const [])
      ..family = const Family(id: 7, name: 'Souza', plan: 'free')
      ..roles = const [Role(id: 1, roleName: 'mother')]
      ..providers = ['google']
      ..sessionEmailValue = 'ana@gmail.com'
      ..identities = const [SignInIdentity('google', email: 'ana@gmail.com')]
      ..hasPassword = hasPassword
      // No password to answer the prompt with: the e-mailed code is the proof.
      ..sudoPassword = null
      ..sudoCode = '246810';

Future<void> pumpProfile(WidgetTester tester, FakeCustodyDataSource ds) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: pt,
    setLanguage: (_) async {},
    child: MaterialApp(
      home: ProfileScreen(
        dataSource: ds,
        sudo: SudoService(ds),
        deliverExport: (_, _) async {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> fillAndSubmit(WidgetTester tester, String pw) async {
  final fields = find.byType(TextField);
  await tester.enterText(fields.at(fields.evaluate().length - 2), pw);
  await tester.enterText(fields.last, pw);
  await tester.tap(find.text(pt[KApp.profSetPasswordAction]).last);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('offered where the server said NO password', (tester) async {
    await pumpProfile(tester, googleOnly());
    expect(find.byKey(setKey), findsOneWidget);
  });

  testWidgets('never on an unanswered question', (tester) async {
    await pumpProfile(tester, googleOnly(hasPassword: null));
    expect(find.byKey(setKey), findsNothing);
  });

  testWidgets('never beside a password', (tester) async {
    await pumpProfile(tester, googleOnly(hasPassword: true));
    expect(find.byKey(setKey), findsNothing);
  });

  testWidgets('the sheet sets: no current-password field, no reset door',
      (tester) async {
    await pumpProfile(tester, googleOnly());
    await tester.tap(find.byKey(setKey));
    await tester.pumpAndSettle();

    expect(find.text(pt[KApp.profSetPasswordTitle]), findsWidgets);
    expect(find.text(pt[KApp.profSetPasswordLead]), findsOneWidget);
    expect(find.text(pt[K.profResetByEmail]), findsNothing);
    expect(find.text(pt[K.profForgotCurrent]), findsNothing);
    expect(find.text(pt[K.sudoCurrentPassword]), findsNothing);
  });

  testWidgets('behind the sudo with the e-mailed code; then the password door '
      'and the Senha card appear without a reload', (tester) async {
    final ds = googleOnly();
    await pumpProfile(tester, ds);
    await tester.tap(find.byKey(setKey));
    await tester.pumpAndSettle();
    await fillAndSubmit(tester, 'novaSenha123');

    // S-10: nothing written before the proof.
    expect(ds.passwordUpdates, isEmpty);
    expect(find.text(pt[K.sudoTitle]), findsOneWidget);
    // The editor stays busy under the prompt (its spinner never settles):
    // plain pumps, as the S-10 profile tests do.
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 300));
      }
    }

    await tester.tap(find.text(pt[KApp.sudoSendCode]));
    await settle();
    await tester.enterText(find.byType(TextField).last, '246810');
    await tester.pump();
    await tester.tap(find.text(pt[K.sudoConfirm]));
    await settle();

    expect(ds.codeAttempts, ['246810']);
    expect(ds.passwordUpdates, ['novaSenha123']);
    expect(ds.accountActions, contains('password_changed'));
    expect(find.text(pt[KApp.profSetPasswordDone]), findsOneWidget);
    // Asked again: both doors, the Senha card, no more "set" action.
    expect(find.byKey(const ValueKey('sign-in-method-email')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-edit-password')), findsOneWidget);
    expect(find.byKey(setKey), findsNothing);
  });

  testWidgets('a short password never reaches the prompt', (tester) async {
    final ds = googleOnly();
    await pumpProfile(tester, ds);
    await tester.tap(find.byKey(setKey));
    await tester.pumpAndSettle();
    await fillAndSubmit(tester, 'curta');
    expect(find.text(pt[KApp.profErrPasswordShort]), findsOneWidget);
    expect(find.text(pt[K.sudoTitle]), findsNothing);
    expect(ds.passwordUpdates, isEmpty);
  });
}
