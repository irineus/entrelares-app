// `/profile` and `/profile/{id}` — every member edit plus the account surface.
//
// The thread running through the file is S-10: granting admin, changing e-mail
// or password, and exporting personal data all cost a password FIRST. Each of
// those tests drives the real sudo sheet, because "the button called the RPC"
// is not the property that matters — "the RPC did not run until the password
// was confirmed" is.
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

const roleMother = Role(id: 1, roleName: 'mother');
const roleFather = Role(id: 2, roleName: 'father');

const adminMember = Member(
  id: 1,
  fullName: 'Ana Souza',
  userId: 'u1',
  isAdmin: true,
  roleId: 1,
  email: 'ana@example.com',
);
const otherMember = Member(
  id: 2,
  fullName: 'Bruno Lima',
  userId: 'u2',
  roleId: 2,
  email: 'bruno@example.com',
);

FakeCustodyDataSource source({List<Member> members = const [adminMember, otherMember]}) =>
    FakeCustodyDataSource(members: members, days: [])
      ..family = const Family(id: 7, name: 'Souza', plan: 'free')
      ..roles = const [roleMother, roleFather]
      ..sudoPassword = 'segredo123';

Future<void> pumpProfile(
  WidgetTester tester,
  FakeCustodyDataSource ds, {
  int? profileId,
  SudoService? sudo,
  AppLanguage language = AppLanguage.ptBr,
  List<String>? deliveredExports,
  Future<void> Function(String, String)? deliverExport,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(language),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: ProfileScreen(
        dataSource: ds,
        sudo: sudo ?? SudoService(ds),
        profileId: profileId,
        // The real delivery needs a temp directory and the share channel;
        // what the test cares about is the payload reaching it.
        deliverExport: deliverExport ??
            (fileName, json) async => deliveredExports?.add(json),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// Drives the 🔐 sheet the way a person would.
Future<void> confirmSudo(WidgetTester tester) async {
  final l = Localization(AppLanguage.ptBr);
  expect(find.text(l[K.sudoTitle]), findsOne,
      reason: 'the action must ask for the password first');
  await tester.enterText(find.byType(TextField).last, 'segredo123');
  await tester.pump();
  await tester.tap(find.text(l[K.sudoConfirm]));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('own profile', () {
    testWidgets('shows the account sections', (tester) async {
      await pumpProfile(tester, source());

      expect(find.text(l[K.profSectionData]), findsOne);
      expect(find.text(l[K.profSectionEmail]), findsOne);
      expect(find.text(l[K.profSectionPassword]), findsOne);
      expect(find.text(l[K.profSectionLgpd]), findsOne);
      // Nobody promotes themselves.
      expect(find.text(l[K.profSectionAdmin]), findsNothing);
    });

    testWidgets('saves the name through the own-profile path', (tester) async {
      final ds = source();
      await pumpProfile(tester, ds);

      await tester.enterText(
          find.widgetWithText(TextField, l[K.registerFullName]),
          'Ana Souza Lima');
      await tester.tap(find.text(l[K.profSaveData]));
      await tester.pumpAndSettle();

      expect(ds.nameUpdates,
          [{'id': 1, 'name': 'Ana Souza Lima', 'own': true}]);
    });

    testWidgets('a one-letter name never reaches the server', (tester) async {
      final ds = source();
      await pumpProfile(tester, ds);

      await tester.enterText(
          find.widgetWithText(TextField, l[K.registerFullName]), 'A');
      await tester.tap(find.text(l[K.profSaveData]));
      await tester.pumpAndSettle();

      expect(find.text(l[KApp.profErrNameTooShort]), findsOne);
      expect(ds.nameUpdates, isEmpty);
    });
  });

  group('another member (admin only)', () {
    testWidgets('an admin opens it and gets the admin section', (tester) async {
      await pumpProfile(tester, source(), profileId: 2);

      expect(find.text('Bruno Lima'), findsWidgets);
      expect(find.text(l[K.profSectionAdmin]), findsOne);
      expect(find.text(l[K.profMakeAdmin]), findsOne);
      // Somebody else's account surface is not an admin's business.
      expect(find.text(l[K.profSectionEmail]), findsNothing);
      expect(find.text(l[K.profSectionLgpd]), findsNothing);
    });

    testWidgets('a NON-admin asking for someone else lands on their own',
        (tester) async {
      // The fake reports the first member as "me".
      await pumpProfile(tester, source(members: const [otherMember, adminMember]),
          profileId: 1);

      expect(find.text('Bruno Lima'), findsWidgets);
      expect(find.text(l[K.profSectionAdmin]), findsNothing);
    });

    testWidgets('an admin changes another member\'s role', (tester) async {
      final ds = source();
      await pumpProfile(tester, ds, profileId: 2);

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mãe').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.profSaveData]));
      await tester.pumpAndSettle();

      expect(ds.roleUpdates, [{'id': 2, 'roleId': 1}]);
    });
  });

  group('S-10 — the password gate', () {
    testWidgets('granting admin asks for the password FIRST', (tester) async {
      final ds = source();
      await pumpProfile(tester, ds, profileId: 2);

      await tester.tap(find.text(l[K.profMakeAdmin]));
      await tester.pumpAndSettle();
      expect(ds.adminUpdates, isEmpty, reason: 'nothing before the password');

      await confirmSudo(tester);

      expect(ds.adminUpdates, [{'id': 2, 'isAdmin': true}]);
    });

    testWidgets('dismissing the prompt leaves the flag alone', (tester) async {
      final ds = source();
      await pumpProfile(tester, ds, profileId: 2);

      await tester.tap(find.text(l[K.profMakeAdmin]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.commonCancel]));
      await tester.pumpAndSettle();

      expect(ds.adminUpdates, isEmpty);
    });

    testWidgets('an already-elevated session acts without asking again',
        (tester) async {
      final ds = source();
      final sudo = SudoService(ds);
      await sudo.elevate('segredo123', l);
      await pumpProfile(tester, ds, profileId: 2, sudo: sudo);

      await tester.tap(find.text(l[K.profMakeAdmin]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.sudoTitle]), findsNothing);
      expect(ds.adminUpdates, [{'id': 2, 'isAdmin': true}]);
    });

    testWidgets('changing the e-mail is gated, and only says "link sent"',
        (tester) async {
      final ds = source();
      await pumpProfile(tester, ds);

      await tester.enterText(
          find.widgetWithText(TextField, l[K.profNewEmail]), 'nova@example.com');
      await tester.tap(find.text(l[K.profChangeEmail]));
      await tester.pumpAndSettle();
      expect(ds.emailUpdates, isEmpty);

      await confirmSudo(tester);

      expect(ds.emailUpdates, ['nova@example.com']);
      expect(find.text(l[K.profEmailLinkSent]), findsOne);
      expect(ds.accountActions, contains('email_change_requested'));
    });

    testWidgets('the same address is refused before the prompt', (tester) async {
      final ds = source();
      await pumpProfile(tester, ds);

      await tester.enterText(
          find.widgetWithText(TextField, l[K.profNewEmail]), 'ANA@example.com');
      await tester.tap(find.text(l[K.profChangeEmail]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.profErrSameEmail]), findsOne);
      expect(find.text(l[K.sudoTitle]), findsNothing);
    });

    testWidgets('changing the password is gated and logged', (tester) async {
      final ds = source();
      await pumpProfile(tester, ds);

      await tester.enterText(
          find.widgetWithText(TextField, l[K.updatePwdNewPassword]),
          'novaSenha123');
      await tester.enterText(
          find.widgetWithText(TextField, l[K.profConfirmNewPassword]),
          'novaSenha123');
      await tester.tap(find.text(l[K.profChangePassword]));
      await tester.pumpAndSettle();
      expect(ds.passwordUpdates, isEmpty);

      await confirmSudo(tester);

      expect(ds.passwordUpdates, ['novaSenha123']);
      expect(ds.accountActions, contains('password_changed'));
    });

    testWidgets('a mismatched confirmation never reaches the prompt',
        (tester) async {
      final ds = source();
      await pumpProfile(tester, ds);

      await tester.enterText(
          find.widgetWithText(TextField, l[K.updatePwdNewPassword]),
          'novaSenha123');
      await tester.enterText(
          find.widgetWithText(TextField, l[K.profConfirmNewPassword]),
          'outraSenha123');
      await tester.tap(find.text(l[K.profChangePassword]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.profErrPasswordMismatch]), findsOne);
      expect(find.text(l[K.sudoTitle]), findsNothing);
    });

    testWidgets('a short password is refused with the catalogued sentence',
        (tester) async {
      final ds = source();
      await pumpProfile(tester, ds);

      await tester.enterText(
          find.widgetWithText(TextField, l[K.updatePwdNewPassword]), 'curta');
      await tester.tap(find.text(l[K.profChangePassword]));
      await tester.pumpAndSettle();

      expect(find.text(l[KApp.profErrPasswordShort]), findsOne);
      expect(ds.passwordUpdates, isEmpty);
    });

    testWidgets('MY OWN reset e-mail needs no elevation — the mailbox is the '
        'proof', (tester) async {
      final ds = source();
      await pumpProfile(tester, ds);

      await tester.tap(find.text(l[K.profResetByEmail]));
      await tester.pumpAndSettle();

      expect(find.text(l[K.sudoTitle]), findsNothing);
      expect(ds.passwordResets, ['ana@example.com']);
    });

    testWidgets('sending it for ANOTHER member does need elevation',
        (tester) async {
      final ds = source();
      await pumpProfile(tester, ds, profileId: 2);

      await tester.tap(find.text(l[K.profSendPasswordReset]));
      await tester.pumpAndSettle();
      expect(ds.passwordResets, isEmpty);

      await confirmSudo(tester);

      expect(ds.passwordResets, ['bruno@example.com']);
    });
  });

  group('F-17 export', () {
    testWidgets('is gated, then fetches, delivers and logs the action',
        (tester) async {
      final ds = source();
      final delivered = <String>[];
      await pumpProfile(tester, ds, deliveredExports: delivered);

      await tester.tap(find.text(l[K.profExportAction]));
      await tester.pumpAndSettle();
      expect(ds.exportFetches, 0, reason: 'no personal data before the password');

      await confirmSudo(tester);

      expect(ds.exportFetches, 1);
      expect(delivered, hasLength(1));
      expect(delivered.single, contains('"exportInfo"'));
      expect(ds.accountActions, contains('data_exported'));
    });

    testWidgets('a delivery that fails says WHY, with no placeholder left',
        (tester) async {
      // Two defects in one screenshot, both found by the web QA: the export
      // failed on the web (the native delivery needs dart:io) and the failure
      // sentence printed its own `{0}` to the user, because the call site read
      // the catalog key instead of formatting it.
      final ds = source();
      await pumpProfile(tester, ds,
          deliverExport: (_, _) async => throw Exception('sem canal de arquivo'));

      await tester.tap(find.text(l[K.profExportAction]));
      await tester.pumpAndSettle();
      await confirmSudo(tester);

      final snack = find.textContaining('sem canal de arquivo');
      expect(snack, findsOneWidget,
          reason: "the server's own words reach the reader (pilot lesson 4)");
      expect(find.textContaining('{0}'), findsNothing,
          reason: 'the placeholder is filled, never printed');
    });

    testWidgets('dismissing the prompt reads nothing at all', (tester) async {
      final ds = source();
      await pumpProfile(tester, ds);

      await tester.tap(find.text(l[K.profExportAction]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.commonCancel]));
      await tester.pumpAndSettle();

      expect(ds.exportFetches, 0);
      expect(ds.accountActions, isEmpty);
    });
  });

  testWidgets('the legal links are reachable from the account page',
      (tester) async {
    await pumpProfile(tester, source());

    expect(find.text(l[K.commonPrivacyPolicy]), findsOne);
    expect(find.text(l[K.commonTermsOfUse]), findsOne);
  });

  testWidgets('a departed member\'s profile is banner-first', (tester) async {
    const departed = Member(
        id: 2,
        fullName: 'Bruno Lima',
        userId: 'u2',
        roleId: 2,
        email: 'bruno@example.com',
        leftAt: '2026-07-01T00:00:00Z');
    await pumpProfile(tester, source(members: const [adminMember, departed]),
        profileId: 2);

    expect(find.text(l[K.profFrozenBanner]), findsOne);
    // Nothing to promote: they hold no seat.
    expect(find.text(l[K.profSectionAdmin]), findsNothing);
  });
}
