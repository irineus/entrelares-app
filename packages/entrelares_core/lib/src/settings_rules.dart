/// T-41 client mirror — the parse/fallback seam of the web's
/// `Entrelares/Services/SettingsService.cs`. The client reads the PUBLIC
/// `app_settings` rows (RLS exposes only those) for UX mirroring; enforcement
/// is ALWAYS server-side (triggers/functions read the true value), so these
/// values only shape the UI and a tampered client cannot gain anything.
///
/// The fetch/caching half lives in the app package; this file is the pure
/// lookup+parse seam so the fallback behaviour is tested without a client.
library;

import 'notice_rules.dart' show noticeMaxPerSenderPerDay;

/// The integer at [key], or [fallback] when the map is null (settings never
/// loaded), the key is missing, or the value is not a valid integer.
///
/// Mirrors `SettingsService.ParseSetting`, including .NET `int.TryParse`
/// semantics: surrounding whitespace and a sign are accepted, anything else
/// ("6.5", "6 meses", "0xFF") falls back. No range checking — `-1` and `0`
/// come back verbatim; callers own domain bounds.
int parseIntSetting(
    Map<String, String>? settings, String key, int fallback) {
  final raw = settings?[key];
  if (raw == null) return fallback;
  return int.tryParse(raw.trim(), radix: 10) ?? fallback;
}

/// Boolean twin of [parseIntSetting] — same fallback semantics.
///
/// Mirrors .NET `bool.TryParse` exactly: only `true`/`false`, case-insensitive,
/// surrounding whitespace tolerated. `"1"`, `"0"`, `"yes"` are NOT booleans
/// here, same as in the web client — do not loosen this.
bool parseBoolSetting(
    Map<String, String>? settings, String key, bool fallback) {
  final raw = settings?[key];
  if (raw == null) return fallback;
  return switch (raw.trim().toLowerCase()) {
    'true' => true,
    'false' => false,
    _ => fallback,
  };
}

/// The typed accessors over the public settings — the same 10 keys the web
/// client reads, with fallbacks mirroring the DB seeds so the UI is sane
/// before the load completes or if a key is ever missing.
///
/// The two `string`-typed public rows (`policy.current_version`,
/// `policy.enforce_from`) are deliberately NOT here — the web mirrors them as
/// compile-time `PolicyVersions` constants, and so will this client (lote 4).
class PublicSettings {
  /// The raw key→value rows, or null when the load never happened/failed —
  /// every accessor then yields its seeded fallback (fail to defaults).
  final Map<String, String>? values;

  const PublicSettings(this.values);

  /// The pre-load / load-failed state.
  static const PublicSettings unloaded = PublicSettings(null);

  int _int(String key, int fallback) => parseIntSetting(values, key, fallback);

  // F-39 horizon + F-37 seats.
  int get calendarMonthsFree => _int('calendar_months_free', 6);
  int get calendarMonthsPremium => _int('calendar_months_premium', 24);
  int get freeCaregivers => _int('free_caregivers', 2);
  int get maxCaregivers => _int('max_caregivers', 4);
  int get overrideFreeDays => _int('override_free_days', 7);
  int get overridePremiumMonths => _int('override_premium_months', 6);

  // F-67 relato do dia — the RPC reads the same three keys.
  int get dayAccountMaxDaysBack => _int('day_account.max_days_back', 30);
  int get dayAccountMaxChars => _int('day_account.max_chars', 1000);
  int get dayAccountDailyCap => _int('day_account.daily_cap', 10);

  // T-83: the F-68 message maximum — public so the form counts to it
  // (seed 2000; the column CHECK is 2000).
  int get supportMessageMaxChars => _int('support.message_max_chars', 2000);

  // T-83: the F-23 safety poll, in seconds (degraded 25, 10–120; healthy 120,
  // 0–600, 0 = off while the socket is up).
  int get pollSecondsDegraded => _int('sync.poll_seconds_degraded', 25);
  int get pollSecondsHealthy => _int('sync.poll_seconds_healthy', 120);

  // T-83: the S-04 inactivity sign-out, in minutes (seed 30, range 5–240).
  int get idleTimeoutMinutes => _int('session.idle_timeout_minutes', 30);

  // T-82: the F-52 aviso cap, an operator parameter since 24/09/2026 (default
  // 2, range 1–3). The constant is the fallback and equals the migration seed.
  int get dayNoticeDailyCap =>
      _int('day_notice.daily_cap', noticeMaxPerSenderPerDay);

  // T-39 billing (F-48 promotional prices: 549, not 490 — Asaas refuses
  // Pix/boleto charges under R$ 5,00). Enabled=false shows the waitlist.
  bool get billingEnabled => parseBoolSetting(values, 'billing.enabled', false);
  int get priceMonthlyCents => _int('billing.price_monthly_cents', 549);
  int get priceAnnualCents => _int('billing.price_annual_cents', 5490);
  // U-22: public so the overdue panel can show the real grace deadline.
  int get graceDays => _int('billing.grace_days', 7);

  /// T-48: the STORE rail's own master switch, independent of
  /// [billingEnabled] (which keeps ruling the web rail). It defaults to FALSE
  /// and stays false until the Play Console side exists — products created,
  /// RTDN wired, service account in place — because an offer the store cannot
  /// honor is worse than no offer: the app falls back to the T-38 neutral
  /// note, which Play always accepts.
  bool get storeBillingEnabled =>
      parseBoolSetting(values, 'billing.store_enabled', false);
}
