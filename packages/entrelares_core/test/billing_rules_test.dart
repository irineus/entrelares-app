import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// T-39 — mirror of `Entrelares.Tests/BillingServiceTests.cs`. Every case there
/// exists here, including the QA regressions the web already paid for: the
/// canceled-but-still-paid family that must land on the offer, the card family
/// that must NOT be offered the F-42 way back, and the settled avulso row that
/// looks reactivatable but is not.
void main() {
  group('computeBillingUi — the Premium-section state machine', () {
    test('billing disabled always yields the F-32 waitlist', () {
      expect(
        computeBillingUi(
            billingEnabled: false,
            isPremium: false,
            onTrial: false,
            subscriptionStatus: null),
        BillingUi.waitlist,
      );
      // Even an active subscription: the master switch wins over everything.
      expect(
        computeBillingUi(
            billingEnabled: false,
            isPremium: true,
            onTrial: false,
            subscriptionStatus: 'active'),
        BillingUi.waitlist,
      );
    });

    test('an active subscription shows management, never a second checkout',
        () {
      expect(
        computeBillingUi(
            billingEnabled: true,
            isPremium: true,
            onTrial: false,
            subscriptionStatus: 'active'),
        BillingUi.manageActive,
      );
    });

    test('overdue warns instead of offering to subscribe again', () {
      expect(
        computeBillingUi(
            billingEnabled: true,
            isPremium: true,
            onTrial: false,
            subscriptionStatus: 'overdue'),
        BillingUi.manageOverdue,
      );
    });

    test('a scheduled subscription gets its own panel (F-42)', () {
      // Nothing was paid yet, so neither the active panel nor the offer can
      // tell the family when the first charge lands.
      expect(
        computeBillingUi(
            billingEnabled: true,
            isPremium: true,
            onTrial: false,
            subscriptionStatus: 'scheduled'),
        BillingUi.manageScheduled,
      );
    });

    test('grandfathered premium has nothing to buy', () {
      expect(
        computeBillingUi(
            billingEnabled: true,
            isPremium: true,
            onTrial: false,
            subscriptionStatus: null),
        BillingUi.premiumForever,
      );
    });

    test('a free family sees the offer', () {
      expect(
        computeBillingUi(
            billingEnabled: true,
            isPremium: false,
            onTrial: false,
            subscriptionStatus: null),
        BillingUi.offer,
      );
    });

    test('trial families see the offer too — trial is not grandfathered', () {
      expect(
        computeBillingUi(
            billingEnabled: true,
            isPremium: true,
            onTrial: true,
            subscriptionStatus: null),
        BillingUi.offer,
      );
    });

    test('canceled/pending rows fall through to the offer', () {
      for (final status in ['canceled', 'pending']) {
        expect(
          computeBillingUi(
              billingEnabled: true,
              isPremium: false,
              onTrial: false,
              subscriptionStatus: status),
          BillingUi.offer,
          reason: status,
        );
      }
    });

    test('QA regression: canceled but STILL PAID lands on the offer', () {
      // Familia 07 in the web: a premium-first check swallowed these into
      // premiumForever, hiding both the "ativo até X" notice and the
      // re-subscribe buttons.
      for (final status in ['canceled', 'pending']) {
        expect(
          computeBillingUi(
              billingEnabled: true,
              isPremium: true,
              onTrial: false,
              subscriptionStatus: status),
          BillingUi.offer,
          reason: status,
        );
      }
    });
  });

  group('paidUntil — the canceled-but-still-paid notice', () {
    final now = DateTime.utc(2026, 7, 28, 12);
    final future = now.add(const Duration(days: 30));
    final past = now.subtract(const Duration(days: 1));

    test('announces only canceled/pending rows with time left', () {
      expect(
        paidUntil(
            subscriptionStatus: 'canceled',
            currentPeriodEndUtc: future,
            nowUtc: now),
        future,
      );
      expect(
        paidUntil(
            subscriptionStatus: 'pending',
            currentPeriodEndUtc: future,
            nowUtc: now),
        future,
      );
    });

    test('says nothing for lapsed, missing or self-managed states', () {
      expect(
          paidUntil(
              subscriptionStatus: 'canceled',
              currentPeriodEndUtc: past,
              nowUtc: now),
          isNull);
      expect(
          paidUntil(
              subscriptionStatus: 'canceled',
              currentPeriodEndUtc: null,
              nowUtc: now),
          isNull);
      // active/overdue have their own panels.
      expect(
          paidUntil(
              subscriptionStatus: 'active',
              currentPeriodEndUtc: future,
              nowUtc: now),
          isNull);
      expect(
          paidUntil(
              subscriptionStatus: 'overdue',
              currentPeriodEndUtc: future,
              nowUtc: now),
          isNull);
      expect(
          paidUntil(
              subscriptionStatus: null,
              currentPeriodEndUtc: future,
              nowUtc: now),
          isNull);
    });
  });

  group('graceDeadline — the overdue panel hard date (U-22)', () {
    test('is overdue_since + grace_days, the cron formula', () {
      final since = DateTime.utc(2026, 8, 1, 9);
      expect(graceDeadline(since, 7), since.add(const Duration(days: 7)));
      expect(graceDeadline(since, 14), since.add(const Duration(days: 14)));
    });

    test('needs an overdue stamp', () {
      expect(graceDeadline(null, 7), isNull);
    });
  });

  group('describeExpiredPremium — the "expirou em X" note (U-22)', () {
    final now = DateTime.utc(2026, 8, 2, 12);

    test('a premium family has nothing expired to announce', () {
      expect(
        describeExpiredPremium(
          isPremium: true,
          subscriptionStatus: 'canceled',
          currentPeriodEndUtc: now.subtract(const Duration(days: 5)),
          trialEndsAtUtc: now.subtract(const Duration(days: 40)),
          nowUtc: now,
        ),
        isNull,
      );
    });

    test('a lapsed trial announces the trial end with the trial wording', () {
      final trialEnd = now.subtract(const Duration(days: 3));
      final expired = describeExpiredPremium(
        isPremium: false,
        subscriptionStatus: null,
        currentPeriodEndUtc: null,
        trialEndsAtUtc: trialEnd,
        nowUtc: now,
      );
      expect(expired, isNotNull);
      expect(expired!.endedAtUtc, trialEnd);
      expect(expired.wasTrial, isTrue);
    });

    test('a lapsed payer announces the paid end, and the LATER date wins', () {
      final paidEnd = now.subtract(const Duration(days: 2));

      final payer = describeExpiredPremium(
        isPremium: false,
        subscriptionStatus: 'canceled',
        currentPeriodEndUtc: paidEnd,
        trialEndsAtUtc: null,
        nowUtc: now,
      );
      expect(payer!.endedAtUtc, paidEnd);
      expect(payer.wasTrial, isFalse);

      // Both survive → the family lost access on the later one.
      final both = describeExpiredPremium(
        isPremium: false,
        subscriptionStatus: 'canceled',
        currentPeriodEndUtc: paidEnd,
        trialEndsAtUtc: now.subtract(const Duration(days: 60)),
        nowUtc: now,
      );
      expect(both!.endedAtUtc, paidEnd);
      expect(both.wasTrial, isFalse);

      final trialLater = describeExpiredPremium(
        isPremium: false,
        subscriptionStatus: 'canceled',
        currentPeriodEndUtc: now.subtract(const Duration(days: 60)),
        trialEndsAtUtc: now.subtract(const Duration(days: 2)),
        nowUtc: now,
      );
      expect(trialLater!.endedAtUtc, now.subtract(const Duration(days: 2)));
      expect(trialLater.wasTrial, isTrue);
    });

    test('overdue, future or nothing announces nothing', () {
      // The manageOverdue panel owns the overdue story (grace copy).
      expect(
        describeExpiredPremium(
          isPremium: false,
          subscriptionStatus: 'overdue',
          currentPeriodEndUtc: now.subtract(const Duration(days: 10)),
          trialEndsAtUtc: now.subtract(const Duration(days: 40)),
          nowUtc: now,
        ),
        isNull,
      );
      expect(
        describeExpiredPremium(
          isPremium: false,
          subscriptionStatus: 'canceled',
          currentPeriodEndUtc: now.add(const Duration(days: 5)),
          trialEndsAtUtc: null,
          nowUtc: now,
        ),
        isNull,
      );
      expect(
        describeExpiredPremium(
          isPremium: false,
          subscriptionStatus: null,
          currentPeriodEndUtc: null,
          trialEndsAtUtc: now.add(const Duration(days: 5)),
          nowUtc: now,
        ),
        isNull,
      );
      expect(
        describeExpiredPremium(
          isPremium: false,
          subscriptionStatus: null,
          currentPeriodEndUtc: null,
          trialEndsAtUtc: null,
          nowUtc: now,
        ),
        isNull,
      );
    });
  });

  group('formatPriceBrl', () {
    test('uses Brazilian conventions regardless of the UI language', () {
      expect(formatPriceBrl(1490), 'R\$ 14,90');
      expect(formatPriceBrl(14900), 'R\$ 149,00');
      expect(formatPriceBrl(149000), 'R\$ 1.490,00');
      // The F-48 promotional prices, the ones actually charged today.
      expect(formatPriceBrl(549), 'R\$ 5,49');
      expect(formatPriceBrl(5490), 'R\$ 54,90');
    });

    test('keeps two decimals and groups every three digits', () {
      expect(formatPriceBrl(0), 'R\$ 0,00');
      expect(formatPriceBrl(5), 'R\$ 0,05');
      expect(formatPriceBrl(100000000), 'R\$ 1.000.000,00');
      // Sign lands after the symbol, as .NET's N2 does under pt-BR.
      expect(formatPriceBrl(-1490), 'R\$ -14,90');
    });
  });

  group('U-46 price card', () {
    test('the per-month equivalent of the annual price rounds UP', () {
      // 5490 / 12 = 457.5 → R$ 4,58, never R$ 4,57: the safe error on a
      // claim about a charge is to overstate it by a centavo.
      expect(monthlyEquivalentCents(5490), 458);
      expect(monthlyEquivalentCents(1200), 100);
      expect(monthlyEquivalentCents(1201), 101);
    });

    test('the free-months badge is derived from the prices, not hardcoded', () {
      // The F-48 promotional pair: annual = 10 × monthly → 2 months free.
      expect(annualFreeMonths(monthlyCents: 549, annualCents: 5490), 2);
      expect(annualFreeMonths(monthlyCents: 100, annualCents: 1100), 1);
    });

    test('no badge when the saving is not a whole number of months', () {
      expect(annualFreeMonths(monthlyCents: 549, annualCents: 5000), 0);
      // Twelve charges, or more, buy nothing back.
      expect(annualFreeMonths(monthlyCents: 100, annualCents: 1200), 0);
      expect(annualFreeMonths(monthlyCents: 100, annualCents: 1300), 0);
      expect(annualFreeMonths(monthlyCents: 0, annualCents: 1300), 0);
    });
  });

  group('F-43 label keys', () {
    test('every timeline category maps to a key, unknown falls back', () {
      expect(historyCategoryKey('payment'), K.premHistoryPayment);
      expect(historyCategoryKey('refund'), K.premHistoryRefund);
      expect(historyCategoryKey('overdue'), K.premHistoryOverdue);
      expect(historyCategoryKey('canceled'), K.premHistoryCanceled);
      expect(historyCategoryKey('downgraded'), K.premHistoryDowngraded);
      expect(historyCategoryKey('mystery'), K.premHistoryOther);
      expect(historyCategoryKey(null), K.premHistoryOther);
    });

    test('known methods map to a key; absent/unknown yields null', () {
      expect(billingTypeKey('PIX'), K.premMethodPix);
      expect(billingTypeKey('CREDIT_CARD'), K.premMethodCard);
      expect(billingTypeKey('BOLETO'), K.premMethodBoleto);
      // Null means "drop the clause", not "print a placeholder".
      expect(billingTypeKey('UNDEFINED'), isNull);
      expect(billingTypeKey(null), isNull);
    });
  });

  group('canReactivate — the F-42 guard chain', () {
    final now = DateTime.utc(2026, 8, 1, 12);

    test('canceled + paid time + invoice method + stored customer is allowed',
        () {
      expect(
        canReactivate(
          subscriptionStatus: 'canceled',
          currentPeriodEndUtc: now.add(const Duration(days: 10)),
          billingType: 'PIX',
          externalCustomerId: 'cus_123',
          nowUtc: now,
        ),
        isTrue,
      );
      expect(
        canReactivate(
          subscriptionStatus: 'canceled',
          currentPeriodEndUtc: now.add(const Duration(days: 10)),
          billingType: 'BOLETO',
          externalCustomerId: 'cus_123',
          nowUtc: now,
        ),
        isTrue,
      );
    });

    test('card is refused — the server has no token to resume an auto-debit',
        () {
      expect(
        canReactivate(
          subscriptionStatus: 'canceled',
          currentPeriodEndUtc: now.add(const Duration(days: 10)),
          billingType: 'CREDIT_CARD',
          externalCustomerId: 'cus_123',
          nowUtc: now,
        ),
        isFalse,
      );
    });

    test('unknown/absent method is refused — a whitelist, not a "not card" test',
        () {
      for (final method in ['UNDEFINED', null]) {
        expect(
          canReactivate(
            subscriptionStatus: 'canceled',
            currentPeriodEndUtc: now.add(const Duration(days: 10)),
            billingType: method,
            externalCustomerId: 'cus_123',
            nowUtc: now,
          ),
          isFalse,
          reason: method ?? 'null',
        );
      }
    });

    test('a lapsed or missing period is a plain checkout, not a reactivation',
        () {
      expect(
        canReactivate(
          subscriptionStatus: 'canceled',
          currentPeriodEndUtc: now.subtract(const Duration(days: 1)),
          billingType: 'PIX',
          externalCustomerId: 'cus_123',
          nowUtc: now,
        ),
        isFalse,
      );
      expect(
        canReactivate(
          subscriptionStatus: 'canceled',
          currentPeriodEndUtc: null,
          billingType: 'PIX',
          externalCustomerId: 'cus_123',
          nowUtc: now,
        ),
        isFalse,
      );
    });

    test('without a stored gateway customer the server has nobody to bill', () {
      for (final customer in [null, '   ']) {
        expect(
          canReactivate(
            subscriptionStatus: 'canceled',
            currentPeriodEndUtc: now.add(const Duration(days: 10)),
            billingType: 'PIX',
            externalCustomerId: customer,
            nowUtc: now,
          ),
          isFalse,
          reason: customer ?? 'null',
        );
      }
    });

    test('only a CANCELED row can be reactivated', () {
      for (final status in ['active', 'overdue', 'pending', 'scheduled', null]) {
        expect(
          canReactivate(
            subscriptionStatus: status,
            currentPeriodEndUtc: now.add(const Duration(days: 10)),
            billingType: 'PIX',
            externalCustomerId: 'cus_123',
            nowUtc: now,
          ),
          isFalse,
          reason: status ?? 'null',
        );
      }
    });

    test('F-48: a settled avulso row is refused by the single_charge flag', () {
      // The row is EXACTLY the shape the guard looks for; the flag is the only
      // thing keeping the button away, because there is no subscription to
      // resume. The second assertion pins that it IS the flag doing the work.
      expect(
        canReactivate(
          subscriptionStatus: 'canceled',
          currentPeriodEndUtc: now.add(const Duration(days: 10)),
          billingType: 'PIX',
          externalCustomerId: 'cus_123',
          nowUtc: now,
          singleCharge: true,
        ),
        isFalse,
      );
      expect(
        canReactivate(
          subscriptionStatus: 'canceled',
          currentPeriodEndUtc: now.add(const Duration(days: 10)),
          billingType: 'PIX',
          externalCustomerId: 'cus_123',
          nowUtc: now,
          singleCharge: false,
        ),
        isTrue,
      );
    });
  });

  group('expiringDaysLeft — the F-48 near-lapse warning', () {
    final now = DateTime.utc(2026, 8, 1, 12);

    test('warns inside the threshold with the ceiling of the remaining time',
        () {
      expect(expiringDaysLeft(now.add(const Duration(days: 2, hours: 12)), now),
          3);
      expect(expiringDaysLeft(now.add(const Duration(hours: 20)), now), 1);
      expect(expiringDaysLeft(now.add(const Duration(days: 7)), now), 7);
    });

    test('stays quiet when comfortably far, lapsed or absent', () {
      expect(expiringDaysLeft(now.add(const Duration(days: 8)), now), isNull);
      // U-22 owns the already-expired message.
      expect(
          expiringDaysLeft(now.subtract(const Duration(days: 1)), now), isNull);
      expect(expiringDaysLeft(null, now), isNull);
    });
  });

  group('the billing settings the switch reads (T-41 mirror)', () {
    test('billing.enabled parses and falls back like the web', () {
      const values = {'billing.enabled': 'true', 'broken': 'not-a-bool'};
      expect(parseBoolSetting(values, 'billing.enabled', false), isTrue);
      expect(parseBoolSetting(values, 'missing', false), isFalse);
      expect(parseBoolSetting(values, 'missing', true), isTrue);
      expect(parseBoolSetting(values, 'broken', false), isFalse);
      expect(parseBoolSetting(null, 'billing.enabled', false), isFalse);
    });
  });
}
