/// F-07 — which door the *Crianças* page offers for the plan's mode.
///
/// The server is the rule (`set_schedule_mode`: the flag, an admin, two
/// children for a plan per child, no pending request from today on); this
/// only decides what the page SHOWS, so a door the server would refuse for a
/// reason the page already knows is not offered.
library;

/// What the plan card offers.
enum ScheduleModeOffer {
  /// The flag is off, or the family has no child: no card at all.
  hidden,

  /// One plan for every child, and fewer than two children: the card says a
  /// plan per child needs two, with no action.
  needsTwoChildren,

  /// One plan for every child and two or more children: an admin may switch
  /// to one plan per child.
  toPerChild,

  /// One plan per child: an admin may go back to one plan for everyone.
  toSingle,
}

abstract final class ScheduleModeRules {
  static const String single = 'single';
  static const String perChild = 'per_child';

  /// The card's state. A non-admin reads the same state; only the ACTION is
  /// the admin's, which the page decides on its own.
  static ScheduleModeOffer offer({
    required bool flagOn,
    required String mode,
    required int childCount,
  }) {
    // The server refuses every switch while the flag is off, so the card
    // (and its door) exists only with the flag on.
    if (!flagOn) return ScheduleModeOffer.hidden;
    if (mode == perChild) return ScheduleModeOffer.toSingle;
    if (childCount == 0) return ScheduleModeOffer.hidden;
    if (childCount < 2) return ScheduleModeOffer.needsTwoChildren;
    return ScheduleModeOffer.toPerChild;
  }
}
