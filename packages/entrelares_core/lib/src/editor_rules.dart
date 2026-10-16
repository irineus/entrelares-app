/// Client mirrors of the day editor's pure decision rules — ported from the
/// inline logic of `entrelares-app` `Entrelares/Pages/Home.razor`.
library;

import 'calendar_rules.dart' show MemberView;
import 'swap_rules.dart' show parseTimeOfDay;

/// F-28: who the current user may offer as the day's REAL responsible.
/// Anyone when they are the day's planned parent (scenario A); otherwise only
/// themselves (scenario B) — offering a third member would open a swap on
/// someone else's behalf (scenario C, forbidden; the service throws as the
/// backstop). The planned parent and the current actual stay listed so
/// no-swap and revert saves keep working. Mirror of `Home.CanOfferAsActual`.
bool canOfferAsActual({
  required int candidateId,
  required int? userProfileId,
  required int editingScheduledParentId,
  required int? existingActualParentId,
}) =>
    userProfileId == editingScheduledParentId ||
    candidateId == userProfileId ||
    candidateId == editingScheduledParentId ||
    candidateId == existingActualParentId;

/// F-56: whether the two-party workflow can exist on a day whose planned
/// parent is [scheduledParentId]. A PENDING member has nobody behind it to
/// approve, so the "real responsible" question is not asked on their days —
/// the sheet says why instead. The database refuses such a swap anyway
/// (`enforce_swap_counterpart`); this only keeps the sheet from offering it.
/// A departed planned parent still returns true: that day is a consult-only
/// ghost handled by the S-11 rules, not a workflow question.
bool swapAvailableForScheduled(
  int? scheduledParentId,
  List<MemberView> members,
) {
  if (scheduledParentId == null || scheduledParentId == 0) return true;
  for (final m in members) {
    if (m.id == scheduledParentId) return !m.isPendingMember;
  }
  return true;
}

/// S-09: rewriting the planned parent of an already-assigned day is
/// exceptional (admin mode only reaches here — the field is locked otherwise)
/// and requires an explicit confirmation before saving. Mirror of the guard
/// at the top of `Home.SaveChanges`.
bool needsAdminScheduleChangeConfirm({
  required int? existingScheduledParentId,
  required int editingScheduledParentId,
  required bool alreadyConfirmed,
}) =>
    existingScheduledParentId != null &&
    existingScheduledParentId != 0 &&
    editingScheduledParentId != existingScheduledParentId &&
    !alreadyConfirmed;

/// U-56: how a day tap opens the day sheet. U-25 opened every assigned day as
/// a read-only summary with the form one pencil away, and the owner watched
/// readers tap the pencil almost every time (23/09/2026) — so a day the
/// reader can change opens READY TO ACT again.
///
/// The wire value is the `mode` of `day-sheet-closed`.
enum DaySheetOpening {
  /// An empty day the reader can plan: the editor, nothing to summarize.
  plan('plan'),

  /// An assigned day, today or ahead, the reader can change: the editor.
  edit('edit'),

  /// Everything else: the summary. A day nothing can be saved on (past
  /// without the admin mode, frozen, offline) has no form to reach; and a
  /// PAST day stays a summary even under the admin mode, because there the
  /// primary is the relato (F-67 — the plan is immutable, what happened is
  /// appended) and the correction is the secondary, behind the pencil.
  view('view');

  const DaySheetOpening(this.wire);
  final String wire;

  bool get opensEditor => this != view;
}

DaySheetOpening daySheetOpening({
  required bool canSave,
  required bool isEmptyDay,
  required bool isPast,
}) {
  if (!canSave) return DaySheetOpening.view;
  if (isEmptyDay) return DaySheetOpening.plan;
  return isPast ? DaySheetOpening.view : DaySheetOpening.edit;
}

/// U-56: how the day sheet ended — the `outcome` of `day-sheet-closed`.
/// [none] is a sheet closed with nothing written: the number that says
/// whether opening in the editor was the right default.
enum DaySheetResult {
  saved('saved'),
  cleared('cleared'),
  swap('swap'),
  revert('revert'),
  report('report'),
  none('none');

