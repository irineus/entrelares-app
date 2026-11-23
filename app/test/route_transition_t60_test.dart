// T-60 — Material left the SDK (Flutter 3.47) and the app moved to
// `package:material_ui`. Its `MaterialApp` is a DIFFERENT class from the one in
// `package:flutter/material.dart`, and go_router picks the page type by asking
// `findAncestorWidgetOfExactType<MaterialApp>()`: go_router 16 asked for the
// SDK class, did not find it, logged "Using WidgetsApp configuration" and
// wrapped every `builder:` route in a `NoTransitionPage`. Every screen of the
// app would have snapped in with no transition, and its error page would have
// been the bare `ErrorScreen` — with all 1731 widget tests green, because none
// of them looked at a transition. go_router 18 asks for the material_ui class.
//
// This test is the coupling, stated as the reader sees it: push a route the
// way the app's 23 routes are declared (`builder:`, never `pageBuilder:`) and a
// transition RUNS — both screens are on stage half-way through, and the page is
// a MaterialPage. If a go_router or material_ui bump ever splits the two worlds
// again, this goes red instead of the phone.
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  GoRouter router0() => GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(body: Text('first')),
            routes: [
              GoRoute(
                path: 'second',
                builder: (_, __) => const Scaffold(body: Text('second')),
              ),
            ],
          ),
        ],
      );

  testWidgets('a builder: route under the material_ui MaterialApp is a MaterialPage',
      (tester) async {
    final router = router0();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/second');
    await tester.pumpAndSettle();

    final navigator = tester.widget<Navigator>(find.byType(Navigator).first);
    expect(navigator.pages.last, isA<MaterialPage<void>>(),
        reason: 'go_router did not recognise the material_ui MaterialApp — '
            'it fell back to the WidgetsApp configuration');
    expect(navigator.pages.last, isNot(isA<NoTransitionPage<void>>()));
  });

  testWidgets('pushing a route animates: both screens are on stage half-way',
      (tester) async {
    final router = router0();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/second');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('first'), findsOneWidget,
        reason: 'a NoTransitionPage swaps the screen in one frame');
    expect(find.text('second'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('first'), findsNothing);
    expect(find.text('second'), findsOneWidget);
  });
}
