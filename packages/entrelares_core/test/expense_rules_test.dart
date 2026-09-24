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
}
