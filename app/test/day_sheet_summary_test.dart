// U-25 — the day sheet opens as a SUMMARY of the day (closed alpha,
// 12/08/2026: "essa lista suspensa está muito poluído… falta um botão
// voltar"). An assigned day shows who has the child, the swap and the handoff
// as pills plus the day's note; the editor is one pencil away; a ✕ closes the
// sheet in every mode; "Cancelar" returns to the summary and drops the draft.
// An empty day has nothing to summarize and opens straight in the editor.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:entrelares_app/screens/day_sheet.dart';
import 'package:entrelares_app/theme/slot_pattern.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';

import 'calendar_slice_test.dart';

final pt = Localization(AppLanguage.ptBr);

CareSchedule noteRow(int id, DateTime date, int scheduled,
        {int? actual, String? notes, String? handoffTime}) =>
    CareSchedule.fromJson({
      'id': id,
      'schedule_date': CareSchedule.isoDate(date),
      'scheduled_parent_id': scheduled,
      'actual_parent_id': actual,
      'revision': 1,
      'revision_token': 'tok-$id',
      'notes': ?notes,
      'handoff_time': ?handoffTime,
    });

Finder get editPencil => find.byKey(daySheetEditKey);
Finder get closeX => find.byKey(AppSheetFrame.closeKey);
Finder get anySheet => find.byType(AppSheetFrame);

