// T-64 — the web channel's URLs, driven through the real app in a real
// browser, because that is the only engine where the defect existed.
//
// The widget suite (`test/route_gate_test.dart`) proves the routing decision.
// It cannot prove THIS: in a test binding nothing forces the address bar to
// disagree with the screen, and the address bar was half the defect — the app
// used to park a cold entry on `/splash`, and go_router reported that park
// late enough to survive everything done afterwards. `/family` → `/splash` →
// the calendar, and even when the screen was right the URL was not.
//
// A cold boot at a deep route is the same code path a browser reload takes:
// both hand the URL to the app as the platform's initial route and both go
// through the session gate. So acceptance 1 and 2 of the card are the same
// assertion made twice, and this file makes it once.
//
// Run locally (needs chromedriver on the PATH):
//   chromedriver --port=4444 &
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/deep_link_test.dart \
//     -d web-server --browser-name=chrome --headless \
//     --dart-define=E2E_SUPABASE_SERVICE_ROLE_KEY=<dev service_role>
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:entrelares_app/main.dart' as app;

import 'e2e_family.dart';

const policyVersion =
    String.fromEnvironment('E2E_POLICY_VERSION', defaultValue: '2026-07-30');

final l = Localization(AppLanguage.ptBr);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late E2eFamily family;
  var appBooted = false;

  setUpAll(() async {
    E2eFamily.requireKey();
    family = await E2eFamily.create(policyVersion: policyVersion);
  });

  tearDownAll(() async {
    await family.purge();
  });

  /// Boots the real app with the platform handing it [route] — which is what a
  /// browser does both for a pasted link and for F5.
  ///
  /// [signedOut] wipes the local session first. When it is false the Supabase
  /// singleton keeps the session it already holds (it is per PROCESS, the
  /// pilot's lesson 8), so the second boot is the one that matters: an
  /// AUTHENTICATED cold entry into an inner route.
  Future<void> bootAt(WidgetTester tester, String route,
      {bool signedOut = true}) async {
    // U-13: the language is pinned, or CI's `en-US` host locale renders the app
    // in English and every selector below misses by one word.
    SharedPreferences.setMockInitialValues({
      'flutter.${LanguageResolver.storageKey}': AppLanguage.ptBrCode,
    });
    if (appBooted && signedOut) {
      await Supabase.instance.client.auth
          .signOut(scope: SignOutScope.local)
          .catchError((_) {});
    }
    tester.binding.platformDispatcher.defaultRouteNameTestValue = route;
    addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    // The harness's own precondition, asserted rather than assumed: everything
    // below is about what the app does with the URL the platform hands it, so
    // a harness that fails to hand it over would look exactly like a product
    // defect. It cost a red CI round to learn that the hard way.
    expect(WidgetsBinding.instance.platformDispatcher.defaultRouteName, route,
        reason: 'the platform must hand the app the URL under test');
    app.main();
    appBooted = true;
    await tester.pumpAndSettle(const Duration(seconds: 15));
  }

  Future<void> signIn(WidgetTester tester, String email) async {
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), email);
    await tester.enterText(fields.at(1), family.password);
    await tester.tap(find.text(l[K.loginSubmit]));
    await tester.pumpAndSettle(const Duration(seconds: 15));
  }

  GoRouter routerOf(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first));

  /// The screen the reader is actually on.
  String location(WidgetTester tester) =>
      routerOf(tester).state.uri.toString();

  /// What the router has REPORTED — the value the address bar carries and the
  /// one a reload starts from. This is the half that used to stay on `/splash`:
  /// the screen was right and the URL was not, so the next F5 replayed the
  /// defect.
  String reported(WidgetTester tester) =>
      routerOf(tester).routeInformationProvider.value.uri.toString();

  testWidgets('p0 — a signed-in reader opening an inner URL cold lands on it, '
      'and the URL still names it', (tester) async {
    // First boot: sign in, so the process holds a live session.
    await bootAt(tester, RouteRules.home);
    await signIn(tester, family.founder.email);
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: 'the founder should reach the authenticated shell');

    // Second boot, cold, straight at Família — a pasted link, a bookmark, F5.
    await bootAt(tester, '/family', signedOut: false);

    expect(location(tester), '/family',
        reason: 'T-64: the URL survived the gate instead of being traded for '
            'the calendar');
    expect(reported(tester), '/family',
        reason: 'and the address bar agrees — without that a reload replays '
            'the whole defect');
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('p0 — a tapped web push opens the notice it names, not the '
      'calendar', (tester) async {
    await bootAt(tester, '/notifications?tab=incoming&n=7', signedOut: false);

    expect(location(tester), '/notifications?tab=incoming&n=7',
        reason: 'the tab and the notice id are what make the TAPPED notice the '
            'one that opens; losing them is what T-62 found');
    expect(reported(tester), '/notifications?tab=incoming&n=7');
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('p0 — a URL this app does not serve says so', (tester) async {
    await bootAt(tester, '/relatorios', signedOut: false);

    expect(find.text(l[K.notFoundTitle]), findsOneWidget,
        reason: 'an unknown path is an answer, not a silent detour to the '
            'calendar');
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('p0 — S-02 is not relaxed: an anonymous visitor gets login',
      (tester) async {
    await bootAt(tester, '/family');

    expect(find.text(l[K.loginSubmit]), findsOneWidget,
        reason: 'restoring a guarded screen for a visitor without a session '
            'would hand over exactly what S-02 refuses');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
