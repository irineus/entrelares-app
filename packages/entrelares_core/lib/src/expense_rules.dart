/// F-34 — shared expenses, as the client mirrors them.
///
/// BRL only, in integer CENTS everywhere (never a double). The stored PT-BR
/// sentences print money exactly as [ExpenseRules.brl] does in Portuguese —
/// `public.brl_text()` is its SQL twin, and `_shared/push.ts` its Deno one.
library;

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
}
