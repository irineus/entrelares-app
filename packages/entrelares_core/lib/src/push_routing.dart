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

  /// F-35 — the Conversa: a chat notice opens the conversation itself, where
  /// the text is, not the notification that announced it.
  chat,

  /// F-77 — the plan page (`/family/plan`): a notice about the Premium trial's
  /// end asks one thing, and the page that answers it is where the subscribe
  /// button is. The row stays in "Todas" with the same way in.
  plan,

  /// F-78 — the calendar with the wizard open on today: a family that never
  /// planned is asked to plan, and the wizard is where that happens.
  planFirst,

  /// F-81 — the calendar with ONE day's sheet open: an admin changed that day
  /// of the reader's, and the day itself answers "what changed?". The day
  /// rides in the payload (`date`); without a real one the tap falls back to
  /// "Todas", where the row always is.
  day,

  /// F-81 — Relatórios → Histórico: an admin changed SEVERAL of the reader's
  /// days in one action, and the Histórico is where that action reads as one
  /// entry (F-51's fold) with every day in it.
  auditTrail,

  /// F-101 — the Família page (`/family`): the invitation the reader sent
  /// expired, and the card there is where "Compartilhar de novo" makes a new
  /// link. The row stays in "Todas" with the same way in.
  family,
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

  /// F-52 — the `kind`s of a `day_notice` that leave the reader with something
  /// to DO. The others (a courtesy note, an answer, a cancellation) are news,
  /// and news belongs in "Todas", where the row always is.
  ///
  /// **Why routing had to learn a second dimension** (18/09/2026). It used to
  /// take a type alone, so `day_notice` had to be all-actionable or
  /// all-receipt. Picking "actionable" meant a courtesy note would open an
  /// empty "Para você"; the first version avoided that by refusing to push a
  /// courtesy note at all — and the owner's first real round sent exactly
  /// that, twice, and no phone rang. "Vou atrasar 15 minutos" is the most
  /// common aviso there is and the one whose whole value is arriving before
  /// the other person leaves the house. So the payload carries `kind` now and
  /// both channels read it, which costs one field and settles the question in
  /// the only place where the answer is actually known.
  static const Set<String> _actionableNoticeKinds = {'pickup', 'keep'};

  /// Where a push of [type] (and, for F-52, [kind]) should land. Unknown
  /// types and kinds go to Todas: a
  /// future writer's notice is a receipt until someone decides otherwise, and
  /// the wrong guess in that direction merely shows a full list instead of an
  /// empty one.
  static NotificationLanding landingFor(String? type, {String? kind}) =>
      _chat.contains(type)
          ? NotificationLanding.chat
          : _plan.contains(type)
              ? NotificationLanding.plan
              : familyTypes.contains(type)
              ? NotificationLanding.family
              : type == 'plan_ending' && planFirstKinds.contains(kind)
                  ? NotificationLanding.planFirst
                  : type == adminChangeType && adminChangeDayKinds.contains(kind)
                      ? NotificationLanding.day
                      : type == adminChangeType &&
                              adminChangeTrailKinds.contains(kind)
                          ? NotificationLanding.auditTrail
                          : _landingForNotice(type, kind: kind);

  /// F-78: the `plan_ending` kinds whose tap opens the wizard.
  static const Set<String> planFirstKinds = {'unplanned'};

  /// F-81: an admin's direct change of the reader's days — one day opens
  /// that day, several open the Histórico. Any other kind is a future
  /// writer's shape and falls to "Todas".
  static const String adminChangeType = 'day_admin_change';
  static const Set<String> adminChangeDayKinds = {'single'};
  static const Set<String> adminChangeTrailKinds = {'batch'};

  /// F-35: the types that open the Conversa.
  static const Set<String> _chat = {'chat_message'};

  /// F-77: the types that open the plan page.
  /// F-80 PR 3: the referral reward too — the new end shows there.
  static const Set<String> planTypes = {'premium_trial', 'referral_reward'};
  static const Set<String> _plan = planTypes;

  /// F-101: the types that open the Família page.
  static const Set<String> familyTypes = {'invitation_expired'};

  static NotificationLanding _landingForNotice(String? type, {String? kind}) =>
      _actionable.contains(type) ||
              (type == 'day_notice' &&
                  _actionableNoticeKinds.contains(kind))
          ? NotificationLanding.incoming
          : NotificationLanding.history;
}
