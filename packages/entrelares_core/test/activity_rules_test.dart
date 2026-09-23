import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('ActivityRules.channel', () {
    test('the native build is android, whatever the standalone fact says', () {
      expect(ActivityRules.channel(isWeb: false, standalone: false),
          ActivityChannel.android);
      expect(ActivityRules.channel(isWeb: false, standalone: true),
          ActivityChannel.android);
    });

    test('the web splits a tab from an installed launch', () {
      expect(ActivityRules.channel(isWeb: true, standalone: false),
          ActivityChannel.web);
      expect(ActivityRules.channel(isWeb: true, standalone: true),
          ActivityChannel.webInstalled);
    });

    test('the wire values are the three the server CHECK names', () {
      expect(ActivityChannel.values.map((c) => c.wire),
          ['android', 'web', 'web-installed']);
    });
  });

  group('ActivityRules.dayKey', () {
    test('is the LOCAL calendar day, zero-padded', () {
      expect(ActivityRules.dayKey(DateTime(2026, 9, 3, 23, 59)), '2026-09-03');
      expect(ActivityRules.dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('ActivityRules.shouldTouch', () {
    final morning = DateTime(2026, 9, 23, 8);

    test('asks when nothing succeeded yet in this process', () {
      expect(ActivityRules.shouldTouch(lastTouchedDay: null, now: morning),
          isTrue);
    });

    test('stays quiet for the rest of a day that already succeeded', () {
      expect(
          ActivityRules.shouldTouch(
              lastTouchedDay: '2026-09-23', now: DateTime(2026, 9, 23, 23, 59)),
          isFalse);
    });

    test('asks again on the next local day — a tab left open overnight', () {
      expect(
          ActivityRules.shouldTouch(
              lastTouchedDay: '2026-09-23', now: DateTime(2026, 9, 24, 0, 1)),
          isTrue);
    });
  });
}
