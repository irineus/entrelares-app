// S-01/S-04 mirrors — same numbers as Login.razor and MainLayout.razor, so
// the two clients throttle and expire identically.
import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'mirrors/repo_files.dart';

void main() {
  group('LoginThrottle.lockoutSecondsFor (S-01)', () {
    test('under 3 failures there is no lockout', () {
      expect(LoginThrottle.lockoutSecondsFor(0), 0);
      expect(LoginThrottle.lockoutSecondsFor(1), 0);
      expect(LoginThrottle.lockoutSecondsFor(2), 0);
    });

    test('3 and 4 failures cost attempts × 5 seconds', () {
      expect(LoginThrottle.lockoutSecondsFor(3), 15);
      expect(LoginThrottle.lockoutSecondsFor(4), 20);
    });

    test('5+ failures cost a flat 60 seconds', () {
      expect(LoginThrottle.lockoutSecondsFor(5), 60);
      expect(LoginThrottle.lockoutSecondsFor(6), 60);
      expect(LoginThrottle.lockoutSecondsFor(100), 60);
    });
  });

  group('LoginThrottle.remainingSeconds (restore path)', () {
    final now = DateTime.utc(2026, 8, 19, 12, 0, 0);

    test('counts down to the persisted instant', () {
      expect(
          LoginThrottle.remainingSeconds(
              now.add(const Duration(seconds: 42)), now),
          42);
    });

    test('an elapsed lockout floors at zero', () {
      expect(LoginThrottle.remainingSeconds(now, now), 0);
      expect(
          LoginThrottle.remainingSeconds(
              now.subtract(const Duration(seconds: 5)), now),
          0);
    });
  });

  group('InactivityPolicy (S-04)', () {
    final now = DateTime.utc(2026, 8, 19, 12, 0, 0);

    test('the threshold is 30 minutes, inclusive', () {
      expect(InactivityPolicy.timeout, const Duration(minutes: 30));
      expect(
          InactivityPolicy.expired(
              now.subtract(const Duration(minutes: 29, seconds: 59)), now),
          isFalse);
      expect(
          InactivityPolicy.expired(
              now.subtract(const Duration(minutes: 30)), now),
          isTrue);
      expect(
          InactivityPolicy.expired(
              now.subtract(const Duration(hours: 5)), now),
          isTrue);
    });

    test('T-83: the operator key sets the timeout; the seed is the migration seed',
        () {
      expect(InactivityPolicy.timeoutFor(PublicSettings.unloaded),
          InactivityPolicy.timeout);
      final ten = InactivityPolicy.timeoutFor(
          PublicSettings(const {'session.idle_timeout_minutes': '10'}));
      expect(ten, const Duration(minutes: 10));
      expect(InactivityPolicy.expired(now.subtract(const Duration(minutes: 10)), now, ten),
          isTrue);
      expect(InactivityPolicy.expired(now.subtract(const Duration(minutes: 9)), now, ten),
          isFalse);
      final seed = RegExp(r"\('session\.idle_timeout_minutes', '(\d+)'").firstMatch(
          migrationsDirectory()
              .listSync()
              .whereType<File>()
              .map((f) => f.readAsStringSync())
              .join('\n'));
      expect(seed, isNotNull);
      expect(InactivityPolicy.timeout.inMinutes, int.parse(seed!.group(1)!));
    });

    test('a future interaction (clock skew) never expires', () {
      expect(
          InactivityPolicy.expired(
              now.add(const Duration(minutes: 45)), now),
          isFalse);
    });
  });

  group('UpdatePasswordRules (mirror of UpdatePassword.razor)', () {
    test('short password wins over mismatch, same order as the web', () {
      expect(UpdatePasswordRules.validationErrorKey('12345', 'different'),
          K.updatePwdErrorShort);
    });

    test('mismatch is refused', () {
      expect(UpdatePasswordRules.validationErrorKey('123456', '123457'),
          K.updatePwdErrorMismatch);
    });

    test('valid pair passes', () {
      expect(UpdatePasswordRules.validationErrorKey('123456', '123456'),
          isNull);
      expect(
          UpdatePasswordRules.validationErrorKey(
              'senha-longa', 'senha-longa'),
          isNull);
    });
  });
}
