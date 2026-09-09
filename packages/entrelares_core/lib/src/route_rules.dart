/// S-02 in router terms: which screens an unauthenticated visitor may reach,
/// and where everyone else is sent. Mirror of the web's `MainLayout.EnforceAuth`
/// allow-list.
///
/// **There is no remembered destination any more (T-64, 08/09/2026).** There
/// used to be: the session gate has to answer BEFORE routing (pilot lesson
/// 1.1), the app parked the cold entry on `/splash` while it did, and the
/// destination was held in a `pendingLocation` to be handed back afterwards.
/// On the web that whole apparatus was a defect factory — go_router runs the
/// top-level redirect at most once per navigation and reports the parked
/// `/splash` late, so the memory was spent by the wrong evaluation and the
/// address bar disagreed with the screen. The app now simply **does not build
/// a router until the gate has answered** (`main.dart`), so the browser's own
/// URL is still the URL when routing starts and the first decision made about
/// it is the right one. Nothing to remember, nothing to lose.
library;

enum AuthPhase {
  /// The restored session is still being validated. **The router does not
  /// exist in this phase** — the app shows the splash instead of routing at
  /// all, which is what leaves the browser's URL untouched. Kept in the enum
  /// because the app's own phase machine needs the state.
  gate,

  /// No live session.
  anon,

  /// F-57: a validated session with NO profile — an OAuth sign-up whose
  /// profile `handle_new_user` deferred. The app is closed to it except the
  /// onboarding screen, where family (or invitation claim) and S-13 consent
  /// are collected.
  onboarding,

  /// A validated session.
  authed,
}

abstract final class RouteRules {
  /// Where the app sits while the gate answers on a platform that hands it no
  /// URL of its own (Android's cold start). On the web the browser's address is
  /// the initial location and this is never entered by the app itself — but it
  /// stays a real route, because an old bookmark or PWA shortcut may still name
  /// it, and it is in [anonymousOnlyRoutes] so a signed-in visitor who lands
  /// here gets the calendar.
  static const String splash = '/splash';
  static const String login = '/login';
  static const String register = '/register';
  static const String resetPassword = '/reset-password';
  static const String updatePassword = '/update-password';

  /// F-57: where a profile-less (deferred OAuth) session lives until it
  /// founds a family or claims its invitation.
  static const String onboarding = '/onboarding';

  static const String home = '/';

  /// Reachable without a session. `/update-password` is here even though the
  /// recovery visitor is technically authenticated: opening it anonymously
  /// shows the web's own "invalid session" message instead of bouncing.
  static const Set<String> publicRoutes = {
    login,
    register,
    resetPassword,
    updatePassword,
  };

  /// Screens an authenticated visitor has no business on: a sign-up form
  /// cannot apply to them, and a login form is already answered. F-57 adds
  /// the onboarding screen — despite the name, a FULLY onboarded visitor has
  /// no business there either (their family already exists), and the
  /// onboarding PHASE forces its own route regardless of this set.
  static const Set<String> anonymousOnlyRoutes = {
    splash,
    login,
    register,
    resetPassword,
    onboarding,
  };

  static bool isPublic(String location) => publicRoutes.contains(location);

  /// Where the router should send this visitor; null means "stay here".
  ///
  /// Staying is the answer that matters on the web: the location this is asked
  /// about is the URL the reader typed, pasted, refreshed or tapped in a
  /// notification, and an authenticated reader keeps it untouched.
  static String? redirect({
    required AuthPhase phase,
    required String location,
  }) =>
      switch (phase) {
        // Unreachable in practice — the app renders the splash instead of
        // routing while the gate decides, precisely so that nothing moves the
        // URL before the answer. Null keeps that promise if it is ever asked.
        AuthPhase.gate => null,
        AuthPhase.anon => isPublic(location) ? null : login,
        // F-57: a profile-less session is confined to the onboarding screen —
        // the S-11 leaving confinement's shape, for the opposite end of the
        // account's life.
        AuthPhase.onboarding => location == onboarding ? null : onboarding,
        AuthPhase.authed =>
            anonymousOnlyRoutes.contains(location) ? home : null,
      };
}
