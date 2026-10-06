// Lote 2 PR 3 — multi-selection and the Bulk Edit sheet against the fake
// data source: long-press/armed selection, the corner mark and action bar,
// the navigation guard on month paging, and the bulk save's pure rules wired
// end to end (S-09 kept planned parent, skip counting, no-op days, the
// admin-only delete-all path and the S-09 overwrite confirmation).
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/services/admin_mode.dart';

import 'calendar_slice_test.dart';

const anaAdmin = Member(
    id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', isAdmin: true);

final pt = Localization(AppLanguage.ptBr);

/// Two distinct future days, or null when the month cannot host them.
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

Future<void> pickBulkScheduled(WidgetTester tester, String fullName) async {
  await tapSheet(tester, find.byKey(const Key('bulkScheduled')));
  await tester.tap(find.text(fullName).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('long-press selects days; the action bar counts them and ✕ '
      'cancels', (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days.$1);
    await longPressDay(tester, days.$2);
    expect(find.text(pt.format(K.selectionEdit, [2])), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNWidgets(2));
    // U-36: the app bar is CONTEXTUAL while selecting — the count is the
    // title and "Calendário" is gone, so the state is announced at the top,
    // where the eye is, and not only in the strip at the bottom.
    expect(find.text(pt.format(K.navGuardSelectedMany, [2])), findsOneWidget);
    expect(find.text(pt[K.navCalendar]), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);

    // In selection mode a TAP toggles instead of opening the editor.
    await tester.tap(find.text('${days.$2}').last);
    await tester.pumpAndSettle();
    expect(find.text(pt.format(K.selectionEdit, [1])), findsOneWidget);
    expect(find.text(pt.format(K.navGuardSelectedOne, [1])), findsOneWidget);

    // ✕ lives in the contextual bar now, and ONLY there.
    await tester.tap(find.byTooltip(pt[K.selectionCancel]));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.text(pt[K.navCalendar]), findsOneWidget);
    expect(find.byIcon(Icons.more_vert), findsOneWidget);
  });

  testWidgets('U-36: "Selecionar vários dias" in the ⋮ menu arms selection '
      'without a long-press, and the bar says what to do until a day is picked',
      (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(pt[K.calActionsMenu]));
    await tester.pumpAndSettle();
    await tester.tap(find.text(pt[K.calSelectDays]));
    await tester.pumpAndSettle();
    // Armed, nothing picked: the contextual title is the instruction itself.
    expect(find.text(pt[K.calSelectDays]), findsOneWidget);
    expect(find.text(pt[K.navCalendar]), findsNothing);

    final dayFinder = find.text('${days.$1}').last;
    await tester.ensureVisible(dayFinder);
    await tester.pumpAndSettle();
    await tester.tap(dayFinder);
    await tester.pumpAndSettle();
    expect(find.text(pt.format(K.selectionEdit, [1])), findsOneWidget);
    expect(find.text(pt.format(K.navGuardSelectedOne, [1])), findsOneWidget);
  });

  testWidgets('U-36: the admin shield stays reachable while selecting — the '
      'bulk edit of a past day is exactly where the mode is needed',
      (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final adminMode = AdminMode();
    final ds = FakeCustodyDataSource(members: [anaAdmin, bruno], days: []);
    await tester.pumpWidget(app(ds, adminMode: adminMode));
    await tester.pumpAndSettle();

    await longPressDay(tester, days.$1);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.shield_outlined));
    await tester.pumpAndSettle();
    expect(adminMode.isActive, isTrue);
    // Still selecting: the count did not move.
    expect(find.text(pt.format(K.navGuardSelectedOne, [1])), findsOneWidget);
  });

  testWidgets('bulk direct save: unassigned days take the chosen parent and '
      'the summary reports it', (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days.$1);
    await longPressDay(tester, days.$2);
    await tester.tap(find.text(pt.format(K.selectionEdit, [2])));
    await tester.pumpAndSettle();

    expect(find.text(pt.format(K.bulkTitleMany, [2])), findsOneWidget);
    await pickBulkScheduled(tester, 'Bruno Lima');
    await tapSheet(tester, find.text('Salvar'));

    expect(ds.inserted, hasLength(2));
    expect(ds.inserted.every((r) => r.scheduledParentId == 2), isTrue);
    expect(find.text('2 dias atualizados'), findsOneWidget);
    // The selection cleared (FinishBulkSave mirror).
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    await settleSnack(tester);
  });

  testWidgets('S-09: assigned days keep their planned parent for non-admins '
      '(no-op day reported, lock hint shown)', (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dayOfMonth(days.$1), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days.$1);
    await longPressDay(tester, days.$2);
    await tester.tap(find.text(pt.format(K.selectionEdit, [2])));
    await tester.pumpAndSettle();

    expect(find.text(pt.format(K.bulkKeptScheduledOne, [1])), findsOneWidget);
    await pickBulkScheduled(tester, 'Bruno Lima');
    await tapSheet(tester, find.text('Salvar'));

    // The unassigned day inserts with Bruno; the assigned one is a no-op.
    expect(ds.inserted.single.scheduledParentId, 2);
    expect(ds.updated, isEmpty);
    expect(find.textContaining('1 dia atualizado'), findsOneWidget);
    expect(find.textContaining('sem alterações'), findsOneWidget);
    await settleSnack(tester);
  });

  testWidgets('S-09: admin overwrite asks first, then rewrites', (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [row(7, dayOfMonth(days.$1), 1)]);
    await tester.pumpWidget(app(ds, adminMode: AdminMode()..toggle()));
    await tester.pumpAndSettle();

    await longPressDay(tester, days.$1);
    await tester.tap(find.text(pt.format(K.selectionEdit, [1])));
    await tester.pumpAndSettle();
    await pickBulkScheduled(tester, 'Bruno Lima');
    await tapSheet(tester, find.text('Salvar'));

    expect(find.text(pt.format(K.bulkOverwriteWarningOne, [1])),
        findsOneWidget);
    expect(ds.updated, isEmpty);

    await tapSheet(tester, find.text(pt[K.editorYesChange]));
    expect(ds.updated.single.scheduledParentId, 2);
    await settleSnack(tester);
  });

  testWidgets('admin delete-all clears the selected rows after its warning',
      (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [row(7, dayOfMonth(days.$1), 1)]);
    await tester.pumpWidget(app(ds, adminMode: AdminMode()..toggle()));
    await tester.pumpAndSettle();

    await longPressDay(tester, days.$1);
    await tester.tap(find.text(pt.format(K.selectionEdit, [1])));
    await tester.pumpAndSettle();
    await tapSheet(tester, find.text(pt[K.bulkClearDaysAction]));
    expect(find.text(pt[K.bulkDeleteAllWarning]), findsOneWidget);

    await tapSheet(tester, find.text(pt[K.bulkYesDelete]));
    expect(ds.deleted, [7]);
    expect(find.textContaining('1 dia apagado'), findsOneWidget);
    await settleSnack(tester);
  });

  testWidgets('past days in the selection are skipped and reported',
      (tester) async {
    final days = twoFutureDays;
    if (days == null || today.day == 1) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, today.day - 1); // F-13: never eligible
    await longPressDay(tester, days.$1);
    await tester.tap(find.text(pt.format(K.selectionEdit, [2])));
    await tester.pumpAndSettle();
    await pickBulkScheduled(tester, 'Bruno Lima');
    await tapSheet(tester, find.text('Salvar'));

    expect(ds.inserted, hasLength(1));
    expect(find.textContaining('1 dia atualizado'), findsOneWidget);
    expect(find.textContaining('1 dia ignorado'), findsOneWidget);
    await settleSnack(tester);
  });

  // F-100 (owner, 05/10/2026): a selection survives the month change — a
  // school vacation runs from December into January. (The web-era guard that
  // asked before discarding it is gone.)
  testWidgets('month paging while selecting keeps the selection',
      (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days.$1);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    final next = DateTime(today.year, today.month + 1, 1);
    expect(find.text(monthHeading(pt, next)), findsOneWidget);
    expect(find.text(pt.format(K.selectionEdit, [1])), findsOneWidget,
        reason: 'the day picked last month is still selected');
  });

  // Owner's QA of 3.1.10 (06/10/2026): press and DRAG paints a run; after
  // the finger lifts, each tap marks or unmarks ONE day — alternate days are
  // three taps (F-100's "press, then tap the last day" took that away).
  Future<TestGesture> pressOn(WidgetTester tester, int day) async {
    final cell = find.text('$day').last;
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(tester.getCenter(cell));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    return gesture;
  }

  testWidgets('press and drag selects the run, and dragging back takes days '
      'out again', (tester) async {
    final lastDay = DateTime(today.year, today.month + 1, 0).day;
    if (today.day + 4 > lastDay) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    final gesture = await pressOn(tester, today.day + 1);
    await gesture.moveTo(tester.getCenter(find.text('${today.day + 4}').last));
    await tester.pump();
    expect(find.text(pt.format(K.selectionEdit, [4])), findsOneWidget);
    await gesture.moveTo(tester.getCenter(find.text('${today.day + 2}').last));
    await tester.pump();
    expect(find.text(pt.format(K.selectionEdit, [2])), findsOneWidget,
        reason: 'the run follows the finger back');
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text(pt.format(K.selectionEdit, [2])), findsOneWidget);
  });

  testWidgets('a press without a drag, then taps: alternate days',
      (tester) async {
    final lastDay = DateTime(today.year, today.month + 1, 0).day;
    if (today.day + 5 > lastDay) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, today.day + 1);
    for (final d in [today.day + 3, today.day + 5]) {
      final cell = find.text('$d').last;
      await tester.ensureVisible(cell);
      await tester.pumpAndSettle();
      await tester.tap(cell);
      await tester.pumpAndSettle();
    }
    expect(find.text(pt.format(K.selectionEdit, [3])), findsOneWidget,
        reason: 'three days, none of the ones between them');
  });

  testWidgets('a second press and drag ADDS a run to the selection',
      (tester) async {
    final lastDay = DateTime(today.year, today.month + 1, 0).day;
    if (today.day + 6 > lastDay) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    var gesture = await pressOn(tester, today.day + 1);
    await gesture.moveTo(tester.getCenter(find.text('${today.day + 2}').last));
    await gesture.up();
    await tester.pumpAndSettle();
    gesture = await pressOn(tester, today.day + 5);
    await gesture.moveTo(tester.getCenter(find.text('${today.day + 6}').last));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text(pt.format(K.selectionEdit, [4])), findsOneWidget);
  });

  testWidgets('on the web, Shift+click closes a run from the last day picked',
      (tester) async {
    final lastDay = DateTime(today.year, today.month + 1, 0).day;
    if (today.day + 4 > lastDay) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, today.day + 1);
    final cell = find.text('${today.day + 4}').last;
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.tap(cell);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();
    expect(find.text(pt.format(K.selectionEdit, [4])), findsOneWidget);
  });

  // Owner's QA of 3.1.14: the same gesture takes days OUT when it starts on
  // a day already selected.
  testWidgets('a press and drag that starts on a selected day unmarks the run',
      (tester) async {
    final lastDay = DateTime(today.year, today.month + 1, 0).day;
    if (today.day + 5 > lastDay) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    var gesture = await pressOn(tester, today.day + 1);
    await gesture.moveTo(tester.getCenter(find.text('${today.day + 5}').last));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text(pt.format(K.selectionEdit, [5])), findsOneWidget);

    gesture = await pressOn(tester, today.day + 2);
    await gesture.moveTo(tester.getCenter(find.text('${today.day + 4}').last));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text(pt.format(K.selectionEdit, [2])), findsOneWidget,
        reason: 'the run from the 2nd to the 4th day came out');
  });
}
