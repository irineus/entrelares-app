/// The `care_schedules` row. Mirrors `Entrelares/Models/CareSchedule.cs` —
/// including the T-33/T-35 concurrency contract: an authenticated UPDATE must
/// send the FULL row, with `revision` as read and `submitted_token` echoing
/// the `revision_token` that was read. Omitting the echo is what a forged
/// payload would do, and the trigger rejects it.
class CareSchedule {
  final int id;
  final DateTime scheduleDate; // date-only; ISO yyyy-MM-dd on the wire
  final String? handoffTime; // "HH:mm:ss" as PostgREST returns it
  final int scheduledParentId;
  final int? actualParentId;
  final String? notes;
  final String? createdAt;
  final String? updatedAt;
  final int revision;
  final String revisionToken;

  const CareSchedule({
    required this.id,
    required this.scheduleDate,
    this.handoffTime,
    required this.scheduledParentId,
    this.actualParentId,
    this.notes,
    this.createdAt,
    this.updatedAt,
    this.revision = 0,
    this.revisionToken = '',
  });

  int get effectiveParentId => actualParentId ?? scheduledParentId;

  static DateTime _parseDate(String iso) {
    final p = iso.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  factory CareSchedule.fromJson(Map<String, dynamic> json) => CareSchedule(
        id: json['id'] as int,
        scheduleDate: _parseDate(json['schedule_date'] as String),
        handoffTime: json['handoff_time'] as String?,
        scheduledParentId: json['scheduled_parent_id'] as int,
        actualParentId: json['actual_parent_id'] as int?,
        notes: json['notes'] as String?,
        createdAt: json['created_at'] as String?,
        updatedAt: json['updated_at'] as String?,
        revision: (json['revision'] as int?) ?? 0,
        revisionToken: (json['revision_token'] as String?) ?? '',
      );

  /// T-18 — the row back in the shape [fromJson] reads, for the device's
  /// offline copy of the calendar. **Never a write payload**: it carries
  /// server-stamped columns a write must not send. `offline_cache_test` reads
  /// this file and fails if the keys here and in [fromJson] ever differ, so a
  /// column added to one side cannot silently vanish from the cache.
  Map<String, dynamic> toRowJson() => {
        'id': id,
        'schedule_date': isoDate(scheduleDate),
        'handoff_time': handoffTime,
        'scheduled_parent_id': scheduledParentId,
        'actual_parent_id': actualParentId,
        'notes': notes,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'revision': revision,
        'revision_token': revisionToken,
      };

  /// INSERT payload: no id (identity), no tokens (server-stamped), no
  /// family_id (trigger_a derives it from scheduled_parent_id).
  Map<String, dynamic> toInsertJson() => {
        'schedule_date': isoDate(scheduleDate),
        'handoff_time': handoffTime,
        'scheduled_parent_id': scheduledParentId,
        'actual_parent_id': actualParentId,
        'notes': notes,
      };

  /// UPDATE payload: the full row, `revision` as read and `submitted_token`
  /// echoing the `revision_token` read — the only way past the T-35 guard.
  Map<String, dynamic> toUpdateJson() => {
        'schedule_date': isoDate(scheduleDate),
        'handoff_time': handoffTime,
        'scheduled_parent_id': scheduledParentId,
        'actual_parent_id': actualParentId,
        'notes': notes,
        'revision': revision,
        'submitted_token': revisionToken.isEmpty ? null : revisionToken,
      };

  static const Object _keep = Object();

  /// [actualParentId], [handoffTime] and [notes] use a keep-sentinel so an
  /// explicit `null` CLEARS the field — the swap approval sets the proposed
  /// handoff even when it is "no time", and the revert restore replays a
  /// snapshot whose fields may be null on purpose.
  CareSchedule copyWith({
    int? scheduledParentId,
    Object? actualParentId = _keep,
    Object? handoffTime = _keep,
    Object? notes = _keep,
  }) =>
      CareSchedule(
        id: id,
        scheduleDate: scheduleDate,
        handoffTime: identical(handoffTime, _keep)
            ? this.handoffTime
            : handoffTime as String?,
        scheduledParentId: scheduledParentId ?? this.scheduledParentId,
        actualParentId: identical(actualParentId, _keep)
            ? this.actualParentId
            : actualParentId as int?,
        notes: identical(notes, _keep) ? this.notes : notes as String?,
        createdAt: createdAt,
        updatedAt: updatedAt,
        revision: revision,
        revisionToken: revisionToken,
      );
}