void main() {
  testWidgets('an assigned day opens as a summary: name, note, pencil and ✕ — '
      'no field and no action row', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [
      noteRow(7, dayOfMonth(day), 1, notes: 'Levar o casaco azul'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    expect(anySheet, findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text(pt[K.commonSave]), findsNothing);
    expect(find.text(pt[K.commonCancel]), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('day-summary-responsible')),
            matching: find.text('Ana Souza')),
        findsOneWidget);
    expect(find.text(pt[K.editorDayNote]), findsOneWidget);
    expect(find.text('Levar o casaco azul'), findsOneWidget);
    expect(find.byKey(const ValueKey('day-summary-swapped')), findsNothing);
    expect(editPencil, findsOneWidget);
    expect(closeX, findsOneWidget);
    // The ✕ and the pencil say what they do to a screen reader.
    expect(find.byTooltip(pt[K.commonClose]), findsOneWidget);
    expect(find.byTooltip(pt[K.editorAriaLabel]), findsOneWidget);
  });

  testWidgets('the pencil opens the editor, and Cancelar returns to the '
      'summary with the draft dropped and nothing written', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [
      noteRow(7, dayOfMonth(day), 1, notes: 'Levar o casaco azul'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    await tapSheet(tester, editPencil);
    expect(find.byType(TextField), findsOneWidget);
    expect(editPencil, findsNothing, reason: 'the pencil is the way IN');
    expect(closeX, findsOneWidget, reason: 'the ✕ stays in the editor');

    await tester.enterText(find.byType(TextField), 'Rascunho descartado');
    await tapSheet(tester, find.text(pt[K.commonCancel]));

    expect(anySheet, findsOneWidget, reason: 'Cancelar is not the ✕');
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Levar o casaco azul'), findsOneWidget);
    expect(find.text('Rascunho descartado'), findsNothing);
    expect(ds.inserted, isEmpty);
    expect(ds.updated, isEmpty);

    // Opening the editor again starts from the stored day, not the draft.
    await tapSheet(tester, editPencil);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Levar o casaco azul');
  });

  testWidgets('the ✕ closes the sheet from the summary and from the editor, '
      'writing nothing', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [noteRow(7, dayOfMonth(day), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    await tapSheet(tester, closeX);
    expect(anySheet, findsNothing);

    await openDay(tester, day);
    await tapSheet(tester, editPencil);
    await tester.enterText(find.byType(TextField), 'Não salvo');
    await tapSheet(tester, closeX);
    expect(anySheet, findsNothing);
    expect(ds.inserted, isEmpty);
    expect(ds.updated, isEmpty);
  });

  testWidgets('an empty day opens straight in the editor, and Cancelar closes '
      'the sheet', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    expect(find.widgetWithText(ChoiceChip, 'Ana'), findsWidgets);
    expect(editPencil, findsNothing,
        reason: 'no summary to come from, so no pencil to go back through');
    expect(closeX, findsOneWidget);

    await tapSheet(tester, find.text(pt[K.commonCancel]));
    expect(anySheet, findsNothing);
    expect(ds.inserted, isEmpty);
  });

  testWidgets('a swapped day: the real carer, the dashed "Trocado" pill, the '
      'planned carer and the handoff time', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [
      noteRow(7, dayOfMonth(day), 1, actual: 2, handoffTime: '18:00:00'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('day-summary-responsible')),
            matching: find.text('Bruno Lima')),
        findsOneWidget);
    // Colour is never the only vector (U-27): the swap wears the dashed
    // outline, exactly as the grid cell and the legend key do.
    final swapped = find.byKey(const ValueKey('day-summary-swapped'));
    expect(
        find.descendant(of: swapped, matching: find.text(pt[K.calSwapped])),
        findsOneWidget);
    expect(
        find.descendant(
            of: swapped,
            matching: find.byWidgetPredicate((w) =>
                w is CustomPaint && w.foregroundPainter is DashedBorderPainter)),
        findsOneWidget);
    expect(find.text(pt.format(KApp.sheetPlanned, ['Ana Souza'])),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('day-summary-handoff')),
            matching: find.text(pt.format(
                KApp.sheetHandoffAt, [pt.formatTimeString('18:00:00')]))),
        findsOneWidget);
  });

  testWidgets('a read-only past day is the same summary with no pencil',
      (tester) async {
    final past = today.day == 1 ? null : today.day - 1;
    if (past == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [noteRow(7, dayOfMonth(past), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, past);
    expect(find.text(pt[K.editorPastReadonly]), findsOneWidget);
    expect(find.byKey(const ValueKey('day-summary-responsible')),
        findsOneWidget);
    expect(editPencil, findsNothing);
    expect(closeX, findsOneWidget);
  });

  testWidgets('the frozen-day sheet — the other sheet a day tap opens — has '
      'the same ✕', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..frozenRequests = [
        SwapRequest.fromJson({
          'id': 10,
          'schedule_date': CareSchedule.isoDate(dayOfMonth(day)),
          'requesting_profile_id': 2,
          'target_profile_id': 1,
          'proposed_actual_parent_id': 1,
          'status': 'pending',
        }),
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    expect(find.textContaining(pt[K.frozenSwapTitle]), findsOneWidget);
    await tapSheet(tester, closeX);
    expect(anySheet, findsNothing);
  });

  testWidgets('344 dp: the longest summary row fits — long names, swap and '
      'handoff wrap instead of overflowing', (tester) async {
    final day = futureDay;
    if (day == null) return;
    tester.view.physicalSize = const Size(344 * 3, 780 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    const longA = Member(
        id: 1,
        fullName: 'Maria Fernanda Albuquerque de Souza',
        colorSlot: 1,
        userId: 'u1');
    const longB = Member(
        id: 2,
        fullName: 'Bartolomeu Cavalcanti Figueiredo',
        colorSlot: 2,
        userId: 'u2');
    final ds = FakeCustodyDataSource(members: [
      longA,
      longB,
    ], days: [
      noteRow(7, dayOfMonth(day), 1,
          actual: 2,
          handoffTime: '18:30:00',
          notes: 'Levar o casaco azul, a mochila da natação e o remédio '
              'das 20h — a pediatra pediu para não pular a dose'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('day-summary-handoff')), findsOneWidget);
    final sheetWidth = tester.getSize(anySheet).width;
    for (final key in const [
      'day-summary-responsible',
      'day-summary-swapped',
      'day-summary-handoff',
    ]) {
      final rect = tester.getRect(find.byKey(ValueKey(key)));
      expect(rect.right, lessThanOrEqualTo(sheetWidth),
          reason: '$key must sit inside a 344 dp sheet');
    }
  });
}
