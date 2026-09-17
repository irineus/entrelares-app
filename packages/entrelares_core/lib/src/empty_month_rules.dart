/// U-40 — what an EMPTY month says under its grid.
///
/// A month with no planned day paints thirty grey "•" cells (`parentInitial`
/// returns '•' for an unassigned day), which looks filled with something and
/// says nothing. The first-use guidance (U-04) never reached the Flutter port
/// — its two catalog keys sat unwired — and it would only have covered the
/// first month anyway: a parent who pages past the generated plan lands on
/// the same thirty dots.
///
/// This file decides WHETHER the grid gets a sentence and WHICH one; the
/// screen only renders. The wizard's start date is not decided here either:
/// it is `monthClearRange(...).from` — the 1st of the month, or today if the
/// month is the current one — so the two entry points that act on "this
/// month from today onward" agree by construction.
library;

import 'freemium_rules.dart';
import 'schedule_range_rules.dart';

/// What the strip under an empty month offers.
enum EmptyMonthPrompt {
  /// Nothing: the month is loading, has planned days, or is already behind
  /// the reader (the past is never offered a plan — F-40/F-51 posture).
  none,

  /// "Nenhum dia planejado em outubro · Gerar plano" — the wizard, opened on
  /// this month.
  offerPlan,

  /// Beyond the F-39 horizon the wizard could not write a single day of this
  /// month, so the strip states the limit instead — the same sentence the
  /// paging bounce already uses. Reachable only when the horizon shrinks
  /// under a month already on screen (settings or entitlement landing after
  /// a swipe): the paging itself never crosses it.
  beyondHorizon,
}

/// Decides the strip for [visibleMonth].
///
/// [hasPlannedDays] is the month's own rows; [loading] hides the strip while
/// they are in flight (a sentence about an absence must not flash before the
/// answer arrives); [horizonDate] is the family's planning horizon, as the
/// paging computes it.
EmptyMonthPrompt emptyMonthPrompt({
  required DateTime visibleMonth,
  required DateTime today,
  required DateTime horizonDate,
  required bool hasPlannedDays,
  required bool loading,
}) {
  if (loading || hasPlannedDays) return EmptyMonthPrompt.none;
  if (monthClearRange(visibleMonth: visibleMonth, today: today) == null) {
    return EmptyMonthPrompt.none;
  }
  return canPageToMonth(visibleMonth, horizonDate)
      ? EmptyMonthPrompt.offerPlan
      : EmptyMonthPrompt.beyondHorizon;
}

/// The day the wizard opens on for an empty [visibleMonth]: its 1st, or
/// today when the month is the current one. Null for a past month, which is
/// never offered.
DateTime? emptyMonthPlanStart({
  required DateTime visibleMonth,
  required DateTime today,
}) =>
    monthClearRange(visibleMonth: visibleMonth, today: today)?.from;
