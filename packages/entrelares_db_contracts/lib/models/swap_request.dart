import 'package:entrelares_core/entrelares_core.dart';

/// The `swap_requests` row. Mirrors `Entrelares/Models/SwapRequest.cs` —
/// `family_id` stays off the client model on purpose (RLS scopes it, the
/// trigger stamps it), and `resolution_log_id` is trigger-owned (client
/// writes to it are inert).
class SwapRequest {
  final int id;
  final DateTime scheduleDate; // date-only; ISO yyyy-MM-dd on the wire
  final int? scheduleId;
  final int requestingProfileId;
  final int targetProfileId;
  final int? previousActualParentId;
  final int proposedActualParentId;
  final String? proposedHandoffTime; // "HH:mm:ss" as PostgREST returns it
  final String status;
  final String? rejectionReason;
  final String? requestMessage; // F-44
  final String? approvalNote; // F-44
  final int? preEditLogId; // F-26
  final int? resolutionLogId;
  final bool revertNotes; // F-47, frozen after insert by the DB
  final String? resolvedBy; // 'user' | 'system' (F-24 auto-approval)

  /// F-24: when the 24–48 h nudge went out. The app never reads it — the
  /// reminder is the server's business — but the gate does: it is the only
  /// observable difference between "the cron looked at this request and decided
  /// it was not ripe yet" and "the cron never ran".
  final DateTime? reminderSentAt;
  final String? createdAt;
  final String? updatedAt;
  final String? resolvedAt;

  const SwapRequest({
    required this.id,
    required this.scheduleDate,
    this.scheduleId,
    required this.requestingProfileId,
    required this.targetProfileId,
    this.previousActualParentId,
    required this.proposedActualParentId,
    this.proposedHandoffTime,
    required this.status,
    this.rejectionReason,
    this.requestMessage,
    this.approvalNote,
    this.preEditLogId,
    this.resolutionLogId,
    this.revertNotes = false,
    this.resolvedBy,
    this.reminderSentAt,
    this.createdAt,
    this.updatedAt,
    this.resolvedAt,
  });

  static DateTime _parseDate(String iso) {
    final p = iso.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// `resolved_at` in local time — the F-20 history semantics measure a
  /// resolved request's urgency against this instant, never the clock.
  DateTime? get resolvedAtLocal {
    final raw = resolvedAt;
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  /// A revert-flavored open request (`FrozenDayPanel.isRevert`).
  bool get isRevertPending => status == 'revert_pending';

  /// F-24: resolved by the 48h server cron, displayed as `🤖 Automático`.
  bool get isAutoResolved =>
      resolvedBy == 'system' &&
      (status == 'approved' || status == 'revert_approved');

  factory SwapRequest.fromJson(Map<String, dynamic> json) => SwapRequest(
        id: json['id'] as int,
        scheduleDate: _parseDate(json['schedule_date'] as String),
        scheduleId: json['schedule_id'] as int?,
        requestingProfileId: json['requesting_profile_id'] as int,
        targetProfileId: json['target_profile_id'] as int,
        previousActualParentId: json['previous_actual_parent_id'] as int?,
        proposedActualParentId: json['proposed_actual_parent_id'] as int,
        proposedHandoffTime: json['proposed_handoff_time'] as String?,
        status: (json['status'] as String?) ?? 'pending',
        rejectionReason: json['rejection_reason'] as String?,
        requestMessage: json['request_message'] as String?,
        approvalNote: json['approval_note'] as String?,
        preEditLogId: json['pre_edit_log_id'] as int?,
        resolutionLogId: json['resolution_log_id'] as int?,
        revertNotes: (json['revert_notes'] as bool?) ?? false,
        resolvedBy: json['resolved_by'] as String?,
        reminderSentAt: json['reminder_sent_at'] == null
            ? null
            : DateTime.parse(json['reminder_sent_at'] as String).toUtc(),
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
        resolvedAt: json['resolved_at'] as String?,
      );

  /// T-18 — the row back in the shape [fromJson] reads, for the device's
  /// offline copy of the calendar. **Never a write payload**: it carries
  /// server-stamped columns a write must not send. `offline_cache_test` reads
  /// this file and fails if the keys here and in [fromJson] ever differ, so a
  /// column added to one side cannot silently vanish from the cache.
  Map<String, dynamic> toRowJson() => {
        'id': id,
        'schedule_date': '${scheduleDate.year.toString().padLeft(4, '0')}-'
            '${scheduleDate.month.toString().padLeft(2, '0')}-'
            '${scheduleDate.day.toString().padLeft(2, '0')}',
        'schedule_id': scheduleId,
        'requesting_profile_id': requestingProfileId,
        'target_profile_id': targetProfileId,
        'previous_actual_parent_id': previousActualParentId,
        'proposed_actual_parent_id': proposedActualParentId,
        'proposed_handoff_time': proposedHandoffTime,
        'status': status,
        'rejection_reason': rejectionReason,
        'request_message': requestMessage,
        'approval_note': approvalNote,
        'pre_edit_log_id': preEditLogId,
        'resolution_log_id': resolutionLogId,
        'revert_notes': revertNotes,
        'resolved_by': resolvedBy,
        'reminder_sent_at': reminderSentAt?.toIso8601String(),
        'created_at': createdAt,
        'updated_at': updatedAt,
        'resolved_at': resolvedAt,
      };

  /// The slice the pure rules consume (frozen set, urgency, resolve subsets).
  SwapRequestView toView() => SwapRequestView(
        id: id,
        scheduleDate: scheduleDate,
        status: status,
        requestingProfileId: requestingProfileId,
        targetProfileId: targetProfileId,
        proposedHandoffTime: proposedHandoffTime,
        resolvedAtLocal: resolvedAtLocal,
      );
}
