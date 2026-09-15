// F-65 — the quick swap from a selected pair of days, against the fake data
// source: the bar offers ⇄ Trocar only for a pair of planned parents with
// equal days (1+1, 2+2 — never 2+1), never to a third caregiver (F-28), never
// over a swapped day; the confirmation names who takes what; confirming opens
// one request per day with the proposals inverted and the F-44 message on
// each; the summary toast reports them and the selection clears.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';

import 'calendar_slice_test.dart';

const carla =
    Member(id: 3, fullName: 'Carla Dias', colorSlot: 3, userId: 'u3');

final pt = Localization(AppLanguage.ptBr);

/// N consecutive future days of the current month, or null when the month
/// cannot host them.
List<int>? futureDays(int n) {
  final lastDay = DateTime(today.year, today.month + 1, 0).day;
  if (today.day + n > lastDay) return null;
  return [for (var i = 1; i <= n; i++) today.day + i];
}

Future<void> longPressDay(WidgetTester tester, int day) async {
  final finder = find.text('$day').last;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.longPress(finder);
  await tester.pumpAndSettle();
}

Finder swapButton(int count) => find.text(pt.format(K.selectionSwap, [count]));

void main() {
  testWidgets('1+1: the bar offers ⇄ Trocar, the sheet says who takes what, '
      'confirming opens two inverted requests with the message',
      (tester) async {
    final days = futureDays(2);
    if (days == null) return;
    final d1 = dayOfMonth(days[0]);
    final d2 = dayOfMonth(days[1]);
    // d1 planned for Ana (me), d2 for Bruno.
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(1, d1, 1), row(2, d2, 2)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days[0]);
    // One day alone: nothing new — only the regular bulk edit.
    expect(swapButton(1), findsNothing);
    expect(find.text(pt.format(K.selectionEdit, [1])), findsOneWidget);

    await longPressDay(tester, days[1]);
    expect(swapButton(2), findsOneWidget);
    // Never beside 🔔 Resolver: a clean pair has nothing to resolve.
    expect(find.textContaining('🔔'), findsNothing);

    await tester.tap(swapButton(2));
    await tester.pumpAndSettle();

    expect(find.text(pt.format(K.quickSwapTitle, [2])), findsOneWidget);
    expect(
        find.text(pt.format(
            K.quickSwapTheyTake, ['Bruno Lima', pt.formatDateShort(d1)])),
        findsOneWidget);
    expect(find.text(pt.format(K.quickSwapYouTake, [pt.formatDateShort(d2)])),
        findsOneWidget);
    expect(find.text(pt.format(K.quickSwapRequests, [2, 'Bruno Lima'])),
        findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, pt[K.bulkMessagePlaceholder]),
        'Consulta na terça');
    await tapSheet(
        tester, find.widgetWithText(FilledButton, pt[K.quickSwapConfirm]));

    expect(ds.createdSwapRequests, hasLength(2));
    final byDate = {
      for (final r in ds.createdSwapRequests) r['date']: r,
    };
    expect(byDate[CareSchedule.isoDate(d1)]!['proposed'], 2);
    expect(byDate[CareSchedule.isoDate(d2)]!['proposed'], 1);
    for (final r in ds.createdSwapRequests) {
      expect(r['requester'], 1);
      expect(r['message'], 'Consulta na terça');
      expect(r['handoff'], isNull);
    }
    // The base rows were refreshed (F-26 snapshot), never rewritten.
    expect(ds.updated, hasLength(2));
    expect(ds.updated.map((r) => r.actualParentId), everyElement(isNull));
    expect(ds.inserted, isEmpty);

    // The toast reports the requests and the selection cleared.
    expect(find.text('2 solicitações de troca'), findsOneWidget);
    expect(find.textContaining('✏️'), findsNothing);
    await settleSnack(tester);
  });

  testWidgets('2+1 is not a pair: the button leaves and comes back with 2+2',
      (tester) async {
    final days = futureDays(4);
    if (days == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [
      row(1, dayOfMonth(days[0]), 1),
      row(2, dayOfMonth(days[1]), 1),
      row(3, dayOfMonth(days[2]), 2),
      row(4, dayOfMonth(days[3]), 2),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days[0]);
    await longPressDay(tester, days[2]);
    expect(swapButton(2), findsOneWidget);

    await longPressDay(tester, days[1]);
    expect(find.textContaining('⇄'), findsNothing);
    expect(find.text(pt.format(K.selectionEdit, [3])), findsOneWidget);

    await longPressDay(tester, days[3]);
    expect(swapButton(4), findsOneWidget);
  });

  testWidgets('F-28: a third caregiver selecting the same pair never sees '
      'the button', (tester) async {
    final days = futureDays(2);
    if (days == null) return;
    // Carla is the signed-in member (first of the roster in the fake).
    final ds = FakeCustodyDataSource(members: [carla, ana, bruno], days: [
      row(1, dayOfMonth(days[0]), 1),
      row(2, dayOfMonth(days[1]), 2),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days[0]);
    await longPressDay(tester, days[1]);
    expect(find.textContaining('⇄'), findsNothing);
    expect(find.text(pt.format(K.selectionEdit, [2])), findsOneWidget);
  });

  testWidgets('a day already swapped hides the button and 🔔 Resolver takes '
      'its place', (tester) async {
    final days = futureDays(2);
    if (days == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [
      row(1, dayOfMonth(days[0]), 1, actual: 2), // approved swap
      row(2, dayOfMonth(days[1]), 2),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await longPressDay(tester, days[0]);
    await longPressDay(tester, days[1]);
    expect(find.textContaining('⇄'), findsNothing);
    expect(find.text(pt.format(K.selectionResolve, [1])), findsOneWidget);
  });
}
