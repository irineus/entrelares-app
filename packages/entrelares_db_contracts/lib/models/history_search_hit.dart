/// One result of `search_history` (F-76) — a text somebody wrote that the
/// Histórico shows, found by word. Nothing is stored for it: the RPC reads
/// the source tables as the caller (SECURITY INVOKER).
class HistorySearchHit {
  /// `relato`, `reply`, `swap_message`, `swap_note`, `day_note`, `agenda`,
  /// `notice` — the source; the screen names it in the reader's language.
  final String kind;

  /// The day the text is ABOUT — the tap opens it in the month view.
  final DateTime day;

  /// When it was written (UTC).
  final DateTime writtenAt;

  /// Who wrote it, when the source records it.
  final int? authorProfileId;

  final String body;

  const HistorySearchHit({
    required this.kind,
    required this.day,
    required this.writtenAt,
    required this.body,
    this.authorProfileId,
  });

  factory HistorySearchHit.fromJson(Map<String, dynamic> json) =>
      HistorySearchHit(
        kind: (json['kind'] as String?) ?? '',
        day: DateTime.parse(json['day'] as String),
        writtenAt: DateTime.parse(json['written_at'] as String).toUtc(),
        authorProfileId: json['author_profile_id'] as int?,
        body: (json['body'] as String?) ?? '',
      );
}
