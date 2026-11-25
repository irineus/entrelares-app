import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_billing.dart';
import '_helpers.dart';

/// T-111 — the operator hears of every sale event, once, with no family data.
///
/// Owner, 25/11/2026: a first purchase, a renewal, a cancellation and a refund
/// each send ONE e-mail to the operator inbox; test purchases are tagged; the
/// key `ops.sale_alert.enabled` turns it off. What the gate can see is the
/// ledger `sale_alerts`, written by `claim_sale_alert` before every send:
///   · ledger and claim are service-role only;
///   · one claim per key — the Asaas CONFIRMED + RECEIVED of one payment, and
///     the DELETED + INACTIVATED of one cancellation, alert once;
///   · the first paid invoice of a gateway subscription is a purchase, the
///     next a renewal;
///   · switched off, the money is still applied and nothing is claimed;
///   · a row carries a CLOSED set of columns — no family, member or e-mail.
/// The stack's operator inbox is on `@resend.dev` (`tool/db_gate_local.sh`),
/// so the send stops at `_shared/mail.ts` and `sent_at` is stamped. The Play
/// paths need the Google API and are not driven here; they share the claim and
/// its key rules (the Google order id), which the RPC cases below pin.
void saleAlertTests(GateFixture fx) {
  final billing = Billing(fx);
  const switchKey = 'ops.sale_alert.enabled';

  Future<List<Map<String, dynamic>>> rowsFor(String key) async =>
      List<Map<String, dynamic>>.from(
          await fx.service.from('sale_alerts').select().eq('sale_key', key));

  Future<bool> claim(String key, {String kind = 'purchase'}) async =>
      (await fx.service.rpc<dynamic>('claim_sale_alert', params: {
        'p_sale_key': key,
        'p_rail': 'play',
        'p_kind': kind,
        'p_cycle': 'monthly',
        'p_amount_cents': 599,
        'p_currency': 'BRL',
        'p_is_test': true,
      })) ==
      true;

  group('SaleAlertTests (T-111)', () {
    test('the ledger and the claim are the service role\'s alone', () async {
      // No grant at all for a client role: a read is REFUSED (42501), which is
      // stronger than RLS answering an empty list.
      await expectRejected(() => fx.founder.from('sale_alerts').select());
      await expectRejected(() => fx.founder.rpc<dynamic>('claim_sale_alert',
              params: {
                'p_sale_key': 'gate:t111:client-${fx.runId}',
                'p_rail': 'play',
                'p_kind': 'purchase',
                'p_cycle': 'monthly',
                'p_amount_cents': 1,
                'p_currency': 'BRL',
                'p_is_test': false,
              }));
      expect(await rowsFor('gate:t111:client-${fx.runId}'), isEmpty);
    });

    test('the switch is seeded ON, server-only, and explained', () async {
      final row = (await fx.service
              .from('app_settings')
              .select('value, value_type, is_public, category, help')
              .eq('key', switchKey))
          .single;
      expect(row['value'], 'true');
      expect(row['value_type'], 'bool');
      expect(row['is_public'], isFalse);
      expect(row['category'], 'operator');
      expect((row['help'] as Map)['controls'], isNotEmpty);
    });

    test('one claim per key; switched off, nothing is claimed', () async {
      final key = 'play:order:GPA.gate-${fx.runId}';
      expect(await claim(key), isTrue);
      // The RTDN of the same period, or a re-verify: same order, no 2nd mail.
      expect(await claim(key), isFalse);
      final rows = await rowsFor(key);
      expect(rows, hasLength(1));
      expect(rows.single['is_test'], isTrue);
      expect(rows.single['amount_cents'], 599);

      final before = await readFlag(fx, switchKey);
      await writeFlag(fx, switchKey, 'false');
      try {
        final off = 'play:order:GPA.gate-off-${fx.runId}';
        expect(await claim(off), isFalse);
        expect(await rowsFor(off), isEmpty);
      } finally {
        await writeFlag(fx, switchKey, before);
      }
    });

    test('a claim refuses a value outside the closed vocabularies', () async {
      await expectRejected(() => fx.service.rpc<dynamic>('claim_sale_alert',
              params: {
                'p_sale_key': 'gate:t111:bad-${fx.runId}',
                'p_rail': 'paypal',
                'p_kind': 'purchase',
                'p_cycle': 'monthly',
                'p_amount_cents': 1,
                'p_currency': 'BRL',
                'p_is_test': false,
              }));
    });

    test('a row carries a closed set of columns — no family data', () async {
      final key = 'play:order:GPA.gate-cols-${fx.runId}';
      await claim(key);
      expect((await rowsFor(key)).single.keys.toSet(), {
        'sale_key',
        'rail',
        'kind',
        'cycle',
        'amount_cents',
        'currency',
        'is_test',
        'created_at',
        'sent_at',
      });
    });

    test('Asaas: a payment alerts once as a purchase, the next as a renewal',
        () async {
      final token = Billing.webhookToken;
      if (token == null) return; // armed by E2E_ASAAS_WEBHOOK_TOKEN

      final fam = await fx.createFamily('t111buy');
      final sub = await billing.seed(fam.familyId, 't111buy', priceCents: 549);
      final now = DateTime.now().toUtc();
      final due = isoDate(DateTime.utc(now.year, now.month, now.day));
      final first = 'pay_t111_a_${billing.uniqueEventSuffix()}';
      final second = 'pay_t111_b_${billing.uniqueEventSuffix()}';

      Future<void> pay(String event, String paymentId) async {
        final (status, body) = await billing.webhook({
          'id': 'evt_e2e_${billing.uniqueEventSuffix()}',
          'event': event,
          'payment': {
            'id': paymentId,
            'subscription': sub.externalSubscriptionId,
            'value': 5.49,
            'dueDate': due,
          },
        }, token);
        expect(status, 200, reason: body);
      }

      // A card charge: CONFIRMED, then RECEIVED for the SAME payment.
      await pay('PAYMENT_CONFIRMED', first);
      await pay('PAYMENT_RECEIVED', first);
      final bought = await rowsFor('asaas:pay:$first');
      expect(bought, hasLength(1));
      expect(bought.single['rail'], 'asaas');
      expect(bought.single['kind'], 'purchase');
      expect(bought.single['cycle'], 'monthly');
      expect(bought.single['amount_cents'], 549);
      expect(bought.single['currency'], 'BRL');
      expect(bought.single['is_test'], isFalse);
      expect(bought.single['sent_at'], isNotNull,
          reason: 'the @resend.dev operator inbox counts as sent');

      // The next invoice of the same gateway subscription.
      await pay('PAYMENT_RECEIVED', second);
      final renewed = await rowsFor('asaas:pay:$second');
      expect(renewed, hasLength(1));
      expect(renewed.single['kind'], 'renewal');
    });

    test('Asaas: a refund and a cancellation alert once each', () async {
      final token = Billing.webhookToken;
      if (token == null) return; // armed by E2E_ASAAS_WEBHOOK_TOKEN

      final fam = await fx.createFamily('t111end');
      final sub = await billing.seed(fam.familyId, 't111end', priceCents: 549);
      final now = DateTime.now().toUtc();
      final paymentId = 'pay_t111_r_${billing.uniqueEventSuffix()}';

      Future<void> send(Map<String, dynamic> payload) async {
        final (status, body) = await billing.webhook({
          'id': 'evt_e2e_${billing.uniqueEventSuffix()}',
          ...payload,
        }, token);
        expect(status, 200, reason: body);
      }

      await send({
        'event': 'PAYMENT_CONFIRMED',
        'payment': {
          'id': paymentId,
          'subscription': sub.externalSubscriptionId,
          'value': 5.49,
          'dueDate': isoDate(DateTime.utc(now.year, now.month, now.day)),
        },
      });
      await send({
        'event': 'PAYMENT_REFUNDED',
        'payment': {
          'id': paymentId,
          'subscription': sub.externalSubscriptionId,
          'value': 5.49,
        },
      });
      final refund = await rowsFor('asaas:refund:$paymentId');
      expect(refund, hasLength(1));
      expect(refund.single['kind'], 'refund');
      expect(refund.single['amount_cents'], 549);

      // Asaas sends BOTH for one cancellation.
      for (final event in ['SUBSCRIPTION_DELETED', 'SUBSCRIPTION_INACTIVATED']) {
        await send({
          'event': event,
          'subscription': {'id': sub.externalSubscriptionId},
        });
      }
      final canceled = await rowsFor('asaas:cancel:${sub.externalSubscriptionId}');
      expect(canceled, hasLength(1));
      expect(canceled.single['kind'], 'canceled');
      expect(canceled.single['amount_cents'], isNull);
    });

    test('switched off, a payment is applied and nothing is claimed',
        () async {
      final token = Billing.webhookToken;
      if (token == null) return; // armed by E2E_ASAAS_WEBHOOK_TOKEN

      final fam = await fx.createFamily('t111off');
      final sub = await billing.seed(fam.familyId, 't111off', priceCents: 549);
      await billing.setPlan(fam.familyId, 'free');
      final now = DateTime.now().toUtc();
      final paymentId = 'pay_t111_off_${billing.uniqueEventSuffix()}';

      final before = await readFlag(fx, switchKey);
      await writeFlag(fx, switchKey, 'false');
      try {
        final (status, body) = await billing.webhook({
          'id': 'evt_e2e_${billing.uniqueEventSuffix()}',
          'event': 'PAYMENT_CONFIRMED',
          'payment': {
            'id': paymentId,
            'subscription': sub.externalSubscriptionId,
            'value': 5.49,
            'dueDate': isoDate(DateTime.utc(now.year, now.month, now.day)),
          },
        }, token);
        expect(status, 200, reason: body);
      } finally {
        await writeFlag(fx, switchKey, before);
      }
      expect(await billing.isPremium(fam.familyId), isTrue);
      expect(await rowsFor('asaas:pay:$paymentId'), isEmpty);
    });
  });
}
