/// Mirror of `entrelares-app` `Entrelares.Tests/PolicyVersionsTests.cs` — the
/// re-consent gate's decision table plus the authoring invariants.
///
/// The near-miss cases matter more than they look: the stamp is compared
/// EXACTLY, so " 2026-07-30", "2026-07-30 " and "2026-7-30" are all *not* the
/// current version. A lenient comparison would silently accept a malformed
/// stamp as consent.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  final beforeEnforce =
      PolicyVersions.enforceFromDate.subtract(const Duration(days: 1));
  final onEnforce = PolicyVersions.enforceFromDate;
  final afterEnforce =
      PolicyVersions.enforceFromDate.add(const Duration(days: 1));

  group('evaluate', () {
    test('the current stamp is up to date, whatever the date', () {
      expect(PolicyVersions.evaluate(PolicyVersions.current, beforeEnforce),
          ConsentGateState.upToDate);
      expect(PolicyVersions.evaluate(PolicyVersions.current, afterEnforce),
          ConsentGateState.upToDate);
    });

    test('an older version only warns inside the notice window', () {
      expect(PolicyVersions.evaluate('2026-07-23', beforeEnforce),
          ConsentGateState.notice);
    });

    test('an older version blocks ON the enforce date itself', () {
      expect(PolicyVersions.evaluate('2026-07-23', onEnforce),
          ConsentGateState.blocked);
    });

    test('an older version blocks after the window', () {
      expect(PolicyVersions.evaluate('2026-07-23', afterEnforce),
          ConsentGateState.blocked);
    });

    test('a legacy null stamp warns before the window', () {
      expect(PolicyVersions.evaluate(null, beforeEnforce),
          ConsentGateState.notice);
    });

    test('a legacy null stamp blocks after the window', () {
      expect(
          PolicyVersions.evaluate(null, afterEnforce), ConsentGateState.blocked);
    });

    test('an unknown FUTURE version is not treated as accepted', () {
      expect(PolicyVersions.evaluate('2099-01-01', afterEnforce),
          ConsentGateState.blocked);
    });

    test('the time of day never changes the verdict', () {
      final morning = DateTime(onEnforce.year, onEnforce.month, onEnforce.day, 0, 1);
      final night = DateTime(onEnforce.year, onEnforce.month, onEnforce.day, 23, 59);
      expect(PolicyVersions.evaluate('2026-07-23', morning),
          ConsentGateState.blocked);
      expect(
          PolicyVersions.evaluate('2026-07-23', night), ConsentGateState.blocked);
    });

    for (final nearMiss in const [
      ' 2026-09-25',
      '2026-09-25 ',
      '2026-9-25',
      '2026-09-25T00:00:00Z',
      '',
    ]) {
      test('"$nearMiss" is not the current version', () {
        expect(PolicyVersions.evaluate(nearMiss, beforeEnforce),
            isNot(ConsentGateState.upToDate));
      });
    }
  });

  group('authoring invariants', () {
    test('the enforce date is not earlier than the version date', () {
      expect(PolicyVersions.enforceFromDate
          .isBefore(DateTime.parse(PolicyVersions.current)), isFalse);
    });

    test('enforceFromDate parses the declared constant', () {
      expect(PolicyVersions.enforceFromDate, DateTime.parse('2026-10-10'));
    });

    test('the change summary is present and non-empty', () {
      expect(PolicyVersions.changeSummary, isNotEmpty);
      for (final entry in PolicyVersions.changeSummary) {
        expect(entry.trim(), isNotEmpty);
      }
    });

    test('both summaries stay index-aligned — a forgotten half is a red gate',
        () {
      expect(PolicyVersions.changeSummaryEn,
          hasLength(PolicyVersions.changeSummary.length));
      for (final entry in PolicyVersions.changeSummaryEn) {
        expect(entry.trim(), isNotEmpty);
      }
    });

    test('changeSummaryFor picks the reader language', () {
      expect(PolicyVersions.changeSummaryFor(english: false),
          same(PolicyVersions.changeSummary));
      expect(PolicyVersions.changeSummaryFor(english: true),
          same(PolicyVersions.changeSummaryEn));
    });
  });
}
