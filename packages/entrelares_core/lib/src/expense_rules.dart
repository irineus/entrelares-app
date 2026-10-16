/// F-34 — shared expenses, as the client mirrors them.
///
/// BRL only, in integer CENTS everywhere (never a double). The stored PT-BR
/// sentences print money exactly as [ExpenseRules.brl] does in Portuguese —
/// `public.brl_text()` is its SQL twin, and `_shared/push.ts` its Deno one.
///
/// The server stores only facts — expenses, their shares, settlements — and
/// the balance is computed here, from the rows ([ExpenseLedger]), the way
/// Splitwise's "simplify debts" reads them.
library;

import 'localization/date_formats.dart';
import 'localization/k.dart';
import 'localization/k_app.dart';
import 'localization/localization.dart';

/// The seven closed categories (wire keys = `expenses.category`'s CHECK).
enum ExpenseCategory {
  school,
  health,
  clothes,
  activities,
  food,
  transport,
  other;

  static ExpenseCategory? parse(String? wire) =>
      values.where((c) => c.name == wire).firstOrNull;

  /// The label — the same words the notification catalog prints.
  String get labelKey => switch (this) {
        ExpenseCategory.school => K.notifRenderExpenseCategorySchool,
        ExpenseCategory.health => K.notifRenderExpenseCategoryHealth,
        ExpenseCategory.clothes => K.notifRenderExpenseCategoryClothes,
        ExpenseCategory.activities => K.notifRenderExpenseCategoryActivities,
        ExpenseCategory.food => K.notifRenderExpenseCategoryFood,
        ExpenseCategory.transport => K.notifRenderExpenseCategoryTransport,
        ExpenseCategory.other => K.notifRenderExpenseCategoryOther,
      };
}

abstract final class ExpenseRules {
  static final RegExp _thousands = RegExp(r'\B(?=(\d{3})+(?!\d))');

  /// "R$ 1.234,56" (PT-BR) or "R$1,234.56" (EN) from integer cents.
  static String brl(int cents, {required bool english}) {
    final v = cents.abs();
    final whole = (v ~/ 100).toString();
    final frac = (v % 100).toString().padLeft(2, '0');
    return english
        ? 'R\$${whole.replaceAll(_thousands, ',')}.$frac'
        : 'R\$ ${whole.replaceAll(_thousands, '.')},$frac';
  }

  /// "12,34" / "1.234,5" / "12.34" / "R$ 12" → hundredths (cents, or basis
  /// points of a percent); null when it is not a number. The LAST `.` or `,`
  /// followed by one or two digits is the decimal mark; every other one is a
  /// thousands separator.
  static int? parseHundredths(String input) {
    final s = input.replaceAll(RegExp(r'[^0-9.,]'), '');
    if (!RegExp(r'\d').hasMatch(s)) return null;
    final m = RegExp(r'^(.*?)[.,](\d{1,2})$').firstMatch(s);
    final whole =
        (m == null ? s : m.group(1)!).replaceAll(RegExp(r'[.,]'), '');
    final frac = m == null ? '' : m.group(2)!;
    final w = whole.isEmpty ? 0 : int.tryParse(whole);
    if (w == null) return null;
    return w * 100 + (frac.isEmpty ? 0 : int.parse(frac.padRight(2, '0')));
  }

  /// The inverse, for a field's initial text: "12,34" (PT) / "12.34" (EN);
  /// a whole number prints without decimals ("12").
  static String formatHundredths(int value, {required bool english}) {
    final whole = value ~/ 100;
    final frac = value % 100;
    if (frac == 0) return '$whole';
    return '$whole${english ? '.' : ','}${frac.toString().padLeft(2, '0')}';
  }
}

/// The four ways to split (wire keys = `expenses.split_method`'s CHECK).
///
/// What a participant's `value` means: nothing (equal), cents (exact), basis
/// points of a percent — 100% = 10000 (percent) — or share units (shares).
enum SplitMethod {
  equal,
  exact,
  percent,
  shares;

  static SplitMethod? parse(String? wire) =>
      values.where((m) => m.name == wire).firstOrNull;
}

/// Why a split was refused — the client's half of `expense_split`, checked
/// before the tap reaches the server (which says the same in its own words).
enum SplitError {
  noParts,
  duplicate,
  negative,
  exactMismatch,
  percentNot100,
  zeroTotal,
}

class SplitException implements Exception {
  final SplitError error;

  /// For [SplitError.exactMismatch]: what the values add up to, in cents.
  final int total;

  const SplitException(this.error, [this.total = 0]);

  @override
  String toString() => 'SplitException($error, $total)';
}

typedef SplitPart = ({int profileId, int value});
typedef SplitShare = ({int profileId, int weight, int shareCents});

/// One expense as the balance reads it: who paid, how much, who owes what.
typedef LedgerExpense = ({int paidBy, int amountCents, Map<int, int> shares});

