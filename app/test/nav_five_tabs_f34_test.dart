// F-34 — the bar with five tabs: Calendário, Família, Notificações,
// Despesas, Relatórios. On a 360 dp phone a slot is 72 dp and "Notificações"
// is 79.7 dp at 1.0× with the real Inter, so the bar shows the selected label
// alone; the host's fallback font would make every glyph a square, so Inter is
// loaded first (the U-34 harness).
import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:entrelares_app/screens/home_shell.dart';
import 'package:entrelares_app/services/account_identity.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'calendar_slice_test.dart' show FakeCustodyDataSource;

Future<void> _loadInter() async {
  Future<ByteData> bytes(String file) async => ByteData.sublistView(
      Uint8List.fromList(await File('assets/fonts/$file').readAsBytes()));
  final inter = FontLoader('Inter');
  for (final f in [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
  ]) {
    inter.addFont(bytes(f));
  }
  await inter.load();
}


const _phone = Size(360, 740);
const _wide = Size(800, 900);
const _paths = ['/', '/family', '/notifications', '/expenses', '/reports'];

Widget _shellApp(Localization l,
    {required int selected,
    required ValueNotifier<bool> expensesTab,
    ValueNotifier<bool>? chatTab}) {
  final router = GoRouter(
    initialLocation: _paths[selected],
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(
            shell: shell,
            adminMode: AdminMode(),
            identity: AccountIdentity(),
            onSignOut: () async {},
            onOpenProfile: () {},
            expensesTab: expensesTab,
            chatTab: chatTab,
            badge: NotificationBadge(
                FakeCustodyDataSource(members: const [], days: []))),
        branches: [
          for (final path in _paths)
            StatefulShellBranch(routes: [
              GoRoute(
                  path: path,
                  builder: (_, _) => Scaffold(body: Text('page:$path'))),
            ]),
        ],
      ),
    ],
  );
  return AppL10n(
    l: l,
    setLanguage: (_) async {},
    child: MaterialApp.router(theme: AppTheme.light, routerConfig: router),
  );
}

/// F-34 — the bar with Despesas: five tabs, responsive (owner, 24/09/2026):
/// every label while they all fit at 1.3×, the selected one alone when not —
/// measured with the real Inter. And no Despesas at all while it is off.
void main() {
  setUpAll(_loadInter);

  Future<void> useSize(WidgetTester tester, Size size, double scale) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }

  RenderParagraph paragraphOf(WidgetTester tester, String label) =>
      tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byType(NavigationBar), matching: find.text(label)));

  void expectOneLineIn(WidgetTester tester, String label, double slot) {
    final paragraph = paragraphOf(tester, label);
    final lines = paragraph
        .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: label.length))
        .map((box) => box.top)
        .toSet();
    expect(lines, hasLength(1), reason: '"$label" wrapped');
    expect(paragraph.size.width, lessThanOrEqualTo(slot),
        reason: '"$label" is wider than its slot');
  }

  final keys = [
    K.navCalendar,
    K.navFamily,
    K.navNotificationsShort,
    KApp.expenseNav,
    K.navReports,
  ];

  for (final language in AppLanguage.values) {
    final l = Localization(language);
    for (final scale in [1.0, 1.3]) {
      for (var selected = 0; selected < _paths.length; selected++) {
        testWidgets(
            '$language @$scale on a 360 dp phone, tab $selected: only the '
            'selected label, on one line inside its slot', (tester) async {
          await useSize(tester, _phone, scale);
          await tester.pumpWidget(_shellApp(l,
              selected: selected, expensesTab: ValueNotifier(true)));
          await tester.pumpAndSettle();

          final bar =
              tester.widget<NavigationBar>(find.byType(NavigationBar));
          expect(bar.destinations, hasLength(5));
          expect(bar.labelBehavior,
              NavigationDestinationLabelBehavior.onlyShowSelected);
          expectOneLineIn(tester, l[keys[selected]], _phone.width / 5);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('$language @1.3 on a wide screen: every label shows',
        (tester) async {
      await useSize(tester, _wide, 1.3);
      await tester.pumpWidget(
          _shellApp(l, selected: 3, expensesTab: ValueNotifier(true)));
      await tester.pumpAndSettle();
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.labelBehavior, isNull);
      for (final key in keys) {
        expectOneLineIn(tester, l[key], _wide.width / 5);
      }
    });
  }

  // F-35 (owner, 24/09/2026): the final bar — Calendário · Família ·
  // Comunicação · Despesas · Relatórios. "Comunicação" (85.6 dp) does not fit
  // a 360 dp slot even alone at 0.85×, so that phone gets ICONS; where it
  // fits, the labels stay. In English the tab is "Inbox", which fits.
  for (final scale in [1.0, 1.3]) {
    testWidgets('PT @$scale, the final bar on 360 dp: icons only, the name '
        'still spoken', (tester) async {
      final l = Localization(AppLanguage.ptBr);
      await useSize(tester, _phone, scale);
      await tester.pumpWidget(_shellApp(l,
          selected: 2,
          expensesTab: ValueNotifier(true),
          chatTab: ValueNotifier(true)));
      await tester.pumpAndSettle();
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.labelBehavior, NavigationDestinationLabelBehavior.alwaysHide);
      expect(find.bySemanticsLabel(RegExp(l[KApp.chatNav])), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('EN @$scale, the final bar on 360 dp: Inbox selected fits',
        (tester) async {
      final l = Localization(AppLanguage.en);
      await useSize(tester, _phone, scale);
      await tester.pumpWidget(_shellApp(l,
          selected: 2,
          expensesTab: ValueNotifier(true),
          chatTab: ValueNotifier(true)));
      await tester.pumpAndSettle();
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.labelBehavior,
          NavigationDestinationLabelBehavior.onlyShowSelected);
      expectOneLineIn(tester, l[KApp.chatNav], _phone.width / 5);
    });
  }

  testWidgets('PT on a 412 dp phone: Comunicação fits alone — the selected '
      'label shows', (tester) async {
    final l = Localization(AppLanguage.ptBr);
    await useSize(tester, const Size(412, 900), 1.0);
    await tester.pumpWidget(_shellApp(l,
        selected: 2,
        expensesTab: ValueNotifier(true),
        chatTab: ValueNotifier(true)));
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.labelBehavior,
        NavigationDestinationLabelBehavior.onlyShowSelected);
    expectOneLineIn(tester, l[KApp.chatNav], 412 / 5);
  });

  testWidgets('off: four tabs, and Relatórios still opens its own branch',
      (tester) async {
    final l = Localization(AppLanguage.ptBr);
    await useSize(tester, _phone, 1.0);
    final tab = ValueNotifier(false);
    await tester.pumpWidget(_shellApp(l, selected: 0, expensesTab: tab));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('nav-expenses')), findsNothing);
    expect(tester.widget<NavigationBar>(find.byType(NavigationBar))
        .destinations, hasLength(4));
    await tester.tap(find.text(l[K.navReports]));
    await tester.pumpAndSettle();
    expect(find.text('page:/reports'), findsOne);

    // The flag arrives after the shell mounted: the tab appears on its own.
    tab.value = true;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-expenses')));
    await tester.pumpAndSettle();
    expect(find.text('page:/expenses'), findsOne);
  });
}
