import 'package:entrelares_core/entrelares_core.dart';

/// The app's `redirect`: [RouteRules] plus the two gates that need state the
/// pure rule cannot see — S-11's exit confinement and S-15's consent block.
///
/// It exists as a class so a test can drive the REAL decision inside a REAL
/// router. That is the asymmetry **T-64** was: `RouteRules` had a suite and was
/// right; the half that lives in the app had none, and it was where every web
/// deep link went to die.
///
/// **There is no remembered destination here, and that is the fix.** The app
/// used to park a cold entry on `/splash` while the session gate answered, and
/// hold its destination in a field. On the web that apparatus could not work:
/// go_router runs the top-level redirect at most once per navigation and
/// reports the parked `/splash` late, so the memory was spent by an evaluation
/// that never reached the reader, and the address bar ended up naming a screen
/// nobody was on. Measured in a browser on 08/09/2026: `/family` → `/splash` →
/// the calendar; and even once the screen was made right, the URL still read
/// `/splash`, so the next F5 replayed the whole thing.
///
/// The app now **builds no router at all while the phase is `gate`** — it
/// renders the splash instead (`main.dart`). The browser's URL is therefore
/// still the URL when routing starts, and the first decision made about it is
/// made by someone who already knows who is asking. Nothing to remember,
/// nothing to hand back, nothing to race.
class AppRouteGate {
  AppRouteGate({
    required this.phase,
    required this.isLeaving,
    required this.consentState,
  });

  /// The app's current auth phase, read at every decision — never cached.
  final AuthPhase Function() phase;

  /// S-11: this member asked to leave (mirror of `MainLayout.EnforceLeaving`).
  final bool Function() isLeaving;

  /// S-15/B-4: whether the re-consent gate warns, blocks, or says nothing.
  final ConsentGateState Function() consentState;

  /// The router's `redirect` callback; null means "stay here".
  String? redirect(String matchedLocation) {
    final current = phase();

    // The web's order, and it matters: authentication first, then the exit
    // confinement, then the consent gate. A member on their way out never
    // meets the re-consent screen — asking someone to accept new terms on the
    // way to deleting their account would be absurd.
    if (current == AuthPhase.authed) {
      if (FamilyLifecycleRules.mustStayOnLeavingScreen(
          isLeaving: isLeaving(), location: matchedLocation)) {
        return FamilyLifecycleRules.leavingRoute;
      }
      if (!isLeaving() &&
          consentState() == ConsentGateState.blocked &&
          matchedLocation != FamilyLifecycleRules.policyUpdateRoute &&
          matchedLocation != RouteRules.login) {
        return FamilyLifecycleRules.policyUpdateRoute;
      }
    }

    return RouteRules.redirect(phase: current, location: matchedLocation);
  }
}
