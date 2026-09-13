/// T-39 client mirror — the pure half of the web's
/// `Entrelares/Services/BillingService.cs`: which block the Premium section
/// shows, whether the F-42 way back is offered, the dates the copy states and
/// the catalogue KEYS of the F-43 ledger labels.
///
/// The DATABASE owns billing: `set_family_plan`, the grace cron, the webhook
/// ledger. Nothing here decides anything — it decides what to SHOW, and every
/// display rule that can drift from a server rule (the reactivate guard chain,
/// the grace deadline formula) is written as the same formula on purpose.
///
/// The fetch/invoke half lives in the app package, as with every other mirror.
library;

import 'localization/k.dart';

/// Which block the Premium section shows. Pure input → output so the free/paid
/// UI line is unit-tested without a DB.
enum BillingUi {
  /// Billing switched off — F-32 waitlist behaviour, unchanged.
  waitlist,

  /// Billing on, no active subscription: show the price offer.
  offer,

  /// Subscription active: status + renewal + cancel.
  manageActive,

  /// Renewal failed: warning + guidance (grace runs server-side).
  manageOverdue,

  /// F-42: reactivated with no charge — the gateway subscription exists and its
  /// first invoice falls due when the paid period ends. Its own block because
  /// nothing was paid for it yet: the family must see WHEN the charge lands,
  /// which neither the active panel (already paid) nor the offer (nothing
  /// scheduled) can say.
  manageScheduled,

  /// Premium without a subscription (grandfathered): nothing to sell.
  premiumForever,
}

/// The Premium-section state machine. A subscription row wins over the plan
/// (it explains WHY the family is premium and what to manage); grandfathered
/// premium (premium with NO subscription row, not trial) has nothing to buy or
/// cancel; everyone else sees the offer — including trial families and
/// canceled-but-still-paid ones, whose offer carries the "Premium ativo até X"
/// notice.
///
/// The QA fix the web paid for is pinned in the tests: a premium-first check
/// swallowed canceled subscriptions into [BillingUi.premiumForever], hiding
/// both the validity date and the re-subscribe buttons.
BillingUi computeBillingUi({
  required bool billingEnabled,
  required bool isPremium,
  required bool onTrial,
  required String? subscriptionStatus,
}) {
  if (!billingEnabled) return BillingUi.waitlist;
  if (subscriptionStatus == 'active') return BillingUi.manageActive;
  if (subscriptionStatus == 'overdue') return BillingUi.manageOverdue;
  if (subscriptionStatus == 'scheduled') return BillingUi.manageScheduled;
  if (isPremium && !onTrial && subscriptionStatus == null) {
    return BillingUi.premiumForever;
  }
  return BillingUi.offer;
}

/// F-42: methods billed by invoice, i.e. chargeable later with no stored
/// instrument. Card is absent on purpose — resuming an auto-debit needs the
/// token our hosted/no-PCI flow never touches.
const Set<String> _reschedulableMethods = {'PIX', 'BOLETO'};

/// F-42: may this family come back WITHOUT paying today? Mirrors the server's
/// guard chain exactly (canceled · paid time still running · gateway customer
/// stored · invoice-style method), because the button must never be offered
/// for a call the function will refuse.
///
/// The method check is a whitelist, not a "not card" test: an unrecognised
/// value means we cannot tell whether billing it needs a stored instrument,
/// and the safe answer is no.
///
/// F-48: a settled avulso row rests at `canceled` with paid time — the exact
/// shape this looks for — but the family never HAD a gateway subscription, so
/// [singleCharge] keeps the button away (the server guards too).
bool canReactivate({
  required String? subscriptionStatus,
  required DateTime? currentPeriodEndUtc,
  required String? billingType,
  required String? externalCustomerId,
  required DateTime nowUtc,
  bool singleCharge = false,
}) {
  if (singleCharge) return false;
  if (subscriptionStatus != 'canceled') return false;
  final end = currentPeriodEndUtc;
  if (end == null || !end.isAfter(nowUtc)) return false;
  final customer = externalCustomerId;
  if (customer == null || customer.trim().isEmpty) return false;
  final method = billingType;
  return method != null && _reschedulableMethods.contains(method.toUpperCase());
}

/// `1490` cents → `R$ 14,90`. Brazilian conventions in BOTH languages,
/// deliberately: the amount is charged in reais, and swapping the decimal
/// separator on a price is how someone misreads what they owe. Number
/// formatting per language is U-24 — the billing surface does NOT follow it.
///
/// Mirrors `.NET`'s `N2` under `pt-BR`: two decimals always, `.` grouping the
/// thousands, and the sign after the currency symbol.
String formatPriceBrl(int cents) {
  final negative = cents < 0;
  final absolute = cents.abs();
  final digits = (absolute ~/ 100).toString();
  final centavos = (absolute % 100).toString().padLeft(2, '0');

  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }

  return 'R\$ ${negative ? '-' : ''}$grouped,$centavos';
}

/// U-46: what the annual price works out to per month, in cents — the line
/// under the big annual price ("equivale a R\$ 4,58/mês"). Rounds UP: a
/// per-month figure is a marketing claim about a charge, and the safe error is
/// to overstate it by a centavo, never to understate what the family pays.
int monthlyEquivalentCents(int annualCents) => (annualCents + 11) ~/ 12;

