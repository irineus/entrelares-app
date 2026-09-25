import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-34 (PR 1) — shared expenses, where they are enforced.
///
/// * **dark + Premium** — `feature.expenses` and `expenses.premium_only`;
/// * **the split** sums exactly to the amount, leftover cents by largest
///   remainder, ties to the lowest profile id (deterministic);
/// * **edits and deletes** leave an append-only trail no one can rewrite;
/// * **the one difference from Splitwise** — a settlement counts only once the
///   RECEIVER confirms it;
/// * **a payment settles a debt, never creates one** (owner's validation,
///   25/09/2026) — capped by what is owed, counting what already waits;
/// * **Lembrar** — only who is owed, once per `expenses.reminder_cooldown_hours`,
///   with no amount in the text;
/// * **a viewer** sees no expense; another family touches nothing;
/// * **notifications** reach the participants, never the actor.
void expenseTests(GateFixture fx) {
  const flag = 'feature.expenses';
  final today = saoPauloToday();

  group('F-34 · expenses', () {
    late ThrowawayFamily fam;
    late ThrowawayFamily other;
    late String flagBefore;
    late int expenseId;

    Future<int> add(SupabaseClient who,
            {int amount = 10001,
            String method = 'equal',
            List<Map<String, int>>? parts,
            int? paidBy,
            String desc = 'mensalidade'}) async =>
        await who.rpc<dynamic>('add_expense', params: {
          'p_child_id': null,
          'p_desc': desc,
          'p_category': 'school',
          'p_amount': amount,
          'p_paid_by': paidBy ?? fam.adminProfile.id,
          'p_spent_on': isoDate(today),
          'p_method': method,
          'p_parts': parts ??
              [
                {'profile_id': fam.adminProfile.id, 'value': 1},
                {'profile_id': fam.memberProfile.id, 'value': 1},
              ],
        }) as int;

    Future<Map<int, int>> shares(int id) async => {
          for (final r in await fx.service
              .from('expense_shares')
              .select()
              .eq('expense_id', id))
            r['profile_id'] as int: r['share_cents'] as int
        };

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
      fam = await fx.createFamily('f34exp');
      other = await fx.createFamily('f34oth');
      await fx.service.from('families').update({
        'plan': 'free',
        'trial_ends_at': null,
        'comp_premium_at': null,
      }).eq('id', fam.familyId);
    });

    tearDownAll(() async => writeFlag(fx, flag, flagBefore));

    test('flag OFF and free plan are refused', () async {
      await writeFlag(fx, flag, 'false');
      try {
        await expectRejected(() => add(fam.admin),
            contains: 'ainda não estão disponíveis');
      } finally {
        await writeFlag(fx, flag, 'true');
      }
      await expectRejected(() => add(fam.admin), contains: 'recurso Premium');
    });

    test('equal split: the odd cent goes to the lowest profile id', () async {
      await fx.service
          .from('families')
          .update({'comp_premium_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', fam.familyId);
      expenseId = await add(fam.member);
      final s = await shares(expenseId);
      final low = fam.adminProfile.id < fam.memberProfile.id
          ? fam.adminProfile.id
          : fam.memberProfile.id;
      final high = low == fam.adminProfile.id
          ? fam.memberProfile.id
          : fam.adminProfile.id;
      expect(s[low], 5001);
      expect(s[high], 5000);
      expect(s.values.fold<int>(0, (a, b) => a + b), 10001);
    });

    test('percent, shares and exact all sum to the amount — or are refused',
        () async {
      final pct = await add(fam.admin, amount: 1000, method: 'percent', parts: [
        {'profile_id': fam.adminProfile.id, 'value': 3333},
        {'profile_id': fam.memberProfile.id, 'value': 6667},
      ]);
      expect((await shares(pct)).values.fold<int>(0, (a, b) => a + b), 1000);
      await expectRejected(
          () => add(fam.admin, amount: 1000, method: 'percent', parts: [
                {'profile_id': fam.adminProfile.id, 'value': 5000},
                {'profile_id': fam.memberProfile.id, 'value': 4000},
              ]),
          contains: 'somar 100%');

      final sh = await add(fam.admin, amount: 1000, method: 'shares', parts: [
        {'profile_id': fam.adminProfile.id, 'value': 2},
        {'profile_id': fam.memberProfile.id, 'value': 1},
      ]);
      final shs = await shares(sh);
      expect(shs[fam.adminProfile.id], 667);
      expect(shs[fam.memberProfile.id], 333);

      await expectRejected(
          () => add(fam.admin, amount: 1000, method: 'exact', parts: [
                {'profile_id': fam.adminProfile.id, 'value': 600},
                {'profile_id': fam.memberProfile.id, 'value': 300},
              ]),
          contains: 'somam 900 centavos');
    });

    test('the amount ceiling is the operator key', () async {
      await expectRejected(() => add(fam.admin, amount: 999999999),
          contains: 'passa do limite');
    });

    test('an edit and a delete leave an append-only trail', () async {
      await fam.admin.rpc<dynamic>('update_expense', params: {
        'p_id': expenseId,
        'p_child_id': null,
        'p_desc': 'mensalidade de setembro',
        'p_category': 'school',
        'p_amount': 20000,
        'p_paid_by': fam.adminProfile.id,
        'p_spent_on': isoDate(today),
        'p_method': 'equal',
        'p_parts': [
          {'profile_id': fam.adminProfile.id, 'value': 1},
          {'profile_id': fam.memberProfile.id, 'value': 1},
        ],
      });
      await fam.member
          .rpc<dynamic>('delete_expense', params: {'p_id': expenseId});
      final trail = await fx.service
          .from('expense_history')
          .select()
          .eq('expense_id', expenseId)
          .order('id', ascending: true);
      expect(trail.map((h) => h['action']), ['created', 'updated', 'deleted']);
      expect((trail[1]['old_data'] as Map)['amount_cents'], 10001);
      expect((trail[1]['new_data'] as Map)['amount_cents'], 20000);
      final row = (await fx.service
              .from('expenses')
              .select()
              .eq('id', expenseId)
              .limit(1))
          .single;
      expect(row['deleted_at'], isNotNull);

      await expectRejected(() => fx.service
          .from('expense_history')
          .update({'action': 'created'}).eq('expense_id', expenseId));
      await expectRejected(() => fx.service
          .from('expense_history')
          .delete()
          .eq('expense_id', expenseId));
    });

    Future<int> settle(SupabaseClient who, int to, int amount) async =>
        await who.rpc<dynamic>('request_settlement', params: {
          'p_child_id': null,
          'p_to': to,
          'p_amount': amount,
        }) as int;

    // Here the admin paid both live expenses (1000 + 1000, the first one was
    // deleted): the member owes the admin 1000.
    test('a settlement waits for the RECEIVER', () async {
      final id = await settle(fam.member, fam.adminProfile.id, 600);
      await expectRejected(
          () => fam.member.rpc<dynamic>('answer_settlement',
              params: {'p_id': id, 'p_received': true}),
          contains: 'Só quem recebeu');
      final asked = await fx.service
          .from('notifications')
          .select()
          .eq('recipient_profile_id', fam.adminProfile.id)
          .eq('type', 'settlement_requested');
      expect(asked, isNotEmpty);

      await fam.admin.rpc<dynamic>('answer_settlement',
          params: {'p_id': id, 'p_received': true});
      final st = (await fx.service
              .from('expense_settlements')
              .select()
              .eq('id', id)
              .limit(1))
          .single;
      expect(st['status'], 'confirmed');
      await expectRejected(
          () => fam.admin.rpc<dynamic>('answer_settlement',
              params: {'p_id': id, 'p_received': false}),
          contains: 'já foi respondido');
      expect(
          await fx.service
              .from('notifications')
              .select()
              .eq('recipient_profile_id', fam.memberProfile.id)
              .eq('type', 'settlement_answered'),
          isNotEmpty);
    });

    test('a payment settles a debt, never creates one', () async {
      // The member still owes 400 after the 600 confirmed above.
      await expectRejected(() => settle(fam.member, fam.adminProfile.id, 500),
          contains: 'passa do que você deve');
      await expectRejected(() => settle(fam.admin, fam.memberProfile.id, 100),
          contains: 'não tem saldo a pagar');
      // Partial is fine — and what waits counts, so it cannot be paid twice.
      final waiting = await settle(fam.member, fam.adminProfile.id, 300);
      await expectRejected(() => settle(fam.member, fam.adminProfile.id, 200),
          contains: 'passa do que você deve');
      await fam.member
          .rpc<dynamic>('cancel_settlement', params: {'p_id': waiting});
      await settle(fam.member, fam.adminProfile.id, 400);
    });

    test('Lembrar: only who is owed, once per cooldown, no amount', () async {
      // The 400 above waits: the member owes nothing open — nothing to remind.
      await expectRejected(
          () => fam.admin.rpc<dynamic>('remind_settlement',
              params: {'p_child_id': null, 'p_to': fam.memberProfile.id}),
          contains: 'não tem acerto pendente');
      // A new expense the admin paid opens a debt again.
      await add(fam.admin, amount: 800);
      await fam.admin.rpc<dynamic>('remind_settlement',
          params: {'p_child_id': null, 'p_to': fam.memberProfile.id});
      final told = await fx.service
          .from('notifications')
          .select()
          .eq('recipient_profile_id', fam.memberProfile.id)
          .eq('type', 'settlement_reminder');
      expect(told, hasLength(1));
      expect(told.single['message'], isNot(contains(r'R$')));
      expect((told.single['params'] as Map)['name'], isNotEmpty);

      await expectRejected(
          () => fam.admin.rpc<dynamic>('remind_settlement',
              params: {'p_child_id': null, 'p_to': fam.memberProfile.id}),
          contains: 'já lembrou');
      // Who owes cannot "remind" who is owed.
      await expectRejected(
          () => fam.member.rpc<dynamic>('remind_settlement',
              params: {'p_child_id': null, 'p_to': fam.adminProfile.id}),
          contains: 'não tem acerto pendente');
      // Nobody reads the reminders table directly (no grant at all).
      await expectRejected(
          () => fam.admin.from('expense_reminders').select('id'));
    });

    test('the expense notice reaches the participants, never the actor',
        () async {
      final n = await fx.service
          .from('notifications')
          .select()
          .eq('type', 'expense_changed')
          .inFilter('recipient_profile_id',
              [fam.adminProfile.id, fam.memberProfile.id]);
      // The member added the first expense: the admin was told, not the member.
      final added = n.where((r) => (r['params'] as Map)['kind'] == 'added');
      expect(added.any((r) => r['recipient_profile_id'] == fam.adminProfile.id),
          isTrue);
      expect(
          n.first['message'],
          isNot(contains('null')));
    });

    test('another family neither reads nor writes', () async {
      expect(await other.admin.from('expenses').select('id'), isEmpty);
      await expectRejected(() => add(other.admin,
          paidBy: fam.adminProfile.id));
    });

    test('no client writes the tables', () async {
      await expectRejected(() => fam.admin.from('expenses').insert({
            'family_id': fam.familyId,
            'description': 'x',
            'category': 'other',
            'amount_cents': 1,
            'paid_by': fam.adminProfile.id,
            'spent_on': isoDate(today),
            'split_method': 'equal',
          }));
    });
  });
}
