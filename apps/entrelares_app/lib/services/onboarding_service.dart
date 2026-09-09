import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';

import 'package:entrelares_db_contracts/models/member.dart';
import 'custody_data_source.dart';
import 'push_service.dart';

/// U-23 — reads the facts the activation checklist is decided from. Port of
/// `Entrelares/Services/OnboardingService.cs`.
///
/// The rules live in core ([OnboardingSteps]); this only gathers evidence, and
/// it is written to be CHEAP because the calendar is the hottest screen in the
/// app: a member who already dismissed the card costs zero queries, and the two
/// optional reads are skipped whenever an earlier fact already settles the step.
class OnboardingService extends ChangeNotifier {
  final CustodyDataSource _dataSource;

  /// F-09. Read rather than queried: [PushService.state] already reflects the
  /// OS permission AND the registration, so the step costs this hot screen
  /// nothing — and it is more truthful than the row alone, which survives a
  /// permission revoked in Settings.
  final PushService? push;

  OnboardingService(this._dataSource, {this.push});

  /// Session-scoped, deliberately not persisted: "show it again" is a request
  /// for THIS session, not a new stored preference.
  bool checklistReopened = false;

  /// U-29: a NOTIFYING flag, because the calendar's State stays alive in the
  /// tab stack — before, the profile's "Ver o tour de novo" set a flag nobody
  /// was watching, and the tour only fired when a background reload happened
  /// to run. Setting it true pings listeners; the calendar reacts at once.
  bool get tourReplayRequested => _tourReplayRequested;
  bool _tourReplayRequested = false;
  set tourReplayRequested(bool value) {
    _tourReplayRequested = value;
    if (value) notifyListeners();
  }

  /// [members] and [invitationsPending] are already in the caller's hands, so
  /// they are passed in rather than re-fetched.
  Future<OnboardingSignals> loadSignals({
    required Member me,
    required List<Member> members,
    bool force = false,
  }) async {
    final pushSupported = push?.supported ?? false;
    final hasPushEnabled = push?.state == PushState.on;

    final dismissed = me.onboardingDismissedAt != null;
    // The whole point of the short-circuit: a dismissed card asks nothing of
    // the network on every calendar open.
    if (dismissed && !force && !checklistReopened) {
      return const OnboardingSignals(checklistDismissed: true);
    }

    final hasOther = members.any((m) => m.id != me.id && m.isActiveMember);
    // F-56: a caregiver on the calendar with no account yet — the solo
    // parent's way of reaching out, invitation or not.
    final hasPending = members.any((m) => m.isPendingMember);
    // Only worth asking when nobody holds the second seat yet.
    final hasInvitation =
        hasOther ? false : await _dataSource.hasOpenInvitation();

    final explained = me.onboardingSwapExplainedAt != null;
    final facts = await _dataSource.fetchOnboardingFacts(
      myProfileId: me.id,
      // Comprehension is not a row; participation is. Skip the second read
      // whenever the explanation already settles the step.
      includeSwapParticipation: !explained,
    );

    return OnboardingSignals(
      hasOtherActiveMember: hasOther,
      hasOpenInvitation: hasInvitation,
      hasPendingMember: hasPending,
      hasAnyPlannedDay: facts.hasAnyPlannedDay,
      hasOpenedSwapExplanation: explained,
      hasTakenPartInASwap: facts.hasTakenPartInASwap,
      checklistDismissed: dismissed,
      pushSupported: pushSupported,
      hasPushEnabled: hasPushEnabled,
    );
  }

  /// Opening the explanation IS completing step 3 — stamped before the sheet
  /// renders, as in the web.
  Future<void> markSwapExplanationSeen() =>
      _dataSource.stampOnboarding(OnboardingStamp.swapExplained);

  Future<void> markTourSeen() =>
      _dataSource.stampOnboarding(OnboardingStamp.tourSeen);

  Future<void> markChecklistDismissed() =>
      _dataSource.stampOnboarding(OnboardingStamp.dismissed);

  /// The permanent door back in, from the profile page. It raises the
  /// session flag AND clears the stored dismissal — a guide you can only read
  /// once, by accident, is not a guide.
  ///
  /// U-29 (owner-reported, round 3): it also NOTIFIES, for the same reason the
  /// tour replay does — the calendar's State stays alive in the tab stack, so
  /// a flag nobody is told about only surfaces when a background reload
  /// happens to run ("sometimes the banner opens").
  ///
  /// U-29 round 5 (owner): the button promises the first steps, not a
  /// launcher to tap — so it also raises [checklistOpenRequested], and the
  /// calendar opens the checklist SHEET on landing.
  Future<void> reopenChecklist() async {
    checklistReopened = true;
    checklistOpenRequested = true;
    await _dataSource.clearChecklistDismissal();
    notifyListeners();
  }

  /// One-shot companion to [checklistReopened]: while that flag stays up for
  /// the whole session (it is what keeps the banner visible past `allDone`),
  /// this one is CONSUMED by the calendar when it opens the sheet — a later
  /// ping (a tour replay, say) must not reopen the sheet as a side effect.
  bool checklistOpenRequested = false;
}
