/// Client mirrors of the bulk-edit rules — ported from `entrelares-app`
/// `Entrelares/Helpers/BulkSummary.cs` plus the pure decision rules inline in
/// `Home.razor` (`OpenBulkSheet` pre-fill, `SaveBulkChanges` eligibility/
/// skip/no-op, the S-09 kept-planned-parent rule). Two Phase 4 QA bugs lived
/// exactly in what the summary claimed versus what the save actually did —
/// that is why every rule here is pure and tested.
///
/// The workflow branches of `SaveBulkChanges` (days routed to a swap request
/// or a revert request) belong to lote 3 — their predicates live in the web's
/// `SwapRequestService` and port with it; the routing seam here stays
/// direct-write only until then.
library;

import 'localization/k.dart';
import 'localization/localization.dart';

// ── BulkSummary (F-11/S-09/T-27) ─────────────────────────────────────────────

/// Builds the "X atualizados · Y solicitações de troca · Z ignorados" summary,
/// omitting any part whose count is zero. [directSingularKey]/[directPluralKey]
/// carry the caller's own "direct change" wording — it differs per call site
/// (updated / deleted). Mirror of `BulkSummary.Build`, same part order.
String bulkSummary(
  Localization l, {
  required int directCount,
  required String directSingularKey,
  required String directPluralKey,
  int swapCount = 0,
  int revertCount = 0,
  int skippedCount = 0,
  int unchangedCount = 0,
}) {
  final parts = <String>[];
  if (directCount > 0) {
    parts.add(bulkPluralize(l, directCount, directSingularKey, directPluralKey));
  }
  if (swapCount > 0) {
    parts.add(
        bulkPluralize(l, swapCount, K.sumSwapRequestOne, K.sumSwapRequestMany));
  }
  if (revertCount > 0) {
    parts.add(bulkPluralize(l, revertCount, K.sumRevertOne, K.sumRevertMany));
  }
  if (unchangedCount > 0) {
    parts.add(
        bulkPluralize(l, unchangedCount, K.sumUnchangedOne, K.sumUnchangedMany));
  }
  if (skippedCount > 0) {
    parts.add(bulkPluralize(l, skippedCount, K.sumSkippedOne, K.sumSkippedMany));
  }
  return parts.isNotEmpty ? parts.join(' · ') : l[K.sumNothingToDo];
}

/// Picks the singular or plural entry and substitutes the count. The number is
/// INSIDE the catalogue text (`"{0} dias ignorados"`) rather than prefixed
/// here, so a language that puts it elsewhere — or drops it — stays
/// expressible. U-13: PT-BR agrees the participle in gender AND number, which
/// is why the catalogue holds two whole phrases per count.
String bulkPluralize(
        Localization l, int count, String singularKey, String pluralKey) =>
    l.format(count == 1 ? singularKey : pluralKey, [count]);

// ── The editable slice of a day the bulk rules read ──────────────────────────

/// A handoff time as the editor holds it (the wire format `HH:mm:ss` is the
/// app package's concern — U-24 keeps ISO on the wire).
typedef HandoffTime = ({int hour, int minute});

/// The editable fields of an existing `care_schedules` row, as the bulk rules
/// need them. `scheduledParentId == 0` mirrors the web's "unassigned" sentinel.
class BulkDayFields {
  final int scheduledParentId;
  final int? actualParentId;
  final String? notes;
  final HandoffTime? handoffTime;

  const BulkDayFields({
    required this.scheduledParentId,
    this.actualParentId,
    this.notes,
    this.handoffTime,
  });
}

/// U-11: bulk selection is active while days are selected or the selection was
/// explicitly armed (the keyboard/mouse-accessible entry point).
bool isSelectionMode({required int selectedCount, required bool armed}) =>
    selectedCount > 0 || armed;

// ── OpenBulkSheet pre-fill: common value or the field's "mixed" sentinel ─────

