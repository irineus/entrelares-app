// U-40 — the empty month says what to do. The strip under the grid appears
// for an empty month that is not in the past, names the month, and opens the
// wizard ON that month; a past month, a loading month and a month with rows
// get nothing; a month that fell beyond the F-39 horizon (settings landing
// after a swipe) states the limit instead of offering a plan.
import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_app/screens/calendar_screen.dart';

import 'calendar_slice_test.dart';
import 'horizon_clamp_test.dart'
    show freeFamily, monthsAhead, swipeToNextMonth, tightSettings;

final _pt = Localization(AppLanguage.ptBr);
final _en = Localization(AppLanguage.en);

/// A source whose month rows and public settings can be held back, so the
/// test can look at the screen BEFORE they land.
class _GatedSource extends FakeCustodyDataSource {
  final monthGate = Completer<void>();
  final settingsGate = Completer<void>();
  bool holdMonth = false;
  bool holdSettings = false;

  _GatedSource({required super.members, required super.days});

  @override
  Future<List<CareSchedule>> fetchMonth(int year, int month) async {
    if (holdMonth) await monthGate.future;
    return super.fetchMonth(year, month);
  }

  @override
  Future<Map<String, String>> fetchPublicSettings() async {
    if (holdSettings) await settingsGate.future;
    return super.fetchPublicSettings();
  }
}

Finder _strip(Localization l, DateTime month) =>
    find.text(l.format(K.calEmptyMonth, [l.monthName(month.month)]));

Finder get _planButton => find.byKey(EmptyMonthStrip.planKey);

/// The wizard's start-date button, by the date it shows — scoped to the
/// button so a date printed elsewhere on the screen cannot answer for it.
Finder _wizardStart(DateTime date) => find.descendant(
    of: find.byKey(const Key('wizStartDate')),
    matching: find.text(_pt.formatDate(date)));

void main() {
  testWidgets('the current month, empty, shows the strip and opens the '
      'wizard on TODAY', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    expect(_strip(_pt, today), findsOneWidget);
    expect(_planButton, findsOneWidget);

    await tester.tap(_planButton);
    await tester.pumpAndSettle();
    expect(find.text(_pt[K.wizTitle]), findsOneWidget);
    expect(_wizardStart(dateOnly(today)), findsOneWidget);
  });

  testWidgets('a future empty month names itself and opens the wizard on '
      'its 1st', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await swipeToNextMonth(tester);
    final next = monthsAhead(1);
    expect(_strip(_pt, next), findsOneWidget);
    // The previous page's strip is gone with its month.
    expect(_strip(_pt, today), findsNothing);

    await tester.tap(_planButton);
    await tester.pumpAndSettle();
    expect(find.text(_pt[K.wizTitle]), findsOneWidget);
    expect(_wizardStart(next), findsOneWidget);
  });

  testWidgets('a past empty month says nothing — the past is never offered',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await tester.fling(find.byType(PageView), const Offset(400, 0), 1000);
    await tester.pumpAndSettle();

    expect(_strip(_pt, monthsAhead(-1)), findsNothing);
    expect(_planButton, findsNothing);
  });

  testWidgets('a month with a planned day gets no strip', (tester) async {
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dayOfMonth(today.day), 1)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    expect(_strip(_pt, today), findsNothing);
    expect(_planButton, findsNothing);
  });

  testWidgets('nothing while the month is still loading; the strip lands '
      'with the rows', (tester) async {
    final ds = _GatedSource(members: [ana, bruno], days: [])..holdMonth = true;
    await tester.pumpWidget(app(ds));
    // Frames, never settle: the skeleton animates until the rows arrive.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(_strip(_pt, today), findsNothing,
        reason: 'a sentence about an absence must not flash before the '
            'answer arrives');

    ds.monthGate.complete();
    await tester.pumpAndSettle();
    expect(_strip(_pt, today), findsOneWidget);
  });

  testWidgets('a month that fell beyond the horizon states the limit and '
      'offers no plan', (tester) async {
    // The paging never crosses the horizon by itself: the free family reads
    // the seeded 6 months while the settings are in flight, swipes two
    // months ahead, and THEN the settings land with a 1-month horizon.
    final ds = _GatedSource(members: [ana, bruno], days: [])
      ..family = freeFamily
      ..publicSettings = tightSettings
      ..holdSettings = true;
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await swipeToNextMonth(tester);
    await swipeToNextMonth(tester);
    final shown = monthsAhead(2);
    expect(_strip(_pt, shown), findsOneWidget);
    expect(_planButton, findsOneWidget);

    ds.settingsGate.complete();
    await tester.pumpAndSettle();

    expect(find.text(_pt.format(K.horizonFree, [1, 24])), findsOneWidget);
    expect(_strip(_pt, shown), findsNothing);
    expect(_planButton, findsNothing);
  });

  testWidgets('an English session reads the strip in English',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds, language: AppLanguage.en));
    await tester.pumpAndSettle();

    expect(_strip(_en, today), findsOneWidget);
    expect(find.text(_en[K.calEmptyMonthPlan]), findsOneWidget);
    expect(_strip(_pt, today), findsNothing);
  });
}
