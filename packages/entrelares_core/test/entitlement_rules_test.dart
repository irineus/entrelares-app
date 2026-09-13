/// F-32 mirror (T-53 lote 1 port) — the freemium entitlement rule. Ported
/// from `Entrelares.Tests/EntitlementServiceTests.cs`, same fixed clock. The
/// two `IsPremium(Family?)` cases live with the app's Family model instead —
/// the core rule is primitive-only.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 12);

  group('computeIsPremium — mirror of public.is_premium()', () {
    test('premium plan is premium regardless of trial', () {
      expect(
          computeIsPremium(
              plan: 'premium',
              trialEndsAtUtc: now.subtract(const Duration(days: 30)),
              nowUtc: now),
          isTrue);
    });

    test('free plan within the trial is premium', () {
      expect(
          computeIsPremium(
              plan: 'free',
              trialEndsAtUtc: now.add(const Duration(days: 10)),
              nowUtc: now),
          isTrue);
    });

    test('free plan with an expired trial is not premium', () {
      expect(
          computeIsPremium(
              plan: 'free',
              trialEndsAtUtc: now.subtract(const Duration(days: 1)),
              nowUtc: now),
          isFalse);
    });

    test('free plan with no trial is not premium', () {
      expect(
          computeIsPremium(plan: 'free', trialEndsAtUtc: null, nowUtc: now),
          isFalse);
    });

    // The DB rule is `trial_ends_at > now()` — strictly greater.
    test('trial boundary is exclusive: expired exactly at now is free', () {
      expect(
          computeIsPremium(plan: 'free', trialEndsAtUtc: now, nowUtc: now),
          isFalse);
    });

    test('plan comparison is case-insensitive', () {
      for (final plan in ['Premium', 'PREMIUM', 'premium']) {
        expect(
            computeIsPremium(plan: plan, trialEndsAtUtc: null, nowUtc: now),
            isTrue,
            reason: plan);
      }
    });

    test('an unknown plan without trial is not premium', () {
      expect(
          computeIsPremium(plan: 'gold', trialEndsAtUtc: null, nowUtc: now),
          isFalse);
      expect(computeIsPremium(plan: null, trialEndsAtUtc: null, nowUtc: now),
          isFalse);
    });
  });

  group('computeIsPremium — F-58 comp (permanent courtesy premium)', () {
    test('comp grants premium even on a free plan with an expired trial', () {
      expect(
          computeIsPremium(
              plan: 'free',
              trialEndsAtUtc: now.subtract(const Duration(days: 90)),
              nowUtc: now,
              compPremiumAtUtc: now.subtract(const Duration(days: 400))),
          isTrue);
    });

    test('without comp the rule is unchanged', () {
      expect(
          computeIsPremium(
              plan: 'free',
              trialEndsAtUtc: now.subtract(const Duration(days: 90)),
              nowUtc: now,
              compPremiumAtUtc: null),
          isFalse);
    });

    // The timestamp records WHEN the comp was granted — it is NOT an expiry.
    test('the comp timestamp is not an expiry: a future stamp still grants',
        () {
      expect(
          computeIsPremium(
              plan: 'free',
              trialEndsAtUtc: null,
              nowUtc: now,
              compPremiumAtUtc: now.add(const Duration(days: 10))),
          isTrue);
    });
  });

  group('describePlan — the plan status label', () {
    test('permanent premium is not on trial', () {
      final status =
          describePlan(plan: 'premium', trialEndsAtUtc: null, nowUtc: now);
      expect(status.isPremium, isTrue);
      expect(status.onTrial, isFalse);
      expect(status.trialDaysLeft, isNull);
    });

    test('trial reports days left rounded UP', () {
      final status = describePlan(
          plan: 'free',
          trialEndsAtUtc: now.add(const Duration(days: 5, hours: 12)),
          nowUtc: now);
      expect(status.isPremium, isTrue);
      expect(status.onTrial, isTrue);
      expect(status.trialDaysLeft, 6);
    });

    test('the trial last moments never show zero days', () {
      final status = describePlan(
          plan: 'free',
          trialEndsAtUtc: now.add(const Duration(minutes: 1)),
          nowUtc: now);
      expect(status.onTrial, isTrue);
      expect(status.trialDaysLeft, 1);
    });

    test('an exactly-integral trial remainder is not rounded up further', () {
      final status = describePlan(
          plan: 'free',
          trialEndsAtUtc: now.add(const Duration(days: 7)),
          nowUtc: now);
      expect(status.trialDaysLeft, 7);
    });

    test('an expired trial is free', () {
      final status = describePlan(
          plan: 'free',
          trialEndsAtUtc: now.subtract(const Duration(days: 1)),
          nowUtc: now);
      expect(status.isPremium, isFalse);
      expect(status.onTrial, isFalse);
      expect(status.trialDaysLeft, isNull);
    });

    test('comp is premium without a trial clock', () {
      final status = describePlan(
          plan: 'free',
          trialEndsAtUtc: null,
          nowUtc: now,
          compPremiumAtUtc: now.subtract(const Duration(days: 5)));
      expect(status.isPremium, isTrue);
      expect(status.onTrial, isFalse);
      expect(status.trialDaysLeft, isNull);
    });

    // A comped family INSIDE a trial must not show the countdown — F-53 owns
    // the comp vocabulary; here it must simply BE premium.
    test('comp during a running trial hides the trial countdown', () {
      final status = describePlan(
          plan: 'free',
          trialEndsAtUtc: now.add(const Duration(days: 10)),
          nowUtc: now,
          compPremiumAtUtc: now.subtract(const Duration(days: 1)));
      expect(status.isPremium, isTrue);
      expect(status.onTrial, isFalse);
      expect(status.trialDaysLeft, isNull);
    });
  });

  group('describePlanRow — the Família row\'s one-line plan summary (U-35)',
      () {
    PlanStatus plan(String p, {DateTime? trial}) =>
        describePlan(plan: p, trialEndsAtUtc: trial, nowUtc: now);

    test('a trial family reads the countdown, whatever the subscription says',
        () {
      final row = describePlanRow(
          plan: plan('free', trial: now.add(const Duration(days: 5))),
          currentPeriodEndUtc: now.add(const Duration(days: 30)),
          nowUtc: now);
      expect(row.kind, PlanRowKind.trial);
      expect(row.trialDaysLeft, 5);
      expect(row.untilUtc, isNull);
    });

    test('a paid family reads the date its period runs to', () {
      final end = now.add(const Duration(days: 12));
      final row = describePlanRow(
          plan: plan('premium'), currentPeriodEndUtc: end, nowUtc: now);
      expect(row.kind, PlanRowKind.premiumUntil);
      expect(row.untilUtc, end);
    });

    test('a period end already behind us is never announced — an overdue '
        'family in grace is plain Premium here, the page has the deadline',
        () {
      final row = describePlanRow(
          plan: plan('premium'),
          currentPeriodEndUtc: now.subtract(const Duration(days: 1)),
          nowUtc: now);
      expect(row.kind, PlanRowKind.premium);
      expect(row.untilUtc, isNull);
    });

    test('permanent premium has no date by design', () {
      final row = describePlanRow(
          plan: plan('premium'), currentPeriodEndUtc: null, nowUtc: now);
      expect(row.kind, PlanRowKind.premium);
    });

    test('a free family is free, even with a stale period end on file', () {
      // The canceled subscription row outlives the entitlement (U-22 reads
      // the lapse from it); the row must not resurrect "Premium até".
      final row = describePlanRow(
          plan: plan('free'),
          currentPeriodEndUtc: now.add(const Duration(days: 3)),
          nowUtc: now);
      expect(row.kind, PlanRowKind.free);
    });
  });
}
