/// U-23 — the steps of the "Primeiros passos" activation checklist. Mirror of
/// `entrelares-app` `Entrelares/Helpers/OnboardingSteps.cs`.
///
/// Order is the order a first session should take them, and it is not
/// arbitrary: inviting comes first because the swap workflow — the whole
/// product — needs two people, and a tester who never reaches the second
/// parent never sees it at all.
library;

import 'localization/k.dart';
import 'localization/k_app.dart';

enum OnboardingStep {
  /// Invite the co-caregiver (F-31's invite loop).
  inviteCoCaregiver(
    titleKey: K.onbStepInviteTitle,
    hintKey: K.onbStepInviteHint,
    doneHintKey: K.onbStepInviteDoneHint,
    actionKey: K.onbStepInviteAction,
  ),

  /// Plan days — any day at all, usually through the 🗓️ wizard.
  planTheDays(
    titleKey: K.onbStepPlanTitle,
    hintKey: K.onbStepPlanHint,
    doneHintKey: K.onbStepPlanDoneHint,
    actionKey: K.onbStepPlanAction,
  ),

  /// Read what a swap request is and why the other parent must accept.
  understandSwaps(
    titleKey: K.onbStepSwapTitle,
    hintKey: K.onbStepSwapHint,
    doneHintKey: K.onbStepSwapDoneHint,
    actionKey: K.onbStepSwapAction,
  ),

  /// F-09 — turn on the phone alerts. LAST on purpose: it is the only step
  /// that asks for something from OUTSIDE the product (an OS permission), and
  /// it only makes sense once there is a second caregiver who might ask for a
  /// swap. Offering it first would spend the one-shot Android dialog on
  /// someone who has not yet seen why they would want it.
  enablePush(
    titleKey: KApp.onbStepPushTitle,
    hintKey: KApp.onbStepPushHint,
    doneHintKey: KApp.onbStepPushDoneHint,
    actionKey: KApp.onbStepPushAction,
  );

  const OnboardingStep({
    required this.titleKey,
    required this.hintKey,
    required this.doneHintKey,
    required this.actionKey,
  });

  final String titleKey;
  final String hintKey;

  /// What the line says once the step is done — the card keeps explaining
  /// itself instead of going blank.
  final String doneHintKey;

  /// The step's call to action. It survives completion on purpose (the web
  /// keeps it too): "Convidar" is still useful after the first invitation.
  final String actionKey;
}

/// The facts a step is decided from. Every field is a plain bool so the rules
/// below are pure and testable without a database — READING the facts is the
/// data source's job, deciding what they MEAN is this file's.
class OnboardingSignals {
  /// A second live member holds a seat in the family.
  final bool hasOtherActiveMember;

  /// An invitation was sent and is neither accepted nor revoked.
  final bool hasOpenInvitation;

  /// F-56: a pending member (invited, not yet joined — or not even invited
  /// yet) is on the calendar. Reaching out happened: the other caregiver
  /// exists in this family's plan, whether or not an e-mail went out.
  final bool hasPendingMember;

  /// The family has at least one row in `care_schedules`, any date.
  final bool hasAnyPlannedDay;

  /// This member opened the explanation sheet at least once
  /// (`profiles.onboarding_swap_explained_at`).
  final bool hasOpenedSwapExplanation;

  /// This member has requested, or been asked to approve, a swap.
  final bool hasTakenPartInASwap;

  /// This member put the card away (`profiles.onboarding_dismissed_at`).
  final bool checklistDismissed;

  /// F-09: whether this BUILD can push at all. False on the web channel, which
  /// has no transport — see [visibleIn] for why that has to gate the step and
  /// not merely grey it out.
  final bool pushSupported;

  /// F-09: a device is registered AND the OS permits notifications. Real state
  /// on both halves: a stored flag would keep claiming push was on after the
  /// permission was revoked in Settings.
  final bool hasPushEnabled;

  const OnboardingSignals({
    this.hasOtherActiveMember = false,
    this.hasOpenInvitation = false,
    this.hasPendingMember = false,
    this.hasAnyPlannedDay = false,
    this.hasOpenedSwapExplanation = false,
    this.hasTakenPartInASwap = false,
    this.checklistDismissed = false,
    this.pushSupported = false,
    this.hasPushEnabled = false,
  });

  /// The web's `with { HasAnyPlannedDay = … }` — Home ORs the loaded signal
  /// with the month it already has in hand rather than re-querying.
  OnboardingSignals copyWith({
    bool? hasOtherActiveMember,
    bool? hasOpenInvitation,
    bool? hasPendingMember,
    bool? hasAnyPlannedDay,
    bool? hasOpenedSwapExplanation,
    bool? hasTakenPartInASwap,
    bool? checklistDismissed,
    bool? pushSupported,
    bool? hasPushEnabled,
  }) =>
      OnboardingSignals(
        hasOtherActiveMember: hasOtherActiveMember ?? this.hasOtherActiveMember,
        hasOpenInvitation: hasOpenInvitation ?? this.hasOpenInvitation,
        hasPendingMember: hasPendingMember ?? this.hasPendingMember,
        hasAnyPlannedDay: hasAnyPlannedDay ?? this.hasAnyPlannedDay,
        hasOpenedSwapExplanation:
            hasOpenedSwapExplanation ?? this.hasOpenedSwapExplanation,
        hasTakenPartInASwap: hasTakenPartInASwap ?? this.hasTakenPartInASwap,
        checklistDismissed: checklistDismissed ?? this.checklistDismissed,
        pushSupported: pushSupported ?? this.pushSupported,
        hasPushEnabled: hasPushEnabled ?? this.hasPushEnabled,
      );
}

