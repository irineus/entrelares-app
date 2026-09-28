/// T-41 mirror (T-53 lote 1 port) — the parse/fallback seam of the public
/// settings. Ported from `Entrelares.Tests/SettingsServiceTests.cs` plus the
/// orphan `ParseBoolSetting_ReadsValue_AndFallsBack` that lives in
/// `BillingServiceTests.cs` in the web repo.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('parseIntSetting', () {
    test('present integer returns the parsed value', () {
      expect(
          parseIntSetting({'calendar_months_free': '12'},
              'calendar_months_free', 6),
          12);
    });

    test('null cache returns the fallback', () {
      expect(parseIntSetting(null, 'calendar_months_free', 6), 6);
    });

    test('missing key returns the fallback', () {
      expect(parseIntSetting({'other': '3'}, 'calendar_months_free', 6), 6);
    });

    for (final broken in ['', '  ', 'abc', '6.5', '6 meses']) {
      test('unparseable value "$broken" returns the fallback', () {
        expect(parseIntSetting({'k': broken}, 'k', 6), 6);
      });
    }

    // No range checking in the seam — callers own domain bounds.
    test('negative integer is returned verbatim', () {
      expect(parseIntSetting({'k': '-1'}, 'k', 6), -1);
    });

    test('zero is a value, not a fallback trigger', () {
      expect(parseIntSetting({'k': '0'}, 'k', 6), 0);
    });

    // .NET int.TryParse refuses hex; Dart's default parser would accept it.
    test('a hex-looking value falls back, as in .NET', () {
      expect(parseIntSetting({'k': '0xFF'}, 'k', 6), 6);
    });
  });

  group('parseBoolSetting', () {
    // The web's single test case, verbatim.
    test('reads a value and falls back on missing/broken/null', () {
      final settings = {'billing.enabled': 'true', 'broken': 'not-a-bool'};
      expect(parseBoolSetting(settings, 'billing.enabled', false), isTrue);
      expect(parseBoolSetting(settings, 'missing', false), isFalse);
      expect(parseBoolSetting(settings, 'missing', true), isTrue);
      expect(parseBoolSetting(settings, 'broken', false), isFalse);
      expect(parseBoolSetting(null, 'billing.enabled', false), isFalse);
    });

    // .NET bool.TryParse semantics — the contract the mirror must not loosen.
    test('is case-insensitive and trims, like .NET bool.TryParse', () {
      expect(parseBoolSetting({'k': ' TRUE '}, 'k', false), isTrue);
      expect(parseBoolSetting({'k': 'False'}, 'k', true), isFalse);
    });

    test('"1"/"0"/"yes" are NOT booleans, like .NET bool.TryParse', () {
      expect(parseBoolSetting({'k': '1'}, 'k', false), isFalse);
      expect(parseBoolSetting({'k': '0'}, 'k', true), isTrue);
      expect(parseBoolSetting({'k': 'yes'}, 'k', false), isFalse);
    });
  });

  group('PublicSettings typed accessors', () {
    // The fallbacks mirror the DB seeds — the UI is sane before the load
    // completes or if a key is ever missing.
    test('unloaded yields every seeded default', () {
      const s = PublicSettings.unloaded;
      expect(s.calendarMonthsFree, 6);
      expect(s.calendarMonthsPremium, 24);
      expect(s.freeCaregivers, 2);
      expect(s.maxCaregivers, 4);
      expect(s.overrideFreeDays, 7);
      expect(s.overridePremiumMonths, 6);
      expect(s.billingEnabled, isFalse);
      expect(s.priceMonthlyCents, 549);
      expect(s.priceAnnualCents, 5490);
      expect(s.graceDays, 7);
      expect(s.reviewPromptEnabled, isTrue);
      expect(s.reviewPromptMinAccountDays, 14);
      expect(s.reviewPromptIntervalDays, 120);
    });

    test('loaded rows override their defaults, the rest keep theirs', () {
      const s = PublicSettings({
        'calendar_months_premium': '36',
        'billing.enabled': 'true',
      });
      expect(s.calendarMonthsPremium, 36);
      expect(s.billingEnabled, isTrue);
      expect(s.calendarMonthsFree, 6);
      expect(s.priceMonthlyCents, 549);
    });
  });
}
