/// U-48 — the document title per route, for the web channel's tab and history.
///
/// T-64 made the URL name the screen; the `<title>` still said "Entrelares"
/// on every one of them, so a browser's tab strip and its history read as
/// twenty identical entries. This is the pure rule: a location → the catalog
/// key that names the screen, and the composed title "Calendário · Entrelares".
///
/// The catalog already carries the old web client's `<title>`s as
/// `*PageTitle` keys, with their own " - Entrelares" tail; the composer strips
/// that tail so every route reads in ONE shape, and a route with no name of
/// its own (the splash) is the brand alone.
library;

import 'family_lifecycle_rules.dart';
import 'localization/k.dart';
import 'localization/k_app.dart';
import 'localization/localization.dart';
import 'route_rules.dart';

abstract final class DocumentTitle {
  /// The product's name, as the title's second half and the bare fallback.
  static const String brand = 'Entrelares';

  /// The separator the card asked for: "Calendário · Entrelares".
  static const String separator = ' · ';

  /// The tail the ported `*PageTitle` strings carry, in both languages.
  static final RegExp _legacyTail = RegExp(r'\s+-\s+Entrelares$');

  /// The catalog key naming the screen at [location] — path only, the query
  /// and the fragment never name a screen. Null for the splash (no screen)
  /// and for an unknown path, which the router answers with the T-64
  /// not-found screen (its title is [K.notFoundTitle], returned here).
  static String? keyFor(String location) {
    final path = Uri.parse(location).path;
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return K.navCalendar;
    switch (segments.first) {
      case 'splash':
        return null;
      case 'login':
        return segments.length == 1 ? K.loginPageTitle : K.notFoundTitle;
      case 'register':
        return segments.length == 1 ? K.registerPageTitle : K.notFoundTitle;
      case 'reset-password':
        return segments.length == 1 ? K.resetPageTitle : K.notFoundTitle;
      case 'update-password':
        return segments.length == 1 ? K.updatePwdPageTitle : K.notFoundTitle;
      case 'onboarding':
        return segments.length == 1 ? KApp.onbFounderTitle : K.notFoundTitle;
      case 'leaving':
        return segments.length == 1 ? K.leavePageTitle : K.notFoundTitle;
      case 'policy-update':
        return segments.length == 1 ? K.policyPageTitle : K.notFoundTitle;
      case 'premium':
        return segments.length == 2 && segments[1] == 'retorno'
            ? K.payPageTitle
            : K.notFoundTitle;
      case 'notifications':
        return segments.length == 1 ? K.notifPageTitle : K.notFoundTitle;
      case 'reports':
        return segments.length == 1 ? K.navReports : K.notFoundTitle;
      case 'family':
        if (segments.length == 1) return K.famHeading;
        switch (segments[1]) {
          case 'custom-roles':
            return segments.length == 2 ? K.rolesPageTitle : K.notFoundTitle;
          case 'plan':
            return segments.length == 2 ? KApp.famPlanRow : K.notFoundTitle;
          case 'admin-mode':
            return segments.length == 2 ? KApp.famAdminRow : K.notFoundTitle;
          case 'delete':
            return segments.length == 2 ? K.famDelReqTitle : K.notFoundTitle;
          case 'profile':
            // `/family/profile` and `/family/profile/<id>` — the other
            // member's name is data the title does not print.
            return segments.length <= 3 ? K.profPageTitle : K.notFoundTitle;
        }
        return K.notFoundTitle;
    }
    return K.notFoundTitle;
  }

  /// "Calendário · Entrelares", in the reader's language, with the
  /// environment prefix ("[Dev] ") in front of it all — the same prefix the
  /// app bar and the notifications already carry, so a dev tab is never
  /// mistaken for production.
  static String compose(
    String location,
    Localization l, {
    String environmentPrefix = '',
  }) {
    final key = keyFor(location);
    if (key == null) return '$environmentPrefix$brand';
    final name = l[key].replaceFirst(_legacyTail, '').trim();
    return '$environmentPrefix$name$separator$brand';
  }

  /// Every location the router serves, for the test that walks them all —
  /// kept beside the rule so a new route is a one-line addition here and a
  /// failure there until it is named.
  static const List<String> knownLocations = [
    RouteRules.home,
    RouteRules.splash,
    RouteRules.login,
    RouteRules.register,
    RouteRules.resetPassword,
    RouteRules.updatePassword,
    RouteRules.onboarding,
    FamilyLifecycleRules.leavingRoute,
    FamilyLifecycleRules.policyUpdateRoute,
    '/premium/retorno',
    '/family',
    '/family/custom-roles',
    '/family/plan',
    '/family/admin-mode',
    '/family/delete',
    '/family/profile',
    '/family/profile/42',
    '/notifications',
    '/reports',
  ];
}
