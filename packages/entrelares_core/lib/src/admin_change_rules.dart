/// F-81 — an admin's DIRECT change of a day, told to the caregivers it
/// affects.
///
/// `flush_admin_change_notices()` writes ONE `day_admin_change` row per
/// affected caregiver per action (per transaction): kind `single` when the
/// action touched one of that reader's days (`params.date` is the day), kind
/// `batch` when it touched several (`params.date` is the first, `params.to`
/// the last, `params.count` how many). The row — and the push — open what
/// answers "what changed?": the day itself for one, the Histórico for many.
library;

import 'dart:convert';

/// What a `day_admin_change` row opens.
enum AdminChangeTarget {
  /// The calendar with that day's sheet open.
  day,

  /// Relatórios → Histórico, where the batch folds into one entry (F-51).
  auditTrail,
}

abstract final class AdminChangeRules {
  /// The notification type the flush writes.
  static const type = 'day_admin_change';

  /// One day of the reader's changed.
  static const single = 'single';

  /// Several days of the reader's changed in one action.
  static const batch = 'batch';

  /// What the row opens, or null when it offers nothing: another type, an
  /// unknown `kind` (a future writer's shape), or a `single` whose day is not
  /// a real ISO date. [paramsJson] is the row's `params` as stored.
  static AdminChangeTarget? targetOf(String type, String? paramsJson) {
    final p = _params(type, paramsJson);
    if (p == null) return null;
    return switch (p['kind']) {
      AdminChangeRules.single when dayOf(type, paramsJson) != null =>
        AdminChangeTarget.day,
      AdminChangeRules.batch => AdminChangeTarget.auditTrail,
      _ => null,
    };
  }

  /// The day a `single` row names, or null.
  static DateTime? dayOf(String type, String? paramsJson) {
    final p = _params(type, paramsJson);
    if (p == null || p['kind'] != single) return null;
    return parseIsoDay(p['date']);
  }

  /// A `YYYY-MM-DD` that round-trips as a calendar day, or null. Shared with
  /// the web's `/?day=` landing, which reads the same shape off the address.
  static DateTime? parseIsoDay(Object? value) {
    if (value is! String) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final day = DateTime(y, mo, d);
    if (day.year != y || day.month != mo || day.day != d) return null;
    return day;
  }

  static Map<String, dynamic>? _params(String type, String? paramsJson) {
    if (type != AdminChangeRules.type || paramsJson == null) return null;
    try {
      final decoded = jsonDecode(paramsJson);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