/// A payment between two caregivers. Only a CONFIRMED one reaches the ledger
/// (the F-34 difference from Splitwise).
typedef LedgerPayment = ({int from, int to, int amountCents});

abstract final class ExpenseSplit {
  /// Mirror of `public.expense_split`: the shares sum EXACTLY to [amount];
  /// the leftover cents go one each to the largest remainders, ties to the
  /// lowest profile id. Throws [SplitException] where the server refuses.
  static List<SplitShare> split(
      int amount, SplitMethod method, List<SplitPart> parts) {
    if (parts.isEmpty) throw const SplitException(SplitError.noParts);
    final ids = {for (final p in parts) p.profileId};
    if (ids.length != parts.length) {
      throw const SplitException(SplitError.duplicate);
    }
    final weights = [
      for (final p in parts) method == SplitMethod.equal ? 1 : p.value
    ];
    if (weights.any((w) => w < 0)) {
      throw const SplitException(SplitError.negative);
    }
    final total = weights.fold<int>(0, (a, b) => a + b);
    if (method == SplitMethod.exact && total != amount) {
      throw SplitException(SplitError.exactMismatch, total);
    }
    if (method == SplitMethod.percent && total != 10000) {
      throw const SplitException(SplitError.percentNot100);
    }
    if (total <= 0) throw const SplitException(SplitError.zeroTotal);

    final base = <int>[];
    final rem = <int>[];
    for (final w in weights) {
      if (method == SplitMethod.exact) {
        base.add(w);
        rem.add(0);
      } else {
        base.add(amount * w ~/ total);
        rem.add(amount * w % total);
      }
    }
    var leftover = amount - base.fold<int>(0, (a, b) => a + b);
    final order = List.generate(parts.length, (i) => i)
      ..sort((a, b) {
        final byRem = rem[b].compareTo(rem[a]);
        return byRem != 0
            ? byRem
            : parts[a].profileId.compareTo(parts[b].profileId);
      });
    final extra = List.filled(parts.length, 0);
    for (final i in order) {
      if (leftover <= 0) break;
      extra[i] = 1;
      leftover--;
    }
    return [
      for (var i = 0; i < parts.length; i++)
        (
          profileId: parts[i].profileId,
          weight: weights[i],
          shareCents: base[i] + extra[i],
        ),
    ]..sort((a, b) => a.profileId.compareTo(b.profileId));
  }
}

abstract final class ExpenseLedger {
  /// Net per person, in cents: positive = is owed, negative = owes. The payer
  /// is credited the amount and each participant debited their share; a
  /// confirmed payment credits who paid and debits who received.
  static Map<int, int> net(
      Iterable<LedgerExpense> expenses, Iterable<LedgerPayment> payments) {
    final net = <int, int>{};
    void add(int id, int v) => net[id] = (net[id] ?? 0) + v;
    for (final e in expenses) {
      add(e.paidBy, e.amountCents);
      e.shares.forEach((id, cents) => add(id, -cents));
    }
    for (final p in payments) {
      add(p.from, p.amountCents);
      add(p.to, -p.amountCents);
    }
    return net;
  }

  /// How much [from] may still pay [to] — mirror of `public.settlement_room`
  /// (owner's validation, 25/09/2026): the smaller of the payer's debt and the
  /// receiver's credit, each net of the payments still [pending]. Zero or less
  /// means there is nothing to pay; the server refuses the same.
  static int room(Map<int, int> net, Iterable<LedgerPayment> pending,
      {required int from, required int to}) {
    var out = 0;
    var into = 0;
    for (final p in pending) {
      if (p.from == from) out += p.amountCents;
      if (p.to == to) into += p.amountCents;
    }
    final owes = -(net[from] ?? 0) - out;
    final owed = (net[to] ?? 0) - into;
    return owes < owed ? owes : owed;
  }

  /// "Simplify debts": the fewest payments that settle [net] — the largest
  /// debtor pays the largest creditor, again and again. Deterministic (ties
  /// to the lowest profile id), so two phones show the same suggestion.
  static List<LedgerPayment> simplify(Map<int, int> net) {
    int byAmountThenId(MapEntry<int, int> a, MapEntry<int, int> b) {
      final byAmount = b.value.compareTo(a.value);
      return byAmount != 0 ? byAmount : a.key.compareTo(b.key);
    }

    final creditors = {
      for (final e in net.entries)
        if (e.value > 0) e.key: e.value
    };
    final debtors = {
      for (final e in net.entries)
        if (e.value < 0) e.key: -e.value
    };
    final out = <LedgerPayment>[];
    while (creditors.isNotEmpty && debtors.isNotEmpty) {
      final c = (creditors.entries.toList()..sort(byAmountThenId)).first;
      final d = (debtors.entries.toList()..sort(byAmountThenId)).first;
      final amount = c.value < d.value ? c.value : d.value;
      out.add((from: d.key, to: c.key, amountCents: amount));
      if (c.value == amount) {
        creditors.remove(c.key);
      } else {
        creditors[c.key] = c.value - amount;
      }
      if (d.value == amount) {
        debtors.remove(d.key);
      } else {
        debtors[d.key] = d.value - amount;
      }
    }
    return out;
  }
}