/// Which steps are done, and whether the checklist belongs on screen.
///
/// **Everything here reads real state, never a "seen" flag** — with exactly one
/// deliberate exception. "Convidar" is true because an invitation exists,
/// "Planejar os dias" because a day exists. A checklist that ticked itself off
/// from a flag would tell someone they had finished something they never did,
/// which is worse than showing no checklist: the card's whole claim is that it
/// describes THEIR family.
///
/// **The exception is understanding.** Nobody's comprehension is a row in any
/// table, so [OnboardingStep.understandSwaps] is satisfied by opening the
/// explanation — or, better, by having actually lived a swap request, which is
/// real state and is why the second signal exists.
abstract final class OnboardingSteps {
  /// Every step this product has, in the order the checklist renders them.
  /// Rendering and counting use [visibleIn] instead — see there.
  static const List<OnboardingStep> all = OnboardingStep.values;

  /// The steps that belong on THIS build's checklist.
  ///
  /// **Why a step can be absent rather than merely unfinished.** The checklist
  /// hides itself when everything is done, so a step that CANNOT be finished
  /// keeps it on screen forever. On the web channel there is no push transport
  /// at all — [OnboardingStep.enablePush] would sit at "3 de 4" for the rest
  /// of that person's life, on a card whose whole claim is that it describes
  /// their family and is nearly done. Greying it out has the same effect on
  /// the count, which is the number people actually read.
  ///
  /// Marking it "done" instead would be worse: it would tell someone they had
  /// finished something they never did, which is the exact failure the file's
  /// header rules out.
  static List<OnboardingStep> visibleIn(OnboardingSignals signals) => [
        for (final step in all)
          if (step != OnboardingStep.enablePush || signals.pushSupported) step,
      ];

  /// The line under a DONE step. One step says something different depending
  /// on HOW it was done: "the other person was invited" is false when the
  /// admin only added them to the calendar (F-56) — that card says so and
  /// keeps the invitation as the next thing to do.
  static String doneHintKeyFor(OnboardingStep step, OnboardingSignals signals) =>
      step == OnboardingStep.inviteCoCaregiver &&
              signals.hasPendingMember &&
              !signals.hasOtherActiveMember &&
              !signals.hasOpenInvitation
          ? KApp.onbStepInviteDoneHintPending
          : step.doneHintKey;

  static bool isDone(OnboardingStep step, OnboardingSignals signals) =>
      switch (step) {
        // A sent invitation counts. The step is "reach out to the other
        // parent", and whether they accept today or on Friday is not something
        // this user can act on — leaving it red would make the card nag about
        // someone else's inbox.
        // F-56: a pending member counts too — the other caregiver is on the
        // calendar, which is the solo parent's whole way of reaching out.
        OnboardingStep.inviteCoCaregiver => signals.hasOtherActiveMember ||
            signals.hasOpenInvitation ||
            signals.hasPendingMember,

        // ANY planned day, not "this month": someone who plans August in July
        // has done this step, and a checklist that reset itself on the 1st
        // would be measuring the calendar, not the person.
        OnboardingStep.planTheDays => signals.hasAnyPlannedDay,

        OnboardingStep.understandSwaps =>
          signals.hasOpenedSwapExplanation || signals.hasTakenPartInASwap,

        // F-09: real state on both halves — a registered device AND an OS that
        // still permits notifications. This is the record's own rule for the
        // step: it closes when THIS DEVICE has a `push_subscriptions` row,
        // never when a sheet was shown.
        OnboardingStep.enablePush => signals.hasPushEnabled,
      };

  /// How many steps are done (the "2 de 3" the card shows).
  static int doneCount(OnboardingSignals signals) =>
      visibleIn(signals).where((step) => isDone(step, signals)).length;

  static bool allDone(OnboardingSignals signals) =>
      visibleIn(signals).every((step) => isDone(step, signals));

  /// Whether the card belongs on the calendar screen right now.
  ///
  /// Two ways to lose it, and they are different things: finishing (nothing
  /// left to say) and dismissing (a decision to put it away). Neither deletes
  /// it — both leave it reachable from the profile page, because a first-run
  /// guide that cannot be reopened is a guide you can only read once, by
  /// accident.
  ///
  /// The invitee's case falls out of this for free: they arrive into a family
  /// that already has a second member and a plan, so two steps are already
  /// ticked and the card renders nearly-done — which is exactly their
  /// situation.
  ///
  /// [reopened] overrides both, because the two states that would otherwise
  /// keep the card hidden are precisely the two an explicit "show it again" is
  /// asking about.
  static bool shouldShowChecklist(OnboardingSignals signals,
          {bool reopened = false}) =>
      reopened || (!signals.checklistDismissed && !allDone(signals));
}
