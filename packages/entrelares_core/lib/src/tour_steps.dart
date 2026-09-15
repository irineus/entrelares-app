/// U-23 — the 4-stop guided tour. Mirror of `entrelares-app`
/// `Entrelares/Helpers/TourSteps.cs`, with the one change the parity map calls
/// for: the web pins each stop to a CSS SELECTOR and spotlights it from
/// `tour.js`; a Flutter tour cannot query the DOM, so a stop names a [TourTarget]
/// and the shell registers a key per target. Same stops, same order, same copy —
/// only the addressing changes.
///
/// The stops are chosen to answer the four questions a first session actually
/// has, in the order it has them: who has the child now, what the colours mean,
/// how to fill an empty calendar, and where the other parent's requests land.
library;

import 'localization/k.dart';

/// What a stop highlights. The shell owns the mapping to real widgets; a target
/// with no registered widget degrades to a card with no spotlight rather than
/// breaking the tour (the same failure mode the web chose).
enum TourTarget {
  todayCard,
  calendarLegend,

  /// U-36: the wizard no longer has an icon of its own — it is an item of the
  /// calendar's ⋮ actions menu, so the stop spotlights the MENU button and the
  /// copy says which item to pick. Named after the widget it lights, not the
  /// feature it explains, so a future item added to the menu does not inherit
  /// a lying name.
  actionsMenu,
  notificationsTab,
}

class TourStep {
  final TourTarget target;
  final String titleKey;
  final String bodyKey;

  const TourStep(this.target, this.titleKey, this.bodyKey);
}

abstract final class TourSteps {
  static const List<TourStep> all = [
    TourStep(TourTarget.todayCard, K.tourTodayTitle, K.tourTodayBody),
    TourStep(TourTarget.calendarLegend, K.tourColoursTitle, K.tourColoursBody),
    TourStep(TourTarget.actionsMenu, K.tourWizardTitle, K.tourWizardBody),
    TourStep(TourTarget.notificationsTab, K.tourNotificationsTitle,
        K.tourNotificationsBody),
  ];

  static int get count => all.length;

  /// The stop at [index], or null when the tour is over — the caller advances
  /// until it gets null instead of tracking the bound itself.
  static TourStep? at(int index) =>
      index >= 0 && index < all.length ? all[index] : null;
}
