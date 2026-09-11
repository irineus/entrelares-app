// The Premium section of the Família page — the T-39 state machine on screen.
//
// What makes this worth its own suite: the six blocks say different things
// about MONEY, and the wrong one is not a cosmetic bug. A canceled family that
// still has paid time must see the date it runs to (and that renewing adds to
// it); an overdue one must see the real grace deadline, or the promise of
// access past it; a store-channel family must see NO price and NO checkout
// link at all (Play's payments policy). The channel is a build fact, so the
// screen takes it as a parameter here to exercise both rails on the VM.
import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:entrelares_app/services/analytics_service.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/subscription.dart';
import 'package:entrelares_app/screens/family_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const _admin = Member(
  id: 1,
  fullName: 'Ana Souza',
  colorSlot: 1,
  userId: 'u1',
  isAdmin: true,
  roleId: 1,
  email: 'ana@example.com',
);
const _plain = Member(
  id: 2,
  fullName: 'Bruno Lima',
  colorSlot: 2,
  userId: 'u2',
  roleId: 2,
  email: 'bruno@example.com',
);

/// Billing ON with the F-48 promotional prices — the production shape since
/// the master switch was flipped.
const _billingOn = {
  'billing.enabled': 'true',
  'billing.price_monthly_cents': '549',
  'billing.price_annual_cents': '5490',
  'billing.grace_days': '7',
};

FakeCustodyDataSource _source({
  String plan = 'free',
  DateTime? trialEndsAt,
  DateTime? compPremiumAt,
  Subscription? subscription,
  Map<String, String> settings = _billingOn,
  bool premiumInterest = false,
  List<Member> members = const [_admin, _plain],
}) {
  final ds = FakeCustodyDataSource(members: members, days: [])
    ..family = Family(
      id: 7,
      name: 'Souza',
      plan: plan,
      trialEndsAt: trialEndsAt,
      compPremiumAt: compPremiumAt,
    )
    ..roles = const [Role(id: 1, roleName: 'mother'), Role(id: 2, roleName: 'father')]
    ..publicSettings = settings
    ..subscription = subscription
    ..premiumInterest = premiumInterest;
  return ds;
}

Subscription _subscription({
  String status = 'active',
  String cycle = 'monthly',
  int priceCents = 549,
  DateTime? currentPeriodEnd,
  DateTime? overdueSince,
  String? billingType,
  String? externalCustomerId,
  bool singleCharge = false,
}) =>
    Subscription(
      id: 1,
      familyId: 7,
      status: status,
      cycle: cycle,
      priceCents: priceCents,
      currentPeriodEnd: currentPeriodEnd,
      overdueSince: overdueSince,
      billingType: billingType,
      externalCustomerId: externalCustomerId,
      singleCharge: singleCharge,
    );

/// Every sentence in this section may carry inline emphasis, so the expected
/// text is compared against the STRIPPED catalog entry — `<strong>` is markup
/// for the reader, never characters on screen.
Finder _text(String value) => find.text(stripRichText(value));

/// The funnel events this screen fires, captured through the REAL service so
/// the props travel exactly as they would in production (channel included).
class _Funnel {
  final List<Map<String, dynamic>> payloads = [];

  late final AnalyticsService service = AnalyticsService(
    websiteId: 'site-1',
    host: 'https://umami.example',
    hostname: 'app.entrelares.app',
    client: MockClient((request) async {
      payloads.add((jsonDecode(request.body) as Map<String, dynamic>)['payload']
          as Map<String, dynamic>);
      return http.Response('', 200);
    }),
  );

  Map<String, dynamic>? event(String name) {
    for (final payload in payloads) {
      if (payload['name'] == name) return payload;
    }
    return null;
  }

  Map<String, dynamic>? dataOf(String name) =>
      event(name)?['data'] as Map<String, dynamic>?;

  int count(String name) =>
      payloads.where((p) => p['name'] == name).length;
}

