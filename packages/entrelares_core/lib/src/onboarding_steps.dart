/// U-23 — the steps of the "Primeiros passos" activation checklist. Mirror of
/// `entrelares-app` `Entrelares/Helpers/OnboardingSteps.cs`.
///
/// Order is the order a first session should take them, and it is the
/// FOUNDER's order (U-61, owner, 07/10/2026): plan first, because a family that
/// never plans never invites the other carer either (20 of 30 families on
/// 23/09 had never planned a day, all single-member — F-78's finding); then
/// invite; then understand the swap. The checklist is the founder's: an
/// invitee arrives into a family that already exists and gets U-58's welcome
/// instead — see [OnboardingSteps.shouldShowChecklist].
///
/// **Exactly three steps, and the intro says "três".** The push ask used to be
/// a fourth step here AND the F-59 strip under the Hoje card — the same
/// one-shot OS dialog offered twice in the first seconds, over a card whose
/// intro counted three. The strip is the one ask now, and
/// [OnboardingSteps.firstRunActive] holds it back until the first run is over
/// or a notice has actually arrived (`PushTodayRules`).
library;

import 'localization/k.dart';
import 'localization/k_app.dart';

enum OnboardingStep {
  /// Plan days — any day at all, usually through the wizard. First: it is
  /// what turns an empty account into a calendar, and the Hoje card without a
  /// plan points here too (`showPlanNudge`).
  planTheDays(
    titleKey: K.onbStepPlanTitle,
    hintKey: K.onbStepPlanHint,
    doneHintKey: K.onbStepPlanDoneHint,
    actionKey: K.onbStepPlanAction,
  ),

  /// Invite the co-caregiver (F-31's invite loop).
  inviteCoCaregiver(
    titleKey: K.onbStepInviteTitle,
    hintKey: K.onbStepInviteHint,
    doneHintKey: K.onbStepInviteDoneHint,
    actionKey: K.onbStepInviteAction,
  ),

  /// Read what a swap request is and why the other parent must accept.
  understandSwaps(
    titleKey: K.onbStepSwapTitle,
    hintKey: K.onbStepSwapHint,
    doneHintKey: K.onbStepSwapDoneHint,
    actionKey: K.onbStepSwapAction,
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

  /// U-61: this member came in through an invitation (`profiles.
  /// joined_via_invite`, S-15 — stamped by trigger, immutable). The checklist
  /// is the founder's first run; the invitee's is U-58's welcome.
  final bool joinedByInvitation;

  const OnboardingSignals({
    this.hasOtherActiveMember = false,
    this.hasOpenInvitation = false,
    this.hasPendingMember = false,
    this.hasAnyPlannedDay = false,
    this.hasOpenedSwapExplanation = false,
    this.hasTakenPartInASwap = false,
    this.checklistDismissed = false,
    this.joinedByInvitation = false,
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
    bool? joinedByInvitation,
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
        joinedByInvitation: joinedByInvitation ?? this.joinedByInvitation,
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
  static const List<OnboardingStep> all = OnboardingStep.values;

  /// The steps that belong on the checklist. Since U-61 every step can be
  /// finished on every build (the push step, which the web channel could
  /// never finish, left the checklist for the F-59 strip), so this is [all];
  /// the seam stays because rendering and counting go through it.
  static List<OnboardingStep> visibleIn(OnboardingSignals signals) => all;

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
  /// **The invitee never gets it on their own (U-61, owner, 07/10/2026).**
  /// Before, they arrived with two steps "already ticked" — "a outra pessoa
  /// já foi convidada", "já existem dias planejados" — for things the FOUNDER
  /// did, on top of the request that was actually waiting for their answer
  /// (T-103, seen on the device). Their first run is U-58's welcome; the
  /// Hoje card names the request that waits for them (U-60/F-94).
  ///
  /// [reopened] overrides all three, because the states that would otherwise
  /// keep the card hidden are precisely what an explicit "show it again" from
  /// the profile is asking about — the invitee included.
  static bool shouldShowChecklist(OnboardingSignals signals,
          {bool reopened = false}) =>
      reopened ||
      (!signals.joinedByInvitation &&
          !signals.checklistDismissed &&
          !allDone(signals));

  /// U-61 — whether the founder is still inside the first run: the checklist
  /// is theirs, has work left and was not put away. While it is true the
  /// other first-session asks wait their turn — the F-59 push strip
  /// (`PushTodayRules.show`) and the F-31 invite nudge behind the plan nudge
  /// (`showPlanNudge`) — so the first screen is the calendar, the plan and one
  /// thing to do, not four strips over a week of the month.
  static bool firstRunActive(OnboardingSignals signals) =>
      !signals.joinedByInvitation &&
      !signals.checklistDismissed &&
      !allDone(signals);
}
