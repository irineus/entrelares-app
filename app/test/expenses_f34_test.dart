// F-34 (PR 2) — the shared expenses on screen.
//
// The server splits, stores and refuses; these pin what the client adds: the
// balance and its "fewest payments" suggestion read from the rows, the split
// it sends, the receiver's answer, the Premium read-only state, the viewer and
// the flag-off states, and the bar that offers Despesas only when it may.
// Since the owner's validation (25/09/2026): "Seu saldo" with Pagar only where
// the reader owes (capped by the debt) and Lembrar only where the reader is
// owed, the activity list with each row's effect, and the live screen.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/expense.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/screens/expenses_screen.dart';
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const ana = Member(
    id: 1,
    fullName: 'Ana Souza',
    colorSlot: 1,
    userId: 'u1',
    roleId: 1,
    isAdmin: true);
const bruno =
    Member(id: 2, fullName: 'Bruno Lima', colorSlot: 2, userId: 'u2', roleId: 1);
const vera = Member(
    id: 3,
    fullName: 'Vera Viewer',
    colorSlot: 3,
    userId: 'u3',
    roleId: 1,
    membershipType: 'viewer');

final today = DateTime(2026, 9, 24, 10);

Expense expense(int id,
        {int paidBy = 1,
        int amount = 10000,
        Map<int, int> shares = const {1: 5000, 2: 5000},
        String desc = 'Mensalidade'}) =>
    Expense(
      id: id,
      description: desc,
      category: 'school',
      amountCents: amount,
      paidBy: paidBy,
      spentOn: DateTime(2026, 9, 10),
      splitMethod: 'exact',
      createdAt: DateTime.utc(2026, 9, 10),
      shares: [
        for (final e in shares.entries)
          ExpenseShare(profileId: e.key, weight: e.value, shareCents: e.value)
      ],
    );

FakeCustodyDataSource source(
        {List<Member> members = const [ana, bruno],
        String plan = 'premium',
        Map<String, String> settings = const {'feature.expenses': 'true'}}) =>
    FakeCustodyDataSource(members: members, days: const [])
      ..family = Family(id: 7, name: 'Souza', plan: plan)
      ..publicSettings = settings;

