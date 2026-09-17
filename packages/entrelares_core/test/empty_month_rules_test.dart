// U-40 — the pure half of the empty-month strip: which months get a
// sentence, which sentence, and where the wizard starts.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

final _today = DateTime(2026, 9, 16, 14, 30);
final _horizon = DateTime(2026, 12, 16); // three months ahead

EmptyMonthPrompt _prompt(DateTime month,
        {bool planned = false, bool loading = false, DateTime? horizon}) =>
    emptyMonthPrompt(
      visibleMonth: month,
      today: _today,
      horizonDate: horizon ?? _horizon,
      hasPlannedDays: planned,
      loading: loading,
    );

void main() {
  group('emptyMonthPrompt', () {
    test('a future empty month within the horizon offers the plan', () {
      expect(_prompt(DateTime(2026, 10, 1)), EmptyMonthPrompt.offerPlan);
    });

    test('the CURRENT month, empty, offers the plan too', () {
      expect(_prompt(DateTime(2026, 9, 1)), EmptyMonthPrompt.offerPlan);
    });

    test('a past month says nothing — the past is never offered', () {
      expect(_prompt(DateTime(2026, 8, 1)), EmptyMonthPrompt.none);
    });

    test('a month with planned days says nothing', () {
      expect(_prompt(DateTime(2026, 10, 1), planned: true),
          EmptyMonthPrompt.none);
    });

    test('nothing while the month is still loading', () {
      expect(_prompt(DateTime(2026, 10, 1), loading: true),
          EmptyMonthPrompt.none);
    });

    test('the horizon month itself is still within reach', () {
      expect(_prompt(DateTime(2026, 12, 1)), EmptyMonthPrompt.offerPlan);
    });

    test('beyond the horizon the strip states the limit instead', () {
      expect(_prompt(DateTime(2027, 1, 1)), EmptyMonthPrompt.beyondHorizon);
    });

    test('a past month beyond nothing: the past wins over the horizon', () {
      // A horizon behind today cannot happen, but the order of the gates is
      // the rule: past → none, before the horizon is even asked.
      expect(_prompt(DateTime(2026, 8, 1), horizon: DateTime(2026, 7, 1)),
          EmptyMonthPrompt.none);
    });

    test('the visible month may carry any day — only year and month count',
        () {
      expect(_prompt(DateTime(2026, 10, 23, 9)), EmptyMonthPrompt.offerPlan);
    });
  });

  group('emptyMonthPlanStart', () {
    test('a future month starts on its 1st', () {
      expect(emptyMonthPlanStart(visibleMonth: DateTime(2026, 10, 1), today: _today),
          DateTime(2026, 10, 1));
    });

    test('the current month starts TODAY, date-only', () {
      expect(emptyMonthPlanStart(visibleMonth: DateTime(2026, 9, 1), today: _today),
          DateTime(2026, 9, 16));
    });

    test('a past month has no start', () {
      expect(emptyMonthPlanStart(visibleMonth: DateTime(2026, 8, 1), today: _today),
          isNull);
    });

    test('it is monthClearRange.from — the two entry points agree', () {
      for (final m in [DateTime(2026, 9, 1), DateTime(2026, 11, 1)]) {
        expect(emptyMonthPlanStart(visibleMonth: m, today: _today),
            monthClearRange(visibleMonth: m, today: _today)!.from);
      }
    });
  });
}
