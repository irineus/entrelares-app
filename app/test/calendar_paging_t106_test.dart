// T-106 — paging the month took 2–3 s: every swipe re-read the whole screen
// (10–14 reads, one after another, each a round trip through the gateway)
// when only the month's own reads change with it. A swipe now reads the month
// alone, a month read before paints in the same frame (and is re-read in
// silence), the months either side are read ahead, and a slow read of a month
// already left behind never writes over the month on screen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';

import 'calendar_slice_test.dart';
import 'horizon_clamp_test.dart' show monthTitle, monthsAhead, swipeToNextMonth;

/// A source that counts the context reads and can hold a month's rows back.
class _HeldMonths extends FakeCustodyDataSource {
  _HeldMonths({required super.members, required super.days});

  final Map<(int, int), Completer<void>> held = {};
  int memberReads = 0;
  int profileReads = 0;
  int upcomingReads = 0;

  void hold(DateTime month) =>
      held[(month.year, month.month)] = Completer<void>();

  void release(DateTime month) =>
      held.remove((month.year, month.month))?.complete();

  @override
  Future<List<CareSchedule>> fetchMonth(int year, int month) async {
    final gate = held[(year, month)];
    if (gate != null) await gate.future;
    return super.fetchMonth(year, month);
  }

  @override
  Future<List<Member>> fetchMembers() {
    memberReads++;
    return super.fetchMembers();
  }

  @override
  Future<Member?> fetchOwnProfile() {
    profileReads++;
    return super.fetchOwnProfile();
  }

  @override
  Future<List<CareSchedule>> fetchUpcoming(DateTime from, int days) {
    upcomingReads++;
    return super.fetchUpcoming(from, days);
  }
}

DateTime _day10(DateTime month) => DateTime(month.year, month.month, 10);

/// A swipe onto a month still loading: its skeleton animates, so the page
/// change is pumped for a fixed time instead of settled.
Future<void> _swipeOntoLoading(WidgetTester tester) async {
  await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final next = monthsAhead(1);
  final afterNext = monthsAhead(2);

  testWidgets('a swipe reads the month alone — the context is not read again', (
    tester,
  ) async {
    final ds = _HeldMonths(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    final members = ds.memberReads;
    final profiles = ds.profileReads;
    final upcoming = ds.upcomingReads;
    final reads = ds.monthReads.length;

    await swipeToNextMonth(tester);

    expect(find.text(monthTitle(next)), findsOneWidget);
    expect(ds.memberReads, members);
    expect(ds.profileReads, profiles);
    expect(ds.upcomingReads, upcoming);
    // The month on screen is read again (the cache is always revalidated),
    // and the month after it is read ahead.
    final since = ds.monthReads.skip(reads).toList();
    expect(since, contains((next.year, next.month)));
    expect(since, contains((afterNext.year, afterNext.month)));
  });

  testWidgets('the month after is read ahead and paints in the swipe, before '
      'its own read answers', (tester) async {
    final ds = _HeldMonths(
      members: [ana, bruno],
      days: [row(1, _day10(next), bruno.id)],
    );
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    // Read ahead while the current month was on screen.
    expect(ds.monthReads, contains((next.year, next.month)));

    // The swipe's own read is held: what shows came from the cache.
    ds.hold(next);
    await swipeToNextMonth(tester);
    expect(find.text(monthTitle(next)), findsOneWidget);
    expect(inGrid('B'), findsWidgets);

    ds.release(next);
    await tester.pumpAndSettle();
    expect(inGrid('B'), findsWidgets);
  });

  testWidgets('a slow read of a month left behind never writes over the month '
      'on screen', (tester) async {
    final ds = _HeldMonths(
      members: [ana, bruno],
      days: [row(1, _day10(next), ana.id), row(2, _day10(afterNext), bruno.id)],
    );
    // Next month's rows are held from the start — its read-ahead too — so
    // the swipe onto it waits, and the reader moves on before it answers.
    ds.hold(next);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await _swipeOntoLoading(tester);
    expect(find.text(monthTitle(next)), findsOneWidget);
    await swipeToNextMonth(tester);
    expect(find.text(monthTitle(afterNext)), findsOneWidget);
    expect(inGrid('B'), findsWidgets);

    // Next month's reads answer now, late: the month on screen keeps its own.
    ds.release(next);
    await tester.pumpAndSettle();
    expect(find.text(monthTitle(afterNext)), findsOneWidget);
    expect(inGrid('B'), findsWidgets);
    expect(inGrid('A'), findsNothing);
  });

  testWidgets('a Realtime change reads the context again, and a month read '
      'before it is read again when shown', (tester) async {
    final ds = _HeldMonths(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    final members = ds.memberReads;

    // Another member plans next month while it sits in the cache.
    ds.days.add(row(1, _day10(next), bruno.id));
    ds.realtimeCallback!();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(ds.memberReads, greaterThan(members));

    await swipeToNextMonth(tester);
    expect(inGrid('B'), findsWidgets);
  });
}
