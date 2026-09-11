// T-64 — the app's own routing decision, which had no test at all until a web
// push landed on the calendar instead of the notice that was tapped.
//
// The suite drives the REAL [AppRouteGate] inside a REAL [GoRouter], entering
// through `defaultRouteName` the way a browser does on a cold load, a paste or
// an F5. `route_rules_test.dart` was green throughout the defect because the
// pure rule it exercises was never the broken half — the same shape as
// `translateSaveError` and `FakeCustodyDataSource` before it, and the reason a
// harness that re-implemented the gate would have proved nothing.
//
// What the redesign made testable is the ORDER: the router is built only once
// the phase is known, so every case below constructs it that way, and the
// question each one asks is the one the reader asks — did the URL I opened stay
// the URL I am on?
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:entrelares_app/routing/app_route_gate.dart';

class _GateHarness extends StatefulWidget {
  const _GateHarness({
    super.key,
    required this.phase,
    this.isLeaving = false,
    this.consentState = ConsentGateState.upToDate,
  });

  final AuthPhase phase;
  final bool isLeaving;
  final ConsentGateState consentState;

  @override
  State<_GateHarness> createState() => _GateHarnessState();
}

class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _GateHarnessState extends State<_GateHarness> {
  final _refresh = _RouterRefresh();
  late AuthPhase phase = widget.phase;
  late bool isLeaving = widget.isLeaving;
  late ConsentGateState consentState = widget.consentState;

  late final AppRouteGate gate = AppRouteGate(
    phase: () => phase,
    isLeaving: () => isLeaving,
    consentState: () => consentState,
  );

  late final GoRouter router = GoRouter(
    initialLocation: RouteRules.home,
    refreshListenable: _refresh,
    redirect: (_, state) => gate.redirect(state.matchedLocation),
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
    _refresh.ping();
  }

  /// What `_applyProfileGates` does on every authenticated boot: one more ping,
  /// from a place that knows nothing about how the app was entered. Under the
  /// old design this beat is what threw the destination away.
  void pingAgain() => _refresh.ping();

  @override
  Widget build(BuildContext context) =>
      MaterialApp.router(routerConfig: router);
}

