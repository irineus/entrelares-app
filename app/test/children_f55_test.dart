// F-55 (PR 1) — the child entity on screen.
//
// The server is the rule (flag, admin, name); these pin what the client adds:
// the Família row exists only with `feature.child_agenda` on and reads the
// name(s), the page is read at rest and edited in a sheet, only an admin gets
// the doors, and a refusal keeps the sheet open with the server's sentence.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/child.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/screens/family_children_screen.dart';
import 'package:entrelares_app/screens/family_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const admin = Member(
    id: 1, fullName: 'Ana Souza', userId: 'u1', isAdmin: true, roleId: 1);
const plain = Member(id: 2, fullName: 'Bruno Lima', userId: 'u2', roleId: 2);

const on = {'feature.child_agenda': 'true'};

FakeCustodyDataSource source({
  List<Member> members = const [admin, plain],
  Map<String, String> settings = on,
  List<Child> children = const [],
  bool premium = false,
}) =>
    FakeCustodyDataSource(members: members, days: [])
      ..family = premium
          ? Family(
              id: 7,
              name: 'Souza',
              plan: 'free',
              compPremiumAt: DateTime.utc(2026, 1, 1))
          : const Family(id: 7, name: 'Souza', plan: 'free')
      ..publicSettings = settings
      ..children = List.of(children);

Future<void> pumpPage(WidgetTester tester, FakeCustodyDataSource ds,
    {AppLanguage language = AppLanguage.ptBr, VoidCallback? onOpenPlan}) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(language),
    setLanguage: (_) async {},
    child: MaterialApp(
        home: FamilyChildrenScreen(dataSource: ds, onOpenPlan: onOpenPlan)),
  ));
  await tester.pumpAndSettle();
}

