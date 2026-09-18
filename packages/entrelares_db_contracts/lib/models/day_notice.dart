/// The `day_notices` row, with its single `day_notice_outcomes` row folded in
/// (F-52).
///
/// An aviso is append-only: nothing ever updates this row, and it is CLOSED by
/// one outcome row, never by a column changing under it. So "is it still open"
/// is not stored — it is the absence of an outcome, and [isOpen] says exactly
/// that rather than trusting a flag somebody has to remember to set.
///
/// The wire values of [reason], [request] and [outcome] are strings on purpose:
/// the enums that interpret them live in `entrelares_core`, which this package
/// must not depend on, and an unknown value has to survive the trip so the
/// reader can fall back instead of crashing on a future writer's row.
class DayNotice {
  final int id;
  final int familyId;

  /// The day it is about — always the sender's "today" in `America/Sao_Paulo`
  /// at the moment it was sent, date-only.
  final DateTime scheduleDate;

  final int senderProfileId;

  /// `atraso` · `medico` · `transito` · `outro`.
  final String reason;

  /// The stated estimate in minutes, or null for "sem previsão". Null is a
  /// VALUE: it is the only state in which the day itself may be offered.
  final int? etaMinutes;

  /// `info` · `pickup` · `keep`.
  final String request;

  /// The sender's optional line, already trimmed by the server.
  final String? note;

  /// UTC instant it was sent.
  final DateTime createdAt;

  /// `cancelled` (PR 1) · `helping` · `keeping` (PR 2), or null while open.
  final String? outcome;

  /// Who closed it — the sender for a cancellation, the answerer otherwise.
  final int? outcomeById;

  final String? outcomeNote;

  /// The swap an answer produced (PR 2). Null for every other outcome, and
  /// the link the history follows back from the calendar change to the aviso
  /// that caused it.
  final int? outcomeSwapRequestId;

  final DateTime? outcomeAt;

  const DayNotice({
    required this.id,
    required this.familyId,
    required this.scheduleDate,
    required this.senderProfileId,
    required this.reason,
    required this.request,
    required this.createdAt,
    this.etaMinutes,
    this.note,
    this.outcome,
    this.outcomeById,
    this.outcomeNote,
    this.outcomeSwapRequestId,
    this.outcomeAt,
  });

  /// Nothing has closed it yet, so an answer is still possible.
  bool get isOpen => outcome == null;

  /// PostgREST hands the embedded outcome over as a LIST (a to-many join),
  /// even though a UNIQUE keeps it to at most one. Reading `[0]` of an empty
  /// list is how an open notice turns into a crash, so the shape is checked
  /// rather than assumed.
  factory DayNotice.fromJson(Map<String, dynamic> json) {
    final embedded = json['day_notice_outcomes'];
    final outcome = switch (embedded) {
      final List<dynamic> rows when rows.isNotEmpty =>
        rows.first as Map<String, dynamic>,
      final Map<String, dynamic> row => row,
      _ => null,
    };

    return DayNotice(
      id: json['id'] as int,
      familyId: (json['family_id'] as int?) ?? 0,
      scheduleDate: DateTime.parse(json['schedule_date'] as String),
      senderProfileId: (json['sender_profile_id'] as int?) ?? 0,
      reason: (json['reason'] as String?) ?? '',
      etaMinutes: json['eta_minutes'] as int?,
      request: (json['request'] as String?) ?? '',
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      outcome: outcome?['outcome'] as String?,
      outcomeById: outcome?['actor_profile_id'] as int?,
      outcomeNote: outcome?['note'] as String?,
      outcomeSwapRequestId: outcome?['swap_request_id'] as int?,
      outcomeAt: outcome?['created_at'] == null
          ? null
          : DateTime.parse(outcome!['created_at'] as String).toUtc(),
    );
  }
}