/// U-46: how many months the annual cycle gives away against twelve monthly
/// charges — the "2 meses grátis" badge. Computed from the SAME `app_settings`
/// prices the buttons charge, so the badge is a factual claim by construction:
/// change the ratio in the database and the badge follows (or disappears)
/// without a code change.
///
/// Zero when the annual price is not a whole number of monthly charges, or
/// buys nothing back — an approximate saving is not a badge, it is a sentence
/// nobody wrote, so the card shows no badge rather than a rounded one.
int annualFreeMonths({required int monthlyCents, required int annualCents}) {
  if (monthlyCents <= 0 || annualCents <= 0) return 0;
  if (annualCents % monthlyCents != 0) return 0;
  final chargedMonths = annualCents ~/ monthlyCents;
  if (chargedMonths >= 12) return 0;
  return 12 - chargedMonths;
}

/// When a canceled (or re-purchase-pending) subscription still has paid time,
/// the date it runs until — the offer then announces "Premium ativo até X" and
/// that a new subscription ADDS to that date (the webhook extends from the
/// later of period-end/payment date), so canceling never feels like losing
/// what was already paid. Null when there is nothing to announce
/// (active/overdue rows have their own panels).
DateTime? paidUntil({
  required String? subscriptionStatus,
  required DateTime? currentPeriodEndUtc,
  required DateTime nowUtc,
}) {
  if (subscriptionStatus != 'canceled' && subscriptionStatus != 'pending') {
    return null;
  }
  final end = currentPeriodEndUtc;
  return end != null && end.isAfter(nowUtc) ? end : null;
}

/// F-48: days left when the paid-but-not-renewing period (avulso or a canceled
/// subscription) is about to lapse — the offer then adds the urgency line +
/// renew CTA. Null while comfortably far (more than [thresholdDays]) or
/// already past (U-22 owns expired). Ceiling, so "expira em 1 dia" only shows
/// within the last 24 h.
int? expiringDaysLeft(
  DateTime? paidUntilUtc,
  DateTime nowUtc, {
  int thresholdDays = 7,
}) {
  final end = paidUntilUtc;
  if (end == null || !end.isAfter(nowUtc)) return null;
  final days = (end.difference(nowUtc).inMicroseconds /
          Duration.microsecondsPerDay)
      .ceil();
  return days <= thresholdDays ? days : null;
}

/// U-22: when the overdue grace window runs out — `overdue_since +
/// billing.grace_days`, the exact formula of the server cron
/// (`billing_grace_downgrade`) and of the S-15/B-3 warning e-mail, so the
/// three surfaces can never disagree on the date. Null while the subscription
/// is not overdue (no `overdue_since` stamp).
DateTime? graceDeadline(DateTime? overdueSinceUtc, int graceDays) =>
    overdueSinceUtc?.add(Duration(days: graceDays));

/// U-22: a lapsed entitlement worth announcing — when it ended and whether it
/// was the 30-day trial (the copy differs: "avaliação terminou" vs "Premium
/// expirou").
class ExpiredPremium {
  final DateTime endedAtUtc;
  final bool wasTrial;

  const ExpiredPremium(this.endedAtUtc, {required this.wasTrial});
}

/// U-22: the "seu Premium expirou em X" notice under the free-plan badge.
///
/// No extra read needed — the data outlives the downgrade: a lapsed trial
/// keeps its past `families.trial_ends_at` (only subscription downgrades null
/// it), and a lapsed payer keeps the past `subscriptions.current_period_end`
/// on its canceled row. When both survive, the LATER one is the date the
/// family actually lost access. Null while premium (nothing expired), and null
/// on an overdue row — the [BillingUi.manageOverdue] panel owns that message
/// (grace deadline / grace ended), and a second date next to the badge would
/// fight it.
ExpiredPremium? describeExpiredPremium({
  required bool isPremium,
  required String? subscriptionStatus,
  required DateTime? currentPeriodEndUtc,
  required DateTime? trialEndsAtUtc,
  required DateTime nowUtc,
}) {
  if (isPremium || subscriptionStatus == 'overdue') return null;

  final periodEnd = currentPeriodEndUtc;
  final paidEnd = subscriptionStatus == 'canceled' &&
          periodEnd != null &&
          !periodEnd.isAfter(nowUtc)
      ? periodEnd
      : null;
  final trialAt = trialEndsAtUtc;
  final trialEnd = trialAt != null && !trialAt.isAfter(nowUtc) ? trialAt : null;

  if (paidEnd != null && (trialEnd == null || !paidEnd.isBefore(trialEnd))) {
    return ExpiredPremium(paidEnd, wasTrial: false);
  }
  return trialEnd == null ? null : ExpiredPremium(trialEnd, wasTrial: true);
}

/// F-43: catalogue KEY for a timeline category. U-13: returns the key rather
/// than the sentence, so the label follows the reader's language instead of
/// the writer's — the ledger is read by whoever opens it.
String historyCategoryKey(String? category) => switch (category) {
      'payment' => K.premHistoryPayment,
      'refund' => K.premHistoryRefund,
      'overdue' => K.premHistoryOverdue,
      'canceled' => K.premHistoryCanceled,
      'downgraded' => K.premHistoryDowngraded,
      _ => K.premHistoryOther,
    };

/// Catalogue KEY for the gateway billing type, or null when absent / not
/// chosen yet. Null still means "say nothing": every call site drops the
/// method clause entirely rather than printing a placeholder for a method the
/// family has not picked.
String? billingTypeKey(String? billingType) => switch (billingType) {
      'PIX' => K.premMethodPix,
      'CREDIT_CARD' => K.premMethodCard,
      'BOLETO' => K.premMethodBoleto,
      _ => null,
    };
