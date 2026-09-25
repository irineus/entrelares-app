// U-25 + U-56 — what a day tap opens.
//
// U-25 (closed alpha, 12/08/2026: "essa lista suspensa está muito poluído…
// falta um botão voltar") made every assigned day open as a SUMMARY with the
// editor one pencil away. U-56 (owner, 23/09/2026: "a maioria das pessoas
// acaba clicando sempre duas vezes") turned the default back: a day the reader
// can change, today or ahead, opens in the EDITOR — with the summary's pills
// on top, without the planned-parent field the reader cannot change, and with
// "Salvar" lit only when something changed. The summary stays for the days
// nothing can be saved on, and for a past day (the relato's, F-67), where the
// admin mode reaches the editor through the pencil. A ✕ closes in every mode.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:entrelares_app/screens/day_sheet.dart';
import 'package:entrelares_app/theme/slot_pattern.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';

import 'calendar_slice_test.dart';
import 'day_editor_test.dart' show anaAdmin, activeAdminMode, pastDay;

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

/// The pinned "Salvar" — null [FilledButton.onPressed] is the unlit state.
bool saveEnabled(WidgetTester tester) => tester
        .widget<FilledButton>(
            find.ancestor(of: find.text(pt[K.commonSave]), matching: find.byType(FilledButton)))
        .onPressed !=
    null;

void main() {
  testWidgets('an assigned day ahead opens in the EDITOR in one tap: the '
      'pills on top, the fields, the ✕ — no pencil, and no planned-parent '
      'field for a reader who cannot change it', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [
      noteRow(7, dayOfMonth(day), 1, notes: 'Levar o casaco azul'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    expect(anySheet, findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('day-summary-responsible')),
            matching: find.text('Ana Souza')),
        findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Levar o casaco azul');
    expect(find.text(pt[K.editorActualParent]), findsOneWidget);
    // S-09: the planned parent of an assigned day is locked for a non-admin —
    // the pill on top already names her; a row of dead chips said it twice.
    expect(find.text(pt[K.editorScheduledParent]), findsNothing);
    expect(editPencil, findsNothing);
    expect(closeX, findsOneWidget);
    expect(find.byTooltip(pt[K.commonClose]), findsOneWidget);
  });

  testWidgets('"Salvar" lights only when the draft differs from the stored '
      'day, and goes out again when the change is undone', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [
      noteRow(7, dayOfMonth(day), 1, notes: 'Levar o casaco azul'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    expect(saveEnabled(tester), isFalse,
        reason: 'opening a day is not a change — a reflex tap must not write');

    await tester.enterText(find.byType(TextField), 'Levar o casaco verde');
    await tester.pump();
    expect(saveEnabled(tester), isTrue);

    // Whitespace is not a change: the save trims before writing.
    await tester.enterText(find.byType(TextField), ' Levar o casaco azul ');
    await tester.pump();
    expect(saveEnabled(tester), isFalse);

    await tapSheet(tester, memberChip('Bruno'));
    expect(saveEnabled(tester), isTrue, reason: 'the real carer is a change');
    await tapSheet(
        tester, find.widgetWithText(ChoiceChip, pt[KApp.editorNoSwap]));
    expect(saveEnabled(tester), isFalse);

    expect(ds.inserted, isEmpty);
    expect(ds.updated, isEmpty);
  });

  testWidgets('Cancelar and the ✕ both close the editor, writing nothing',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [noteRow(7, dayOfMonth(day), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    await tester.enterText(find.byType(TextField), 'Não salvo');
    await tapSheet(tester, find.text(pt[K.commonCancel]));
    expect(anySheet, findsNothing,
        reason: 'opened in the editor, so there is no summary to go back to');

    await openDay(tester, day);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
        reason: 'the draft died with the sheet');
    await tester.enterText(find.byType(TextField), 'Também não');
    await tapSheet(tester, closeX);
    expect(anySheet, findsNothing);
    expect(ds.inserted, isEmpty);
    expect(ds.updated, isEmpty);
  });

  testWidgets('an empty day opens in the editor with the planned-parent '
      'question — the only thing to do there — and no pills', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    expect(find.text(pt[K.editorScheduledParent]), findsOneWidget);
    expect(memberChip('Ana'), findsWidgets);
    expect(find.byKey(const ValueKey('day-summary-responsible')), findsNothing);
    expect(editPencil, findsNothing);
    expect(closeX, findsOneWidget);
    expect(saveEnabled(tester), isFalse, reason: 'nobody chosen yet');

    await tapSheet(tester, find.text(pt[K.commonCancel]));
    expect(anySheet, findsNothing);
    expect(ds.inserted, isEmpty);
  });

  testWidgets('a swapped day: the real carer, the dashed "Trocado" pill, the '
      'planned carer and the handoff time lead the editor', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [
      noteRow(7, dayOfMonth(day), 1, actual: 2, handoffTime: '18:00:00'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, day);
    expect(find.text(pt[K.editorActualParent]), findsOneWidget);
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
    expect(
        find.descendant(of: anySheet, matching: find.text(pt[K.calSwapped])),
        findsOneWidget,
        reason: 'the pill says it — the U-28 badge on the "Responsável real" '
            'label said it a second time once the pills led the form');
    expect(find.text(pt.format(KApp.sheetPlanned, ['Ana Souza'])),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('day-summary-handoff')),
            matching: find.text(pt.format(
                KApp.sheetHandoffAt, [pt.formatTimeString('18:00:00')]))),
        findsOneWidget);
  });

  testWidgets('a read-only past day is the summary, with the note and no '
      'pencil', (tester) async {
    final past = pastDay;
    if (past == null) return;
    final ds = FakeCustodyDataSource(members: [
      ana,
      bruno
    ], days: [
      noteRow(7, dayOfMonth(past), 1, notes: 'Levar o casaco azul'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, past);
    expect(find.text(pt[K.editorPastReadonly]), findsOneWidget);
    expect(find.byKey(const ValueKey('day-summary-responsible')),
        findsOneWidget);
    expect(find.text('Levar o casaco azul'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(editPencil, findsNothing);
    expect(closeX, findsOneWidget);
  });

  testWidgets('a past day under the admin mode stays the summary — the relato '
      'is its primary — and the pencil reaches the correction; Cancelar goes '
      'back to the summary', (tester) async {
    final past = pastDay;
    if (past == null) return;
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [noteRow(7, dayOfMonth(past), 1)])
      ..family = const Family(id: 1, plan: 'free')
      ..publicSettings = const {'override_free_days': '400'};
    await tester.pumpWidget(app(ds, adminMode: activeAdminMode()));
    await tester.pumpAndSettle();

    await openDay(tester, past);
    expect(find.byType(TextField), findsNothing);
    expect(editPencil, findsOneWidget);
    expect(find.text(pt[KApp.dayAccountAction]), findsOneWidget);

    await tapSheet(tester, editPencil);
    expect(find.text(pt[K.editorActualParent]), findsOneWidget);
    await tapSheet(tester, find.text(pt[K.commonCancel]));
    expect(anySheet, findsOneWidget, reason: 'Cancelar is not the ✕ here');
    expect(editPencil, findsOneWidget);
    expect(ds.updated, isEmpty);
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

  testWidgets('344 dp: the longest pill row fits on top of the editor — long '
      'names, swap and handoff wrap instead of overflowing', (tester) async {
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
