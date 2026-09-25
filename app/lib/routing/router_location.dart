import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

/// The location on SCREEN, and the signal that it moved — for what names the
/// screen (the U-48 document title).
///
/// Not the route information provider, and that is the whole point: a
/// navigation the router makes ON ITS OWN — the redirect a `refreshListenable`
/// ping re-runs, which is how a sign-in leaves `/login` for the calendar —
/// reaches the provider through `routerReportsNewRouteInformation`, which
/// updates its value WITHOUT notifying (go_router 16.3.0). The ping itself
/// does notify the provider, but before the redirect has run, so a listener
/// there reads `/login` one last time and then never hears of `/`. On
/// 23/09/2026 that left the tab saying "[Dev] Login · Entrelares" over the
/// calendar. The delegate notifies on every configuration it installs — a
/// `go`, a redirect, a pop — with the new one already in place.
abstract final class RouterLocation {
  /// Calls [onChange] after the router installed a new configuration, and
  /// returns what detaches it.
  ///
  /// The router installs its FIRST configuration while it is being built (the
  /// T-64 mount, when the gate phase ends), and a `setState` from inside a
  /// build is an assertion — so a change heard mid-build is handed to the end
  /// of that frame.
  static VoidCallback listen(GoRouter router, VoidCallback onChange) {
    void listener() {
      final scheduler = SchedulerBinding.instance;
      if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        scheduler.addPostFrameCallback((_) => onChange());
      } else {
        onChange();
      }
    }

    router.routerDelegate.addListener(listener);
    return () => router.routerDelegate.removeListener(listener);
  }

  /// The configuration on screen — path and query, as the address bar will
  /// carry it. Before the first configuration exists (an empty match list,
  /// whose uri is empty) the provider's value is the only answer there is.
  static String of(GoRouter router) {
    final location = router.routerDelegate.currentConfiguration.uri.toString();
    if (location.isNotEmpty) return location;
    return router.routeInformationProvider.value.uri.toString();
  }
}