Future<void> pumpFamily(WidgetTester tester, FakeCustodyDataSource ds,
    {VoidCallback? onOpenChildren}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: FamilyScreen(
        dataSource: ds,
        adminMode: AdminMode(),
        sudo: SudoService(ds),
        onOpenChildren: onOpenChildren,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

const lia = Child(id: 5, familyId: 7, firstName: 'Lia', sortOrder: 0);

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('the Família row', () {
    testWidgets('flag OFF: no row at all — the server would refuse the page',
        (tester) async {
      await pumpFamily(tester, source(settings: const {}),
          onOpenChildren: () {});
      expect(find.byKey(const ValueKey('family-children-row')), findsNothing);
    });

    testWidgets('flag ON: the row names the child, and opens the page',
        (tester) async {
      var opened = 0;
      await pumpFamily(tester, source(children: const [lia]),
          onOpenChildren: () => opened++);
      final row = find.byKey(const ValueKey('family-children-row'));
      expect(row, findsOne);
      expect(find.descendant(of: row, matching: find.text('Lia')), findsOne);
      await tester.tap(row);
      expect(opened, 1);
    });

    testWidgets('flag ON with no child: the row says there is none',
        (tester) async {
      await pumpFamily(tester, source(), onOpenChildren: () {});
      expect(find.text(l[KApp.famChildRowEmpty]), findsOne);
    });
  });

  group('the page', () {
    testWidgets('an admin with no child adds one through the sheet',
        (tester) async {
      final ds = source();
      await pumpPage(tester, ds);
      await tester.tap(find.text(l[KApp.childAdd]));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('child-name-field')), '  Maria   Clara ');
      await tester.tap(find.text(l[K.commonSave]));
      await tester.pumpAndSettle();

      expect(ds.childWrites, ['add:Maria Clara']);
      expect(find.text('Maria Clara'), findsOne);
      expect(find.text(l[KApp.childAdded]), findsOne);
      // F-07: a free family has one child included — the next one is the
      // Premium gate, not a door the server would refuse.
      expect(find.text(l[KApp.childAdd]), findsNothing);
      expect(find.byKey(const ValueKey('child-add-another')), findsNothing);
      expect(find.byKey(const ValueKey('child-free-cap')), findsOne);
    });

    testWidgets('an empty name never reaches the server', (tester) async {
      final ds = source();
      await pumpPage(tester, ds);
      await tester.tap(find.text(l[KApp.childAdd]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.commonSave]));
      await tester.pumpAndSettle();
      expect(ds.childWrites, isEmpty);
      expect(find.text('Informe o primeiro nome da criança.'), findsOne);
    });

    testWidgets('a server refusal keeps the sheet open with its sentence',
        (tester) async {
      final ds = source()
        ..throwOnChildWrite =
            Exception('{"code":"23514","message":'
                '"Já existe uma criança com esse nome na família."}');
      await pumpPage(tester, ds);
      await tester.tap(find.text(l[KApp.childAdd]));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('child-name-field')), 'Lia');
      await tester.tap(find.text(l[K.commonSave]));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('child-name-field')), findsOne);
      expect(find.textContaining('Já existe uma criança'), findsOne);
    });

    testWidgets('an admin renames through the pencil', (tester) async {
      final ds = source(children: const [lia]);
      await pumpPage(tester, ds);
      await tester.tap(find.byKey(const ValueKey('child-edit-5')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('child-name-field')), 'Lia Maria');
      await tester.tap(find.text(l[K.commonSave]));
      await tester.pumpAndSettle();
      expect(ds.childWrites, ['rename:5:Lia Maria']);
      expect(find.text('Lia Maria'), findsOne);
    });

    testWidgets('removing asks first, in the sheet, and only then removes',
        (tester) async {
      final ds = source(children: const [lia]);
      await pumpPage(tester, ds);
      await tester.tap(find.byKey(const ValueKey('child-edit-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('child-remove')));
      await tester.pumpAndSettle();
      expect(ds.childWrites, isEmpty);
      final confirm = find.byKey(const ValueKey('child-remove-confirm'));
      expect(
          find.descendant(
              of: confirm,
              matching:
                  find.text(l.format(KApp.childRemoveConfirm, ['Lia']))),
          findsOne);
      await tester.tap(find.descendant(
          of: confirm, matching: find.text(l[KApp.childRemove])));
      await tester.pumpAndSettle();
      expect(ds.childWrites, ['remove:5']);
      expect(find.text(l[KApp.childRemoved]), findsOne);
      expect(find.text(l[KApp.childEmpty]), findsOne);
    });

    testWidgets('a member reads the name and gets no door', (tester) async {
      await pumpPage(tester,
          source(members: const [plain, admin], children: const [lia]));
      expect(find.text('Lia'), findsOne);
      expect(find.byKey(const ValueKey('child-edit-5')), findsNothing);
      expect(find.text(l[KApp.childAdminOnly]), findsOne);
    });

    testWidgets('a member with no child sees no add door', (tester) async {
      await pumpPage(tester, source(members: const [plain, admin]));
      expect(find.text(l[KApp.childAdd]), findsNothing);
      expect(find.text(l[KApp.childAdminOnly]), findsOne);
    });

    testWidgets('the name is family data: shown as typed in English',
        (tester) async {
      await pumpPage(tester, source(children: const [lia]),
          language: AppLanguage.en);
      expect(find.text('Lia'), findsOne);
      expect(find.text('Children'), findsOne);
    });
  });

  // F-07 (PR 1): more than one child; the second one onwards is Premium.
  group('more than one child', () {
    const theo = Child(id: 6, familyId: 7, firstName: 'Theo', sortOrder: 1);

    testWidgets('free with one child: the gate says the live number and '
        'lands on the plan page', (tester) async {
      var opened = 0;
      await pumpPage(tester, source(children: const [lia]),
          onOpenPlan: () => opened++);
      final gate = find.byKey(const ValueKey('child-free-cap'));
      expect(
          find.descendant(
              of: gate,
              matching: find.text(l.format(KApp.childFreeCapOne, [1]))),
          findsOne);
      await tester.tap(
          find.descendant(of: gate, matching: find.text(l[K.famSeePremium])));
      expect(opened, 1);
    });

    testWidgets('the operator raising children.free_max opens the door',
        (tester) async {
      await pumpPage(
          tester,
          source(
              children: const [lia],
              settings: const {...on, 'children.free_max': '2'}));
      expect(find.byKey(const ValueKey('child-free-cap')), findsNothing);
      expect(find.byKey(const ValueKey('child-add-another')), findsOne);
    });

    testWidgets('Premium adds another child and lists both', (tester) async {
      final ds = source(children: const [lia], premium: true);
      await pumpPage(tester, ds);
      await tester.tap(find.byKey(const ValueKey('child-add-another')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('child-name-field')), 'Theo');
      await tester.tap(find.text(l[K.commonSave]));
      await tester.pumpAndSettle();
      expect(ds.childWrites, ['add:Theo']);
      expect(find.text('Lia'), findsOne);
      expect(find.text('Theo'), findsOne);
      expect(find.byKey(const ValueKey('child-add-another')), findsOne);
    });

    testWidgets('a downgraded family keeps both children; only the next '
        'one meets the gate', (tester) async {
      await pumpPage(tester, source(children: const [lia, theo]));
      expect(find.text('Lia'), findsOne);
      expect(find.text('Theo'), findsOne);
      expect(find.byKey(const ValueKey('child-edit-6')), findsOne);
      expect(find.byKey(const ValueKey('child-free-cap')), findsOne);
    });

    testWidgets('at the ceiling there is no door, only the limit',
        (tester) async {
      await pumpPage(
          tester,
          source(
              children: const [lia, theo],
              premium: true,
              settings: const {...on, 'children.max_per_family': '2'}));
      expect(find.byKey(const ValueKey('child-add-another')), findsNothing);
      expect(find.byKey(const ValueKey('child-free-cap')), findsNothing);
      expect(find.text(l.format(KApp.childMaxCap, [2])), findsOne);
    });

    testWidgets('a member sees neither the door nor the gate', (tester) async {
      await pumpPage(tester,
          source(members: const [plain, admin], children: const [lia]));
      expect(find.byKey(const ValueKey('child-free-cap')), findsNothing);
      expect(find.byKey(const ValueKey('child-add-another')), findsNothing);
    });

    testWidgets('the Família row names every child', (tester) async {
      await pumpFamily(tester, source(children: const [lia, theo]),
          onOpenChildren: () {});
      expect(find.text('Lia e Theo'), findsOne);
    });
  });
}
