// F-95 — a swapped day keeps its story, a frozen day keeps its content, and
// no sheet acts on stale data.
//
// The T-103 audit (04/10/2026): the story of a swap lived only in
// Relatórios; a day with a pending request opened only the request panel (its
// agenda, note and relatos unreachable for days); yesterday's push still
// offered "Aprovar" on a request the cron had approved, and failed with a raw
// `PostgrestException`; and after a T-33 conflict every retry failed on the
// old revision.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:entrelares_app/screens/day_sheet.dart';

import 'calendar_slice_test.dart';
import 'frozen_day_test.dart' show swapReq;

final pt = Localization(AppLanguage.ptBr);

SwapRequest approvedReq(int id, DateTime date,
        {String resolvedBy = 'user', String? note}) =>
    SwapRequest.fromJson({
      'id': id,
      'schedule_date': CareSchedule.isoDate(date),
      'requesting_profile_id': 1,
      'target_profile_id': 2,
      'proposed_actual_parent_id': 2,
      'status': 'approved',
      'resolved_by': resolvedBy,
      'approval_note': note,
      'created_at': DateTime(date.year, date.month, 1, 9, 12).toUtc().toIso8601String(),
      'resolved_at': DateTime(date.year, date.month, 2, 18, 12).toUtc().toIso8601String(),
    });

void main() {
  testWidgets('a swapped day says who asked, who approved, when and the note',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final date = dayOfMonth(day);
    final ds = FakeCustodyDataSource(members: [
      ana,
      bruno
    ], days: [
      row(7, date, ana.id, actual: bruno.id),
    ])
      ..daySwapOrigins = {
        CareSchedule.isoDate(date): approvedReq(50, date, note: 'combinado')
      };
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    final story = find.byKey(const ValueKey('day-swap-story'));
    expect(story, findsOneWidget);
    final text = tester.widget<Text>(story).data!;
    expect(text, startsWith('Pedida por Ana Souza em '));
    expect(text, contains('aprovada por Bruno Lima em '));
    expect(text, endsWith('· "combinado"'));
  });

  testWidgets('an auto-approved swap says so', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final date = dayOfMonth(day);
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, date, ana.id, actual: bruno.id)])
      ..daySwapOrigins = {
        CareSchedule.isoDate(date): approvedReq(51, date, resolvedBy: 'system')
      };
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('day-swap-story')))
            .data,
        contains('aprovada automaticamente em '));
  });

  testWidgets('a request settled since the push reads as settled and offers '
      'nothing to act on', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final date = dayOfMonth(day);
    final open = swapReq(60, date);
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, date, ana.id)])
      ..frozenRequests = [open]
      ..swapRequestsById = {60: approvedReq(60, date)};
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    expect(find.byKey(const ValueKey('frozen-resolved')), findsOneWidget);
    expect(find.text(pt[KApp.frozenAlreadyResolved]), findsOneWidget);
    expect(find.text(pt[K.frozenApprove]), findsNothing);
  });

  testWidgets('an answer the server refuses as settled is a state, never raw '
      'text', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final date = dayOfMonth(day);
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, date, ana.id)])
      ..frozenRequests = [swapReq(61, date)]
      ..alreadyAnswered.add(61);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    await tapSheet(tester, find.text(pt[K.frozenApprove]));
    expect(find.text(pt[KApp.frozenAlreadyResolved]), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing);
    expect(find.text(pt[K.frozenApprove]), findsNothing);
  });

  testWidgets('"Ver o dia" opens the frozen day itself, read-only',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final date = dayOfMonth(day);
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, date, ana.id)])
      ..frozenRequests = [swapReq(62, date)];
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    await tapSheet(tester, find.byKey(const ValueKey('frozen-view-day')));
    expect(find.text(pt[K.editorFrozenReadonly]), findsOneWidget,
        reason: 'the day sheet, with the frozen guard');
    expect(find.byKey(daySheetAskSwapKey), findsNothing);
  });

  testWidgets('after a T-33 conflict the day is reloaded in place, and the '
      'retry carries the winner\'s revision', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final date = dayOfMonth(day);
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, date, ana.id)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDay(tester, day);

    // Someone else saved first: the server now holds revision 2.
    ds.days = [row(7, date, ana.id, revision: 2)];
    ds.throwOnWrite = Exception('Outro responsável salvou este dia primeiro');
    await tester.enterText(find.byType(TextField).first, 'Levar o casaco');
    await tester.pump();
    await tapSheet(tester, find.text(pt[K.commonSave]));
    expect(find.text(pt[KApp.errConflictReloaded]), findsOneWidget);

    ds.throwOnWrite = null;
    await tapSheet(tester, find.text(pt[K.commonSave]));
    expect(ds.updated.last.revision, 2);
  });
}