void main() {
  final key = GlobalKey<_GateHarnessState>();

  /// Boots the harness the way the app does: the phase is ALREADY known when
  /// the router is built, and the platform's initial route is the URL the
  /// reader opened.
  Future<_GateHarnessState> bootAt(
    WidgetTester tester,
    String url, {
    required AuthPhase phase,
    bool isLeaving = false,
    ConsentGateState consentState = ConsentGateState.upToDate,
  }) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = url;
    addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    await tester.pumpWidget(_GateHarness(
      key: key,
      phase: phase,
      isLeaving: isLeaving,
      consentState: consentState,
    ));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  /// The screen the reader is on.
  String where(_GateHarnessState state) =>
      state.router.routerDelegate.currentConfiguration.uri.toString();

  /// What the router has REPORTED — the value the address bar carries and the
  /// one a reload starts from. Asserting it is the point: a screen that is
  /// right under a URL that is wrong is a reload away from being wrong too,
  /// and that is exactly the state the old design left the reader in.
  String reported(_GateHarnessState state) =>
      state.router.routeInformationProvider.value.uri.toString();

  group('a cold entry into an inner URL', () {
    testWidgets('/family opens on Família and the URL never moves',
        (tester) async {
      final app = await bootAt(tester, '/family', phase: AuthPhase.authed);

      expect(find.text('FAMILY'), findsOneWidget);
      expect(where(app), '/family');
      expect(reported(app), '/family',
          reason: 'T-64: nothing may rewrite the URL the reader opened — an '
              'address bar that says /splash is an F5 away from the calendar');
    });

    testWidgets('a query survives with the path — the push notice id does',
        (tester) async {
      final app = await bootAt(tester, '/notifications?tab=incoming&n=42',
          phase: AuthPhase.authed);

      expect(where(app), '/notifications?tab=incoming&n=42',
          reason: 'the tab and the notice id are what make the TAPPED notice '
              'the one that opens');
      expect(reported(app), '/notifications?tab=incoming&n=42');
    });

    testWidgets('a later phase ping does not undo it', (tester) async {
      final app = await bootAt(tester, '/family', phase: AuthPhase.authed);

      // The beat that used to lose the destination.
      app.pingAgain();
      await tester.pumpAndSettle();

      expect(where(app), '/family',
          reason: 'the second ping of an authenticated boot must not send the '
              'reader back to the calendar');
    });

    testWidgets('a nested route opens too', (tester) async {
      final app =
          await bootAt(tester, '/family/profile', phase: AuthPhase.authed);
      expect(where(app), '/family/profile');
    });
  });

  group('S-02 is not relaxed', () {
    testWidgets('an anonymous visitor gets login for a guarded route',
        (tester) async {
      final app = await bootAt(tester, '/family', phase: AuthPhase.anon);

      expect(find.text('LOGIN'), findsOneWidget);
      expect(where(app), RouteRules.login);
    });

    testWidgets('and lands on it after signing in', (tester) async {
      final app = await bootAt(tester, '/family', phase: AuthPhase.anon);
      expect(where(app), RouteRules.login);

      // The sign-in does not restore anything by itself — the app navigates on
      // its own after `_signIn`, exactly as it always did. What matters here is
      // that the reader is not left somewhere absurd.
      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();
      expect(where(app), RouteRules.home,
          reason: 'a login form is already answered for a signed-in reader');
    });

    testWidgets('a public destination opens as itself — the invitation link '
        'keeps its token', (tester) async {
      final app = await bootAt(tester, '/register?token=abc123',
          phase: AuthPhase.anon);

      expect(find.text('REGISTER'), findsOneWidget);
      expect(where(app), '/register?token=abc123',
          reason: 'an invitation arriving cold must reach the form holding its '
              'token — the case the deleted pendingLocation existed for, now '
              'free because the URL was never taken away');
      expect(reported(app), '/register?token=abc123');
    });
  });

  group('the phases that confine', () {
    testWidgets('F-57: a profile-less session is held on /onboarding',
        (tester) async {
      final app = await bootAt(tester, '/family', phase: AuthPhase.onboarding);
      expect(where(app), RouteRules.onboarding);

      app.setPhase(AuthPhase.authed);
      await tester.pumpAndSettle();
      expect(where(app), RouteRules.home,
          reason: 'the onboarding screen is answered once the profile exists');
    });

    testWidgets('S-11: a member on their way out is confined to /leaving',
        (tester) async {
      final app = await bootAt(tester, '/family',
          phase: AuthPhase.authed, isLeaving: true);
      expect(where(app), FamilyLifecycleRules.leavingRoute);
    });

    testWidgets('S-15: a blocked consent gate wins over the destination',
        (tester) async {
      final app = await bootAt(tester, '/family',
          phase: AuthPhase.authed,
          consentState: ConsentGateState.blocked);
      expect(where(app), FamilyLifecycleRules.policyUpdateRoute);
    });
  });

  group('the screens that are already answered', () {
    testWidgets('an anonymous-only URL falls back to the calendar',
        (tester) async {
      for (final url in [RouteRules.splash, RouteRules.login, '/register']) {
        final app = await bootAt(tester, url, phase: AuthPhase.authed);
        expect(where(app), RouteRules.home, reason: '$url for a signed-in '
            'reader is the calendar');
      }
    });

    testWidgets('an Android cold start opens the calendar', (tester) async {
      // The platform hands the app no URL, so `initialLocation` decides — and
      // it is the calendar, not the splash: the splash is a WIDGET now, not a
      // place.
      final app = await bootAt(tester, '/', phase: AuthPhase.authed);
      expect(where(app), RouteRules.home);
    });
  });

  group('a URL this app does not serve', () {
    testWidgets('says so instead of being swallowed by the calendar',
        (tester) async {
      final app = await bootAt(tester, '/relatorios', phase: AuthPhase.authed);

      expect(find.text('404 /relatorios'), findsOneWidget,
          reason: 'T-64: an unknown path is an answer, not a silent detour');
      expect(where(app), '/relatorios',
          reason: 'and the URL still shows what was asked for, so the reader '
              'can see the typo');
    });
  });
}
