// U-41 — the wizard's preview strip: the calendar about to be born, painted
// from `generateRotation`'s first days. Two halves: the widget on its own
// (colours, initials, the handoff edge, the unpicked block, the one-sentence
// semantics) and the strip inside the wizard (every preset agrees with the
// generation cell by cell; the start date re-anchors the Sunday-first row).
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/cycle_strip.dart';

import 'calendar_slice_test.dart';

final pt = Localization(AppLanguage.ptBr);

const carla = Member(id: 3, fullName: 'Carla Melo', colorSlot: 3, userId: 'u3');
const dora = Member(id: 4, fullName: 'Dora Reis', colorSlot: 4, userId: 'u4');

/// U-36: the wizard is an item of the calendar's ⋮ menu.
Future<void> openWizard(WidgetTester tester) async {
  await tester.tap(find.byTooltip(pt[K.calActionsMenu]));
  await tester.pumpAndSettle();
  await tester.tap(find.text(pt[K.calWizard]));
  await tester.pumpAndSettle();
}

/// The dropdown paints the chosen label twice once open (field + menu item);
/// the menu's is the last in the tree.
Future<void> pickPreset(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.byKey(const Key('wizPreset')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('wizPreset')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Widget standalone(Widget child) => AppL10n(
      l: pt,
      setLanguage: (_) async {},
      child: MaterialApp(home: Scaffold(body: Center(child: child))),
    );

Color cellColour(WidgetTester tester, int index) =>
    (tester.widget<Container>(find.byKey(CycleStrip.cellKey(index))).decoration
            as BoxDecoration)
        .color!;

String cellInitial(WidgetTester tester, int index) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(CycleStrip.cellKey(index)), matching: find.byType(Text)))
    .data!;

AppTokens tokensOf(WidgetTester tester) =>
    tester.element(find.byType(CycleStrip)).tokens;

int blanksRendered(WidgetTester tester) {
  var n = 0;
  while (find.byKey(CycleStrip.blankKey(n)).evaluate().isNotEmpty) {
    n++;
  }
  return n;
}

int cellsRendered(WidgetTester tester) {
  var n = 0;
  while (find.byKey(CycleStrip.cellKey(n)).evaluate().isNotEmpty) {
    n++;
  }
  return n;
}

final presetLabels = {
  '7-7': pt[K.wizPreset77],
  '14-14': pt[K.wizPreset1414],
  '1-1': pt[K.wizPreset11],
  '5-2-2-5': pt[K.wizPreset5225],
  '2-2-3': pt[K.wizPreset223],
};

