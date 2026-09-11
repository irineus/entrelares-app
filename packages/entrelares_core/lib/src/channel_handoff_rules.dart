/// T-65 — how the WEB channel hands a reader over to the installed Android app.
///
/// A person reading `web.entrelares.app` in Chrome on Android who also has the
/// Play app had no way across: the two channels shared a product and nothing
/// else. The handoff is a link, and the whole decision is **which address it
/// uses**, because an address has an owner.
///
/// It is NOT an App Link. Covering `/` would end the web channel outright
/// (§1 — every visit to the site would open the app), and path-scoped App
/// Links for internal routes carry the same defect in miniature: the same
/// `https` URL, pasted in a browser or sent in an e-mail, would start opening
/// the app for everyone who has it. An App Link is a claim on an address, not
/// a button. So the handoff rides the custom scheme the app ALREADY owns —
/// the `${applicationId}` filter F-57 established — under a second host beside
/// `login-callback`:
///
/// ```
/// com.entrelares.app://open/notifications?tab=incoming
/// ```
///
/// The location travels in the PATH, and that is the load-bearing detail:
/// Android's Flutter embedding builds the initial route out of the intent's
/// `getPath()`, appending `?query` and `#fragment`, and returns null when the
/// path is empty. So go_router receives the location itself, with no parsing
/// step and no listener of our own; `…://open/` degrades to the app's
/// `initialLocation` instead of to an error. A `?path=` parameter would have
/// arrived as a route with an EMPTY path and needed an interceptor to undo.
///
/// **No session travels with it.** The URI carries a location and nothing
/// else; the installed app answers with its own session, or sends the reader
/// to its own login. Anything else would be a credential crossing channels
/// inside a URL — the exact shape `crash_rules.dart` exists to mask.
library;

import 'route_rules.dart';

abstract final class ChannelHandoffRules {
  /// The host of the intent filter that opens the app. Spelled once here;
  /// `web_channel_test` reads this literal and fails the build if
  /// `AndroidManifest.xml` registers a different one — the two sides are in
  /// two languages, and a rename would leave the button pointing at a URI no
  /// activity answers, which Chrome reports as a dead page and nothing else.
  static const String host = 'open';

  /// Where a handoff from [location] actually lands.
  ///
  /// The banner only ever renders inside the authenticated shell, so in
  /// practice this is the reader's own screen. The refusal below is defence in
  /// depth and costs one set lookup: an anonymous-only or public route is
  /// never worth crossing to (the app would bounce it anyway), and
  /// `/update-password` in particular carries the recovery token in its
  /// fragment — a location that must never be copied into a second channel.
  static String targetFor(String location) {
    if (!location.startsWith('/')) return RouteRules.home;
    final path = Uri.parse(location).path;
    if (RouteRules.anonymousOnlyRoutes.contains(path) ||
        RouteRules.publicRoutes.contains(path)) {
      return RouteRules.home;
    }
    return location;
  }

  /// The URI the web channel hands to Android.
  ///
  /// [androidPackage] is the flavor's `applicationId` (`Env.current`), which is
  /// also the scheme — so a device carrying both flavors never opens a chooser
  /// and the web build of one environment can never wake the app of the other.
  static Uri handoffUri({
    required String androidPackage,
    required String location,
  }) {
    final target = Uri.parse(targetFor(location));
    return Uri(
      scheme: androidPackage,
      host: host,
      path: target.path.isEmpty ? RouteRules.home : target.path,
      query: target.query.isEmpty ? null : target.query,
      fragment: target.fragment.isEmpty ? null : target.fragment,
    );
  }
}
