/// F-59 — the *Ativar notificações* strip under the Hoje card.
///
/// Origin: on 02/10/2026 the owner moved every notice that is not essential
/// out of e-mail — swap requests and answers, the 24 h reminder, the
/// auto-approval, someone joining or leaving, the plan's end — so that the
/// product can be opened to a wider audience without the per-account Resend
/// allowance becoming its ceiling. From then on a member whose devices have no
/// push learns of those only by opening the app, and on 21/09/2026 that was 31
/// of the 35 active members in production (U-54's count). The Notificações
/// screen already holds the one door to the OS dialog (F-09, U-43); this strip
/// is the sign on the street that points to it.
///
/// A pure function of what the app already holds:
///  * the [PushNudgeStep] U-54 settles for THIS device — only a step with a
///    button ([PushNudgeStep.isActionable]) earns the strip; a refusal or an
///    unsupported browser keeps its quiet line on Notificações;
///  * the dismissals recorded on this device, with U-54's rhythm (back after
///    [InstallHintRules.snooze], quiet after [InstallHintRules.maxDismissals]);
///  * whether the ACCOUNT has push on any device, and when the newest unread
///    notification addressed to the reader was written.
///
/// **The owner's rule (02/10/2026): a notice that reached nobody re-asks.**
/// When the account has no push on any device and something new arrived for
/// the reader after the last dismissal, the strip comes back — whatever the
/// rhythm says, the third dismissal included. That notice went out with no
/// e-mail behind it, so the reader just learned by opening the app what a
/// phone would have told them; the moment to ask again is exactly then. A
/// reader whose OTHER phone rings is not chased: the notice reached them.
///
/// **U-61 (owner, 07/10/2026): not in the first seconds.** The audit saw the
/// strip over a founder's empty calendar — "trocas não vêm por e-mail" before
/// any swap, or any second carer, existed. While the founder's first run is
/// still active (`OnboardingSteps.firstRunActive`: the checklist is theirs,
/// has work left and was not put away) the strip waits — unless a notice has
/// already arrived for the reader, which is the moment the owner's rule above
/// names. Finishing or dismissing the checklist ends the first run and the
/// strip takes its turn in the one-strip queue.
library;

import 'install_hint_rules.dart';
import 'push_nudge_rules.dart';

abstract final class PushTodayRules {
  /// The whole decision.
  static bool show({
    required PushNudgeStep step,
    required InstallHintDismissals dismissals,
    required DateTime now,
    required bool accountHasPush,
    DateTime? newestUnreadAt,
    bool firstRunActive = false,
  }) {
    if (!step.isActionable) return false;
    // U-61: the first run has its own asks; this one waits for a notice or
    // for the end of the run. A notice that arrived IS the moment to ask.
    if (firstRunActive && newestUnreadAt == null) return false;
    if (!InstallHintRules.isQuiet(dismissals, now)) return true;
    return missedSinceDismissal(
      dismissals: dismissals,
      accountHasPush: accountHasPush,
      newestUnreadAt: newestUnreadAt,
    );
  }

  /// Whether a notice reached nobody since the strip was last sent away: no
  /// device of the account receives push, and the newest unread notification
  /// is younger than that dismissal. A dismissal with no date (none here, but
  /// the record type allows it) is read as "long ago".
  static bool missedSinceDismissal({
    required InstallHintDismissals dismissals,
    required bool accountHasPush,
    DateTime? newestUnreadAt,
  }) {
    if (accountHasPush || newestUnreadAt == null) return false;
    final last = dismissals.last;
    return last == null || newestUnreadAt.isAfter(last);
  }
}
