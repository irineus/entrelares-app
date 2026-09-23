/// F-70 — the plan-end notification's one action: planning the next months.
///
/// `plan_end_reminders_due()` writes a `plan_ending` row whose `params.date` is
/// the family's LAST planned day (ISO `yyyy-MM-dd`) and whose `kind` says
/// whether that day is still ahead (`ending`) or already past (`ended`). The
/// row's action opens the wizard on the first day with no plan — which is the
/// day after the last one, unless that day is already behind us, where the
/// first plannable day is today (the past never enters a plan, F-51).
library;

import 'dart:convert';

abstract final class PlanEndRules {
  /// The notification type the job writes.
  static const type = 'plan_ending';

  /// The two `kind`s the job writes; anything else is a future writer's shape
  /// and gets no action (the row still renders its stored sentence).
  static const kinds = {'ending', 'ended'};

  /// The day the row's action opens the wizard on, or null when the row
  /// offers no action: another type, an unknown `kind`, or no real date.
  /// [paramsJson] is the row's `params` as stored.
  static DateTime? actionStart(String type, String? paramsJson, DateTime today) {
    if (type != PlanEndRules.type || paramsJson == null) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(paramsJson);
    } on FormatException {
      return null;
    }
    if (decoded is! Map || !kinds.contains(decoded['kind'])) return null;
    final date = decoded['date'];
    return date is String ? wizardStart(date, today) : null;
  }

  /// The day the wizard opens on: [isoLastDay] + 1, never before [today].
  /// Null when [isoLastDay] is not a real ISO date.
  static DateTime? wizardStart(String? isoLastDay, DateTime today) {
    final last = _parseIso(isoLastDay);
    return last == null ? null : startAfter(last, today);
  }

  /// The first plannable day after the plan's [lastDay]: the next day, or
  /// [today] when that one is already past.
  static DateTime startAfter(DateTime lastDay, DateTime today) {
    final next = DateTime(lastDay.year, lastDay.month, lastDay.day + 1);
    final floor = DateTime(today.year, today.month, today.day);
    return next.isBefore(floor) ? floor : next;
  }

  /// The window in which the calendar says the plan is ending — the same 30
  /// days the job's first reminder uses, so the strip and the notification
  /// never disagree about whether there is anything to say.
  static const stripWindowDays = 30;

  /// The calendar's plan-end strip: `ending` while [lastDay] is at most
  /// [stripWindowDays] ahead (today included), `ended` once it is past, null
  /// when it is further away or when the family never planned (that is the
  /// empty-month strip's case, U-40, not this one). Unlike the notification,
  /// the strip is a STATE, not an event: it shows every day until the family
  /// plans further, whichever door — e-mail, push, a plain visit — they came
  /// through.
  static String? stripKind(DateTime? lastDay, DateTime today) {
    if (lastDay == null) return null;
    final last = DateTime.utc(lastDay.year, lastDay.month, lastDay.day);
    final floor = DateTime.utc(today.year, today.month, today.day);
    if (last.isBefore(floor)) return 'ended';
    // Calendar days in UTC: a DST shift must not move the edge.
    return last.difference(floor).inDays <= stripWindowDays ? 'ending' : null;
  }

  static DateTime? _parseIso(String? value) {
    if (value == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final parsed = DateTime(y, mo, d);
    // `DateTime` rolls an impossible day over (2026-02-30 → 02/03); a day
    // that does not round-trip is not the day the server meant.
    if (parsed.year != y || parsed.month != mo || parsed.day != d) return null;
    return parsed;
  }
}
