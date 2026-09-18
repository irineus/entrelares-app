/// F-09 — where a tapped notification lands.
///
/// **Why this is not simply "the Notificações screen".** That screen has three
/// tabs and only one of them is right for a given notice. "Para você" lists
/// OPEN requests awaiting this person; a notification saying a swap was
/// approved is about a request that is now closed, so the tab it opens on is
/// empty — the person taps a notice and arrives at "nada pendente para você",
/// which reads as the app having lost what it just told them (owner, on the
/// first real device round, 29/08/2026).
///
/// **Why "Todas" and not "Enviadas".** Enviadas lists the requests this
/// person OPENED, so it holds the answer to a swap they asked for — and holds
/// nothing when the notice is about a request somebody else opened, or about a
/// day resolved automatically. Todas is the notification list itself, so
/// the row that was tapped is always in it, for every type this product pushes
/// and every type it may push later.
library;

/// The tab the Notificações screen should open on.
enum NotificationLanding {
  /// "Para você" — there is something here for this person to DO.
  incoming,

  /// "Todas" — the notice is a receipt; this is the tab that always holds
  /// the row that was tapped.
  history,
}

abstract final class PushRouting {
  /// The types that leave the recipient with an action pending.
  ///
  /// `auto_reminder` belongs here and it is the one worth reading twice: it
  /// goes to the APPROVER to say the request auto-approves in 24h if nobody
  /// replies. It is the most actionable notice the product sends — landing it
  /// in a read-only history would bury exactly the tap that still has a
  /// deadline attached.
  static const Set<String> _actionable = {
    'swap_requested',
    'revert_requested',
    'auto_reminder',
  };

  /// Where a push of [type] should land. Unknown types go to Todas: a
  /// future writer's notice is a receipt until someone decides otherwise, and
  /// the wrong guess in that direction merely shows a full list instead of an
  /// empty one.
  static NotificationLanding landingFor(String? type) =>
      _actionable.contains(type)
          ? NotificationLanding.incoming
          : NotificationLanding.history;
}
