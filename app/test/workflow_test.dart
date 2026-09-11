// Lote 3 PR 3 — the workflow branches of the day editor and the bulk sheet,
// and the "🔔 Resolver" bulk resolution, all against the fake data source:
// an actual-parent change routes to a swap request (F-44 message riding it),
// undoing an approved swap routes to a revert (with the F-47 observation
// question when the texts differ), the per-day F-28 gate skips instead of
// failing, and the resolve sheet batches the three subsets.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';

import 'calendar_slice_test.dart';
import 'frozen_day_test.dart' show swapReq;

const carla =
    Member(id: 3, fullName: 'Carla Dias', colorSlot: 3, userId: 'u3');

final pt = Localization(AppLanguage.ptBr);

(int, int)? get twoFutureDays {
  final lastDay = DateTime(today.year, today.month + 1, 0).day;
  return today.day + 2 > lastDay ? null : (today.day + 1, today.day + 2);
}

Future<void> longPressDay(WidgetTester tester, int day) async {
  final finder = find.text('$day').last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.longPress(finder);
  await tester.pumpAndSettle();
}

Future<void> tapChip(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(ChoiceChip, label).last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> tapSave(WidgetTester tester) async {
  final save = find.widgetWithText(FilledButton, pt[K.commonSave]);
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('editor: proposing the other member opens a swap request with '
      'the F-44 message', (tester) async {
    final day = futureDay;
    if (day == null) return;
    // Day scheduled for Ana (me) — proposing Bruno is scenario A.
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(1, dayOfMonth(day), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    // Before picking an actual there is no F-44 field.
    expect(find.text(pt[K.editorMessagePlaceholder]), findsNothing);

    await tapChip(tester, 'Bruno');
    // F-44 appears once the save would open a workflow.
    expect(find.text(pt[K.editorMessagePlaceholder]), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, pt[K.editorMessagePlaceholder]),
        'Tenho consulta');

    await tapSave(tester);

    expect(ds.createdSwapRequests, hasLength(1));
    expect(ds.createdSwapRequests.single['proposed'], 2);
    expect(ds.createdSwapRequests.single['message'], 'Tenho consulta');
    expect(ds.createdSwapRequests.single['requester'], 1);
    // No direct write happened.
    expect(ds.updated.where((r) => r.actualParentId == 2), isEmpty);
    expect(find.text(pt[K.toastSwapRequested]), findsOneWidget);
  });

  testWidgets('editor: undoing an approved swap asks the F-47 question when '
      'the observation changed, then opens the revert', (tester) async {
    final day = futureDay;
    if (day == null) return;
    // Swapped day (scheduled Ana, actual Bruno); the note was rewritten
    // after the swap — the snapshot holds a different text.
    final swapped = CareSchedule.fromJson({
      'id': 1,
      'schedule_date': CareSchedule.isoDate(dayOfMonth(day)),
      'scheduled_parent_id': 1,
      'actual_parent_id': 2,
      'notes': 'Levar mochila',
      'revision': 1,
      'revision_token': 'tok-1',
    });
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [swapped])
      ..preEditNotes = const PreEditNotes('Consulta às 15h');
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    // Set the actual back to "same as planned" → revert scenario.
    await tapChip(tester, pt[K.editorSameAsPlanned]);
    await tapSave(tester);

    // The F-47 question interrupts the save.
    expect(find.text(pt[K.editorRevertNotesQuestion]), findsOneWidget);
    expect(ds.revertRequests, isEmpty);

    // Keep the current observation.
    final keep = find.widgetWithText(FilledButton, pt[K.editorKeepCurrent]);
    await tester.ensureVisible(keep);
    await tester.pumpAndSettle();
    await tester.tap(keep);
    await tester.pumpAndSettle();

    expect(ds.revertRequests, hasLength(1));
    expect(ds.revertRequests.single['restoreNotes'], false);
    expect(ds.revertRequests.single['currentActual'], 2);
    expect(ds.revertRequests.single['scheduled'], 1);
    expect(find.text(pt[K.toastRevertRequested]), findsOneWidget);
  });

  testWidgets('editor: no snapshot difference → the revert goes straight out',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final swapped = row(1, dayOfMonth(day), 1, actual: 2);
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [swapped]);
    // preEditNotes stays null — nothing to restore from, no question.
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    await tapChip(tester, pt[K.editorSameAsPlanned]);
    await tapSave(tester);

    expect(find.text(pt[K.editorRevertNotesQuestion]), findsNothing);
    expect(ds.revertRequests, hasLength(1));
    expect(find.text(pt[K.toastRevertRequested]), findsOneWidget);
  });

  testWidgets('bulk: actual-parent change routes per day — swap where I '
      'participate, F-28 skip where I do not', (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    // d1 scheduled Ana (me) → proposing Carla is scenario A (allowed).
    // d2 scheduled Bruno → Ana proposing Carla is scenario C (skipped).
    final ds = FakeCustodyDataSource(members: [ana, bruno, carla], days: [
      row(1, dayOfMonth(days.$1), 1),
      row(2, dayOfMonth(days.$2), 2),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days.$1);
    await longPressDay(tester, days.$2);
    await tester.tap(find.text(pt.format(K.selectionEdit, [2])));
    await tester.pumpAndSettle();

    // Scheduled pre-fills mixed (0) — pick one to enable the fields.
    await tapSheet(tester, find.byKey(const Key('bulkScheduled')));
    await tester.tap(find.text('Ana Souza').last);
    await tester.pumpAndSettle();

    await tapSheet(tester, find.byKey(const Key('bulkActual')));
    await tester.tap(find.text('Carla Dias').last);
    await tester.pumpAndSettle();

    // F-44 message field appears for a workflow-capable batch.
    expect(find.text(pt[K.bulkMessagePlaceholder]), findsOneWidget);

    await tapSheet(tester, find.widgetWithText(FilledButton, pt[K.commonSave]));

    expect(ds.createdSwapRequests, hasLength(1));
    expect(ds.createdSwapRequests.single['date'],
        CareSchedule.isoDate(dayOfMonth(days.$1)));
    // The summary reports 1 swap request and 1 skipped day (F-28).
    final expectedSummary = [
      bulkPluralize(pt, 1, K.sumSwapRequestOne, K.sumSwapRequestMany),
      bulkPluralize(pt, 1, K.sumSkippedOne, K.sumSkippedMany),
    ].join(' · ');
    // The S-09 kept-planned-parent suffix rides the same toast.
    expect(find.textContaining(expectedSummary), findsOneWidget);
  });

  testWidgets('bulk: clearing the actual on approved-swap days routes to '
      'revert requests', (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [
      row(1, dayOfMonth(days.$1), 1, actual: 2), // approved swap
      row(2, dayOfMonth(days.$2), 1), // plain day
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days.$1);
    await tester.tap(find.text(pt.format(K.selectionEdit, [1])));
    await tester.pumpAndSettle();

    // Prefill: scheduled=Ana, actual=Bruno. Tick "Limpar" on the actual.
    await tapSheet(tester, find.byKey(const Key('bulkActual')));
    await tester.tap(find.text(pt[K.editorSameAsPlanned]).last);
    await tester.pumpAndSettle();
    final clearBoxes = find.byType(Checkbox);
    await tapSheet(tester, clearBoxes.first); // actual's Limpar is the first
    await tapSheet(tester, find.widgetWithText(FilledButton, pt[K.commonSave]));

    expect(ds.revertRequests, hasLength(1));
    expect(ds.revertRequests.single['date'],
        CareSchedule.isoDate(dayOfMonth(days.$1)));
    expect(ds.revertRequests.single['restoreNotes'], false);
  });

  testWidgets('🔔 Resolver: the bar counts actionable days and the sheet '
      'batches the approval', (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..frozenRequests = [
        swapReq(10, dayOfMonth(days.$1)), // awaiting me (Ana)
        swapReq(11, dayOfMonth(days.$2), requesting: 1, target: 2, proposed: 2),
      ];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days.$1);
    await longPressDay(tester, days.$2);

    // 1 awaiting me + 1 sent by me.
    final resolveLabel = pt.format(K.selectionResolve, [2]);
    expect(find.text(resolveLabel), findsOneWidget);
    await tester.tap(find.text(resolveLabel));
    await tester.pumpAndSettle();

    expect(find.text(pt[K.wfTitle]), findsOneWidget);
    expect(find.text(pt.format(K.wfAwaitingYou, [1])), findsOneWidget);
    expect(find.text(pt.format(K.wfSentByYouOne, [1])), findsOneWidget);

    await tester.tap(find.text(pt.format(K.wfApprove, [1])));
    await tester.pumpAndSettle();

    expect(ds.approvedSwaps, [(id: 10, note: null)]);
    // Summary toast: "1 aprovada" — selection cleared.
    expect(find.text(pt.format(K.sumApprovedOne, [1])), findsOneWidget);
    expect(find.text('✓'), findsNothing);
  });

  testWidgets('🔔 Resolver: approved-swap days offer the batch revert',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(1, dayOfMonth(day), 1, actual: 2)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, day);
    await tester.tap(find.text(pt.format(K.selectionResolve, [1])));
    await tester.pumpAndSettle();

    expect(find.text(pt.format(K.wfApprovedSwaps, [1])), findsOneWidget);
    await tester.tap(find.text(pt.format(K.wfRequestRevert, [1])));
    await tester.pumpAndSettle();

    expect(ds.revertRequests, hasLength(1));
    expect(ds.revertRequests.single['restoreNotes'], false);
    expect(find.text(pt.format(K.sumRevertOne, [1])), findsOneWidget);
  });
}
