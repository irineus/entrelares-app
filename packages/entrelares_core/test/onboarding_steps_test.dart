/// Mirror of `entrelares-app` `Entrelares.Tests/OnboardingStepsTests.cs` — same
/// cases, same verdicts.
///
/// The two facts worth reading twice: a fresh founder sees 0 of 3, and an
/// INVITEE arrives with 2 of 3 already ticked. The second is not a special
/// case in the code — it falls out of reading real family state, which is the
/// whole design.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('shape', () {
    test('four steps, in activation order', () {
      expect(OnboardingSteps.all, [
        OnboardingStep.inviteCoCaregiver,
        OnboardingStep.planTheDays,
        OnboardingStep.understandSwaps,
        // F-09, and last on purpose: the only step that asks for something
        // from OUTSIDE the product, and the only one whose prompt cannot be
        // re-offered once refused.
        OnboardingStep.enablePush,
      ]);
    });

    test('every step carries its four copy keys', () {
      for (final step in OnboardingSteps.all) {
        expect(step.titleKey.trim(), isNotEmpty);
        expect(step.hintKey.trim(), isNotEmpty);
        expect(step.doneHintKey.trim(), isNotEmpty);
        expect(step.actionKey.trim(), isNotEmpty);
      }
    });

    test('no two steps share a copy key', () {
      final keys = [
        for (final step in OnboardingSteps.all) ...[
          step.titleKey,
          step.hintKey,
          step.doneHintKey,
          step.actionKey,
        ]
      ];
      expect(keys.toSet(), hasLength(keys.length));
    });
  });

  group('enablePush (F-09)', () {
    const onAndroid = OnboardingSignals(pushSupported: true);

    test('is absent from a build with no push transport', () {
      // The web channel. A step that can never be finished keeps the card on
      // screen forever, at "3 de 4", for the rest of that person's life.
      expect(OnboardingSteps.visibleIn(const OnboardingSignals()),
          isNot(contains(OnboardingStep.enablePush)));
      expect(OnboardingSteps.visibleIn(onAndroid),
          contains(OnboardingStep.enablePush));
    });

    test('the count and the "all done" verdict follow the visible steps', () {
      // Everything the product can ask of a web reader is done, so the card
      // has nothing left to say and must go — even though `all` still holds a
      // fourth step this build cannot offer.
      const webDone = OnboardingSignals(
        hasOtherActiveMember: true,
        hasAnyPlannedDay: true,
        hasTakenPartInASwap: true,
      );
      expect(OnboardingSteps.doneCount(webDone), 3);
      expect(OnboardingSteps.allDone(webDone), isTrue);
      expect(OnboardingSteps.shouldShowChecklist(webDone), isFalse);

      // The same family on Android still has one thing to do.
      final androidDone = webDone.copyWith(pushSupported: true);
      expect(OnboardingSteps.doneCount(androidDone), 3);
      expect(OnboardingSteps.allDone(androidDone), isFalse);
      expect(OnboardingSteps.shouldShowChecklist(androidDone), isTrue);

      expect(
          OnboardingSteps.allDone(androidDone.copyWith(hasPushEnabled: true)),
          isTrue);
    });

    test('closes on real state, never on a sheet having been shown', () {
      expect(OnboardingSteps.isDone(OnboardingStep.enablePush, onAndroid),
          isFalse);
      expect(
          OnboardingSteps.isDone(OnboardingStep.enablePush,
              onAndroid.copyWith(hasPushEnabled: true)),
          isTrue);
    });
  });

  group('inviteCoCaregiver', () {
    test('done when a second member holds a seat', () {
      expect(
          OnboardingSteps.isDone(OnboardingStep.inviteCoCaregiver,
              const OnboardingSignals(hasOtherActiveMember: true)),
          isTrue);
    });

    test('done when an invitation is open — the step is "reach out", not '
        '"be accepted"', () {
      expect(
          OnboardingSteps.isDone(OnboardingStep.inviteCoCaregiver,
              const OnboardingSignals(hasOpenInvitation: true)),
          isTrue);
    });

    test('not done when the family is still one person', () {
      expect(
          OnboardingSteps.isDone(
              OnboardingStep.inviteCoCaregiver, const OnboardingSignals()),
          isFalse);
    });

    test('F-56: done when a pending member is on the calendar, and the done '
        'line says the invitation is still to come', () {
      const solo = OnboardingSignals(hasPendingMember: true);
      expect(
          OnboardingSteps.isDone(OnboardingStep.inviteCoCaregiver, solo),
          isTrue);
      expect(
          OnboardingSteps.doneHintKeyFor(
              OnboardingStep.inviteCoCaregiver, solo),
          KApp.onbStepInviteDoneHintPending);

      // Once an invitation exists the ordinary line is the true one again.
      const invited = OnboardingSignals(
          hasPendingMember: true, hasOpenInvitation: true);
      expect(
          OnboardingSteps.doneHintKeyFor(
              OnboardingStep.inviteCoCaregiver, invited),
          K.onbStepInviteDoneHint);
      // Other steps never branch.
      expect(
          OnboardingSteps.doneHintKeyFor(OnboardingStep.planTheDays, solo),
          OnboardingStep.planTheDays.doneHintKey);
    });
  });

  group('planTheDays', () {
    test('done on ANY planned day, whatever the month', () {
      expect(
          OnboardingSteps.isDone(OnboardingStep.planTheDays,
              const OnboardingSignals(hasAnyPlannedDay: true)),
          isTrue);
    });

    test('not done on an empty calendar', () {
      expect(
          OnboardingSteps.isDone(
              OnboardingStep.planTheDays, const OnboardingSignals()),
          isFalse);
    });
  });

  group('understandSwaps', () {
    test('done by opening the explanation', () {
      expect(
          OnboardingSteps.isDone(OnboardingStep.understandSwaps,
              const OnboardingSignals(hasOpenedSwapExplanation: true)),
          isTrue);
    });

    test('done by having lived a swap, even without opening it', () {
      expect(
          OnboardingSteps.isDone(OnboardingStep.understandSwaps,
              const OnboardingSignals(hasTakenPartInASwap: true)),
          isTrue);
    });

    test('not done otherwise', () {
      expect(
          OnboardingSteps.isDone(
              OnboardingStep.understandSwaps, const OnboardingSignals()),
          isFalse);
    });
  });

  group('progress and visibility', () {
    const fresh = OnboardingSignals();
    const invitee = OnboardingSignals(
      hasOtherActiveMember: true,
      hasAnyPlannedDay: true,
    );
    const finished = OnboardingSignals(
      hasOtherActiveMember: true,
      hasAnyPlannedDay: true,
      hasOpenedSwapExplanation: true,
    );

    test('a fresh account is 0 of 3 and sees the card', () {
      expect(OnboardingSteps.doneCount(fresh), 0);
      expect(OnboardingSteps.allDone(fresh), isFalse);
      expect(OnboardingSteps.shouldShowChecklist(fresh), isTrue);
    });

    test('an invitee arrives with 2 of 3 already done', () {
      expect(OnboardingSteps.doneCount(invitee), 2);
      expect(OnboardingSteps.shouldShowChecklist(invitee), isTrue);
    });

    test('finishing removes the card', () {
      expect(OnboardingSteps.doneCount(finished), 3);
      expect(OnboardingSteps.allDone(finished), isTrue);
      expect(OnboardingSteps.shouldShowChecklist(finished), isFalse);
    });

    test('dismissing hides it even with work left', () {
      expect(
          OnboardingSteps.shouldShowChecklist(
              fresh.copyWith(checklistDismissed: true)),
          isFalse);
    });

    for (final dismissed in [true, false]) {
      for (final done in [true, false]) {
        test('reopening from the profile brings it back '
            '(dismissed: $dismissed, finished: $done)', () {
          final signals = (done ? finished : fresh)
              .copyWith(checklistDismissed: dismissed);
          expect(OnboardingSteps.shouldShowChecklist(signals, reopened: true),
              isTrue);
        });
      }
    }
  });

  group('copyWith', () {
    test('Home ORs the loaded signal with the month it already holds', () {
      const loaded = OnboardingSignals(hasOtherActiveMember: true);
      final effective = loaded.copyWith(
          hasAnyPlannedDay: loaded.hasAnyPlannedDay || true);
      expect(effective.hasAnyPlannedDay, isTrue);
      expect(effective.hasOtherActiveMember, isTrue);
    });

    test('leaves untouched fields alone', () {
      const signals = OnboardingSignals(
          hasOpenInvitation: true, checklistDismissed: true);
      final copy = signals.copyWith(hasAnyPlannedDay: true);
      expect(copy.hasOpenInvitation, isTrue);
      expect(copy.checklistDismissed, isTrue);
    });
  });
}
