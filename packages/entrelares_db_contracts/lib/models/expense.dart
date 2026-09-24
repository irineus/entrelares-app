/// F-34 — the shared-expense rows a caregiver reads. Written only through the
/// RPCs (`add_expense`, `update_expense`, `delete_expense`,
/// `request_settlement`, `answer_settlement`, `cancel_settlement`); a viewer
/// reads none of them (RLS).
library;

DateTime _date(Object? raw) => DateTime.parse(raw as String);
DateTime? _instant(Object? raw) =>
    raw == null ? null : DateTime.parse(raw as String).toUtc();
int _int(Object? raw) => raw is int ? raw : int.parse('$raw');
int? _intOrNull(Object? raw) => raw == null ? null : _int(raw);

/// One participant's part of an expense: what the payer typed ([weight]) and
/// what they owe of it ([shareCents] — the shares sum to the amount).
class ExpenseShare {
  final int profileId;
  final int weight;
  final int shareCents;

  const ExpenseShare(
      {required this.profileId, required this.weight, required this.shareCents});

  factory ExpenseShare.fromJson(Map<String, dynamic> json) => ExpenseShare(
        profileId: _int(json['profile_id']),
        weight: _int(json['weight']),
        shareCents: _int(json['share_cents']),
      );
}

class Expense {
  final int id;
  final int? childId;
  final String description;

  /// Wire key of the closed category (`ExpenseCategory`).
  final String category;
  final int amountCents;
  final int paidBy;
  final DateTime spentOn;

  /// Wire key of the split (`SplitMethod`).
  final String splitMethod;
  final int? createdBy;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final DateTime? deletedAt;
  final int? deletedBy;
  final List<ExpenseShare> shares;

  const Expense({
    required this.id,
    required this.description,
    required this.category,
    required this.amountCents,
    required this.paidBy,
    required this.spentOn,
    required this.splitMethod,
    required this.createdAt,
    this.childId,
    this.createdBy,
    this.updatedAt,
    this.deletedAt,
    this.deletedBy,
    this.shares = const [],
  });

  bool get isDeleted => deletedAt != null;

  /// A row with its shares embedded (`select('*, expense_shares(*)')`).
  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: _int(json['id']),
        childId: _intOrNull(json['child_id']),
        description: json['description'] as String,
        category: json['category'] as String,
        amountCents: _int(json['amount_cents']),
        paidBy: _int(json['paid_by']),
        spentOn: _date(json['spent_on']),
        splitMethod: json['split_method'] as String,
        createdBy: _intOrNull(json['created_by']),
        createdAt: _instant(json['created_at'])!,
        updatedAt: _instant(json['updated_at']),
        deletedAt: _instant(json['deleted_at']),
        deletedBy: _intOrNull(json['deleted_by']),
        shares: [
          for (final s in (json['expense_shares'] as List?) ?? const [])
            ExpenseShare.fromJson(s as Map<String, dynamic>)
        ],
      );
}

/// One entry of the append-only trail. [oldData] is the expense (with its
/// shares) BEFORE an update or a delete.
class ExpenseHistoryEntry {
  final int id;
  final int expenseId;

  /// `created`, `updated` or `deleted`.
  final String action;
  final int? actorId;
  final DateTime at;
  final Map<String, dynamic>? oldData;
  final Map<String, dynamic>? newData;

  const ExpenseHistoryEntry({
    required this.id,
    required this.expenseId,
    required this.action,
    required this.at,
    this.actorId,
    this.oldData,
    this.newData,
  });

  factory ExpenseHistoryEntry.fromJson(Map<String, dynamic> json) =>
      ExpenseHistoryEntry(
        id: _int(json['id']),
        expenseId: _int(json['expense_id']),
        action: json['action'] as String,
        actorId: _intOrNull(json['actor_id']),
        at: _instant(json['at'])!,
        oldData: json['old_data'] as Map<String, dynamic>?,
        newData: json['new_data'] as Map<String, dynamic>?,
      );
}

/// "I paid X to Y" — it counts in the balance only once [status] is
/// `confirmed` by the one who received (the F-34 difference from Splitwise).
class ExpenseSettlement {
  final int id;
  final int? childId;
  final int fromProfile;
  final int toProfile;
  final int amountCents;

  /// `pending`, `confirmed`, `rejected` or `cancelled`.
  final String status;
  final DateTime createdAt;
  final DateTime? answeredAt;

  const ExpenseSettlement({
    required this.id,
    required this.fromProfile,
    required this.toProfile,
    required this.amountCents,
    required this.status,
    required this.createdAt,
    this.childId,
    this.answeredAt,
  });

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';

  factory ExpenseSettlement.fromJson(Map<String, dynamic> json) =>
      ExpenseSettlement(
        id: _int(json['id']),
        childId: _intOrNull(json['child_id']),
        fromProfile: _int(json['from_profile']),
        toProfile: _int(json['to_profile']),
        amountCents: _int(json['amount_cents']),
        status: json['status'] as String,
        createdAt: _instant(json['created_at'])!,
        answeredAt: _instant(json['answered_at']),
      );
}