/// What the bulk sheet opens with. Sentinels mirror the web's: 0 for parents,
/// null for notes, hour −1 for "no common handoff".
class BulkPrefill {
  final int scheduledParentId;
  final int actualParentId;
  final String? notes;
  final int handoffHour;
  final int handoffMinute;

  const BulkPrefill({
    required this.scheduledParentId,
    required this.actualParentId,
    required this.notes,
    required this.handoffHour,
    required this.handoffMinute,
  });
}

/// Mirror of `OpenBulkSheet`: each field pre-fills with the value ALL selected
/// existing rows share, or its "mixed" sentinel. [selected] holds only the
/// rows that exist — selected days with no row contribute nothing, exactly as
/// the web's join against `monthlySchedules`.
BulkPrefill bulkPrefill(List<BulkDayFields> selected) {
  final scheduled = selected.map((s) => s.scheduledParentId).toSet();
  final actual = selected.map((s) => s.actualParentId ?? 0).toSet();
  final notes = selected.map((s) => s.notes).toSet();
  final hours = selected.map((s) => s.handoffTime?.hour ?? -1).toSet();
  final minutes = selected.map((s) => s.handoffTime?.minute ?? 0).toSet();
  final commonHandoff = hours.length == 1 && minutes.length == 1;
  return BulkPrefill(
    scheduledParentId: scheduled.length == 1 ? scheduled.first : 0,
    actualParentId: actual.length == 1 ? actual.first : 0,
    notes: notes.length == 1 ? notes.first : null,
    handoffHour: commonHandoff ? hours.first : -1,
    handoffMinute: commonHandoff ? minutes.first : 0,
  );
}

// ── SaveBulkChanges: eligibility and skip counting ───────────────────────────

/// Mirror of the eligibility pass at the top of `SaveBulkChanges`:
/// F-13 drops past days (except admin bypass — F-14), F-12 drops frozen days,
/// and when [clearScheduledParent] is on, days holding an approved swap are
/// also dropped (deleting the row would erase the swap). Every drop counts as
/// skipped — the summary reports them, never silently.
({List<DateTime> eligible, int skipped}) bulkEligibleDays({
  required Iterable<DateTime> selectedDates,
  required DateTime today,
  required bool adminBypass,
  required Iterable<DateTime> frozenDates,
  required BulkDayFields? Function(DateTime) existingFor,
  required bool clearScheduledParent,
}) {
  final t = DateTime(today.year, today.month, today.day);
  final frozen = {
    for (final f in frozenDates) DateTime(f.year, f.month, f.day)
  };
  final eligible = <DateTime>[];
  var skipped = 0;
  for (final raw in selectedDates) {
    final date = DateTime(raw.year, raw.month, raw.day);
    if (!adminBypass && date.isBefore(t)) {
      skipped++;
      continue;
    }
    if (frozen.contains(date)) {
      skipped++;
      continue;
    }
    final existing = existingFor(date);
    if (clearScheduledParent &&
        existing != null &&
        existing.actualParentId != null &&
        existing.actualParentId != existing.scheduledParentId) {
      skipped++;
      continue;
    }
    eligible.add(date);
  }
  return (eligible: eligible, skipped: skipped);
}

// ── S-09: the planned parent a day actually carries after the bulk edit ──────

/// Regular users keep the existing value on assigned days (the bulk choice
/// applies only to unassigned days); admin mode (confirmed) overwrites.
/// Mirror of the local `DayScheduled` in `SaveBulkChanges`.
int bulkDayScheduled({
  required bool overwriteScheduled,
  required BulkDayFields? existing,
  required int bulkScheduledParentId,
}) =>
    !overwriteScheduled && existing != null && existing.scheduledParentId != 0
        ? existing.scheduledParentId
        : bulkScheduledParentId;

