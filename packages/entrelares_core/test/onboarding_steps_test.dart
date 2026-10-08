/// Mirror of `entrelares-app` `Entrelares.Tests/OnboardingStepsTests.cs` — same
/// cases, same verdicts — plus U-61's shape (07/10/2026).
///
/// The facts worth reading twice: a fresh founder sees 0 of 3, in the
/// founder's order (plan → invite → understand); an INVITEE sees no checklist
/// at all — their first run is U-58's welcome; and the push ask is not a step
/// here any more, so the intro's "três" is the count.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('shape', () {
    test('three steps, in the founder\'s order (U-61)', () {
      expect(OnboardingSteps.all, [
        // Plan first: a family that never plans never invites either (F-78's
        // 20 of 30 single-member families), and the Hoje card points here.
        OnboardingStep.planTheDays,
        OnboardingStep.inviteCoCaregiver,
        OnboardingStep.understandSwaps,
      ]);
      expect(OnboardingSteps.visibleIn(const OnboardingSignals()),
          OnboardingSteps.all);
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

    test('the intro counts the steps — "três" is three (U-61)', () {
      // The audit read "Três coisas transformam…" over a list of four. The
      // push step left the checklist for the F-59 strip; the sentence stays
      // and the list matches it, in both languages.
      expect(OnboardingSteps.all, hasLength(3));
      expect(Localization(AppLanguage.ptBr)[K.onbChecklistIntro],
          startsWith('Três'));
      expect(Localization(AppLanguage.en)[K.onbChecklistIntro],
          startsWith('Three'));
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
    const joinedFamily = OnboardingSignals(
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

    test('a founder whose family already has a member and a plan is 2 of 3',
        () {
      expect(OnboardingSteps.doneCount(joinedFamily), 2);
      expect(OnboardingSteps.shouldShowChecklist(joinedFamily), isTrue);
    });

    test('U-61: the invitee never sees the checklist on their own — the '
        'ticks would be the founder\'s, not theirs', () {
      final invitee = joinedFamily.copyWith(joinedByInvitation: true);
      expect(OnboardingSteps.shouldShowChecklist(invitee), isFalse);
      // Nothing done, nothing dismissed: still not theirs.
      expect(
          OnboardingSteps.shouldShowChecklist(
              fresh.copyWith(joinedByInvitation: true)),
          isFalse);
      // An explicit "show it again" from the profile is honoured.
      expect(OnboardingSteps.shouldShowChecklist(invitee, reopened: true),
          isTrue);
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

  group('firstRunActive (U-61)', () {
    const fresh = OnboardingSignals();
    const finished = OnboardingSignals(
      hasOtherActiveMember: true,
      hasAnyPlannedDay: true,
      hasOpenedSwapExplanation: true,
    );

    test('a founder with work left and the card up is inside the first run',
        () {
      expect(OnboardingSteps.firstRunActive(fresh), isTrue);
      expect(
          OnboardingSteps.firstRunActive(
              fresh.copyWith(hasAnyPlannedDay: true)),
          isTrue);
    });

    test('it ends by finishing or by dismissing — and never began for the '
        'invitee', () {
      expect(OnboardingSteps.firstRunActive(finished), isFalse);
      expect(
          OnboardingSteps.firstRunActive(
              fresh.copyWith(checklistDismissed: true)),
          isFalse);
      expect(
          OnboardingSteps.firstRunActive(
              fresh.copyWith(joinedByInvitation: true)),
          isFalse);
    });
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
          hasOpenInvitation: true,
          checklistDismissed: true,
          joinedByInvitation: true);
      final copy = signals.copyWith(hasAnyPlannedDay: true);
      expect(copy.hasOpenInvitation, isTrue);
      expect(copy.checklistDismissed, isTrue);
      expect(copy.joinedByInvitation, isTrue);
    });
  });
}
