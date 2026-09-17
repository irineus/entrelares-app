// U-48 — the web channel's input model: what a keyboard and a mouse reach on
// the calendar. The app is a phone UI on a laptop since 23/08/2026, and a
// 600 px column still owes a keyboard a way to change the month, a pointer a
// cursor and a hover, and Escape a way out of a sheet.
//
// Key events are the same in a widget test and in a browser — unlike T-64's
// URL, nothing here is "web by construction" — so this is a widget suite,
// not an integration one.
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/screens/day_sheet.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart' as cal;

final pt = Localization(AppLanguage.ptBr);

Future<cal.FakeCustodyDataSource> _pump(WidgetTester tester) async {
  const size = Size(600, 900);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ds = cal.FakeCustodyDataSource(
    members: [cal.ana, cal.bruno],
    days: [cal.row(1, cal.dayOfMonth(cal.today.day), 1, handoffTime: '18:00')],
  );
  await tester.pumpWidget(
    AppL10n(
      l: pt,
      setLanguage: (_) async {},
      child: MaterialApp(
        theme: AppTheme.light,
        home: CalendarScreen(dataSource: ds, adminMode: AdminMode()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ds;
}

/// The month the bar names right now.
String _monthOnScreen(WidgetTester tester) {
  final titles = find.byWidgetPredicate(
    (w) =>
        w is Text &&
        w.data != null &&
        RegExp(r'^[A-Z][a-zç]+ de \d{4}$').hasMatch(w.data!),
  );
  return tester.widget<Text>(titles.first).data!;
}

String _monthName(DateTime m) => pt
    .formatMonthYear(m.year, m.month)
    .replaceFirstMapped(RegExp(r'^\w'), (x) => x.group(0)!.toUpperCase());

DateTime _shift(int delta) =>
    DateTime(cal.today.year, cal.today.month + delta, 1);

Finder _inGrid(Finder f) =>
    find.descendant(of: find.byType(GridView).first, matching: f);

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

void main() {
  group('keyboard: the month', () {
    testWidgets('PageDown / PageUp change the month from anywhere — the '
        'screen holds focus as it mounts', (tester) async {
      await _pump(tester);
      expect(_monthOnScreen(tester), _monthName(_shift(0)));
      // Nothing was tabbed to: the screen's own node has focus.
      expect(FocusManager.instance.primaryFocus, isNotNull);
      await _key(tester, LogicalKeyboardKey.pageDown);
      expect(_monthOnScreen(tester), _monthName(_shift(1)));
      await _key(tester, LogicalKeyboardKey.pageUp);
      await _key(tester, LogicalKeyboardKey.pageUp);
      expect(_monthOnScreen(tester), _monthName(_shift(-1)));
    });

    testWidgets('the screen\'s focus node is not a Tab stop', (tester) async {
      await _pump(tester);
      final before = FocusManager.instance.primaryFocus;
      await _key(tester, LogicalKeyboardKey.tab);
      final after = FocusManager.instance.primaryFocus;
      expect(
        after,
        isNot(same(before)),
        reason: 'Tab leaves the screen node for a real control',
      );
      expect(after!.skipTraversal, isFalse);
    });

    testWidgets('← and → step the month while the month bar has focus', (
      tester,
    ) async {
      await _pump(tester);
      final next = find.byTooltip(pt[K.calNextMonth]);
      // Focus the "next month" arrow the way a keyboard reader would land
      // on it, then use the arrows the bar suggests.
      // `Focus.of` climbs from a context INSIDE the button — the glyph — to
      // the button's own node; from the button's element it would find the
      // screen's node above it instead.
      Focus.of(
        tester.element(
          find.descendant(of: next, matching: find.byIcon(Icons.chevron_right)),
        ),
      ).requestFocus();
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_monthOnScreen(tester), _monthName(_shift(1)));
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      await _key(tester, LogicalKeyboardKey.arrowLeft);
      expect(_monthOnScreen(tester), _monthName(_shift(-1)));
    });

    testWidgets('over the grid the arrows keep their meaning: focus moves, '
        'the month stays', (tester) async {
      await _pump(tester);
      // The 1st's number, a context inside the first cell (see above).
      final first = tester.element(_inGrid(find.text('1')).first);
      final node = Focus.of(first);
      node.requestFocus();
      await tester.pump();
      expect(node.hasPrimaryFocus, isTrue);
      await _key(tester, LogicalKeyboardKey.arrowRight);
      expect(_monthOnScreen(tester), _monthName(_shift(0)));
      expect(
        node.hasPrimaryFocus,
        isFalse,
        reason: '→ moved focus to the next cell',
      );
    });

    testWidgets('a focused cell opens on Enter and on Space', (tester) async {
      await _pump(tester);
      // Today's number, a context inside today's cell.
      final node = Focus.of(
        tester.element(_inGrid(find.text('${cal.today.day}'))),
      );
      node.requestFocus();
      await tester.pump();
      expect(node.hasPrimaryFocus, isTrue);
      await _key(tester, LogicalKeyboardKey.enter);
      expect(
        find.byType(BottomSheet),
        findsOneWidget,
        reason: 'Enter opens the day the way a tap does',
      );
      await _key(tester, LogicalKeyboardKey.escape);
      expect(find.byType(BottomSheet), findsNothing);
      node.requestFocus();
      await tester.pump();
      await _key(tester, LogicalKeyboardKey.space);
      expect(
        find.byType(BottomSheet),
        findsOneWidget,
        reason: 'and so does Space',
      );
    });

    testWidgets('Escape closes the sheet a day opened', (tester) async {
      await _pump(tester);
      await cal.openDay(tester, cal.today.day);
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byKey(daySheetEditKey), findsOneWidget);
      await _key(tester, LogicalKeyboardKey.escape);
      expect(
        find.byType(BottomSheet),
        findsNothing,
        reason: 'Escape is the keyboard\'s way out of a modal sheet',
      );
    });
  });

  group('pointer: the cell', () {
    testWidgets('a day cell shows the click cursor and a slot-toned hover '
        'ABOVE its tint', (tester) async {
      await _pump(tester);
      // Today's cell, the one with a fill: its hover is the slot's colour.
      final todayCell = find.ancestor(
        of: _inGrid(find.text('${cal.today.day}')),
        matching: find.byType(InkWell),
      );
      final well = tester.widget<InkWell>(todayCell.first);
      expect(well.hoverColor, isNotNull);
      expect(
        well.hoverColor!.a,
        closeTo(0.08, 1e-6),
        reason: 'Material 3\'s hover state layer, on the slot\'s own colour',
      );
      // The ink paints on a Material INSIDE the tinted container, so it is
      // visible over the fill. Between the InkWell and the Scaffold's
      // Material there is a transparent one of the cell's own.
      final material = tester.widget<Material>(
        find
            .ancestor(of: todayCell.first, matching: find.byType(Material))
            .first,
      );
      expect(material.type, MaterialType.transparency);
      final tinted = find.ancestor(
        of: find.byWidget(material),
        matching: find.byType(Container),
      );
      expect(
        (tester.widget<Container>(tinted.first).decoration as BoxDecoration)
            .color,
        isNotNull,
        reason: 'the transparent Material sits inside the filled box',
      );

      // And the pointer: the InkWell's default cursor is
      // `WidgetStateMouseCursor.clickable` — the hand over an enabled cell —
      // so the contract here is that nothing overrode it.
      expect(well.mouseCursor, isNull);
      expect(well.onTap, isNotNull);
    });
  });
}
