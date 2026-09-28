/// The `day_account_replies` row — a reply to a relato do dia (F-75).
///
/// Append-only, like [DayAccount]: a correction is ANOTHER row whose
/// [correctsId] points at the reply it corrects; both stay.
class DayAccountReply {
  final int id;
  final int familyId;

  /// The relato (`day_accounts.id`) this reply answers.
  final int accountId;

  final int authorProfileId;

  /// The text, already trimmed by the server.
  final String body;

  /// The reply this one corrects, or null for the reply itself.
  final int? correctsId;

  /// UTC instant it was WRITTEN.
  final DateTime createdAt;

  const DayAccountReply({
    required this.id,
    required this.familyId,
    required this.accountId,
    required this.authorProfileId,
    required this.body,
    required this.createdAt,
    this.correctsId,
  });

  factory DayAccountReply.fromJson(Map<String, dynamic> json) =>
      DayAccountReply(
        id: json['id'] as int,
        familyId: (json['family_id'] as int?) ?? 0,
        accountId: (json['account_id'] as int?) ?? 0,
        authorProfileId: (json['author_profile_id'] as int?) ?? 0,
        body: (json['body'] as String?) ?? '',
        correctsId: json['corrects_id'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      );
}
