// F-39 call site (T-53 lote 2): month paging stops at the family's planning
// horizon — the swipe bounces back and the tier message explains, mirroring
// the web's NextMonth. The call site is fail-OPEN by design: a failed
// entitlement read defaults to premium so paging is never wrongly blocked
// (the DB enforces the real limit regardless).
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/family.dart';

import 'calendar_slice_test.dart';

const freeFamily = Family(id: 1, plan: 'free');

/// Settings shrinking the free horizon to 1 month so the second forward swipe
/// crosses it whatever today is; premium stays at the seeded 24.
const tightSettings = {'calendar_months_free': '1'};

final _pt = Localization(AppLanguage.ptBr);

String monthTitle(DateTime month) =>
    monthHeading(_pt, month);

DateTime monthsAhead(int n) => DateTime(today.year, today.month + n, 1);

Future<void> swipeToNextMonth(WidgetTester tester) async {
  await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('free family: paging beyond the horizon bounces with the tier '
      'message', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..family = freeFamily
      ..publicSettings = tightSettings;
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    // Month 1 (today + 1) is the horizon month itself — reachable.
    await swipeToNextMonth(tester);
    expect(find.text(monthTitle(monthsAhead(1))), findsOneWidget);

    // Month 2 crosses the horizon: refused, explained, bounced back.
    await swipeToNextMonth(tester);
    expect(find.text(monthTitle(monthsAhead(1))), findsOneWidget);
    expect(find.text(monthTitle(monthsAhead(2))), findsNothing);
    expect(
        find.text(_pt.format(K.horizonFree, [1, 24])), findsOneWidget);
  });

  testWidgets('premium family: the free horizon does not clamp',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..family = const Family(id: 1, plan: 'premium')
      ..publicSettings = tightSettings;
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await swipeToNextMonth(tester);
    await swipeToNextMonth(tester);
    expect(find.text(monthTitle(monthsAhead(2))), findsOneWidget);
  });

  testWidgets('entitlement read failure fails OPEN: paging is never wrongly '
      'blocked', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..throwOnFamily = Exception('offline')
      ..publicSettings = tightSettings;
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await swipeToNextMonth(tester);
    await swipeToNextMonth(tester);
    expect(find.text(monthTitle(monthsAhead(2))), findsOneWidget);
  });

  testWidgets('paging backwards is never clamped', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..family = freeFamily
      ..publicSettings = tightSettings;
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();
    expect(find.text(monthTitle(monthsAhead(-1))), findsOneWidget);
  });
}