/// F-93 — the fields an edit can change, as the trail records them.
enum ExpenseField { description, amount, category, paidBy, spentOn, split }

/// One field that changed between two snapshots of `expense_history`. For
/// [ExpenseField.split], [shares] holds each person whose part moved
/// (null = was not / is no longer in the split); [before]/[after] stay null.
class ExpenseFieldChange {
  final ExpenseField field;
  final Object? before;
  final Object? after;
  final List<({int profileId, int? beforeCents, int? afterCents})> shares;

  const ExpenseFieldChange(this.field,
      {this.before, this.after, this.shares = const []});
}

/// F-93 — what an edit actually changed. The trail always held the whole
/// expense before and after (`expense_snapshot`: payer, date, category, the
/// split per person), and the screens printed only the description and the
/// amount — a 70/30 → 50/50 edit read as no change at all.
abstract final class ExpenseDiff {
  static int? _cents(Object? raw) =>
      raw == null ? null : (raw is int ? raw : int.tryParse('$raw'));

  static Map<int, int> _shares(Map<String, dynamic> snap) => {
        for (final s in (snap['shares'] as List?) ?? const [])
          if (_cents((s as Map)['profile_id']) != null)
            _cents(s['profile_id'])!: _cents(s['share_cents']) ?? 0
      };

  /// The fields that differ between [before] and [after], in reading order.
  /// The split is compared by what each person OWES (`share_cents`): a
  /// method change that leaves every part where it was changed nothing.
  static List<ExpenseFieldChange> between(
      Map<String, dynamic>? before, Map<String, dynamic>? after) {
    if (before == null || after == null) return const [];
    final out = <ExpenseFieldChange>[];
    void plain(ExpenseField f, String key, Object? Function(Object?) read) {
      final b = read(before[key]);
      final a = read(after[key]);
      if (b != a) out.add(ExpenseFieldChange(f, before: b, after: a));
    }

    String? text(Object? raw) => raw == null ? null : '$raw';
    plain(ExpenseField.description, 'description', text);
    plain(ExpenseField.amount, 'amount_cents', _cents);
    plain(ExpenseField.category, 'category', text);
    plain(ExpenseField.paidBy, 'paid_by', _cents);
    plain(ExpenseField.spentOn, 'spent_on', text);

    final b = _shares(before);
    final a = _shares(after);
    final ids = {...b.keys, ...a.keys}.toList()..sort();
    final moved = [
      for (final id in ids)
        if (b[id] != a[id])
          (profileId: id, beforeCents: b[id], afterCents: a[id])
    ];
    if (moved.isNotEmpty) {
      out.add(ExpenseFieldChange(ExpenseField.split, shares: moved));
    }
    return out;
  }

  /// One sentence per changed field, in the reader's words — the same lines
  /// on the expense's sheet and in the PDF. [nameOf] answers a profile id.
  static List<String> describe(List<ExpenseFieldChange> changes,
      Localization l, String Function(int profileId) nameOf) {
    String money(Object? c) =>
        c == null ? '—' : ExpenseRules.brl(c as int, english: l.isEnglish);
    String category(Object? c) => l[
        (ExpenseCategory.parse(c as String?) ?? ExpenseCategory.other)
            .labelKey];
    String day(Object? d) {
      final parsed = d == null ? null : DateTime.tryParse('$d');
      return parsed == null ? '—' : l.formatDate(parsed);
    }

    String person(Object? id) => id == null ? '—' : nameOf(id as int);
    String line(String labelKey, String b, String a) =>
        l.format(KApp.expenseDiffLine, [l[labelKey], b, a]);

    return [
      for (final c in changes)
        switch (c.field) {
          ExpenseField.description => line(KApp.expenseDesc,
              '"${c.before ?? ''}"', '"${c.after ?? ''}"'),
          ExpenseField.amount =>
            line(KApp.expenseDiffAmount, money(c.before), money(c.after)),
          ExpenseField.category => line(
              KApp.expenseCategory, category(c.before), category(c.after)),
          ExpenseField.paidBy =>
            line(KApp.expensePaidBy, person(c.before), person(c.after)),
          ExpenseField.spentOn =>
            line(KApp.expenseDate, day(c.before), day(c.after)),
          ExpenseField.split => l.format(KApp.expenseDiffSplit, [
              [
                for (final s in c.shares)
                  l.format(KApp.expenseDiffShare, [
                    nameOf(s.profileId),
                    money(s.beforeCents),
                    money(s.afterCents),
                  ])
              ].join('; ')
            ]),
        }
    ];
  }
}
