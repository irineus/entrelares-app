// U-48 follow-up (23/09/2026) — the tab title after a sign-in.
//
// Seen on the owner's phone: a signed-out deep link to
// /notifications?tab=history went to /login, the sign-in landed on the
// calendar (T-64 keeps no remembered destination), and the tab still read
// "[Dev] Login · Entrelares" over the Calendário screen. The title listened to
// the route information provider, and the redirect a phase ping re-runs
// reaches that provider without a notification — see [RouterLocation].
//
// The harness is the app's wiring reduced to what the title sees: the REAL
// [AppRouteGate] in a REAL [GoRouter], the phase flipped by a
// `refreshListenable` ping as `_setPhase` does, a listener that rebuilds the
// root, and `MaterialApp.router(title:)` composed by the core rule. What is
// asserted is the [Title] widget — the value the browser tab receives.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:entrelares_app/routing/app_route_gate.dart';
import 'package:entrelares_app/routing/router_location.dart';

final _l = Localization(AppLanguage.ptBr);
final _prefix = environmentTitlePrefix(isProduction: false);

class _RouterRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

class _TitleHarness extends StatefulWidget {
  const _TitleHarness({super.key, required this.phase});

  final AuthPhase phase;

  @override
  State<_TitleHarness> createState() => _TitleHarnessState();
}

class _TitleHarnessState extends State<_TitleHarness> {
  final _refresh = _RouterRefresh();
  late AuthPhase phase = widget.phase;

  late final AppRouteGate gate = AppRouteGate(
    phase: () => phase,
    isLeaving: () => false,
    consentState: () => ConsentGateState.upToDate,
  );

  late final GoRouter router = GoRouter(
    initialLocation: RouteRules.home,
    refreshListenable: _refresh,
    redirect: (_, state) => gate.redirect(state.matchedLocation),
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const Text('LOGIN')),
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

  late final VoidCallback _stopTitle;

  @override
  void initState() {
    super.initState();
    _stopTitle = RouterLocation.listen(router, _refreshTitle);
  }

  @override
  void dispose() {
    _stopTitle();
    router.dispose();
    _refresh.dispose();
    super.dispose();
  }

  void _refreshTitle() {
    if (mounted) setState(() {});
  }

  /// The app's `_setPhase`, reduced to what routing sees.
  void setPhase(AuthPhase next) {
    phase = next;
    _refresh.ping();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: DocumentTitle.compose(RouterLocation.of(router), _l,
            environmentPrefix: _prefix),
        routerConfig: router,
      );
}

void main() {
  final key = GlobalKey<_TitleHarnessState>();

  Future<_TitleHarnessState> bootAt(WidgetTester tester, String url,
      {required AuthPhase phase}) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = url;
    addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue);
    await tester.pumpWidget(_TitleHarness(key: key, phase: phase));
    await tester.pumpAndSettle();
    return key.currentState!;
  }

  /// What the browser tab receives.
  String tabTitle(WidgetTester tester) =>
      tester.widget<Title>(find.byType(Title)).title;

  testWidgets(
      'a signed-out deep link goes to Login, and the sign-in retitles the '
      'tab to the calendar it lands on', (tester) async {
    final app = await bootAt(tester, '/notifications?tab=history',
        phase: AuthPhase.anon);
    expect(find.text('LOGIN'), findsOneWidget);
    expect(tabTitle(tester), '${_prefix}Login · Entrelares',
        reason: 'the gate\'s own redirect names the screen it lands on');

    app.setPhase(AuthPhase.authed);
    await tester.pumpAndSettle();

    expect(find.text('CALENDAR'), findsOneWidget);
    expect(RouterLocation.of(app.router), RouteRules.home);
    expect(tabTitle(tester), '${_prefix}Calendário · Entrelares',
        reason: 'the post-login redirect is made by the router itself, and '
            'the route information provider does not announce it — a title '
            'bound there kept saying Login over the calendar');
  });

  testWidgets('an explicit navigation after that still retitles',
      (tester) async {
    final app = await bootAt(tester, '/login', phase: AuthPhase.anon);
    app.setPhase(AuthPhase.authed);
    await tester.pumpAndSettle();

    app.router.go('/family');
    await tester.pumpAndSettle();

    expect(tabTitle(tester), '${_prefix}Família · Entrelares');
  });

  testWidgets('a sign-out redirect retitles back to Login', (tester) async {
    final app = await bootAt(tester, '/family', phase: AuthPhase.authed);
    expect(tabTitle(tester), '${_prefix}Família · Entrelares');

    app.setPhase(AuthPhase.anon);
    await tester.pumpAndSettle();

    expect(find.text('LOGIN'), findsOneWidget);
    expect(tabTitle(tester), '${_prefix}Login · Entrelares');
  });
}