void main() {
  group('U-41 · CycleStrip on its own', () {
    final start = DateTime(2026, 9, 16); // a Wednesday
    final views = [ana, bruno, carla, dora].map((m) => m.toView()).toList();

    testWidgets('a four-carer cycle renders four slot colours and initials',
        (tester) async {
      final days = generateRotation(
        start: start,
        end: DateTime(2026, 9, 24),
        blocks: const [
          CycleBlock(1, 2),
          CycleBlock(2, 2),
          CycleBlock(3, 2),
          CycleBlock(4, 2),
        ],
      );
      await tester.pumpWidget(standalone(CycleStrip(days: days, views: views)));
      await tester.pumpAndSettle();

      final tokens = tokensOf(tester);
      expect(cellsRendered(tester), 8);
      final colours = {for (var i = 0; i < 8; i++) cellColour(tester, i)};
      expect(colours, {
        for (var slot = 1; slot <= 4; slot++) tokens.slot(slot).tone.solid,
      });
      expect([for (var i = 0; i < 8; i += 2) cellInitial(tester, i)],
          ['A', 'B', 'C', 'D']);
    });

    testWidgets('leads with the blanks of a Sunday-first week, like the grid',
        (tester) async {
      final days = generateRotation(
        start: start,
        end: DateTime(2026, 9, 30),
        blocks: const [CycleBlock(1, 7), CycleBlock(2, 7)],
      );
      await tester.pumpWidget(standalone(CycleStrip(days: days, views: views)));
      await tester.pumpAndSettle();

      // Wednesday → three blanks (Sun, Mon, Tue), the month view's own count.
      expect(blanksRendered(tester), 3);
      for (final w in pt[K.calWeekdayInitials].split(',')) {
        expect(find.text(w), findsWidgets);
      }
    });

    testWidgets('T-27: the handoff edge marks transition days only',
        (tester) async {
      final days = generateRotation(
        start: start,
        end: DateTime(2026, 9, 20),
        blocks: const [CycleBlock(1, 2), CycleBlock(2, 2)],
        handoffTime: (hour: 18, minute: 0),
      );
      await tester.pumpWidget(standalone(CycleStrip(days: days, views: views)));
      await tester.pumpAndSettle();

      final tokens = tokensOf(tester);
      bool hasEdge(int i) => find
          .descendant(
              of: find.byKey(CycleStrip.cellKey(i)),
              matching: find.byWidgetPredicate(
                  (w) => w is Container && w.color == tokens.text))
          .evaluate()
          .isNotEmpty;
      // Day 0 starts the plan (no previous carer), day 2 is the first change.
      expect([for (var i = 0; i < 4; i++) hasEdge(i)],
          [false, false, true, false]);
    });

    testWidgets('a block without a carer paints slot 0 and "?"',
        (tester) async {
      final days = generateRotation(
        start: start,
        end: DateTime(2026, 9, 18),
        blocks: const [CycleBlock(1, 1), CycleBlock(0, 1)],
      );
      await tester.pumpWidget(standalone(CycleStrip(days: days, views: views)));
      await tester.pumpAndSettle();

      expect(cellColour(tester, 1), tokensOf(tester).slot(0).tone.solid);
      expect(cellInitial(tester, 1), '?');
    });

    testWidgets('reads to a screen reader as ONE sentence of runs',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final days = generateRotation(
        start: start,
        end: DateTime(2026, 9, 30),
        blocks: const [
          CycleBlock(1, 5),
          CycleBlock(2, 2),
          CycleBlock(1, 2),
          CycleBlock(2, 5),
        ],
      );
      await tester.pumpWidget(standalone(CycleStrip(days: days, views: views)));
      await tester.pumpAndSettle();

      expect(
          find.bySemanticsLabel(
              'Prévia a partir de ${pt.formatDate(start)}: Ana Souza por 5 '
              'dias, Bruno Lima por 2 dias, Ana Souza por 2 dias, Bruno Lima '
              'por 5 dias.'),
          findsOneWidget);
      // The initials are painted, never announced as loose letters.
      expect(find.bySemanticsLabel('A'), findsNothing);
      semantics.dispose();
    });

    testWidgets('an unpicked block is named in the sentence, not dropped',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final days = generateRotation(
        start: start,
        end: DateTime(2026, 9, 18),
        blocks: const [CycleBlock(1, 1), CycleBlock(0, 1)],
      );
      await tester.pumpWidget(standalone(CycleStrip(days: days, views: views)));
      await tester.pumpAndSettle();

      expect(
          find.bySemanticsLabel(RegExp(
              'Ana Souza por 1 dia, ${pt[K.wizStripNobody]} por 1 dia\\.\$')),
          findsOneWidget);
      semantics.dispose();
    });

    testWidgets('nothing to show renders nothing', (tester) async {
      await tester.pumpWidget(
          standalone(CycleStrip(days: const [], views: views)));
      await tester.pumpAndSettle();
      expect(cellsRendered(tester), 0);
      expect(find.text(pt[K.calWeekdayInitials].split(',').first),
          findsNothing);
    });
  });

  group('U-41 · the strip inside the wizard', () {
    testWidgets('every preset agrees with generateRotation, cell by cell',
        (tester) async {
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await openWizard(tester);

      final views = [ana.toView(), bruno.toView()];
      for (final preset in wizardPresetIds) {
        await pickPreset(tester, presetLabels[preset]!);
        await tester.ensureVisible(find.byType(CycleStrip));
        await tester.pumpAndSettle();

        final blocks = wizardPresetBlocks(preset, const [1, 2]);
        final cycle = blocks.fold(0, (sum, b) => sum + b.days);
        final length = cycleStripLength(cycle);
        final expected = generateRotation(
          start: dateOnly(today),
          end: DateTime(today.year, today.month, today.day + length),
          blocks: blocks,
        );
        final tokens = tokensOf(tester);

        expect(cellsRendered(tester), length, reason: preset);
        for (final (i, day) in expected.indexed) {
          expect(cellColour(tester, i),
              tokens.slot(profileSlotIndex(day.scheduledParentId, views))
                  .tone.solid,
              reason: '$preset · day $i');
          expect(cellInitial(tester, i),
              displayInitials(day.scheduledParentId, views),
              reason: '$preset · day $i');
        }
        // And the sentence under it stays.
        expect(find.textContaining('dias por ciclo'), findsOneWidget);
      }
    });

    testWidgets('the start date re-anchors the Sunday-first row',
        (tester) async {
      final future = futureDay;
      if (future == null) return;
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await openWizard(tester);

      expect(blanksRendered(tester), today.weekday % 7);

      await tester.ensureVisible(find.byKey(const Key('wizStartDate')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('wizStartDate')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(
          of: find.byType(DatePickerDialog), matching: find.text('$future')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final picked = dayOfMonth(future);
      expect(blanksRendered(tester), picked.weekday % 7);
      expect(find.text(pt.formatDate(picked)), findsOneWidget);
    });

    testWidgets('a handoff time picked on the sheet reaches the strip',
        (tester) async {
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await openWizard(tester);

      final tokens = tokensOf(tester);
      bool edgeOn(int i) => find
          .descendant(
              of: find.byKey(CycleStrip.cellKey(i)),
              matching: find.byWidgetPredicate(
                  (w) => w is Container && w.color == tokens.text))
          .evaluate()
          .isNotEmpty;
      expect(edgeOn(7), isFalse);

      await pickTime(tester, find.byKey(const Key('wizHandoff')), hour: 1);
      await tester.ensureVisible(find.byType(CycleStrip));
      await tester.pumpAndSettle();

      // 7/7: day 7 is the first transition; day 0 and day 8 are not.
      expect(edgeOn(0), isFalse);
      expect(edgeOn(7), isTrue);
      expect(edgeOn(8), isFalse);
    });
  });
}