Future<void> pump(WidgetTester tester, FakeCustodyDataSource ds) async {
  await tester.binding.setSurfaceSize(const Size(420, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: ExpensesScreen(
          dataSource: ds, onOpenPlan: () {}, now: () => today),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);
  String brl(int c) => ExpenseRules.brl(c, english: false);

  testWidgets('"Seu saldo": the debtor reads the number and pays that person',
      (tester) async {
    // Bruno owes Ana 50,00 — seen from Bruno's side (the fake's own profile
    // is the first member).
    final ds = source(members: const [bruno, ana])
      ..expenses = [expense(1)]
      ..expenseActorId = 2;
    await pump(tester, ds);

    expect(find.text(l.format(KApp.expenseHeadOwe, [brl(5000)])), findsOne);
    expect(find.text(l.format(KApp.expenseRowYouOwe, [brl(5000)])), findsOne);
    expect(find.byKey(const ValueKey('expenses-remind-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('expenses-pay-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l[KApp.expenseSettle]).last);
    await tester.pumpAndSettle();
    expect(ds.expenseWrites, ['settle:1:5000']);
    // Nothing moves until Ana confirms: the debt is still there, it is
    // waiting — and there is nothing left to pay twice.
    expect(find.text(l.format(KApp.expenseHeadOwe, [brl(5000)])), findsOne);
    expect(
        find.text(l.format(
            KApp.expensePendingFromMe, [brl(5000), 'Ana Souza'])),
        findsOne);
    expect(find.byKey(const ValueKey('expenses-pay-1')), findsNothing);
  });

  testWidgets('a payment is capped by the debt; less is fine', (tester) async {
    final ds = source(members: const [bruno, ana])
      ..expenses = [expense(1)]
      ..expenseActorId = 2;
    await pump(tester, ds);
    await tester.tap(find.byKey(const ValueKey('expenses-pay-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('settle-amount')), '80');
    await tester.tap(find.text(l[KApp.expenseSettle]).last);
    await tester.pumpAndSettle();
    expect(ds.expenseWrites, isEmpty);
    expect(
        find.text(l.format(KApp.expenseSettleOver, ['Ana Souza', brl(5000)])),
        findsWidgets);
    await tester.enterText(find.byKey(const ValueKey('settle-amount')), '20');
    await tester.tap(find.text(l[KApp.expenseSettle]).last);
    await tester.pumpAndSettle();
    expect(ds.expenseWrites, ['settle:1:2000']);
  });

  testWidgets('who is owed has no Pagar — a Lembrar instead', (tester) async {
    final ds = source()..expenses = [expense(1)]; // Ana paid; Bruno owes her
    await pump(tester, ds);
    expect(find.text(l.format(KApp.expenseHeadGets, [brl(5000)])), findsOne);
    expect(find.byKey(const ValueKey('expenses-pay-2')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('expenses-remind-2')));
    await tester.pumpAndSettle();
    expect(ds.expenseWrites, ['remind:2']);
    expect(find.text(l[KApp.expenseReminded]), findsOne);
  });

  testWidgets('a reminder the server refuses says why', (tester) async {
    final ds = source()
      ..expenses = [expense(1)]
      ..throwOnRemind = Exception(
          'PostgrestException(message: Você já lembrou essa pessoa há pouco. '
          'Um novo lembrete fica disponível 24 h depois do anterior., '
          'code: 23514, details: null, hint: null)');
    await pump(tester, ds);
    await tester.tap(find.byKey(const ValueKey('expenses-remind-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Você já lembrou essa pessoa'), findsOne);
  });

  testWidgets('an empty group: no balance, one main action', (tester) async {
    final ds = source();
    await pump(tester, ds);
    expect(find.byKey(const ValueKey('expenses-balance')), findsNothing);
    expect(find.byKey(const ValueKey('expenses-empty')), findsOne);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('expenses-add')))
            .onPressed,
        isNotNull);
  });

  testWidgets('the activity: expenses and payments, each with its effect on '
      'the reader', (tester) async {
    final ds = source()
      ..expenses = [expense(1), expense(2, paidBy: 2, desc: 'Tênis')]
      ..settlements = [
        ExpenseSettlement(
            id: 9,
            fromProfile: 2,
            toProfile: 1,
            amountCents: 2000,
            status: 'confirmed',
            createdAt: DateTime.utc(2026, 9, 20),
            answeredAt: DateTime.utc(2026, 9, 21)),
      ];
    await pump(tester, ds);
    // Ana paid Mensalidade: she lent Bruno his half. Bruno paid Tênis: her
    // share. Bruno's payment reached her.
    expect(find.text(l.format(KApp.expenseYouLent, [brl(5000)])), findsOne);
    expect(find.text(l.format(KApp.expenseYourShare, [brl(5000)])), findsOne);
    expect(find.byKey(const ValueKey('payment-9')), findsOne);
    expect(find.text(l[KApp.expenseYouReceived]), findsOne);

    await tester.tap(find.byKey(const ValueKey('expenses-filter-payments')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expense-1')), findsNothing);
    expect(find.byKey(const ValueKey('payment-9')), findsOne);
    await tester.tap(find.byKey(const ValueKey('expenses-filter-expenses')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('expense-1')), findsOne);
    expect(find.byKey(const ValueKey('payment-9')), findsNothing);
  });

  testWidgets('an expense written on the other phone shows up by itself',
      (tester) async {
    final ds = source()..expenses = [expense(1)];
    await pump(tester, ds);
    expect(find.text('Tênis'), findsNothing);
    ds.expenses = [...ds.expenses, expense(2, paidBy: 2, desc: 'Tênis')];
    ds.expenseListener!();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('Tênis'), findsOne);
    // 50 owed by Bruno, 50 owed to him: even.
    expect(find.text(l[KApp.expenseBalanceEven]), findsOne);
  });

  testWidgets('the receiver confirms, and only then the balance clears',
      (tester) async {
    final ds = source()
      ..expenses = [expense(1)]
      ..settlements = [
        ExpenseSettlement(
            id: 9,
            fromProfile: 2,
            toProfile: 1,
            amountCents: 5000,
            status: 'pending',
            createdAt: DateTime.utc(2026, 9, 20)),
      ];
    await pump(tester, ds);
    expect(
        find.text(l.format(KApp.expensePendingToMe, ['Bruno Lima', brl(5000)])),
        findsOne);
    await tester.tap(find.byKey(const ValueKey('settlement-confirm-9')));
    await tester.pumpAndSettle();
    expect(ds.expenseWrites, ['answer:9:true']);
    expect(find.text(l[KApp.expenseBalanceEven]), findsOne);
  });

  testWidgets('a new expense sends the split the reader chose',
      (tester) async {
    final ds = source();
    await pump(tester, ds);
    expect(find.byKey(const ValueKey('expenses-empty')), findsOne);

    await tester.tap(find.byKey(const ValueKey('expenses-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('expense-desc')), 'Consulta');
    await tester.enterText(
        find.byKey(const ValueKey('expense-amount')), '100,01');
    await tester.pump();
    // Equal: the odd cent goes to the lowest profile id — shown before saving.
    expect(find.text(l.format(KApp.expenseShareOf, [brl(5001)])), findsOne);

    await tester.tap(find.text(l[K.commonSave]));
    await tester.pumpAndSettle();
    expect(ds.expenseWrites, ['add:Consulta:other:10001:1:equal:1=1,2=1']);
    expect(find.text('Consulta'), findsOne);
  });

  testWidgets('percentages that do not add to 100% never reach the server',
      (tester) async {
    final ds = source();
    await pump(tester, ds);
    await tester.tap(find.byKey(const ValueKey('expenses-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('expense-desc')), 'Tênis');
    await tester.enterText(
        find.byKey(const ValueKey('expense-amount')), '200');
    await tester.tap(find.text(l[KApp.expenseSplitPercent]));
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('expense-value-1')), '50');
    await tester.enterText(find.byKey(const ValueKey('expense-value-2')), '40');
    await tester.tap(find.text(l[K.commonSave]));
    await tester.pumpAndSettle();
    expect(ds.expenseWrites, isEmpty);
    expect(find.text(l[KApp.expenseErrPercent]), findsWidgets);
  });

  testWidgets('without Premium the expenses are read-only, with the way in',
      (tester) async {
    final ds = source(plan: 'free')..expenses = [expense(1)];
    await pump(tester, ds);
    expect(find.byKey(const ValueKey('expenses-premium')), findsOne);
    expect(find.byKey(const ValueKey('expenses-add')), findsNothing);
    expect(find.byKey(const ValueKey('expenses-remind-2')), findsNothing);
    expect(find.text('Mensalidade'), findsOne);
  });

  testWidgets('flag off: no expense', (tester) async {
    await pump(tester, source(settings: const {}));
    expect(find.byKey(const ValueKey('expenses-off')), findsOne);
  });

  testWidgets('a viewer sees no expense', (tester) async {
    await pump(tester, source(members: const [vera, ana]));
    expect(find.byKey(const ValueKey('expenses-viewer')), findsOne);
  });

  testWidgets('a delete asks first and says what stays', (tester) async {
    final ds = source()..expenses = [expense(1)];
    await pump(tester, ds);
    await tester.tap(find.text('Mensalidade'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('expense-delete')));
    await tester.pumpAndSettle();
    expect(ds.expenseWrites, isEmpty);
    await tester.tap(find.text(l[KApp.expenseDelete]).last);
    await tester.pumpAndSettle();
    expect(ds.expenseWrites, ['delete:1']);
    expect(find.byKey(const ValueKey('expenses-empty')), findsOne);
  });

  test('an expense or settle-up notification opens Despesas', () {
    expect(NotificationsScreen.expenseTypes, {
      'expense_changed',
      'settlement_requested',
      'settlement_answered',
      'settlement_reminder',
    });
  });
}
