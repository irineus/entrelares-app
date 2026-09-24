/// F-50 — the Visualizador, as the client mirrors it.
///
/// The database is the rule (`create_viewer_invitation`, the viewer guard on
/// every table of the plan, the notification filter); this only decides what
/// the screen OFFERS, so a door the server would refuse is not shown.
library;

/// Why a new viewer invitation would be refused, or [none].
enum ViewerInviteBlock { none, freeCap, maxCap }

abstract final class ViewerRules {
  /// [viewersTaken] = viewers in the family + open viewer invitations — the
  /// server's `viewer_count()`.
  static ViewerInviteBlock inviteBlock({
    required int viewersTaken,
    required bool isPremium,
    required int freeViewers,
    required int maxViewers,
  }) {
    if (viewersTaken >= maxViewers) return ViewerInviteBlock.maxCap;
    if (!isPremium && viewersTaken >= freeViewers) {
      return ViewerInviteBlock.freeCap;
    }
    return ViewerInviteBlock.none;
  }
}
