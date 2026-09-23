/// U-55 — one handoff time for every future transition day, and the strip
/// that offers it on a plan born without one.
///
/// The write itself is `set_handoff_time_range` (migration
/// `20260923003000`, SECURITY INVOKER, F-51's shape): it writes ONLY future
/// transition days that have no time, spares frozen days, and answers the
/// counts. This file decides when the admin is OFFERED it and turns the
/// answer into words.
library;

import 'bulk_rules.dart' show bulkPluralize;
import 'calendar_rules.dart' show isTransitionDay;
import 'date_math.dart';
import 'localization/k.dart';
import 'localization/localization.dart';

/// What the RPC answers — every count is the SERVER's.
class HandoffRangeResult {
  /// Transition days that received the time.
  final int updated;

  /// Transition days without a time left alone: a request is pending (F-12).
  final int keptFrozen;

  /// Transition days that already had a time — never overwritten.
  final int keptExisting;

  /// F-51: the stamp every audit row of this call carries.
  final String? batchId;

  const HandoffRangeResult({
    required this.updated,
    required this.keptFrozen,
    required this.keptExisting,
    this.batchId,
  });

  factory HandoffRangeResult.fromJson(Map<String, dynamic> json) {
    int count(String key) {
      final v = json[key];
      return v is num ? v.toInt() : 0;
    }

    final batch = json['batch_id'];
    return HandoffRangeResult(
      updated: count('updated'),
      keptFrozen: count('kept_frozen'),
      keptExisting: count('kept_existing'),
      batchId: batch is String && batch.isNotEmpty ? batch : null,
    );
  }
}

/// The closing line: "12 trocas com horário definido · 1 dia mantido
/// (solicitação pendente)", or the sentence for a plan with nothing to fill.
String handoffRangeSummary(Localization l, HandoffRangeResult r) {
  final parts = [
    if (r.updated > 0)
      bulkPluralize(
          l, r.updated, K.handoffRangeUpdatedOne, K.handoffRangeUpdatedMany),
    if (r.keptExisting > 0)
      bulkPluralize(l, r.keptExisting, K.handoffRangeKeptExistingOne,
          K.handoffRangeKeptExistingMany),
    if (r.keptFrozen > 0)
      bulkPluralize(l, r.keptFrozen, K.sumKeptFrozenOne, K.sumKeptFrozenMany),
  ];
  return parts.isNotEmpty ? parts.join(' · ') : l[K.handoffRangeNothing];
}

/// One day of the calendar's upcoming window, as the strip rule reads it.
class HandoffNudgeDay {
  final DateTime date;

  /// `actual ?? scheduled` — the T-27 rule compares the EFFECTIVE carer.
  final int effectiveParentId;
  final bool hasTime;

  const HandoffNudgeDay({
    required this.date,
    required this.effectiveParentId,
    required this.hasTime,
  });
}

/// U-55: whether the admin is offered "Definir horário" for the plan.
///
/// Shown when the upcoming window ([upcoming], from today on — the calendar
/// already holds `[today, today + 91]`) has at least one TRANSITION day and
/// NONE of them carries a time: a family that uses handoff times anywhere in
/// the window has made its choice, and a single day without one is an
/// exception, not a plan born without the question. [yesterday] closes the
/// first day's T-27 test; a missing day before a day (a gap in the plan, or
/// no row yesterday) makes it a transition, as the database says.
///
/// Admin-only — the RPC refuses anyone else — and silent for good once the
/// reader [dismissed] it on this device.
bool showHandoffNudge({
  required bool isAdmin,
  required bool dismissed,
  required List<HandoffNudgeDay> upcoming,
  HandoffNudgeDay? yesterday,
}) {
  if (!isAdmin || dismissed || upcoming.isEmpty) return false;
  final days = [...upcoming]..sort((a, b) => a.date.compareTo(b.date));
  var previous = yesterday;
  var anyTransition = false;
  for (final day in days) {
    final contiguous = previous != null &&
        dateOnly(previous.date) ==
            DateTime(day.date.year, day.date.month, day.date.day - 1);
    final transition = isTransitionDay(
        contiguous ? previous.effectiveParentId : null,
        day.effectiveParentId);
    if (transition) {
      if (day.hasTime) return false;
      anyTransition = true;
    }
    previous = day;
  }
  return anyTransition;
}