Future<void> _pump(
  WidgetTester tester,
  FakeCustodyDataSource ds, {
  bool store = false,
  AppLanguage language = AppLanguage.ptBr,
  _Funnel? funnel,
  List<String>? opened,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(language),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: FamilyScreen(
        dataSource: ds,
        adminMode: AdminMode(),
        sudo: SudoService(ds),
        isStoreChannel: store,
        analytics: funnel?.service,
        openExternal: opened == null
            ? (_) async {}
            : (url) async => opened.add(url),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);
  final now = DateTime.now().toUtc();

  group('badge', () {
    testWidgets('a trial family shows the countdown AND the end date',
        (tester) async {
      // U-22: the countdown alone hid the date; both come from trial_ends_at.
      final trialEnd = now.add(const Duration(days: 12));
      await _pump(tester, _source(trialEndsAt: trialEnd));

      final until =
          l.format(K.premBadgeTrialUntil, [l.formatDate(trialEnd.toLocal())]);
      expect(_text(l.format(K.premBadgeTrialMany, [12, until])), findsOne);
    });

    testWidgets('grandfathered premium says so instead of showing a bare badge',
        (tester) async {
      await _pump(tester, _source(plan: 'premium'));

      expect(_text(l[K.premBadgeForever]), findsOne);
      expect(find.textContaining(l[K.premBadgeActive]), findsNothing);
    });

    testWidgets('a free family that HAD a trial is told when it ended',
        (tester) async {
      final trialEnd = now.subtract(const Duration(days: 3));
      await _pump(tester, _source(trialEndsAt: trialEnd));

      expect(_text(l[K.premBadgeFree]), findsOne);
      expect(
        _text(
            l.format(K.premExpiredTrial, [l.formatDate(trialEnd.toLocal())])),
        findsOne,
      );
    });

    testWidgets('a lapsed payer gets the paid wording, not the trial one',
        (tester) async {
      final paidEnd = now.subtract(const Duration(days: 2));
      await _pump(
        tester,
        _source(
            subscription: _subscription(
                status: 'canceled', currentPeriodEnd: paidEnd)),
      );

      expect(
        _text(
            l.format(K.premExpiredPaid, [l.formatDate(paidEnd.toLocal())])),
        findsOne,
      );
    });
  });

  group('state machine', () {
    testWidgets('billing off shows the F-32 waitlist, whatever else is true',
        (tester) async {
      await _pump(
        tester,
        _source(
          settings: const {'billing.enabled': 'false'},
          subscription: _subscription(status: 'active'),
        ),
      );

      expect(_text(l[K.premInterestWant]), findsOne);
      expect(_text(l[K.premInterestHint]), findsOne);
      // No management surface while the switch is off.
      expect(_text(l[K.premCancelButton]), findsNothing);
    });

    testWidgets('the waitlist button registers interest and flips to done',
        (tester) async {
      final ds = _source(settings: const {'billing.enabled': 'false'});
      await _pump(tester, ds);

      await tester.tap(_text(l[K.premInterestWant]));
      await tester.pumpAndSettle();

      expect(ds.registeredInterest, ['family']);
      expect(_text(l[K.premInterestDone]), findsOne);
    });

    testWidgets('an active subscription shows cycle, price and renewal',
        (tester) async {
      final renews = now.add(const Duration(days: 20));
      await _pump(
        tester,
        _source(
          plan: 'premium',
          subscription: _subscription(
              status: 'active', priceCents: 549, currentPeriodEnd: renews),
        ),
      );

      expect(
        _text(l.format(K.premActiveStatus,
            [l[K.premCycleMonthly], 'R\$ 5,49'])),
        findsOne,
      );
      expect(
        _text(
            l.format(K.premActiveRenews, [l.formatDate(renews.toLocal())])),
        findsOne,
      );
    });

    testWidgets('cancel asks first, promises the paid time, then calls',
        (tester) async {
      final paidEnd = now.add(const Duration(days: 20));
      final ds = _source(
        plan: 'premium',
        subscription:
            _subscription(status: 'active', currentPeriodEnd: paidEnd),
      );
      await _pump(tester, ds);

      await tester.tap(_text(l[K.premCancelButton]));
      await tester.pumpAndSettle();
      expect(
        _text(l.format(
            K.premCancelWarningUntil, [l.formatDate(paidEnd.toLocal())])),
        findsOne,
      );
      expect(ds.cancelCalls, 0);

      await tester.tap(_text(l[K.premCancelConfirm]));
      await tester.pump();
      expect(ds.cancelCalls, 1);
      expect(_text(l[K.famSubscriptionCancelled]), findsOne);
    });

    testWidgets('a non-admin never sees the cancel button', (tester) async {
      await _pump(
        tester,
        _source(
          plan: 'premium',
          members: const [_plain, _admin],
          subscription: _subscription(status: 'active'),
        ),
      );

      expect(_text(l[K.premCancelButton]), findsNothing);
    });

    testWidgets('overdue inside the window promises access until the deadline',
        (tester) async {
      final since = now.subtract(const Duration(days: 2));
      await _pump(
        tester,
        _source(
          plan: 'premium',
          subscription:
              _subscription(status: 'overdue', overdueSince: since),
        ),
      );

      final deadline = since.add(const Duration(days: 7));
      expect(
        _text(
            l.format(K.premOverdueInGrace, [l.formatDate(deadline.toLocal())])),
        findsOne,
      );
    });

    testWidgets('overdue past the window stops promising access',
        (tester) async {
      // The cron already downgraded; the status stays 'overdue' so a late
      // payment still reactivates, and the old copy would be a lie.
      final since = now.subtract(const Duration(days: 30));
      await _pump(
        tester,
        _source(
            subscription:
                _subscription(status: 'overdue', overdueSince: since)),
      );

      final deadline = since.add(const Duration(days: 7));
      expect(
        _text(l.format(
            K.premOverdueGraceEnded, [l.formatDate(deadline.toLocal())])),
        findsOne,
      );
    });

    testWidgets('scheduled says nothing was charged and when it will be',
        (tester) async {
      final dueAt = now.add(const Duration(days: 9));
      await _pump(
        tester,
        _source(
          plan: 'premium',
          subscription: _subscription(
            status: 'scheduled',
            currentPeriodEnd: dueAt,
            billingType: 'PIX',
            priceCents: 549,
          ),
        ),
      );

      expect(_text(l[K.premScheduledStatus]), findsOne);
      expect(
        _text(l.format(K.premScheduledDetailMethod, [
          l.formatDate(dueAt.toLocal()),
          'R\$ 5,49',
          l[K.premCycleMonthly],
          l[K.premMethodPix],
        ])),
        findsOne,
      );
    });
  });

  group('offer — canceled but still paid', () {
    testWidgets('states the date and that renewing is additive',
        (tester) async {
      final paidUntilDate = now.add(const Duration(days: 20));
      await _pump(
        tester,
        _source(
          plan: 'premium',
          subscription: _subscription(
              status: 'canceled', currentPeriodEnd: paidUntilDate),
        ),
      );

      // The QA regression: this family must NOT land on premiumForever, which
      // would hide both the date and the way back.
      expect(
        _text(l.format(
            K.premPaidUntilPeriod, [l.formatDate(paidUntilDate.toLocal())])),
        findsOne,
      );
      expect(_text(l[K.premBadgeForever]), findsNothing);
    });

    testWidgets('an avulso row gets the no-recurrence wording', (tester) async {
      final paidUntilDate = now.add(const Duration(days: 20));
      await _pump(
        tester,
        _source(
          plan: 'premium',
          subscription: _subscription(
            status: 'canceled',
            currentPeriodEnd: paidUntilDate,
            singleCharge: true,
          ),
        ),
      );

      expect(
        _text(l.format(
            K.premPaidUntilAvulso, [l.formatDate(paidUntilDate.toLocal())])),
        findsOne,
      );
    });

    testWidgets('the near lapse is announced next to the way back',
        (tester) async {
      final paidUntilDate = now.add(const Duration(days: 3));
      await _pump(
        tester,
        _source(
          plan: 'premium',
          subscription: _subscription(
            status: 'canceled',
            currentPeriodEnd: paidUntilDate,
            billingType: 'PIX',
            externalCustomerId: 'cus_1',
          ),
        ),
      );

      expect(_text(l.format(K.premExpiringSoonMany, [3])), findsOne);
      expect(_text(l[K.premReactivateButton]), findsOne);
    });

    testWidgets('F-42: Pix gets the way back with the date-and-method hint',
        (tester) async {
      final paidUntilDate = now.add(const Duration(days: 20));
      final ds = _source(
        plan: 'premium',
        subscription: _subscription(
          status: 'canceled',
          currentPeriodEnd: paidUntilDate,
          billingType: 'PIX',
          externalCustomerId: 'cus_1',
        ),
      );
      await _pump(tester, ds);

      expect(
        _text(l.format(K.premReactivateHintMethodDate, [
          'R\$ 5,49',
          l[K.premCycleMonthly],
          l[K.premMethodPix],
          l.formatDate(paidUntilDate.toLocal()),
        ])),
        findsOne,
      );

      await tester.tap(_text(l[K.premReactivateButton]));
      await tester.pumpAndSettle();
      expect(ds.reactivateCalls, 1);
    });

    testWidgets('F-42: a card family is never offered the way back',
        (tester) async {
      // Resuming an auto-debit needs a token the hosted flow never holds, and
      // the server would refuse — so the button must not exist.
      await _pump(
        tester,
        _source(
          plan: 'premium',
          subscription: _subscription(
            status: 'canceled',
            currentPeriodEnd: now.add(const Duration(days: 20)),
            billingType: 'CREDIT_CARD',
            externalCustomerId: 'cus_1',
          ),
        ),
      );

      expect(_text(l[K.premReactivateButton]), findsNothing);
    });

    testWidgets('a refusal shows the SERVER text, not a generic one',
        (tester) async {
      final ds = _source(
        plan: 'premium',
        subscription: _subscription(
          status: 'canceled',
          currentPeriodEnd: now.add(const Duration(days: 20)),
          billingType: 'PIX',
          externalCustomerId: 'cus_1',
        ),
      )..throwOnBillingAction =
          const BillingRefused('Sua assinatura tinha cartão; refaça a compra.');
      await _pump(tester, ds);

      await tester.tap(_text(l[K.premReactivateButton]));
      await tester.pumpAndSettle();

      expect(_text('Sua assinatura tinha cartão; refaça a compra.'),
          findsOne);
    });

    testWidgets('a member who is not admin is told who can pay', (tester) async {
      await _pump(tester, _source(members: const [_plain, _admin]));

      expect(_text(l[K.premAdminOnly]), findsOne);
    });

    testWidgets('F-46: paying during the trial starts the cycle at trial end',
        (tester) async {
      final trialEnd = now.add(const Duration(days: 10));
      await _pump(tester, _source(trialEndsAt: trialEnd));

      expect(
        _text(
            l.format(K.premTrialAdditive, [l.formatDate(trialEnd.toLocal())])),
        findsOne,
      );
    });
  });

  group('store channel (T-38)', () {
    testWidgets('the offer collapses into the neutral note — no price, no link',
        (tester) async {
      await _pump(tester, _source(), store: true);

      expect(_text(l[K.premStoreNote]), findsOne);
      // Nothing that steers to an external purchase, and no price anywhere in
      // the offer: this is what keeps the Play listing compliant.
      expect(_text(l[K.premReactivateButton]), findsNothing);
      expect(find.textContaining('R\$'), findsNothing);
    });

    testWidgets('a store family still learns until when it is covered',
        (tester) async {
      final paidUntilDate = now.add(const Duration(days: 20));
      await _pump(
        tester,
        _source(
          plan: 'premium',
          subscription: _subscription(
              status: 'canceled', currentPeriodEnd: paidUntilDate),
        ),
        store: true,
      );

      expect(
        _text(l.format(K.premStorePaidUntilPeriod,
            [l.formatDate(paidUntilDate.toLocal())])),
        findsOne,
      );
    });

    testWidgets('a store family on trial sees the trial end, no CTA',
        (tester) async {
      final trialEnd = now.add(const Duration(days: 8));
      await _pump(tester, _source(trialEndsAt: trialEnd), store: true);

      expect(
        _text(l.format(
            K.premStoreTrialUntil, [l.formatDate(trialEnd.toLocal())])),
        findsOne,
      );
      expect(_text(l[K.premTrialAdditive]), findsNothing);
    });
  });

  group('checkout rails (web)', () {
    testWidgets('the monthly subscription leaves for the gateway URL',
        (tester) async {
      final ds = _source();
      final funnel = _Funnel();
      final opened = <String>[];
      await _pump(tester, ds, funnel: funnel, opened: opened);

      await tester.tap(_text(l.format(K.premSubscribeMonthly, ['R\$ 5,49'])));
      await tester.pumpAndSettle();

      expect(ds.checkouts, [(action: 'checkout', cycle: 'monthly')]);
      expect(opened, ['https://pagamento.example/abc']);
      expect(funnel.dataOf('premium-checkout-start'),
          {'channel': 'web', 'cycle': 'monthly', 'mode': 'recurring'});
    });

    testWidgets('F-48: the avulso rail is a different mode, same function',
        (tester) async {
      final ds = _source();
      final funnel = _Funnel();
      await _pump(tester, ds, funnel: funnel);

      await tester.tap(_text(l.format(K.premAvulsoAnnual, ['R\$ 54,90'])));
      await tester.pumpAndSettle();

      expect(ds.checkouts, [(action: 'avulso', cycle: 'annual')]);
      expect(funnel.dataOf('premium-checkout-start'),
          {'channel': 'web', 'cycle': 'annual', 'mode': 'avulso'});
    });

    testWidgets('the 7-day guarantee is on the payment surface', (tester) async {
      // A visible mirror of Terms §10 / CDC art. 49 — same promise, same
      // channel, so it must not be reachable only from the legal page.
      await _pump(tester, _source());

      expect(_text(l[K.premGuarantee]), findsOne);
      expect(_text(l[K.premPaymentHint]), findsOne);
    });

    testWidgets('a refused checkout says what the SERVER said, and goes nowhere',
        (tester) async {
      final opened = <String>[];
      final ds = _source()
        ..throwOnBillingAction = const BillingRefused('Cobrança desativada.');
      await _pump(tester, ds, opened: opened);

      await tester.tap(_text(l.format(K.premSubscribeMonthly, ['R\$ 5,49'])));
      await tester.pumpAndSettle();

      expect(_text('Cobrança desativada.'), findsOne);
      expect(opened, isEmpty);
    });

    testWidgets('the store channel has no checkout button at all',
        (tester) async {
      await _pump(tester, _source(), store: true);

      expect(_text(l.format(K.premSubscribeMonthly, ['R\$ 5,49'])), findsNothing);
      expect(_text(l.format(K.premAvulsoMonthly, ['R\$ 5,49'])), findsNothing);
    });
  });

  group('F-43 payment history', () {
    testWidgets('loads once on the first expand and lists the entries',
        (tester) async {
      final occurred = DateTime.utc(2026, 7, 15, 12);
      final ds = _source(
        plan: 'premium',
        subscription: _subscription(status: 'active'),
      )..billingHistory = [
          BillingHistoryEntry(
            occurredAt: occurred,
            category: 'payment',
            amount: 54.90,
            billingType: 'PIX',
          ),
        ];
      await _pump(tester, ds);

      await tester.tap(_text('▸ ${l[K.premHistoryToggle]}'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
            '${l.formatDate(occurred.toLocal())} · ${l[K.premHistoryPayment]}'),
        findsOne,
      );
      // The amount arrives as a decimal; rounding it wrong prints R$ 54,89.
      // (The subscription's own price line shows R$ 5,49, so this also pins
      // that the row states the ENTRY's amount, not the plan's.)
      expect(find.textContaining('R\$ 54,90'), findsOne);
      expect(ds.billingHistoryFetches, 1);

      // Collapsing and expanding again reads the cache, not the RPC.
      await tester.tap(_text('▾ ${l[K.premHistoryToggle]}'));
      await tester.pumpAndSettle();
      await tester.tap(_text('▸ ${l[K.premHistoryToggle]}'));
      await tester.pumpAndSettle();
      expect(ds.billingHistoryFetches, 1);
    });

    testWidgets('a failed load closes the panel and says so', (tester) async {
      final ds = _source(
        plan: 'premium',
        subscription: _subscription(status: 'active'),
      )..throwOnBillingHistory = Exception('boom');
      await _pump(tester, ds);

      await tester.tap(_text('▸ ${l[K.premHistoryToggle]}'));
      await tester.pumpAndSettle();

      expect(_text(l[K.famBillingHistoryLoadFailed]), findsOne);
      expect(_text(l[K.premHistoryEmpty]), findsNothing);
    });

    testWidgets('a family with no subscription has no ledger to offer',
        (tester) async {
      await _pump(tester, _source());

      expect(find.textContaining(l[K.premHistoryToggle]), findsNothing);
    });

    testWidgets('a non-admin never sees the toggle — the RPC would refuse',
        (tester) async {
      await _pump(
        tester,
        _source(
          plan: 'premium',
          members: const [_plain, _admin],
          subscription: _subscription(status: 'active'),
        ),
      );

      expect(find.textContaining(l[K.premHistoryToggle]), findsNothing);
    });
  });

  group('funnel (T-37)', () {
    testWidgets('the paywall view fires once per visit, only on the offer',
        (tester) async {
      final funnel = _Funnel();
      await _pump(tester, _source(), funnel: funnel);

      expect(funnel.count('premium-paywall-view'), 1);
      expect(funnel.dataOf('premium-paywall-view'), {'channel': 'web'});

      // A reload within the same visit must not count again.
      await tester.drag(find.byType(RefreshIndicator), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(funnel.count('premium-paywall-view'), 1);
    });

    testWidgets('an active subscriber is not a paywall view', (tester) async {
      final funnel = _Funnel();
      await _pump(
        tester,
        _source(plan: 'premium', subscription: _subscription(status: 'active')),
        funnel: funnel,
      );

      expect(funnel.count('premium-paywall-view'), 0);
    });

    testWidgets('the F-37 gate CTA records the intent and scrolls, no price',
        (tester) async {
      final funnel = _Funnel();
      await _pump(
        tester,
        _source(settings: {..._billingOn, 'freemium.free_caregivers': '2'}),
        funnel: funnel,
      );

      await tester.tap(_text(l[K.famSeePremium]));
      await tester.pumpAndSettle();

      expect(funnel.dataOf('premium-gate-click'), {'gate': 'extra-caregiver'});
    });

    testWidgets('the store cohort is tagged as store, not web', (tester) async {
      // This dimension is the whole reason the funnel exists: it is what tells
      // the store cohort apart from the web one.
      final funnel = _Funnel();
      await _pump(tester, _source(), funnel: funnel, store: true);

      expect(funnel.dataOf('premium-paywall-view'), {'channel': 'store'});
    });
  });

  group('U-13', () {
    testWidgets('an English session reads the section in English',
        (tester) async {
      final english = Localization(AppLanguage.en);
      await _pump(tester, _source(plan: 'premium'),
          language: AppLanguage.en);

      expect(_text(english[K.premBadgeForever]), findsOne);
      expect(_text(l[K.premBadgeForever]), findsNothing);
    });

    testWidgets('the price stays Brazilian in an English session',
        (tester) async {
      // The amount is charged in reais; swapping the separator is how someone
      // misreads what they owe (U-24 does not reach the billing surface).
      await _pump(
        tester,
        _source(
          plan: 'premium',
          subscription: _subscription(status: 'active', priceCents: 5490),
        ),
        language: AppLanguage.en,
      );

      expect(find.textContaining('R\$ 54,90'), findsOne);
    });
  });
}
