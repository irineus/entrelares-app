import 'localization/k_app.dart';

/// U-58 — the one sheet an invitee sees right after the invitation is
/// claimed, before the tour (`tour_steps.dart`).
///
/// It exists for the reader who arrives suspicious — often the other parent,
/// who did not choose the app — and answers three questions in order: what I
/// see now, what the others see about me, and what the record already holds.
///
/// Shown ONLY in the session where the claim happened: the client raises the
/// flag at the claim's own call site (`register-invitee`, `claim-invitation`),
/// never from a stored fact, so a member who joined before this item never
/// sees it. A Visualizador (F-50) gets its own lines: it changes nothing and
/// takes no part in swaps, so the caregiver's second point would be false.
abstract final class InviteeWelcomeRules {
  /// The points under the lead, in reading order.
  static List<String> pointKeys({required bool viewer}) => viewer
      ? const [
          KApp.viewerWelcomeSees,
          KApp.viewerWelcomeLimits,
          KApp.viewerWelcomeSeen,
        ]
      : const [
          KApp.welcomeSees,
          KApp.welcomeSeen,
          KApp.welcomeRecord,
        ];

  /// `member` prop of the `invitee-welcome-view` event: a closed token, never
  /// a name (T-78).
  static String memberProp({required bool viewer}) => viewer ? 'viewer' : 'full';
}

/// What the claim's call site knows and the calendar needs to say it: the
/// family and who invited. Held in memory for the session only.
class InviteeWelcome {
  final String familyName;
  final String inviterName;

  const InviteeWelcome({required this.familyName, required this.inviterName});
}
