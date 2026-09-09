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

  const AuditLogView({
    required this.id,
    required this.affectedDate,
    required this.createdAtLocal,
    required this.action,
    this.oldData,
    this.newData,
    this.performedById,
  });
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

/// The icon the account timeline puts on a row — mirror of the badge switch
/// in `ReportsAudit.razor`.
(AuditBadge, String) accountActionBadge(String action) => switch (action) {
      'invitation_created' ||
      'pending_member_added' ||
      'pending_member_claimed' =>
        (AuditBadge.created, '＋'),
      'invitation_revoked' ||
      'pending_member_removed' =>
        (AuditBadge.deleted, '✕'),
      'admin_granted' || 'admin_revoked' => (AuditBadge.updated, '🛡️'),
      'password_changed' ||
      'email_change_requested' =>
        (AuditBadge.updated, '🔐'),
      'data_exported' => (AuditBadge.updated, '📦'),
      'comp_premium_granted' => (AuditBadge.created, '🎁'),
      'comp_premium_revoked' => (AuditBadge.deleted, '🎁'),
      'plan_premium_payment' ||
      'plan_premium_avulso' ||
      'plan_premium_set' =>
        (AuditBadge.created, '💳'),
      'plan_free_overdue' ||
      'plan_free_canceled' ||
      'plan_free_set' =>
        (AuditBadge.deleted, '💳'),
      _ => (AuditBadge.updated, '✏️'),
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
