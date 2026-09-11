// F-32 — the Family model half of the entitlement mirror: the null-family
// fail-closed default (EntitlementServiceTests' IsPremium(Family?) cases) and
// the wire parsing. The rule itself is core (entitlement_rules_test).
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/family.dart';

void main() {
  final now = DateTime.utc(2026, 7, 23, 12);

  test('a null family is free — fail closed', () {
    expect(Family.isPremiumFamily(null, now), isFalse);
  });

  test('a premium family is premium', () {
    expect(
        Family.isPremiumFamily(const Family(id: 1, plan: 'premium'), now),
        isTrue);
  });

  test('fromJson: wire timestamps land as UTC, plan defaults to free', () {
    final family = Family.fromJson({
      'id': 7,
      'plan': null,
      'trial_ends_at': '2026-08-22T12:00:00+00:00',
      'comp_premium_at': null,
    });
    expect(family.plan, 'free');
    expect(family.trialEndsAt, DateTime.utc(2026, 8, 22, 12));
    expect(family.trialEndsAt!.isUtc, isTrue);
    expect(family.compPremiumAt, isNull);
    expect(Family.isPremiumFamily(family, now), isTrue,
        reason: 'trial still running at the fixed clock');
  });
}
