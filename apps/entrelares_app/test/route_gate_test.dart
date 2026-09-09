// T-64 — the STATE half of the routing rules, which had no test at all until
// a web push landed on the calendar instead of the notice that was tapped.
//
// This suite drives the REAL [AppRouteGate] inside a REAL [GoRouter], entering
// through `defaultRouteName` the way the browser does on a cold load. That
// matters more here than usual: `route_rules_test.dart` was green throughout
// the defect, because the pure rule it exercises was never the broken half —
// the same shape as `translateSaveError` and `FakeCustodyDataSource` before
// it. A harness that re-implemented the gate would have been green too.
//
// The scenario each case replays is the web's, and it has two beats the
// Android channel never had:
//
//   1. the gate parks the deep entry on `/splash`, and go_router does NOT
//      report that redirect as route information — the router keeps coming
//      back to `/splash`;
//   2. `_applyProfileGates` pings a SECOND time on every authenticated boot.
//      Under the old code the first ping consumed the memory and the second
//      one, finding nothing, fell to the calendar.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:entrelares_app/routing/app_route_gate.dart';

/// The app's own shape, minus the screens: what decides is the gate.
class _GateHarness extends StatefulWidget {
  const _GateHarness({super.key});

  @override
  State<_GateHarness> createState() => _GateHarnessState();
}

class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _GateHarnessState extends State<_GateHarness> {
  final _refresh = _RouterRefresh();
  AuthPhase phase = AuthPhase.gate;
  bool isLeaving = false;
  ConsentGateState consentState = ConsentGateState.upToDate;

  late final AppRouteGate gate = AppRouteGate(
    phase: () => phase,
    isLeaving: () => isLeaving,
    consentState: () => consentState,
    go: (location) => router.go(location),
  );

  late final GoRouter router = GoRouter(
    initialLocation: RouteRules.splash,
    refreshListenable: _refresh,
    redirect: (_, state) =>
        gate.redirect(matchedLocation: state.matchedLocation, uri: state.uri),
    errorBuilder: (_, state) => Text('404 ${state.uri}'),
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const Text('SPLASH')),
      GoRoute(path: '/login', builder: (_, _) => const Text('LOGIN')),
      GoRoute(path: '/register', builder: (_, _) => const Text('REGISTER')),
      GoRoute(path: '/onboarding', builder: (_, _) => const Text('ONBOARDING')),
      GoRoute(
          path: FamilyLifecycleRules.leavingRoute,
          builder: (_, _) => const Text('LEAVING')),
      GoRoute(
          path: FamilyLifecycleRules.policyUpdateRoute,
          builder: (_, _) => const Text('POLICY')),
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => shell,
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, _) => const Text('CALENDAR')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/family', builder: (_, _) => const Text('FAMILY')),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/notifications',
                builder: (_, _) => const Text('NOTIFICATIONS')),
          ]),
        ],
      ),
    ],
  );

  /// The app's `_setPhase`, reduced to what routing sees.
  void setPhase(AuthPhase next) {
    phase = next;
    if (!gate.restorePendingDestination()) _refresh.ping();
  }

  /// What `_applyProfileGates` does on every authenticated boot: one more ping,
  /// from a place that knows nothing about the deep entry.
  void pingAgain() => _refresh.ping();

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: router);
}

