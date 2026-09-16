/// Client mirrors of the audit trail — ported from `entrelares-app`
/// `Entrelares/Services/AuditService.cs` (ComputeDiff, ResolutionOriginText,
/// AccountActionLabel) and the vocabulary `ReportsAudit.razor` renders around
/// them.
///
/// The rows themselves are written ONLY by DB triggers and definer RPCs — the
/// client has family-scoped SELECT and nothing else. Everything here is
/// presentation of an immutable record: which fields changed, who caused the
/// change, and (F-45) which swap request produced it.
library;

import 'calendar_rules.dart' show MemberView;
import 'localization/k.dart';
import 'localization/k_app.dart';
import 'localization/localization.dart';

/// Page size of the incremental timeline ("Carregar mais"), mirroring
/// `AuditService.PageSize`. The client asks for exactly this many rows and
/// treats a FULL page as "there may be more" — same heuristic as the web.
const int auditPageSize = 20;

/// The slice of an `activity_logs` row these rules need. The app package maps
/// its Supabase row onto this (same pattern as [DayAssignment]/[MemberView]).
class AuditLogView {
  final int id;

  /// The calendar day the change affected (date-only).
  final DateTime affectedDate;

  /// `created_at` already converted to LOCAL time — the timeline and the F-33
  /// report both show device-local time, and the report footer says so.
  final DateTime createdAtLocal;

  /// Trigger vocabulary on `care_schedules`: INSERT / UPDATE / DELETE.
  final String action;

  /// The row snapshots as decoded jsonb (null when the trigger stored none).
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;

  final int? performedById;

  /// F-61: the facts stamped at write time. Null before F-61 — unknown.
  final AuditContext? context;

  const AuditLogView({
    required this.id,
    required this.affectedDate,
    required this.createdAtLocal,
    required this.action,
    this.oldData,
    this.newData,
    this.performedById,
    this.context,
  });
}

/// F-61 — what `audit_care_schedule_changes` stamps in `activity_logs.context`
/// at the instant of the write. Every field is a recorded FACT, never an
/// inference made here: whether the assigned parents had an account, whether
/// the actor was an admin, and whether the write went through only on the
/// admin's authority (a DELETE, or a planned/real-parent UPDATE, by an admin
/// who was not the target of a pending request on that day).
///
/// A missing key is `null` — the trigger strips unknowns (a system write has
/// no actor), and rows older than F-61 have no context at all. The renderer
/// says nothing for `null`: "unknown" and "no" are different answers on a
/// record.
///
/// F-51: a row written by a range operation (`clear_schedule_range` /
/// `replace_schedule_range`) also carries the batch it belongs to — the same
/// [batchId] on every row of one call, and a [batchKind] naming the operation
/// (`clear_range` / `replace_range`). A single-day write carries neither, so
/// the history can fold a batch into one entry without ever folding a lone
/// edit.
class AuditContext {
  final bool? scheduledParentHasAccount;
  final bool? actualParentHasAccount;
  final bool? actorIsAdmin;
  final bool? adminOverride;
  final String? batchId;
  final String? batchKind;

  const AuditContext({
    this.scheduledParentHasAccount,
    this.actualParentHasAccount,
    this.actorIsAdmin,
    this.adminOverride,
    this.batchId,
    this.batchKind,
  });