  const DaySheetResult(this.wire);
  final String wire;
}

/// U-56: whether the editor's draft differs from the stored day — "Salvar"
/// lights only then. A day sheet now opens in the editor, and a reflex
/// "Salvar" on an untouched day would still write: `care_schedules` has no
/// no-op guard, so the audit trigger records an UPDATE that changed nothing
/// and the Histórico gains an empty entry.
///
/// Both sides are normalized the way the save writes them: a planned or real
/// parent of 0 is "none" / "same as planned", the note is trimmed, and the
/// time is compared as hour and minute (the wire carries seconds).
bool dayDraftChanged({
  required int? storedScheduledParentId,
  required int? storedActualParentId,
  required String? storedNotes,
  required String? storedHandoffTime,
  required int? draftScheduledParentId,
  required int? draftActualParentId,
  required String draftNotes,
  required ({int hour, int minute})? draftHandoff,
}) {
  int? id(int? v) => (v == null || v == 0) ? null : v;
  if (id(storedScheduledParentId) != id(draftScheduledParentId)) return true;
  if (id(storedActualParentId) != id(draftActualParentId)) return true;
  if ((storedNotes ?? '').trim() != draftNotes.trim()) return true;
  final stored = parseTimeOfDay(storedHandoffTime);
  return stored?.hour != draftHandoff?.hour ||
      stored?.minute != draftHandoff?.minute;
}

/// F-99 (owner, 05/10/2026) — the client half of `enforce_handoff_party`: a
/// day's handoff time is changed by its two ends (the day's planned or real
/// carer, and the previous day's effective carer) or by an admin. A hint for
/// the UI only; the database refuses everyone else.
bool mayChangeHandoff({
  required int? me,
  required bool isAdmin,
  required int? scheduledParentId,
  required int? actualParentId,
  required int? previousEffectiveParentId,
}) {
  if (isAdmin) return true;
  if (me == null) return false;
  return me == scheduledParentId ||
      me == actualParentId ||
      me == previousEffectiveParentId;
}

/// Owner's QA of 3.1.10 (06/10/2026) — who "Pedir para outra pessoa ficar com
/// este dia" pre-selects. With two carers it is obvious; with three or more the
/// first of the roster read as a guess. In order:
///
/// 1. the day is the father's and the mother can take it, or the other way
///    round — they swap between themselves (built-in roles only, by their
///    canonical name; step-parents follow rule 2, there is no kinship guess);
/// 2. whoever has the child the day before or the day after (same lane) — the
///    other side of the routine at that point;
/// 3. a tie, or nobody around: the one with more days this month; still tied,
///    the roster order of [candidates].
///
/// [candidates] are the carers who may take the day (F-28's filter), already
/// without the day's planned one. [canonicalRoleOf] answers a built-in role's
/// canonical name (`father`, `mother`, …) or null. A pre-selection only — the
/// asker can pick any other chip.
int? suggestSwapCandidate({
  required int scheduledParentId,
  required List<int> candidates,
  required String? Function(int profileId) canonicalRoleOf,
  int? previousCarerId,
  int? nextCarerId,
  Map<int, int> daysInMonth = const {},
}) {
  if (candidates.isEmpty) return null;
  final partner = const {'father': 'mother', 'mother': 'father'}[
      canonicalRoleOf(scheduledParentId)];
  if (partner != null) {
    for (final c in candidates) {
      if (canonicalRoleOf(c) == partner) return c;
    }
  }
  final around = [
    for (final c in candidates)
      if (c == previousCarerId || c == nextCarerId) c
  ];
  final pool = around.isNotEmpty ? around : candidates;
  var best = pool.first;
  for (final c in pool.skip(1)) {
    if ((daysInMonth[c] ?? 0) > (daysInMonth[best] ?? 0)) best = c;
  }
  return best;
}
