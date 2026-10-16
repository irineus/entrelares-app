import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_billing.dart';
import '_helpers.dart';

/// F-43 — the payment-history RPC (`get_billing_history`):
///   · family ADMINS get a sanitized, family-scoped timeline, never the raw
///     ledger payloads;
///   · `CONFIRMED` + `RECEIVED` for the same gateway payment collapse to ONE
///     row — a payer who saw one charge must read one line;
///   · non-admins are refused by the DB itself;
///   · another family's events never leak.
///
/// Port of `db-gate/Entrelares.IntegrationTests/BillingHistoryTests.cs`.
void billingHistoryTests(GateFixture fx) {
  final billing = Billing(fx);

  Future<List<Map<String, dynamic>>> historyAs(SupabaseClient caller) async {
    final result = await caller.rpc<dynamic>('get_billing_history');
    return (result as List).cast<Map<String, dynamic>>();
  }

  group('BillingHistoryTests', () {
    test('an admin sees a sanitized timeline, with the duplicate collapsed',
        () async {
      final fam = await fx.createFamily('f43hist');

      await billing.seedEvent(fam.familyId, 'PAYMENT_CONFIRMED',
          paymentId: 'pay_h1',
          value: 14.90,
          billingType: 'PIX',
          invoiceUrl: 'https://sandbox.asaas.com/i/h1');
      await billing.seedEvent(fam.familyId, 'PAYMENT_RECEIVED',
          paymentId: 'pay_h1',
          value: 14.90,
          billingType: 'PIX',
          invoiceUrl: 'https://sandbox.asaas.com/i/h1');
      await billing.seedEvent(fam.familyId, 'PAYMENT_REFUNDED',
          paymentId: 'pay_h1', value: 14.90, billingType: 'PIX');
      await billing.seedEvent(fam.familyId, 'GRACE_DOWNGRADE');
      // Internal/ops events must never surface — the timeline is for a payer,
      // not for us.
      await billing.seedEvent(fam.familyId, 'CHECKOUT_ERROR');
      await billing.seedEvent(fam.familyId, 'PAYMENT_CREATED',
          paymentId: 'pay_h2');

      final rows = await historyAs(fam.admin);
      final categories = [for (final r in rows) r['category']];

      expect(rows, hasLength(3)); // payment (deduped) + refund + downgrade
      expect(categories.where((c) => c == 'payment'), hasLength(1));
      expect(categories, contains('refund'));
      expect(categories, contains('downgraded'));
      expect(categories, isNot(contains(null)));

      final payment = rows.firstWhere((r) => r['category'] == 'payment');
      expect((payment['amount'] as num).toDouble(), closeTo(14.90, 0.001));
      expect(payment['billing_type'], 'PIX');
      expect(payment['invoice_url'], 'https://sandbox.asaas.com/i/h1');
    });

    test('F-107: Play money is in the timeline — one row per Google order',
        () async {
      final fam = await fx.createFamily('f107play');
      var n = 0;
      Future<void> play(String type, {Map<String, dynamic>? purchase}) =>
          fx.service.from('billing_events').insert({
            'event_id': 'evt_e2e_f107_${fam.familyId}_${n++}',
            'event_type': type,
            'family_id': fam.familyId,
            'payload': {
              'subscriptionNotification': {'purchaseToken': 'tok-f107'},
              'purchase': ?purchase,
            },
          });
      Map<String, dynamic> paid(String orderId, {int state = 1}) => {
            'orderId': orderId,
            'priceAmountMicros': '5990000',
            'priceCurrencyCode': 'BRL',
            'paymentState': state,
          };

      // The purchase: verified by the app AND announced by RTDN 4 — one row.
      await play('PLAY_PURCHASE_VERIFIED', purchase: paid('GPA.1-2-3'));
      await play('PLAY_RTDN_4', purchase: paid('GPA.1-2-3'));
      // The first renewal — its own order.
      await play('PLAY_RTDN_2', purchase: paid('GPA.1-2-3..1'));
      // An RTDN from before F-107 carries no purchase: left out.
      await play('PLAY_RTDN_2');
      // A purchase still pending payment is no money.
      await play('PLAY_PURCHASE_VERIFIED',
          purchase: paid('GPA.9-9-9', state: 0));
      // Canceled, then expired.
      await play('PLAY_RTDN_3');
      await play('PLAY_RTDN_13');
      // Dunning stays out, as it was.
      await play('PLAY_RTDN_6');

      final rows = await historyAs(fam.admin);
      final payments = rows.where((r) => r['category'] == 'payment').toList();
      expect(payments, hasLength(2));
      for (final p in payments) {
        expect((p['amount'] as num).toDouble(), closeTo(5.99, 0.001));
        expect(p['billing_type'], 'PLAY');
        expect(p['invoice_url'], isNull);
      }
      expect(rows.where((r) => r['category'] == 'canceled'), hasLength(1));
      expect(rows.where((r) => r['category'] == 'downgraded'), hasLength(1));
      expect(rows, hasLength(4));
    });

    test('a non-admin is refused by the database itself', () async {
      final fam = await fx.createFamily('f43deny');
      await expectRejected(
          () => fam.member.rpc<dynamic>('get_billing_history'));
    });

    test("another family's events never leak", () async {
      final fam = await fx.createFamily('f43iso');
      await billing.seedEvent(fam.familyId, 'PAYMENT_CONFIRMED',
          paymentId: 'pay_iso', value: 14.90);

      expect(await historyAs(fx.founder), isEmpty);
    });
  });
}