/// S-09: assigned days whose planned parent the bulk choice would REWRITE —
/// admin mode asks for explicit confirmation when this is > 0. Mirror of
/// `overwriteCount` in `SaveBulkChanges`.
int bulkOverwriteCount({
  required Iterable<DateTime> days,
  required BulkDayFields? Function(DateTime) existingFor,
  required int bulkScheduledParentId,
}) =>
    days.where((d) {
      final existing = existingFor(d);
      return existing != null &&
          existing.scheduledParentId != 0 &&
          existing.scheduledParentId != bulkScheduledParentId;
    }).length;

// ── Field application: what the bulk edit proposes for one day ───────────────

/// The actual parent this bulk edit would end up applying to the day: a picked
/// parent wins, "Limpar" clears, otherwise the existing value stays.
int? bulkProposedActual({
  required int bulkActualParentId,
  required bool clearActual,
  required int? existingActualParentId,
}) =>
    bulkActualParentId != 0
        ? bulkActualParentId
        : clearActual
            ? null
            : existingActualParentId;

/// The handoff time to carry into the save — same precedence as
/// [bulkProposedActual] (hour −1 = "not set in the sheet"). T-27's
/// transition-only rule applies AFTER this, at the call site that knows the
/// previous day's effective parent.
HandoffTime? bulkProposedHandoff({
  required int bulkHour,
  required int bulkMinute,
  required bool clearHandoff,
  required HandoffTime? existing,
}) =>
    bulkHour >= 0
        ? (hour: bulkHour, minute: bulkMinute)
        : clearHandoff
            ? null
            : existing;

/// Mirror of the Case-3 assembly in `SaveBulkChanges`: the day's final fields
/// after applying every sheet input. [proposedHandoff] arrives already
/// transition-filtered (null on non-transition days — T-27); it only lands
/// when the sheet set an hour, mirroring the web's `bulkSwapHour >= 0` branch.
BulkDayFields bulkComposeDay({
  required BulkDayFields? existing,
  required int dayScheduled,
  required int bulkActualParentId,
  required bool clearActual,
  required String? bulkNotes,
  required bool clearNotes,
  required int bulkHour,
  required bool clearHandoff,
  required HandoffTime? proposedHandoff,
}) {
  final actual = bulkActualParentId != 0
      ? bulkActualParentId
      : clearActual
          ? null
          : existing?.actualParentId;
  final notes = (bulkNotes != null && bulkNotes.isNotEmpty)
      ? bulkNotes
      : clearNotes
          ? null
          : existing?.notes;
  final handoff = bulkHour >= 0
      ? proposedHandoff
      : clearHandoff
          ? null
          : existing?.handoffTime;
  return BulkDayFields(
    scheduledParentId: dayScheduled,
    actualParentId: actual,
    notes: notes,
    handoffTime: handoff,
  );
}

/// A day whose final state equals the current one is a no-op: skip the API
/// call and don't report it as updated (the S-09 regression the summary tests
/// pin). Mirror of the field-by-field comparison in `SaveBulkChanges`.
bool bulkDayIsNoOp(BulkDayFields existing, BulkDayFields proposed) =>
    proposed.scheduledParentId == existing.scheduledParentId &&
    proposed.actualParentId == existing.actualParentId &&
    proposed.notes == existing.notes &&
    proposed.handoffTime == existing.handoffTime;

/// F-100 (T-103 audit) — a holiday or a school vacation is edited as ONE
/// range: press the first day, tap the last. Every day from [a] to [b]
/// (either order), inclusive, never past the planning horizon [horizon]
/// (F-39 — beyond it no day can be written, so none is selected).
List<DateTime> selectionRange(DateTime a, DateTime b, {DateTime? horizon}) {
  var from = DateTime(a.year, a.month, a.day);
  var to = DateTime(b.year, b.month, b.day);
  if (to.isBefore(from)) (from, to) = (to, from);
  if (horizon != null) {
    final cap = DateTime(horizon.year, horizon.month, horizon.day);
    if (to.isAfter(cap)) to = cap;
  }
  return [
    for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1))
      d,
  ];
}
