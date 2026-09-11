// F-41 custom family roles.
//
// Three asymmetries carry the file, because each one is a product decision and
// not an oversight: a custom name is NEVER translated (it is family data),
// create/edit are Premium but DELETE is not (a lapsed family must still be able
// to clean up), and the client checks only length/emoji — every other rule is
// the DB's, whose sentence reaches the user verbatim.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_app/screens/custom_roles_screen.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const admin = Member(
    id: 1, fullName: 'Ana Souza', userId: 'u1', isAdmin: true, roleId: 1);
const plain = Member(id: 2, fullName: 'Bruno Lima', userId: 'u2', roleId: 2);

const builtIn = Role(id: 1, roleName: 'mother');
const custom = Role(id: 90, roleName: 'Vovó Coruja', familyId: 7, emoji: '🦉');
const customNoEmoji = Role(id: 91, roleName: 'Madrinha do coração', familyId: 7);

FakeCustodyDataSource source({
  String plan = 'premium',
  List<Role> roles = const [builtIn, custom],
  List<Member> members = const [admin],
}) =>
    FakeCustodyDataSource(members: members, days: [])
      ..family = Family(id: 7, name: 'Souza', plan: plan)
      ..roles = roles;

Future<void> pumpRoles(
  WidgetTester tester,
  FakeCustodyDataSource ds, {
  AppLanguage language = AppLanguage.ptBr,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(language),
    setLanguage: (_) async {},
    child: MaterialApp(home: CustomRolesScreen(dataSource: ds)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('listing', () {
    testWidgets('shows only the family\'s own roles, never the built-ins',
        (tester) async {
      await pumpRoles(tester, source());

      expect(find.text('🦉 Vovó Coruja'), findsOne);
      expect(find.text('Mãe'), findsNothing);
    });

    testWidgets('a role with no emoji renders bare', (tester) async {
      await pumpRoles(
          tester, source(roles: const [builtIn, customNoEmoji]));

      expect(find.text('Madrinha do coração'), findsOne);
    });

    testWidgets('an empty list says so', (tester) async {
      await pumpRoles(tester, source(roles: const [builtIn]));

      expect(find.text(l[K.rolesEmpty]), findsOne);
    });

    testWidgets('a custom name is NOT translated in an English session',
        (tester) async {
      await pumpRoles(tester, source(), language: AppLanguage.en);

      expect(find.text('🦉 Vovó Coruja'), findsOne);
    });
  });

  group('guards', () {
    testWidgets('a non-admin gets no form at all', (tester) async {
      await pumpRoles(tester, source(members: const [plain, admin]));

      expect(find.text(l[K.rolesCreate]), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a free family sees the Premium gate instead of the form',
        (tester) async {
      await pumpRoles(tester, source(plan: 'free'));

      expect(find.text(l[K.rolesPremiumGate]), findsOne);
      expect(find.text(l[K.rolesCreate]), findsNothing);
    });

    testWidgets('a free family can still DELETE — a lapsed plan must not trap '
        'the family with roles it cannot remove', (tester) async {
      final ds = source(plan: 'free');
      await pumpRoles(tester, ds);

      expect(find.byIcon(Icons.delete_outline), findsOne);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
    });
  });

  group('create', () {
    testWidgets('sends label and emoji', (tester) async {
      final ds = source();
      await pumpRoles(tester, ds);

      await tester.enterText(find.byType(TextField), 'Tia do interior');
      await tester.tap(find.widgetWithText(ChoiceChip, '🦋'));
      await tester.pump();
      await tester.tap(find.text(l[K.rolesCreate]));
      await tester.pumpAndSettle();

      expect(ds.customRoleWrites,
          [{'label': 'Tia do interior', 'emoji': '🦋', 'id': null}]);
    });

    testWidgets('"Sem emoji" sends none', (tester) async {
      final ds = source();
      await pumpRoles(tester, ds);

      await tester.enterText(find.byType(TextField), 'Sem carinha');
      await tester.tap(find.widgetWithText(ChoiceChip, l[KApp.rolesNoEmoji]));
      await tester.pump();
      await tester.tap(find.text(l[K.rolesCreate]));
      await tester.pumpAndSettle();

      expect(ds.customRoleWrites.single['emoji'], isNull);
    });

    testWidgets('a blank name never reaches the server, with the RPC\'s own '
        'wording', (tester) async {
      final ds = source();
      await pumpRoles(tester, ds);

      await tester.tap(find.text(l[K.rolesCreate]));
      await tester.pumpAndSettle();

      expect(find.text('Informe o nome do papel.'), findsOne);
      expect(ds.customRoleWrites, isEmpty);
    });

    testWidgets('the server\'s duplicate refusal is shown verbatim',
        (tester) async {
      final ds = source()
        ..throwOnFamilyWrite = Exception(
            '{"code":"23514","message":"Já existe um papel com esse nome."}');
      await pumpRoles(tester, ds);

      await tester.enterText(find.byType(TextField), 'Vovó Coruja');
      await tester.tap(find.text(l[K.rolesCreate]));
      await tester.pumpAndSettle();

      expect(find.text('Já existe um papel com esse nome.'), findsOne);
    });
  });

  group('edit', () {
    testWidgets('seeds the form with the current name and emoji',
        (tester) async {
      await pumpRoles(tester, source());

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      expect(find.text(l[KApp.rolesEditTitle]), findsOne);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, 'Vovó Coruja');
      expect(find.text(l[K.rolesSaveEdit]), findsOne);
    });

    testWidgets('saves against the role id', (tester) async {
      final ds = source();
      await pumpRoles(tester, ds);

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Vovó Corujinha');
      await tester.tap(find.text(l[K.rolesSaveEdit]));
      await tester.pumpAndSettle();

      expect(ds.customRoleWrites,
          [{'label': 'Vovó Corujinha', 'emoji': '🦉', 'id': 90}]);
    });

    testWidgets('cancelling returns to the create form', (tester) async {
      await pumpRoles(tester, source());

      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, l[K.commonCancel]));
      await tester.pumpAndSettle();

      expect(find.text(l[KApp.rolesCreateTitle]), findsOne);
    });
  });

  group('delete', () {
    testWidgets('asks before deleting', (tester) async {
      final ds = source();
      await pumpRoles(tester, ds);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text(l[K.rolesDeleteConfirm]), findsOne);
      expect(ds.deletedRoles, isEmpty);
    });

    testWidgets('confirming deletes', (tester) async {
      final ds = source();
      await pumpRoles(tester, ds);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.rolesYes]));
      await tester.pumpAndSettle();

      expect(ds.deletedRoles, [90]);
    });

    testWidgets('declining leaves it alone', (tester) async {
      final ds = source();
      await pumpRoles(tester, ds);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.rolesNo]));
      await tester.pumpAndSettle();

      expect(ds.deletedRoles, isEmpty);
      expect(find.text(l[K.rolesDeleteConfirm]), findsNothing);
    });

    testWidgets('the "role in use" refusal reaches the user verbatim',
        (tester) async {
      final ds = source()
        ..throwOnFamilyWrite = Exception(
            '{"code":"23514","message":"Este papel está em uso por um membro '
            'ou convite e não pode ser excluído."}');
      await pumpRoles(tester, ds);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.rolesYes]));
      await tester.pumpAndSettle();

      expect(find.textContaining('está em uso'), findsOne);
    });
  });
}
