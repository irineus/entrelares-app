// F-51 — "Limpar mês": the ⋮ menu's one-tap clear of the displayed month,
// against the fake data source. What the tests pin: the item exists only
// under the admin bypass; the confirmation spells the count and the range and
// nothing is written before the yes; the write is ONE range call from today
// to the end of the month; the toast is the server's own counts; and a month
// with nothing planned ahead says so instead of asking.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/member.dart';
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
  testWidgets('without admin mode the menu has no "Limpar mês"',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [anaAdmin, bruno], days: []);
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
