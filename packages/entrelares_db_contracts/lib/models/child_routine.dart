/// The `child_routines` row — a weekly model of the day agenda (F-55, PR 3).
///
/// Written only through `save_child_routine` / `stop_child_routine`. Its [id]
/// is the `batch_id` of every `child_events` row it generated; a re-apply
/// replaces the routine's events from a day on, and an event edited on its own
/// leaves the routine. [weekdays] are ISO (1 = Monday … 7 = Sunday), the same
/// numbering as Dart's `DateTime.weekday`.
class ChildRoutine {
  final String id;
  final int familyId;
  final int? childId;
  final String kind;

  /// `HH:mm` (the server's `HH:mm:ss` is cut), or null.
  final String? startTime;
  final String? endTime;
  final String? body;
  final List<int> weekdays;

  /// Date-only: the first day it was applied from, and the last day it
  /// reached (the end of the plan when it was last applied).
  final DateTime startsOn;
  final DateTime endsOn;
  final DateTime? stoppedAt;

  /// F-55 PR 4 — who the creator chose to tell (`none`, `self`,
  /// `responsible`, `family`), on which channels, and the reminder offset in
  /// minutes (0/15/30/60, only with a start time).
  final String notifyTo;
  final bool notifyPush;
  final bool notifyInApp;
  final int? remindMinutes;

  const ChildRoutine({
    required this.id,
    required this.familyId,
    required this.kind,
    required this.weekdays,
    required this.startsOn,
    required this.endsOn,
    this.childId,
    this.startTime,
    this.endTime,
    this.body,
    this.stoppedAt,
    this.notifyTo = 'none',
    this.notifyPush = true,
    this.notifyInApp = true,
    this.remindMinutes,
  });

  bool get isStopped => stoppedAt != null;

  static String? _hm(Object? raw) {
    final s = raw as String?;
    if (s == null || s.length < 5) return s;
    return s.substring(0, 5);
  }

  factory ChildRoutine.fromJson(Map<String, dynamic> json) => ChildRoutine(
        id: json['id'] as String,
        familyId: (json['family_id'] as int?) ?? 0,
        childId: json['child_id'] as int?,
        kind: (json['kind'] as String?) ?? 'other',
        startTime: _hm(json['start_time']),
        endTime: _hm(json['end_time']),
        body: json['body'] as String?,
        weekdays: [
          for (final w in (json['weekdays'] as List? ?? const [])) w as int
        ]..sort(),
        startsOn: DateTime.parse(json['starts_on'] as String),
        endsOn: DateTime.parse(json['ends_on'] as String),
        stoppedAt: json['stopped_at'] == null
            ? null
            : DateTime.parse(json['stopped_at'] as String).toUtc(),
        notifyTo: (json['notify_to'] as String?) ?? 'none',
        notifyPush: (json['notify_push'] as bool?) ?? true,
        notifyInApp: (json['notify_in_app'] as bool?) ?? true,
        remindMinutes: json['remind_minutes'] as int?,
      );
}
