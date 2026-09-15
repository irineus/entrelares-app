/// F-51 — clear planned days in one action. The pure half of the two entry
/// points: the RANGE each one asks the server to clear, and the sentence each
/// one closes with.
///
/// The operation itself is one `SECURITY INVOKER` RPC per entry point
/// (`clear_schedule_range`, `replace_schedule_range` — migration
/// `20260915181851`), so `enforce_day_protection` and RLS judge every row as
/// the caller. Nothing here decides what may be deleted: the trigger decides,
/// the RPC's WHERE spares what the trigger would refuse, and this file only
/// turns a calendar position into a range and a result into words.
///
/// Vocabulary is the bulk edit's, on purpose (F-44's lesson: two words for one
/// action): the S-09 overwrite warning (`bulkOverwriteWarningOne/Many`) is the
/// wizard's confirmation, and the closing counts reuse the `sum.*` family.
library;

import 'bulk_rules.dart' show bulkPluralize;
import 'date_math.dart';
import 'localization/k.dart';
import 'localization/localization.dart';

/// An inclusive date range, date-only on both ends.
typedef DateRange = ({DateTime from, DateTime to});

/// "Limpar mês": from TODAY (inclusive) to the last day of the displayed
/// month, never the past — a future month is whole, the current month starts
/// today, and a month already behind us has nothing to clear (null). The
/// narrowing is deliberate even for an admin who could edit past days one by
/// one (F-40): a bulk action must not be able to rewrite history by accident.
DateRange? monthClearRange({
  required DateTime visibleMonth,
  required DateTime today,
}) {
  final t = dateOnly(today);
  final first = DateTime(visibleMonth.year, visibleMonth.month, 1);
  final last = DateTime(visibleMonth.year, visibleMonth.month + 1, 0);
  if (last.isBefore(t)) return null;
  return (from: first.isBefore(t) ? t : first, to: last);
}

/// The wizard's replace range: exactly what it is about to generate —
/// `generateRotation` walks `[start, end)`, so the inclusive end is the day
/// before [end]. Null when the plan is empty (nothing to clear for nothing).
DateRange? wizardReplaceRange({
  required DateTime start,
  required DateTime end,
}) {
  final from = dateOnly(start);
  final to = DateTime(end.year, end.month, end.day - 1);
  if (to.isBefore(from)) return null;
  return (from: from, to: to);
}

/// How many of [plannedDates] fall inside [range] — the honest number a
/// confirmation shows before the call (the calendar holds the displayed
/// month's rows, and a month-clear range never leaves that month).
int plannedDaysInRange(Iterable<DateTime> plannedDates, DateRange range) =>
    plannedDates.where((raw) {
      final d = dateOnly(raw);
      return !d.isBefore(range.from) && !d.isAfter(range.to);
    }).length;

/// What a range RPC answers. Every count is the SERVER's — the client never
/// derives one, because only the server saw which rows the trigger's rules
/// spared. [inserted] and [keptExisting] are zero on a plain clear.
class ScheduleRangeResult {
  /// Planned days deleted.
  final int deleted;

  /// Days kept because a request is pending on them (frozen — F-12).
  final int keptFrozen;

  /// Days kept because they hold an approved swap.
  final int keptSwap;

  /// Generated days written (replace only).
  final int inserted;

  /// Generated days NOT written because a row still stood on that date — the
  /// kept days above, or a day another member planted meanwhile (replace).
  final int keptExisting;

  /// F-51: the stamp every audit row of this call carries.
  final String? batchId;

  const ScheduleRangeResult({
    required this.deleted,
    required this.keptFrozen,
    required this.keptSwap,
    this.inserted = 0,
    this.keptExisting = 0,
    this.batchId,
  });

  /// The RPC's jsonb, as PostgREST decodes it. A missing count reads as 0 —
  /// the plain clear answers no `inserted`.
  factory ScheduleRangeResult.fromJson(Map<String, dynamic> json) {
    int count(String key) {
      final v = json[key];
      return v is num ? v.toInt() : 0;
    }

    final batch = json['batch_id'];
    return ScheduleRangeResult(
      deleted: count('deleted'),
      keptFrozen: count('kept_frozen'),
      keptSwap: count('kept_swap'),
      inserted: count('inserted'),
      keptExisting: count('kept_existing'),
      batchId: batch is String && batch.isNotEmpty ? batch : null,
    );
  }

  int get kept => keptFrozen + keptSwap;
}

/// The kept days, each with its reason, in the bulk summary's own shape
/// ("1 dia mantido (solicitação pendente)") — empty when nothing was kept.
List<String> rangeKeptParts(Localization l, ScheduleRangeResult r) => [
      if (r.keptFrozen > 0)
        bulkPluralize(l, r.keptFrozen, K.sumKeptFrozenOne, K.sumKeptFrozenMany),
      if (r.keptSwap > 0)
        bulkPluralize(l, r.keptSwap, K.sumKeptSwapOne, K.sumKeptSwapMany),
    ];

/// The month clear's toast: "5 dias apagados · 1 dia mantido (solicitação
/// pendente)", or the bulk summary's "nothing to do" when nothing moved and
/// nothing was kept.
String clearRangeSummary(Localization l, ScheduleRangeResult r) {
  final parts = [
    if (r.deleted > 0)
      bulkPluralize(l, r.deleted, K.sumDeletedOne, K.sumDeletedMany),
    ...rangeKeptParts(l, r),
  ];
  return parts.isNotEmpty ? parts.join(' · ') : l[K.sumNothingToDo];
}

/// The wizard's closing sentence when it replaced: the days created, the days
/// of the previous plan that went, and — only when there are any — the days
/// kept with their reason. The F-39 clamp note is the caller's, appended as
/// on the additive path.
String wizardReplaceSummary(Localization l, ScheduleRangeResult r) {
  var text = l.format(K.wizDoneCreated, [r.inserted]);
  if (r.deleted > 0) {
    text += bulkPluralize(
        l, r.deleted, K.wizDoneReplacedOne, K.wizDoneReplacedMany);
  }
  final kept = rangeKeptParts(l, r);
  if (kept.isNotEmpty) text += ' ${kept.join(' · ')}.';
  return text;
}
