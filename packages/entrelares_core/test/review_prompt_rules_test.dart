// F-73 — when the Android app asks Play for the review sheet: one test per
// floor, so a floor that stops holding goes red by name.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

final now = DateTime.utc(2026, 9, 28, 12);

bool ask({
  bool enabled = true,
  bool store = true,
  bool viewer = false,
  bool offline = false,
  DateTime? created,
  DateTime? last,
  int minDays = 14,
  int interval = 120,
  bool noAccountDate = false,
}) =>
    ReviewPromptRules.shouldRequest(
      enabled: enabled,
      isStoreBuild: store,
      isViewer: viewer,
      offline: offline,
      accountCreatedAt:
          noAccountDate ? null : (created ?? now.subtract(const Duration(days: 60))),
      lastRequestedAt: last,
      now: now,
      minAccountDays: minDays,
      intervalDays: interval,
    );

void main() {
  group('the moment', () {
    test('an unread swap_approved addressed to me is it', () {
      expect(
          ReviewPromptRules.isTrigger(
              type: 'swap_approved', addressedToMe: true, isRead: false),
          isTrue);
    });

    test('already read is not the FIRST time', () {
      expect(
          ReviewPromptRules.isTrigger(
              type: 'swap_approved', addressedToMe: true, isRead: true),
          isFalse);
    });

    test('auto-approval, reverts, receipts and the fan-out are not it', () {
      for (final type in [
        'auto_approved',
        'revert_approved',
        'swap_approved_self',
        'revert_approved_self',
        'swap_family_info',
        'swap_rejected',
      ]) {
        expect(
            ReviewPromptRules.isTrigger(
                type: type, addressedToMe: true, isRead: false),
            isFalse,
            reason: type);
      }
    });

    test('a row addressed to someone else is not mine to act on', () {
      expect(
          ReviewPromptRules.isTrigger(
              type: 'swap_approved', addressedToMe: false, isRead: false),
          isFalse);
    });
  });

  group('the store build', () {
    test('only the Android production release build', () {
      expect(
          ReviewPromptRules.isStoreBuild(
              isWeb: false, isAndroid: true, isProduction: true, isRelease: true),
          isTrue);
    });

    test('never the web, a dev build, iOS or a debug run of prod', () {
      for (final (web, android, prod, release) in [
        (true, false, true, true),
        (false, true, false, true),
        (false, false, true, true),
        (false, true, true, false),
      ]) {
        expect(
            ReviewPromptRules.isStoreBuild(
                isWeb: web,
                isAndroid: android,
                isProduction: prod,
                isRelease: release),
            isFalse,
            reason: '$web $android $prod $release');
      }
    });
  });

  group('the floors', () {
    test('everything satisfied asks', () => expect(ask(), isTrue));

    test('review_prompt.enabled off never asks',
        () => expect(ask(enabled: false), isFalse));

    test('outside the store build never asks',
        () => expect(ask(store: false), isFalse));

    test('a Visualizador is never asked', () => expect(ask(viewer: true), isFalse));

    test('offline is never the moment', () => expect(ask(offline: true), isFalse));

    test('min_account_days: a younger account waits, the day itself asks', () {
      expect(ask(created: now.subtract(const Duration(days: 13))), isFalse);
      expect(ask(created: now.subtract(const Duration(days: 14))), isTrue);
      expect(
          ask(minDays: 30, created: now.subtract(const Duration(days: 20))),
          isFalse);
    });

    test('an unknown account date fails closed',
        () => expect(ask(noAccountDate: true), isFalse));

    test('interval_days: a recent request on this device waits', () {
      expect(ask(last: now.subtract(const Duration(days: 119))), isFalse);
      expect(ask(last: now.subtract(const Duration(days: 120))), isTrue);
      expect(ask(interval: 30, last: now.subtract(const Duration(days: 31))),
          isTrue);
    });
  });

  test('the floors default to the migration seeds', () {
    const s = PublicSettings.unloaded;
    expect(s.reviewPromptEnabled, isTrue);
    expect(s.reviewPromptMinAccountDays, 14);
    expect(s.reviewPromptIntervalDays, 120);
  });
}
