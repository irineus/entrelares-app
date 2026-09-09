import 'package:entrelares_core/entrelares_core.dart';

/// The STATE half of [RouteRules]: where a cold entry wanted to go before the
/// session gate had answered, and what happens to that memory once it has.
///
/// The pure half was always right and has its own suite. This half — one
/// nullable string that has to survive an async phase change — had no test at
/// all, and that asymmetry is where **T-64** lived: on the web every direct
/// entry into an inner route (`/family`, a pasted link, F5, the tap on a web
/// push) ended on the calendar.
///
/// Two facts about go_router on the web explain it, and together they are why
/// the destination is restored by an **explicit navigation** instead of being
/// handed back from the redirect:
///
///  * the top-level redirect runs **at most once per navigation** (go_router's
///    own words, `configuration.dart`), and the location it redirects TO is
///    never reported as route information. So once the gate parks a deep entry
///    on `/splash`, the router's route information — and the address bar —
///    stay on `/splash` even while the reader is looking at Notificações;
///  * every later phase ping therefore re-evaluates `/splash`. Handing the
///    destination back from the redirect consumed it on the FIRST of those,
///    and `_applyProfileGates` fires a second one on every authenticated boot:
///    that second evaluation found nothing remembered and fell to `home`.
///    `/notifications?tab=incoming&n=1` → `/splash` → `/`, measured in a
///    browser on 08/09/2026.
///
/// An explicit `go` is a real navigation: it updates the route information and
/// the address bar, so there is no stale `/splash` left for a later ping to get
/// wrong — and F5 on the restored screen stays put, because the URL finally
/// names the screen the reader is on.
class AppRouteGate {
  AppRouteGate({
    required this.phase,
    required this.isLeaving,
    required this.consentState,
    required this.go,
  });

  /// The app's current auth phase, read at every decision — never cached.
  final AuthPhase Function() phase;

  /// S-11: this member asked to leave (mirror of `MainLayout.EnforceLeaving`).
  final bool Function() isLeaving;

  /// S-15/B-4: whether the re-consent gate warns, blocks, or says nothing.
  final ConsentGateState Function() consentState;

  /// A real navigation — `GoRouter.go`, never a redirect.
  final void Function(String location) go;

  String? _pendingLocation;

  /// What the gate is still holding, if anything.
  String? get pendingLocation => _pendingLocation;

  /// The router's `redirect` callback.
  String? redirect({required String matchedLocation, required Uri uri}) {
    final current = phase();

    if (current == AuthPhase.gate) {
      // Remember the destination WITH its query — the invite token lives there
      // — for as long as the gate is still deciding.
      if (matchedLocation != RouteRules.splash) {
        _pendingLocation = uri.toString();
      }
      return RouteRules.redirect(
          phase: AuthPhase.gate, location: matchedLocation);
    }

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

    // No `pendingLocation` here, on purpose: a redirect that hands the memory
    // back is consumed by whichever evaluation happens to come first, and on
    // the web that is not the one that reaches the reader. Restoring is
    // [restorePendingDestination]'s job, and it runs exactly once per phase.
    return RouteRules.redirect(phase: current, location: matchedLocation);
  }

  /// Called the moment the auth phase moves, and only then.
  ///
  /// Returns whether it navigated — the caller pings the router itself when it
  /// did not, since a `go` already re-runs the whole redirect chain.
  bool restorePendingDestination() {
    final pending = _pendingLocation;
    final current = phase();
    if (pending == null || current == AuthPhase.gate) return false;

    // The same pure rule, asked from the screen the gate parked us on: for an
    // anonymous visitor only a public destination (restoring a guarded screen
    // would hand over exactly what S-02 refuses), for an authenticated one
    // anything that is not an anonymous-only screen, and the calendar when the
    // memory is not honourable.
    final destination = RouteRules.redirect(
      phase: current,
      location: RouteRules.splash,
      pendingLocation: pending,
    );

    // Forget it once it has been honoured — or once the phase is AUTHED, the
    // terminal answer: a destination that is not honourable to a signed-in
    // reader never will be. An ANONYMOUS answer is not terminal, which is what
    // makes "deep link → login → the screen you asked for" work, and the same
    // for the F-57 onboarding detour.
    if (destination == pending || current == AuthPhase.authed) {
      _pendingLocation = null;
    }

    if (destination == null || destination == RouteRules.splash) return false;
    go(destination);
    return true;
  }
}
