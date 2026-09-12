// Lote 2 PR 2 — the full day editor against the fake data source: note +
// handoff fields, the T-27 transition-only clearing, the S-09 planned-parent
// lock and admin confirmation, the admin-only clear day, the F-14 admin-mode
// toggle/bypass and the F-40 proactive retro-reach gate.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/services/admin_mode.dart';

import 'calendar_slice_test.dart';

const anaAdmin = Member(
    id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', isAdmin: true);

final pt = Localization(AppLanguage.ptBr);

/// Yesterday, unless the month starts today (a fixed CI clock rarely hits it;
/// the guarded tests short-circuit like the write tests do via [futureDay]).
int? get pastDay => today.day == 1 ? null : today.day - 1;

AdminMode activeAdminMode() => AdminMode()..toggle();

/// U-37: the hour + minute dropdowns became one field and the platform picker.
Future<void> pickHour(WidgetTester tester, int hour) =>
    pickTime(tester, find.byKey(const Key('handoff')), hour: hour);

void main() {
  testWidgets('note and handoff save together on a transition day',
      (tester) async {
    final future = futureDay;
    if (future == null) return;
    // Previous day (today) belongs to Ana; picking Bruno makes a transition.
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(1, dayOfMonth(today.day), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, future);
    await tapSheet(tester, find.widgetWithText(ChoiceChip, 'Bruno').first);
    await tester.enterText(find.byType(TextField), 'Consulta médica');
    await pickHour(tester, 1);
    await tapSheet(tester, find.text(pt[K.commonSave]));

    final saved = ds.inserted.single;
    expect(saved.scheduledParentId, 2);
    expect(saved.notes, 'Consulta médica');
    expect(saved.handoffTime, '01:00:00');
    await settleSnack(tester);
  });

  testWidgets('T-27: a handoff on a non-transition day warns and clears',
      (tester) async {
    final future = futureDay;
    if (future == null) return;
    // Previous day (today) belongs to Ana; picking Ana again = no transition.
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(1, dayOfMonth(today.day), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, future);
    await tapSheet(tester, find.widgetWithText(ChoiceChip, 'Ana').first);
    await pickHour(tester, 1);
    expect(find.text(pt[K.editorNoTransitionHint]), findsOneWidget);

    await tapSheet(tester, find.text(pt[K.commonSave]));
    expect(ds.inserted.single.handoffTime, isNull);
    await settleSnack(tester);
  });

  testWidgets('S-09: the planned parent of an assigned day is locked for '
      'non-admins', (tester) async {
    final future = futureDay;
    if (future == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dayOfMonth(future), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, future);
    // U-28 QA: the explanation moved off the label and into an ⓘ tooltip, so
    // it is a Tooltip's message now and not a line of text under the chips.
    expect(
        find.byWidgetPredicate(
            (w) => w is Tooltip && w.message == pt[K.editorLockedHint]),
        findsOneWidget);
    // Chip disabled — no effect.
    await tapSheet(tester, find.widgetWithText(ChoiceChip, 'Bruno').first);
    await tapSheet(tester, find.text(pt[K.commonSave]));

    expect(ds.updated.single.scheduledParentId, 1);
    await settleSnack(tester);
  });

  testWidgets('S-09: admin mode changes it, but only after the explicit '
      'confirmation', (tester) async {
    final future = futureDay;
    if (future == null) return;
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [row(7, dayOfMonth(future), 1)]);
    await tester.pumpWidget(app(ds, adminMode: activeAdminMode()));
    await tester.pumpAndSettle();

    await openDay(tester, future);
    expect(find.text(pt[K.editorLockedHint]), findsNothing);
    await tapSheet(tester, find.widgetWithText(ChoiceChip, 'Bruno').first);
    await tapSheet(tester, find.text(pt[K.commonSave]));

    // Asked first — nothing written yet.
    expect(find.text(pt[K.editorAdminChangeWarning]), findsOneWidget);
    expect(ds.updated, isEmpty);

    await tapSheet(tester, find.text(pt[K.editorYesChange]));
    expect(ds.updated.single.scheduledParentId, 2);
    await settleSnack(tester);
  });

  testWidgets('clearing a day is hidden from non-admins', (tester) async {
    final future = futureDay;
    if (future == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dayOfMonth(future), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, future);
    expect(find.text(pt[K.editorClearDay]), findsNothing);
  });

  testWidgets('admin mode clears a day and reports its own toast',
      (tester) async {
    final future = futureDay;
    if (future == null) return;
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [row(7, dayOfMonth(future), 1)]);
    await tester.pumpWidget(app(ds, adminMode: activeAdminMode()));
    await tester.pumpAndSettle();
    await openDay(tester, future);
    await tapSheet(tester, find.text(pt[K.editorClearDay]));

    expect(ds.deleted, [7]);
    expect(find.text(pt[K.toastDayCleared]), findsOneWidget);
    await settleSnack(tester);
  });

  testWidgets('admin past-day correction: override banner and the actual '
      'field open up', (tester) async {
    final past = pastDay;
    if (past == null) return;
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [row(7, dayOfMonth(past), 1)])
      ..family = const Family(id: 1, plan: 'free')
      ..publicSettings = const {'override_free_days': '400'};
    await tester.pumpWidget(app(ds, adminMode: activeAdminMode()));
    await tester.pumpAndSettle();

    await openDay(tester, past);
    expect(find.text(pt[K.editorAdminOverride]), findsOneWidget);
    expect(find.text(pt[K.editorActualParent]), findsOneWidget);

    // F-28 scenario A (the user is the day's planned parent): Bruno offered.
    // The ACTUAL section renders after the scheduled one — .last targets it.
    await tapSheet(tester, find.widgetWithText(ChoiceChip, 'Bruno').last);
    await tapSheet(tester, find.text(pt[K.commonSave]));
    expect(ds.updated.single.actualParentId, 2);
    await settleSnack(tester);
  });

  testWidgets('non-admins keep the read-only past day (no admin fields)',
      (tester) async {
    final past = pastDay;
    if (past == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dayOfMonth(past), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, past);
    expect(find.text(pt[K.editorPastReadonly]), findsOneWidget);
    expect(find.text(pt[K.editorActualParent]), findsNothing);
    expect(find.text(pt[K.commonSave]), findsNothing);
  });

  testWidgets('F-40: beyond the retroactive reach the save is disabled and '
      'the tier hint explains', (tester) async {
    final past = pastDay;
    if (past == null) return;
    // Free window of 0 days: EVERY past day sits beyond the floor.
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [row(7, dayOfMonth(past), 1)])
      ..family = const Family(id: 1, plan: 'free')
      ..publicSettings = const {'override_free_days': '0'};
    await tester.pumpWidget(app(ds, adminMode: activeAdminMode()));
    await tester.pumpAndSettle();

    await openDay(tester, past);
    expect(find.text(pt.format(KApp.editorRetroBeyondFree, [0, 6])),
        findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(
                FilledButton, pt[K.commonSave]))
            .onPressed,
        isNull);
  });

  testWidgets('the shield toggle never shows for non-admins', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
  });

  testWidgets('the shield toggle flips admin mode for admins', (tester) async {
    final adminMode = AdminMode();
    final ds = FakeCustodyDataSource(members: [anaAdmin, bruno], days: []);
    await tester.pumpWidget(app(ds, adminMode: adminMode));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.shield_outlined));
    await tester.pumpAndSettle();
    expect(adminMode.isActive, isTrue);
    expect(find.byIcon(Icons.shield), findsOneWidget);
  });

  testWidgets('F-56: a pending planned parent hides the real-responsible '
      'question and says why — and keeps its own colour on the chip',
      (tester) async {
    final future = futureDay;
    if (future == null) return;
    // Eva has no account yet (user_id null, left_at null): assignable, never
    // a swap counterpart.
    const eva =
        Member(id: 5, fullName: 'Eva Pendente', colorSlot: 3, roleId: 2);
    final ds = FakeCustodyDataSource(
        members: [ana, bruno, eva], days: [row(7, dayOfMonth(future), 5)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openDay(tester, future);
    expect(
        find.textContaining(
            pt.format(KApp.sheetSwapUnavailablePending, ['Eva Pendente'])),
        findsOneWidget);
    expect(find.text(pt[K.editorActualParent]), findsNothing);
    expect(find.text(pt[K.editorSameAsPlanned]), findsNothing);
    // Not the departed ghost: the chip carries the pending mark, not "(saiu)".
    expect(find.widgetWithText(ChoiceChip, 'Eva ${pt[KApp.calMemberPending]}'),
        findsOneWidget);
    expect(find.textContaining(pt[K.calMemberLeft]), findsNothing);
  });
}
