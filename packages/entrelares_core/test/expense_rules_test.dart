import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-34 — money in cents, printed the way the stored sentences print it.
void main() {
  test('brl: PT-BR and EN, thousands and cents', () {
    expect(ExpenseRules.brl(123456, english: false), 'R\$ 1.234,56');
    expect(ExpenseRules.brl(5, english: false), 'R\$ 0,05');
    expect(ExpenseRules.brl(100000000, english: false), 'R\$ 1.000.000,00');
    expect(ExpenseRules.brl(123456, english: true), 'R\$1,234.56');
  });

  test('the seven categories are the CHECK\'s wire keys', () {
    expect(ExpenseCategory.values.map((c) => c.name), [
      'school', 'health', 'clothes', 'activities', 'food', 'transport', 'other'
    ]);
    expect(ExpenseCategory.parse('food'), ExpenseCategory.food);
    expect(ExpenseCategory.parse('car'), isNull);
  });

  group('split — the mirror of expense_split', () {
    List<int> cents(List<SplitShare> s) => [for (final x in s) x.shareCents];

    test('equal: the odd cent goes to the lowest profile id', () {
      final s = ExpenseSplit.split(10001, SplitMethod.equal, [
        (profileId: 9, value: 0),
        (profileId: 4, value: 0),
      ]);
      expect([for (final x in s) x.profileId], [4, 9]);
      expect(cents(s), [5001, 5000]);
    });

    test('percent and shares: largest remainder, sums exactly', () {
      final pct = ExpenseSplit.split(1000, SplitMethod.percent, [
        (profileId: 1, value: 3333),
        (profileId: 2, value: 6667),
      ]);
      expect(cents(pct), [333, 667]);
      final sh = ExpenseSplit.split(1000, SplitMethod.shares, [
        (profileId: 1, value: 2),
        (profileId: 2, value: 1),
      ]);
      expect(cents(sh), [667, 333]);
      final three = ExpenseSplit.split(100, SplitMethod.equal, [
        (profileId: 3, value: 1),
        (profileId: 1, value: 1),
        (profileId: 2, value: 1),
      ]);
      expect(cents(three), [34, 33, 33]);
    });

    test('refusals match the server', () {
      Matcher refused(SplitError e) =>
          throwsA(isA<SplitException>().having((x) => x.error, 'error', e));
      expect(() => ExpenseSplit.split(1, SplitMethod.equal, []),
          refused(SplitError.noParts));
      expect(
          () => ExpenseSplit.split(1000, SplitMethod.exact, [
                (profileId: 1, value: 600),
                (profileId: 2, value: 300),
              ]),
          throwsA(isA<SplitException>().having((x) => x.total, 'total', 900)));
      expect(
          () => ExpenseSplit.split(1000, SplitMethod.percent, [
                (profileId: 1, value: 5000),
                (profileId: 2, value: 4000),
              ]),
          refused(SplitError.percentNot100));
      expect(
          () => ExpenseSplit.split(1000, SplitMethod.shares, [
                (profileId: 1, value: 0),
              ]),
          refused(SplitError.zeroTotal));
      expect(
          () => ExpenseSplit.split(1000, SplitMethod.shares, [
                (profileId: 1, value: 1),
                (profileId: 1, value: 1),
              ]),
          refused(SplitError.duplicate));
    });
  });

  test('typed money and percentages become hundredths', () {
    expect(ExpenseRules.parseHundredths('12,34'), 1234);
    expect(ExpenseRules.parseHundredths('1.234,5'), 123450);
    expect(ExpenseRules.parseHundredths('12.34'), 1234);
    expect(ExpenseRules.parseHundredths('R\$ 12'), 1200);
    expect(ExpenseRules.parseHundredths('1,234.56'), 123456);
    expect(ExpenseRules.parseHundredths('abc'), isNull);
    expect(ExpenseRules.formatHundredths(1234, english: false), '12,34');
    expect(ExpenseRules.formatHundredths(1200, english: true), '12');
  });

  group('the ledger', () {
    test('net: the payer is credited, the participants debited', () {
      final net = ExpenseLedger.net([
        (paidBy: 1, amountCents: 10000, shares: {1: 5000, 2: 5000}),
        (paidBy: 2, amountCents: 3000, shares: {1: 1500, 2: 1500}),
      ], const []);
      expect(net, {1: 3500, 2: -3500});
    });

    test('only what the caller passes as confirmed moves the balance', () {
      final net = ExpenseLedger.net([
        (paidBy: 1, amountCents: 10000, shares: {1: 5000, 2: 5000}),
      ], [
        (from: 2, to: 1, amountCents: 5000),
      ]);
      expect(net.values.every((v) => v == 0), isTrue);
      expect(ExpenseLedger.simplify(net), isEmpty);
    });

    test('simplify: the fewest payments, deterministic', () {
      // A paid 90 for A, B, C (30 each); C paid 30 for B and C (15 each).
      final net = ExpenseLedger.net([
        (paidBy: 1, amountCents: 9000, shares: {1: 3000, 2: 3000, 3: 3000}),
        (paidBy: 3, amountCents: 3000, shares: {2: 1500, 3: 1500}),
      ], const []);
      expect(net, {1: 6000, 2: -4500, 3: -1500});
      expect(ExpenseLedger.simplify(net), [
        (from: 2, to: 1, amountCents: 4500),
        (from: 3, to: 1, amountCents: 1500),
      ]);
    });
  });
}