void main() {
  // The MECHANISM, driven call by call.
  //
  // The widget group below cannot prove this one, and that is worth saying out
  // loud: in a test binding go_router DOES report the location it redirected
  // to, so the router never comes back to `/splash` and the old code passes
  // every scenario there. The web is where it does not — measured in a browser
  // on 08/09/2026: the screen showed Notificações while the address bar still
  // read `/splash`, and the next ping decided from that stale `/splash`.
  //
  // So the assertion that fails on the old behaviour is this one: the
  // destination has to be reached by a NAVIGATION. A redirect's answer is not
  // reported, and anything the router is not told about is a screen the reader
  // cannot reload, bookmark or share.
  group('the restore is a navigation, not a redirect', () {
    late List<String> navigated;
    late AuthPhase phase;
    late AppRouteGate gate;

    setUp(() {
      navigated = <String>[];
      phase = AuthPhase.gate;
      gate = AppRouteGate(
        phase: () => phase,
        isLeaving: () => false,
        consentState: () => ConsentGateState.upToDate,
        go: navigated.add,
      );
    });

    test('a cold deep entry is parked, then navigated to', () {
      expect(
          gate.redirect(
              matchedLocation: '/notifications',
              uri: Uri.parse('/notifications?tab=incoming&n=42')),
          RouteRules.splash,
          reason: 'nothing renders before the gate has answered');
      expect(gate.pendingLocation, '/notifications?tab=incoming&n=42');

      phase = AuthPhase.authed;
      expect(gate.restorePendingDestination(), isTrue);
      expect(navigated, ['/notifications?tab=incoming&n=42'],
          reason: 'T-64: handing the destination back from the redirect is '
              'what left the address bar on /splash and the reader one ping '
              'away from the calendar');
      expect(gate.pendingLocation, isNull,
          reason: 'honoured once, and never again');
    });

    test('a stale evaluation of /splash after the restore is harmless', () {
      gate.redirect(matchedLocation: '/family', uri: Uri.parse('/family'));
      phase = AuthPhase.authed;
      gate.restorePendingDestination();
      navigated.clear();

      // Whatever else pings the router — `_applyProfileGates` does, on every
      // authenticated boot — finds nothing left to spend.
      expect(gate.restorePendingDestination(), isFalse);
      expect(navigated, isEmpty);
    });

    test('an anonymous answer is not terminal: the memory waits for the login',
        () {
      gate.redirect(matchedLocation: '/family', uri: Uri.parse('/family'));

      phase = AuthPhase.anon;
      expect(gate.restorePendingDestination(), isTrue);
      expect(navigated, [RouteRules.login],
          reason: 'S-02: a guarded screen is never restored for a visitor '
              'without a session');
      expect(gate.pendingLocation, '/family',
          reason: 'the destination is still what they asked for');

      phase = AuthPhase.authed;
      expect(gate.restorePendingDestination(), isTrue);
      expect(navigated.last, '/family');
    });
  });

  final key = GlobalKey<_GateHarnessState>();

  /// Boots the harness the way a browser boots the app: with the URL as the
  /// platform's initial route.
  Future<_GateHarnessState> bootAt(WidgetTester tester, String url) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = url;
    addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    await tester.pumpWidget(_GateHarness(key: key));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  String where(_GateHarnessState state) =>
      state.router.routerDelegate.currentConfiguration.uri.toString();

  group('a cold deep entry survives the gate', () {
    testWidgets('/family, and a second phase ping does not undo it',
        (tester) async {
      final app = await bootAt(tester, '/family');
      expect(find.text('SPLASH'), findsOneWidget,
          reason: 'nothing may render before the gate has answered');

      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();
      expect(where(app), '/family');
      expect(find.text('FAMILY'), findsOneWidget);

      // The beat that used to lose it.
      app.pingAgain();
      await tester.pumpAndSettle();
      expect(where(app), '/family',
          reason: 'T-64: the second ping of an authenticated boot must not '
              'send the reader back to the calendar');
    });

    testWidgets('a query survives with the path — the push notice id does',
        (tester) async {
      final app = await bootAt(tester, '/notifications?tab=incoming&n=42');

      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();
      app.pingAgain();
      await tester.pumpAndSettle();

      expect(where(app), '/notifications?tab=incoming&n=42',
          reason: 'the tab and the notice id are what make the tapped notice '
              'the one that opens');
    });

    testWidgets('the address bar names the screen, so F5 stays put',
        (tester) async {
      final app = await bootAt(tester, '/family');
      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();

      // What the browser would show: the router's own reported location, not
      // just whatever widget happens to be on screen. A redirect that is never
      // reported leaves the URL on `/splash`, and the next reload replays the
      // whole defect.
      expect(app.router.routeInformationProvider.value.uri.toString(),
          '/family');
    });
  });

  group('S-02 is not relaxed by the restore', () {
    testWidgets('an anonymous visitor gets login for a guarded route',
        (tester) async {
      final app = await bootAt(tester, '/family');

      app.setPhase(AuthPhase.anon);
      await tester.pumpAndSettle();
      expect(where(app), '/login');
      expect(find.text('LOGIN'), findsOneWidget);
    });

    testWidgets('and lands on it once they sign in — the memory outlives the '
        'anonymous answer', (tester) async {
      final app = await bootAt(tester, '/family');

      app.setPhase(AuthPhase.anon);
      await tester.pumpAndSettle();
      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();

      expect(where(app), '/family');
    });

    testWidgets('a public destination is restored for an anonymous visitor — '
        'the invitation link keeps its token', (tester) async {
      final app = await bootAt(tester, '/register?token=abc123');

      app.setPhase(AuthPhase.anon);
      await tester.pumpAndSettle();
      expect(where(app), '/register?token=abc123');
    });
  });

  group('the memory is not honoured where it makes no sense', () {
    testWidgets('F-57: a profile-less session is confined to onboarding',
        (tester) async {
      final app = await bootAt(tester, '/family');

      app.setPhase(AuthPhase.onboarding);
      await tester.pumpAndSettle();
      expect(where(app), '/onboarding');

      // …and the destination is still there once the profile exists.
      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();
      expect(where(app), '/family');
    });

    testWidgets('an anonymous-only screen falls back to the calendar',
        (tester) async {
      final app = await bootAt(tester, '/login');

      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();
      app.pingAgain();
      await tester.pumpAndSettle();

      expect(where(app), '/',
          reason: 'a login form is already answered for a signed-in reader');
    });

    testWidgets('a plain boot with nothing remembered opens the calendar',
        (tester) async {
      final app = await bootAt(tester, '/splash');

      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();
      expect(where(app), '/');
      expect(app.gate.pendingLocation, isNull);
    });
  });

  group('a URL this app does not serve', () {
    testWidgets('says so instead of being swallowed by the calendar',
        (tester) async {
      final app = await bootAt(tester, '/relatorios');

      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();

      expect(find.text('404 /relatorios'), findsOneWidget,
          reason: 'T-64: an unknown path is an answer, not a silent detour');
    });
  });

  group('the authenticated gates still win over a remembered destination', () {
    testWidgets('S-11: a member on their way out is confined to /leaving',
        (tester) async {
      final app = await bootAt(tester, '/family');
      app.isLeaving = true;

      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();
      expect(where(app), FamilyLifecycleRules.leavingRoute);
    });

    testWidgets('S-15: a blocked consent gate wins too', (tester) async {
      final app = await bootAt(tester, '/family');
      app.consentState = ConsentGateState.blocked;

      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();
      expect(where(app), FamilyLifecycleRules.policyUpdateRoute);
    });
  });
}