  /// [raw] as PostgREST hands it over — a decoded JSON object, or null.
  /// Anything that is not an object (or a boolean inside it) reads as unknown.
  static AuditContext? parse(Object? raw) {
    if (raw is! Map) return null;
    bool? flag(String key) {
      final value = raw[key];
      return value is bool ? value : null;
    }

    String? text(String key) {
      final value = raw[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return AuditContext(
      scheduledParentHasAccount: flag('scheduled_parent_has_account'),
      actualParentHasAccount: flag('actual_parent_has_account'),
      actorIsAdmin: flag('actor_is_admin'),
      adminOverride: flag('admin_override'),
      batchId: text('batch_id'),
      batchKind: text('batch_kind'),
    );
  }
}

/// F-61 — the dated facts a trail line carries beyond its diff, in the
/// reader's language, one sentence each:
///
///   · a parent the day names who had NO account at that instant (the planned
///     one, the real one, or both — the same person is named once);
///   · the write being the admin's direct change (S-09 / F-14 / a clear).
///
/// Neutral by construction: each sentence names a person and a state with the
/// row's own timestamp next to it; none qualifies anyone's conduct. Shared by
/// the Histórico timeline and the F-33 document so the two cannot drift.
/// A log without context (older than F-61) yields nothing.
List<String> authorshipLines({
  required AuditLogView log,
  required List<MemberView> profiles,
  required Localization l,
}) {
  final ctx = log.context;
  if (ctx == null) return const [];

  // The day as recorded: the new row, or — for a DELETE — the one that went.
  final row = log.newData ?? log.oldData;
  final withoutAccount = <String>[];
  void nameIf(bool? hasAccount, String key) {
    if (hasAccount != false) return;
    final idText = _snapshotString(row, key);
    if (idText == null) return;
    final name = _resolveParent(idText, profiles);
    if (!withoutAccount.contains(name)) withoutAccount.add(name);
  }

  nameIf(ctx.scheduledParentHasAccount, 'scheduled_parent_id');
  nameIf(ctx.actualParentHasAccount, 'actual_parent_id');

  return [
    for (final name in withoutAccount)
      l.format(K.auditAuthorshipNoAccount, [name]),
    if (ctx.adminOverride == true)
      l.format(K.auditAuthorshipAdminOverride, [
        _nameOf(profiles, log.performedById) ?? l[K.auditOriginSomeCaregiver],
      ]),
  ];
}

/// The slice of a `swap_requests` row the F-45 origin sentence needs. Kept
/// apart from [SwapRequestView] on purpose: the workflow rules care about the
/// date and the priority clock, the audit trail cares about who asked, who
/// answered and what they wrote.
class SwapOrigin {
  final int requestingProfileId;
  final int targetProfileId;

  /// `approved` / `revert_approved` — the revert flavor changes the sentence.
  final String status;

  /// 'user' or 'system' (F-24 auto-approval).
  final String? resolvedBy;

  /// F-44 free texts, already normalized on the way in.
  final String? requestMessage;
  final String? approvalNote;

  const SwapOrigin({
    required this.requestingProfileId,
    required this.targetProfileId,
    required this.status,
    this.resolvedBy,
    this.requestMessage,
    this.approvalNote,
  });
}

/// One field-level difference between two snapshots (F-02). Mirrors
/// `Entrelares/Models/AuditFieldChange.cs`: a null [from] reads as "set", a
/// null [to] as "cleared".
class AuditFieldChange {
  final String label;
  final String? from;
  final String? to;

  const AuditFieldChange(this.label, this.from, this.to);
}

/// Mirror of `AuditService.ComputeDiff` — the four fields the calendar day
/// carries, in the web's order. Values are resolved for a reader: parent ids
/// become names, `handoff_time` loses its seconds, an empty note reads "—".
List<AuditFieldChange> computeAuditDiff({
  required AuditLogView log,
  required List<MemberView> profiles,
  required Localization l,
}) {
  final changes = <AuditFieldChange>[];

  _diffParent(l[K.auditFieldScheduledParent], 'scheduled_parent_id', log,
      profiles, changes);
  _diffParent(
      l[K.auditFieldActualParent], 'actual_parent_id', log, profiles, changes);
  _diffField(l[K.auditFieldHandoffTime], 'handoff_time', log, changes,
      formatAuditTime);
  _diffField(l[K.auditFieldDayNote], 'notes', log, changes,
      (v) => v.isEmpty ? '—' : v);

  return changes;
}

void _diffField(
  String label,
  String key,
  AuditLogView log,
  List<AuditFieldChange> changes,
  String Function(String) format,
) {
  final oldVal = _snapshotString(log.oldData, key);
  final newVal = _snapshotString(log.newData, key);
  if (oldVal == newVal) return;

  changes.add(AuditFieldChange(
    label,
    oldVal == null ? null : format(oldVal),
    newVal == null ? null : format(newVal),
  ));
}

void _diffParent(
  String label,
  String key,
  AuditLogView log,
  List<MemberView> profiles,
  List<AuditFieldChange> changes,
) {
  final oldVal = _snapshotString(log.oldData, key);
  final newVal = _snapshotString(log.newData, key);
  if (oldVal == newVal) return;

  changes.add(AuditFieldChange(
    label,
    oldVal == null ? null : _resolveParent(oldVal, profiles),
    newVal == null ? null : _resolveParent(newVal, profiles),
  ));
}

/// A missing key and a JSON null are the SAME thing here — mirrors the C#
/// `GetString`, where both paths return null and therefore compare equal.
String? _snapshotString(Map<String, dynamic>? snapshot, String key) {
  if (snapshot == null) return null;
  final value = snapshot[key];
  if (value == null) return null;
  return value.toString();
}

/// An unknown id renders as the raw value: the audit log is a record, and
/// showing what was stored is truthful where inventing a name is not.
String _resolveParent(String idText, List<MemberView> profiles) {
  final id = int.tryParse(idText);
  if (id != null) {
    for (final p in profiles) {
      if (p.id == id) return p.fullName;
    }
  }
  return idText;
}

/// `handoff_time` on the wire is `HH:mm[:ss]`; the trail shows `HH:mm`.
/// Anything unparseable passes through untouched (same fallback as C#).
String formatAuditTime(String raw) {
  final parts = raw.split(':');
  if (parts.length < 2) return raw;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return raw;
  return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
}

/// The calendar-change action, in the reader's language — the timeline's
/// phrasing (`ReportsAudit.razor`).
String scheduleActionLabel(String action, Localization l) => switch (action) {
      'INSERT' => l[K.auditCreatedSchedule],
      'DELETE' => l[K.auditDeletedSchedule],
      _ => l[K.auditUpdatedSchedule],
    };

/// The same action phrased as a neutral third-person statement for the F-33
/// document (`ReportPdfService.ActionLabel`).
String reportActionLabel(String action, Localization l) => switch (action) {
      'INSERT' => l[K.pdfDocActionInsert],
      'DELETE' => l[K.pdfDocActionDelete],
      _ => l[K.pdfDocActionUpdate],
    };

/// How a timeline row is badged. The web computes this inline in the markup;
/// extracting it keeps the two timelines (calendar and account) from drifting.
enum AuditBadge { created, deleted, updated }

AuditBadge scheduleActionBadge(String action) => switch (action) {
      'INSERT' => AuditBadge.created,
      'DELETE' => AuditBadge.deleted,
      _ => AuditBadge.updated,
    };

/// F-45 — the origin sentence for a calendar change produced by a swap
/// workflow. Shared by the Histórico timeline and the F-33 report so the two
/// phrasings cannot drift; branches on revert vs. swap and on manual vs.
/// automatic (`resolved_by = 'system'`) resolution.
///
/// U-13: the four combinations are FOUR whole catalog entries rather than a
/// sentence assembled from fragments — Portuguese agrees the participle with
/// the noun it follows ("da troca solicitada … e aprovada"), so the pieces are
/// not independent.
String resolutionOriginText(
  SwapOrigin origin,
  List<MemberView> profiles,
  Localization l,
) {
  final requester = _nameOf(profiles, origin.requestingProfileId) ??
      l[K.auditOriginSomeCaregiver];
  final approver = _nameOf(profiles, origin.targetProfileId) ??
      l[K.auditOriginOtherCaregiver];
  final isRevert = origin.status == 'revert_approved';
  final isAuto = origin.resolvedBy == 'system';

  if (isRevert && isAuto) return l.format(K.auditOriginRevertAuto, [requester]);
  if (isRevert) return l.format(K.auditOriginRevertManual, [requester, approver]);
  if (isAuto) return l.format(K.auditOriginSwapAuto, [requester]);
  return l.format(K.auditOriginSwapManual, [requester, approver]);
}

String? _nameOf(List<MemberView> profiles, int? id) {
  if (id == null) return null;
  for (final p in profiles) {
    if (p.id == id) return p.fullName;
  }
  return null;
}

/// S-10 — the account-operation label in the reader's language. An UNKNOWN
/// action falls through to its RAW key on purpose: the audit log is a record,
/// and showing the stored value is truthful where inventing a label is not.
String accountActionLabel(String action, Localization l) {
  final key = switch (action) {
    'admin_granted' => K.auditActionAdminGranted,
    'admin_revoked' => K.auditActionAdminRevoked,
    'role_changed' => K.auditActionRoleChanged,
    'name_changed' => K.auditActionNameChanged,
    'email_changed' => K.auditActionEmailChanged,
    'family_renamed' => K.auditActionFamilyRenamed,
    'invitation_created' => K.auditActionInvitationCreated,
    'invitation_revoked' => K.auditActionInvitationRevoked,
    'invitation_accepted' => K.auditActionInvitationAccepted,
    'comp_premium_granted' => K.auditActionCompGranted,
    'comp_premium_revoked' => K.auditActionCompRevoked,
    'plan_premium_payment' => K.auditActionPlanPremiumPayment,
    'plan_premium_avulso' => K.auditActionPlanPremiumAvulso,
    'plan_premium_set' => K.auditActionPlanPremiumSet,
    'plan_free_overdue' => K.auditActionPlanFreeOverdue,
    'plan_free_canceled' => K.auditActionPlanFreeCanceled,
    'plan_free_set' => K.auditActionPlanFreeSet,
    'account_deletion_requested' => K.auditActionLeaveRequested,
    'account_deletion_cancelled' => K.auditActionLeaveCancelled,
    'password_changed' => K.auditActionPasswordChanged,
    'email_change_requested' => K.auditActionEmailChangeRequested,
    'data_exported' => K.auditActionDataExported,
    // F-56: the pending member's three moments.
    'pending_member_added' => KApp.auditActionPendingAdded,
    'pending_member_removed' => KApp.auditActionPendingRemoved,
    'pending_member_claimed' => KApp.auditActionPendingClaimed,
    _ => null,
  };
  return key == null ? action : l[key];
}

/// What the account timeline's dot SAYS about a row — a meaning, never a
/// glyph: core cannot name a Flutter icon, and U-31 took out the emoji that
/// used to stand here. The app maps each value to its vector icon.
enum AuditMarker {
  added,
  removed,
  admin,
  credentials,
  export,
  gift,
  billing,
  edited,
}

/// The tone and the marker of an account timeline row — mirror of the badge
/// switch in `ReportsAudit.razor`.
(AuditBadge, AuditMarker) accountActionBadge(String action) => switch (action) {
      'invitation_created' ||
      'pending_member_added' ||
      'pending_member_claimed' =>
        (AuditBadge.created, AuditMarker.added),
      'invitation_revoked' ||
      'pending_member_removed' =>
        (AuditBadge.deleted, AuditMarker.removed),
      'admin_granted' || 'admin_revoked' => (AuditBadge.updated, AuditMarker.admin),
      'password_changed' ||
      'email_change_requested' =>
        (AuditBadge.updated, AuditMarker.credentials),
      'data_exported' => (AuditBadge.updated, AuditMarker.export),
      'comp_premium_granted' => (AuditBadge.created, AuditMarker.gift),
      'comp_premium_revoked' => (AuditBadge.deleted, AuditMarker.gift),
      'plan_premium_payment' ||
      'plan_premium_avulso' ||
      'plan_premium_set' =>
        (AuditBadge.created, AuditMarker.billing),
      'plan_free_overdue' ||
      'plan_free_canceled' ||
      'plan_free_set' =>
        (AuditBadge.deleted, AuditMarker.billing),
      _ => (AuditBadge.updated, AuditMarker.edited),
    };

/// A `role_changed` row stores ROLE NAMES; the timeline translates them like
/// every other role label. Every other action's values pass through as stored.
String? accountLogValueDisplay(
  String action,
  String? value,
  String Function(String roleName) translateRole,
) {
  if (value == null) return null;
  return action == 'role_changed' ? translateRole(value) : value;
}

/// F-58 QA 2 — a trial that simply RAN OUT leaves no row anywhere: the family
/// keeps `trial_ends_at` (only plan transitions clear it), so the timeline
/// computes the entry from the fact itself. Never shown while the family is
/// premium or comped — there was no lived "loss" to narrate.
///
/// Returns the UTC instant the trial ended, or null when there is no entry.
DateTime? trialEndedEntry({
  required String? plan,
  required DateTime? trialEndsAtUtc,
  required DateTime? compPremiumAtUtc,
  required DateTime nowUtc,
}) {
  if (plan != null && plan.toLowerCase() == 'premium') return null;
  if (compPremiumAtUtc != null) return null;
  if (trialEndsAtUtc == null) return null;
  return trialEndsAtUtc.isAfter(nowUtc) ? null : trialEndsAtUtc;
}

// ── F-51: a range operation is ONE entry of the timeline ────────────────────

/// The rows one range call (`clear_schedule_range` / `replace_schedule_range`)
/// wrote, folded into one timeline entry. The rows stay in the record exactly
/// as written — one per day, trigger-written, append-only; only the
/// RENDERING folds them, because a year's re-plan is ~730 rows and a screen
/// that shows them one by one stops being readable at the first real use.
class AuditBatch {
  final String batchId;

  /// `clear_range` / `replace_range`, as the RPC stamped it.
  final String? kind;

  /// The rows, in the order the timeline holds them (newest first).
  final List<AuditLogView> logs;

  const AuditBatch({
    required this.batchId,
    required this.kind,
    required this.logs,
  });

  bool get isReplace => kind == 'replace_range';

  int get deleted => logs.where((l) => l.action == 'DELETE').length;
  int get created => logs.where((l) => l.action == 'INSERT').length;

  /// The T-45 cascade on the day after the range rides the same transaction,
  /// so a batch can carry an UPDATE row too.
  int get updated => logs.where((l) => l.action == 'UPDATE').length;

  DateTime get firstDate =>
      logs.map((l) => l.affectedDate).reduce((a, b) => a.isBefore(b) ? a : b);
  DateTime get lastDate =>
      logs.map((l) => l.affectedDate).reduce((a, b) => a.isAfter(b) ? a : b);

  /// The batch happened at one instant; the newest row's stamp stands for it.
  DateTime get createdAtLocal =>
      logs.map((l) => l.createdAtLocal).reduce((a, b) => a.isAfter(b) ? a : b);

  int? get performedById => logs.first.performedById;
}

/// One item of the folded timeline: a lone row, or a whole batch.
sealed class AuditEntry {
  const AuditEntry();
}

class AuditSingleEntry extends AuditEntry {
  final AuditLogView log;
  const AuditSingleEntry(this.log);
}

class AuditBatchEntry extends AuditEntry {
  final AuditBatch batch;
  const AuditBatchEntry(this.batch);
}

/// Folds CONSECUTIVE rows that share a `context.batch_id` into one
/// [AuditBatchEntry]; every other row stays an [AuditSingleEntry]. Consecutive
/// on purpose: a batch is written in one transaction, so its rows are
/// adjacent in a `created_at` order, and two batches over the same range
/// (a plan replaced twice) must stay two entries. A row without a stamp is
/// never folded — a single-day edit is not a batch of one.
List<AuditEntry> groupAuditBatches(List<AuditLogView> logs) {
  final entries = <AuditEntry>[];
  var i = 0;
  while (i < logs.length) {
    final id = logs[i].context?.batchId;
    if (id == null) {
      entries.add(AuditSingleEntry(logs[i]));
      i++;
      continue;
    }
    var j = i;
    while (j < logs.length && logs[j].context?.batchId == id) {
      j++;
    }
    entries.add(AuditBatchEntry(AuditBatch(
      batchId: id,
      kind: logs[i].context?.batchKind,
      logs: logs.sublist(i, j),
    )));
    i = j;
  }
  return entries;
}

/// The batch's counts, in the bulk summary's shape: "88 dias apagados · 90
/// dias planejados · 1 dia atualizado".
String auditBatchCounts(AuditBatch batch, Localization l) {
  final parts = <String>[
    if (batch.deleted > 0)
      l.format(batch.deleted == 1 ? K.sumDeletedOne : K.sumDeletedMany,
          [batch.deleted]),
    if (batch.created > 0)
      l.format(
          batch.created == 1
              ? K.auditBatchCreatedOne
              : K.auditBatchCreatedMany,
          [batch.created]),
    if (batch.updated > 0)
      l.format(batch.updated == 1 ? K.sumUpdatedOne : K.sumUpdatedMany,
          [batch.updated]),
  ];
  return parts.join(' · ');
}
