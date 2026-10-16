import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_billing.dart';

/// T-39 (PR2) — the billing-checkout guard chain, in order: 401 without a user
/// JWT (`verify_jwt` stays ON for this function), 403 for a non-admin member,
/// 409 while `billing.enabled` is false.
///
/// The Asaas key is deliberately NOT needed: every test stops at a guard that
/// fires BEFORE the gateway is touched, so the suite never creates a sandbox
/// subscription and never leaves a payment link behind.
///
/// Port of `db-gate/Entrelares.IntegrationTests/BillingCheckoutTests.cs`.
void billingCheckoutTests(GateFixture fx) {
  final billing = Billing(fx);

  group('BillingCheckoutTests', () {
    test('a checkout with no session is rejected by the platform', () async {
      final (status, _) =
          await billing.checkout({'action': 'checkout', 'cycle': 'monthly'}, null);
      expect(status, 401);
    });

    test('a non-admin member cannot start a checkout', () async {
      // The payer is an admin — F-40/T-39 keep billing admin-only throughout.
      final token = fx.member.auth.currentSession!.accessToken;
      final (status, body) = await billing
          .checkout({'action': 'checkout', 'cycle': 'monthly'}, token);
      expect(status, 403);
      expect(body, contains('administradores'));
    });

    test('the guard chain refuses whether billing is open or already bought',
        () async {
      // Asserted against a family that ALREADY has an active subscription, so
      // the test is deterministic in both environments — flag off → "assinaturas
      // não abertas"; flag on → "família já tem uma assinatura" — and NEVER
      // reaches the gateway. The first version assumed the flag was off and
      // broke the moment dev enabled billing for the sandbox QA.
      final fam = await fx.createFamily('t39co');
      await billing.seed(fam.familyId, 't39co', status: 'active');

      final token = fam.admin.auth.currentSession!.accessToken;
      final (status, body) = await billing
          .checkout({'action': 'checkout', 'cycle': 'monthly'}, token);
      expect(status, 409);
      expect(body, contains('assinatura')); // both refusal texts mention it
    });

    test('a cancel with no subscription fails cleanly', () async {
      // Guard order puts `enabled` BEFORE the row lookup, so with billing
      // disabled this is a 409 — the assert accepts the disabled answer too,
      // which keeps it honest in both dev states rather than passing for the
      // wrong reason in one of them.
      final token = fx.founder.auth.currentSession!.accessToken;
      final (status, _) = await billing.checkout({'action': 'cancel'}, token);
      expect(status, anyOf(404, 409),
          reason: 'expected 404 (no subscription) or 409 (billing disabled), '
              'got $status');
    });

    // F-84: a subscription bought through Google Play is Google's. Our
    // cancel used to flip only our row — Google kept charging while the app
    // said "Assinatura cancelada". The refusal comes BEFORE the master switch
    // and the gateway key, so it is asserted the same way in every state.
    for (final action in const ['cancel', 'reactivate', 'overdue_invoice']) {
      test('F-84: $action on a Play subscription is refused and changes nothing',
          () async {
        final fam = await fx.createFamily('f84${action.substring(0, 3)}');
        final seeded = await billing.seed(fam.familyId, 'f84$action',
            status: action == 'reactivate' ? 'canceled' : 'active',
            periodEnd: DateTime.now().toUtc().add(const Duration(days: 20)));
        await fx.service
            .from('subscriptions')
            .update({'gateway': 'play'}).eq('id', seeded.id);

        final token = fam.admin.auth.currentSession!.accessToken;
        final (status, body) =
            await billing.checkout({'action': action}, token);
        expect(status, 409);
        expect(body, contains('Google Play'));

        final after = await billing.reload(seeded.id);
        expect(after.status, seeded.status);
        expect(after.canceledAt, isNull);
      });
    }

    test('F-84: overdue_invoice answers the open invoice from the ledger',
        () async {
      final fam = await fx.createFamily('f84inv');
      await billing.seed(fam.familyId, 'f84inv',
          status: 'overdue', overdueSince: DateTime.now().toUtc());
      // An older charge that WAS paid afterwards, then the one still open.
      await billing.seedEvent(fam.familyId, 'PAYMENT_OVERDUE',
          paymentId: 'pay_f84_old',
          value: 5.49,
          invoiceUrl: 'https://sandbox.asaas.com/i/f84-old');
      await billing.seedEvent(fam.familyId, 'PAYMENT_RECEIVED',
          paymentId: 'pay_f84_old', value: 5.49);
      await billing.seedEvent(fam.familyId, 'PAYMENT_OVERDUE',
          paymentId: 'pay_f84_open',
          value: 5.49,
          invoiceUrl: 'https://sandbox.asaas.com/i/f84-open');

      final token = fam.admin.auth.currentSession!.accessToken;
      final (status, body) =
          await billing.checkout({'action': 'overdue_invoice'}, token);
      expect(status, 200, reason: body);
      expect(body, contains('https://sandbox.asaas.com/i/f84-open'));
    });

    test('F-84: overdue_invoice never hands back a charge already paid',
        () async {
      final fam = await fx.createFamily('f84paid');
      await billing.seed(fam.familyId, 'f84paid',
          status: 'overdue', overdueSince: DateTime.now().toUtc());
      await billing.seedEvent(fam.familyId, 'PAYMENT_OVERDUE',
          paymentId: 'pay_f84_paid',
          value: 5.49,
          invoiceUrl: 'https://sandbox.asaas.com/i/f84-paid');
      await billing.seedEvent(fam.familyId, 'PAYMENT_CONFIRMED',
          paymentId: 'pay_f84_paid', value: 5.49);

      final token = fam.admin.auth.currentSession!.accessToken;
      final (status, body) =
          await billing.checkout({'action': 'overdue_invoice'}, token);
      // The ledger has nothing open, so the gateway half runs — and in the
      // gate it stops at the switch (409), the missing key (503) or a gateway
      // that knows no such subscription (404). Never the paid invoice.
      expect(status, isNot(200));
      expect(body, isNot(contains('f84-paid')));
    });

    test('F-84: overdue_invoice refuses a subscription that is not overdue',
        () async {
      final fam = await fx.createFamily('f84act');
      await billing.seed(fam.familyId, 'f84act', status: 'active');
      final token = fam.admin.auth.currentSession!.accessToken;
      final (status, body) =
          await billing.checkout({'action': 'overdue_invoice'}, token);
      expect(status, 409);
      expect(body, contains('cobrança pendente'));
    });
  });
}
