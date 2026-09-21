// F-51 — "Limpar mês": the ⋮ menu's one-tap clear of the displayed month,
// against the fake data source. What the tests pin: the item exists only
// under the admin bypass; the confirmation spells the count and the range and
// nothing is written before the yes; the write is ONE range call from today
// to the end of the month; the toast is the server's own counts; and a month
// with nothing planned ahead says so instead of asking.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:entrelares_app/services/admin_mode.dart';

import 'calendar_slice_test.dart';

/// The admin of the fake roster — the shield only shows for a real admin.
const anaAdmin = Member(
    id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', isAdmin: true);

final pt = Localization(AppLanguage.ptBr);

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byTooltip(pt[K.calActionsMenu]));
  await tester.pumpAndSettle();
}

DateTime get endOfMonth => DateTime(today.year, today.month + 1, 0);

void main() {
  // F-67 Part B: an ADMIN with the mode off sees the item (picking it asks),
  // so the reader with no "Limpar mês" is a member who is not an admin.
  testWidgets('a non-admin sees no "Limpar mês"', (tester) async {
    final ds = FakeCustodyDataSource(members: [bruno, anaAdmin], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openMenu(tester);
    expect(find.text(pt[K.calWizard]), findsOneWidget);
    expect(find.text(pt[K.calClearMonth]), findsNothing);
  });

  testWidgets('admin mode: the item asks with the count and the range, and '
      'the yes clears today → end of month in ONE call', (tester) async {
    final future = futureDay;
    if (future == null) return;
    final ds = FakeCustodyDataSource(members: [anaAdmin, bruno], days: [
      row(7, dayOfMonth(future), 1),
      if (future < endOfMonth.day) row(8, dayOfMonth(future + 1), 2),
    ]);
    final planned = ds.days.length;
    await tester.pumpWidget(app(ds, adminMode: AdminMode()..toggle()));
    await tester.pumpAndSettle();

    await openMenu(tester);
    await tester.tap(find.text(pt[K.calClearMonth]));
    await tester.pumpAndSettle();

    final from = pt.formatDate(dateOnly(today));
    final to = pt.formatDate(endOfMonth);
    expect(
        find.text(pt.format(
            planned == 1 ? K.calClearMonthBodyOne : K.calClearMonthBodyMany,
            [planned, from, to])),
        findsOneWidget);
    expect(ds.clearedRanges, isEmpty);

    await tester.tap(find.text(pt[K.bulkYesDelete]));
    await tester.pumpAndSettle();

    final call = ds.clearedRanges.single;
    expect(call.from, dateOnly(today));
    expect(call.to, endOfMonth);
    // The per-day delete never ran.
    expect(ds.deleted, isEmpty);
    expect(
        find.textContaining(
            pt.format(planned == 1 ? K.sumDeletedOne : K.sumDeletedMany,
                [planned])),
        findsOneWidget);
    await settleSnack(tester);
  });

  testWidgets('the count leaves out what the server keeps — a frozen day and '
      'an approved swap', (tester) async {
    final future = futureDay;
    if (future == null || future + 2 > endOfMonth.day) return;
    final ds = FakeCustodyDataSource(members: [anaAdmin, bruno], days: [
      row(7, dayOfMonth(future), 1),
      row(8, dayOfMonth(future + 1), 1, actual: 2), // approved swap: kept
      row(9, dayOfMonth(future + 2), 1), // frozen below: kept
    ])
      ..frozenRequests = [
        SwapRequest.fromJson({
          'id': 1,
          'schedule_date': CareSchedule.isoDate(dayOfMonth(future + 2)),
          'schedule_id': 9,
          'requesting_profile_id': 2,
          'target_profile_id': 1,
          'proposed_actual_parent_id': 2,
          'status': 'pending',
          'created_at': '2026-09-01T00:00:00Z',
        }),
      ];
    await tester.pumpWidget(app(ds, adminMode: AdminMode()..toggle()));
    await tester.pumpAndSettle();

    await openMenu(tester);
    await tester.tap(find.text(pt[K.calClearMonth]));
    await tester.pumpAndSettle();

    expect(
        find.text(pt.format(K.calClearMonthBodyOne, [
          1,
          pt.formatDate(dateOnly(today)),
          pt.formatDate(endOfMonth),
        ])),
        findsOneWidget);
  });

  testWidgets('cancelling the question writes nothing', (tester) async {
    final future = futureDay;
    if (future == null) return;
    final ds = FakeCustodyDataSource(
        members: [anaAdmin, bruno], days: [row(7, dayOfMonth(future), 1)]);
    await tester.pumpWidget(app(ds, adminMode: AdminMode()..toggle()));
    await tester.pumpAndSettle();

    await openMenu(tester);
    await tester.tap(find.text(pt[K.calClearMonth]));
    await tester.pumpAndSettle();
    await tester.tap(find.text(pt[K.commonCancel]));
    await tester.pumpAndSettle();

    expect(ds.clearedRanges, isEmpty);
    expect(ds.days, hasLength(1));
  });

  testWidgets('a month with nothing planned from today on says so — no '
      'question, no call', (tester) async {
    // A row BEFORE today is never in the range: the past is never offered.
    final ds = FakeCustodyDataSource(members: [anaAdmin, bruno], days: [
      if (today.day > 1) row(7, dayOfMonth(today.day - 1), 1),
    ]);
    await tester.pumpWidget(app(ds, adminMode: AdminMode()..toggle()));
    await tester.pumpAndSettle();

    await openMenu(tester);
    await tester.tap(find.text(pt[K.calClearMonth]));
    await tester.pumpAndSettle();

    expect(find.text(pt[K.calClearMonthTitle]), findsNothing);
    expect(ds.clearedRanges, isEmpty);
    expect(
        find.textContaining(pt.format(K.calClearMonthNothing,
            [pt.formatDate(dateOnly(today)), pt.formatDate(endOfMonth)])),
        findsOneWidget);
    await settleSnack(tester);
  });
}
