// F-59 — the *Ativar notificações* strip under the Hoje card: U-54's rhythm,
// plus the owner's rule that a notice which reached nobody re-asks.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

final _now = DateTime(2026, 10, 2, 12);

InstallHintDismissals _dismissed(int count, {required int daysAgo}) =>
    InstallHintDismissals(
        count: count, last: _now.subtract(Duration(days: daysAgo)));

void main() {
  group('PushTodayRules.show', () {
    test('only a step with a button earns the strip', () {
      for (final step in PushNudgeStep.values) {
        expect(
            PushTodayRules.show(
              step: step,
              dismissals: InstallHintDismissals.none,
              now: _now,
              accountHasPush: false,
              newestUnreadAt: _now,
            ),
            step.isActionable,
            reason: '$step');
      }
    });

    test('never dismissed: shown', () {
      expect(
          PushTodayRules.show(
            step: PushNudgeStep.enable,
            dismissals: InstallHintDismissals.none,
            now: _now,
            accountHasPush: true,
          ),
          isTrue);
    });

    test("dismissed inside the snooze, nothing new: quiet (U-54's rhythm)", () {
      expect(
          PushTodayRules.show(
            step: PushNudgeStep.enable,
            dismissals: _dismissed(1, daysAgo: 3),
            now: _now,
            accountHasPush: false,
            newestUnreadAt: _now.subtract(const Duration(days: 4)),
          ),
          isFalse);
    });

    test('the snooze runs out: shown again', () {
      expect(
          PushTodayRules.show(
            step: PushNudgeStep.install,
            dismissals: _dismissed(1, daysAgo: 14),
            now: _now,
            accountHasPush: true,
          ),
          isTrue);
    });

    test('a notice that reached nobody re-asks, even inside the snooze', () {
      expect(
          PushTodayRules.show(
            step: PushNudgeStep.enable,
            dismissals: _dismissed(1, daysAgo: 3),
            now: _now,
            accountHasPush: false,
            newestUnreadAt: _now.subtract(const Duration(hours: 2)),
          ),
          isTrue);
    });

    test('...and after the third dismissal too (owner, 02/10/2026)', () {
      expect(
          PushTodayRules.show(
            step: PushNudgeStep.enable,
            dismissals: _dismissed(InstallHintRules.maxDismissals, daysAgo: 30),
            now: _now,
            accountHasPush: false,
            newestUnreadAt: _now.subtract(const Duration(days: 1)),
          ),
          isTrue);
    });

    test('quiet after three dismissals when nothing new arrived', () {
      expect(
          PushTodayRules.show(
            step: PushNudgeStep.enable,
            dismissals: _dismissed(InstallHintRules.maxDismissals, daysAgo: 30),
            now: _now,
            accountHasPush: false,
            newestUnreadAt: _now.subtract(const Duration(days: 31)),
          ),
          isFalse);
    });

    test('a reader whose other phone rings is not chased', () {
      expect(
          PushTodayRules.show(
            step: PushNudgeStep.enable,
            dismissals: _dismissed(1, daysAgo: 3),
            now: _now,
            accountHasPush: true,
            newestUnreadAt: _now,
          ),
          isFalse);
    });

    test('no unread notification: nothing missed', () {
      expect(
          PushTodayRules.missedSinceDismissal(
            dismissals: _dismissed(1, daysAgo: 3),
            accountHasPush: false,
          ),
          isFalse);
    });
  });
}
