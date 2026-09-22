/// The `day_accounts` row — a relato do dia (F-67).
///
/// Append-only: nothing ever updates this row. A correction is ANOTHER row
/// whose [correctsId] points at this one, so "was it corrected" is not stored
/// here — it is whether some other relato names this id, which
/// `entrelares_core`'s `DayAccountRules` answers from the list.
class DayAccount {
  final int id;
  final int familyId;

  /// The day it is ABOUT, date-only. Always a day before the author's
  /// "today" in `America/Sao_Paulo` at the moment it was written.
  final DateTime accountDate;

  final int authorProfileId;

  /// The text, already trimmed by the server.
  final String body;

  /// The relato this one corrects, or null for a first account.
  final int? correctsId;

  /// UTC instant it was WRITTEN — the record prints it beside [accountDate].
  final DateTime createdAt;

  const DayAccount({
    required this.id,
    required this.familyId,
    required this.accountDate,
    required this.authorProfileId,
    required this.body,
    required this.createdAt,
    this.correctsId,
  });

  factory DayAccount.fromJson(Map<String, dynamic> json) => DayAccount(
        id: json['id'] as int,
        familyId: (json['family_id'] as int?) ?? 0,
        accountDate: DateTime.parse(json['account_date'] as String),
        authorProfileId: (json['author_profile_id'] as int?) ?? 0,
        body: (json['body'] as String?) ?? '',
        correctsId: json['corrects_id'] as int?,
        createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      );
}
