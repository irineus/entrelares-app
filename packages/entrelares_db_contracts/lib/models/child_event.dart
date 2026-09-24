/// The `child_events` row — one event of the day agenda (F-55).
///
/// Written only through `add_child_event` / `update_child_event` /
/// `delete_child_event`; every member of the family reads it. A delete is
/// SOFT: the row stays with [deletedAt]/[deletedBy], because the Histórico says
/// that it was removed. [sourceScheduleId] marks a note converted from the old
/// "Observação do dia" (no author: nobody wrote it through the agenda).
class ChildEvent {
  final int id;
  final int familyId;

  /// Null only on a note — a note belongs to the DAY.
  final int? childId;

  /// Date-only.
  final DateTime eventDate;

  /// `HH:mm` (the server's `HH:mm:ss` is cut), or null.
  final String? startTime;
  final String? endTime;

  /// The closed wire key: school, health, medicine, activity, free, note,
  /// other. `entrelares_core`'s `AgendaKind` parses it.
  final String kind;

  /// Free text as written (trimmed by the server), or null.
  final String? body;

  final int? sourceScheduleId;
  final String? batchId;
  final int? createdBy;
  final DateTime createdAt;
  final int? deletedBy;
  final DateTime? deletedAt;

  const ChildEvent({
    required this.id,
    required this.familyId,
    required this.eventDate,
    required this.kind,
    required this.createdAt,
    this.childId,
    this.startTime,
    this.endTime,
    this.body,
    this.sourceScheduleId,
    this.batchId,
    this.createdBy,
    this.deletedBy,
    this.deletedAt,
  });

  bool get isDeleted => deletedAt != null;

  static String? _hm(Object? raw) {
    final s = raw as String?;
    if (s == null || s.length < 5) return s;
    return s.substring(0, 5);
  }

  factory ChildEvent.fromJson(Map<String, dynamic> json) => ChildEvent(
        id: json['id'] as int,
        familyId: (json['family_id'] as int?) ?? 0,
        childId: json['child_id'] as int?,
        eventDate: DateTime.parse(json['event_date'] as String),
        startTime: _hm(json['start_time']),
        endTime: _hm(json['end_time']),
        kind: (json['kind'] as String?) ?? 'other',
        body: json['body'] as String?,
        sourceScheduleId: json['source_schedule_id'] as int?,
        batchId: json['batch_id'] as String?,
        createdBy: json['created_by'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
        deletedBy: json['deleted_by'] as int?,
        deletedAt: json['deleted_at'] == null
            ? null
            : DateTime.parse(json['deleted_at'] as String).toUtc(),
      );
}
