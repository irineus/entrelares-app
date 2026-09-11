// Lote 2 PR 3 — multi-selection and the Bulk Edit sheet against the fake
// data source: long-press/armed selection, the corner mark and action bar,
// the navigation guard on month paging, and the bulk save's pure rules wired
// end to end (S-09 kept planned parent, skip counting, no-op days, the
// admin-only delete-all path and the S-09 overwrite confirmation).
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
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
    expect(find.text('✓'), findsNWidgets(2));

    // In selection mode a TAP toggles instead of opening the editor.
    await tester.tap(find.text('${days.$2}').last);
    await tester.pumpAndSettle();
    expect(find.text(pt.format(K.selectionEdit, [1])), findsOneWidget);

    await tester.tap(find.byTooltip(pt[K.selectionCancel]));
    await tester.pumpAndSettle();
    expect(find.textContaining('✏️'), findsNothing);
  });

  testWidgets('U-11: the ☑️ button arms selection without a long-press',
      (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(pt[K.calSelectDays]));
    await tester.pumpAndSettle();
    final dayFinder = find.text('${days.$1}').last;
    await tester.ensureVisible(dayFinder);
    await tester.pumpAndSettle();
    await tester.tap(dayFinder);
    await tester.pumpAndSettle();
    expect(find.text(pt.format(K.selectionEdit, [1])), findsOneWidget);
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
    expect(find.textContaining('✏️'), findsNothing);
    await settleSnack(tester);
  });

  testWidgets('S-09: assigned days keep their planned parent for non-admins '
      '(no-op day reported, 🔒 hint shown)', (tester) async {
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

  testWidgets('month paging while selecting asks before discarding',
      (tester) async {
    final days = twoFutureDays;
    if (days == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days.$1);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();

    expect(find.text(pt[K.navGuardBody]), findsOneWidget);
    // "Não, ficar aqui": the month stays and the selection survives.
    await tester.tap(find.text(pt[K.navGuardNo]));
    await tester.pumpAndSettle();
    expect(find.text(pt.format(K.selectionEdit, [1])), findsOneWidget);
    expect(
        find.text(monthHeading(pt, today)), findsOneWidget);

    // Same swipe, "Sim, continuar": month advances, selection discarded.
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
    await tester.pumpAndSettle();
    await tester.tap(find.text(pt[K.navGuardYes]));
    await tester.pumpAndSettle();
    final next = DateTime(today.year, today.month + 1, 1);
    expect(find.text(monthHeading(pt, next)),
        findsOneWidget);
    expect(find.textContaining('✏️'), findsNothing);
  });
}
