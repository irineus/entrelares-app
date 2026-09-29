// F-07 (owner's QA, 29/09/2026, round 3): the calendar's key opened the
// LAST profile visited instead of the tapped one. go_router keys a page by
// its route PATTERN (`/family/profile/:id`), so going from one member's
// profile to another's kept the page — and the State that had loaded the
// first member in initState. The fix keys the screen by the id; this pins
// both the premise and the fix.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Loads extends StatefulWidget {
  final String id;
  const _Loads({super.key, required this.id});

  @override
  State<_Loads> createState() => _LoadsState();
}

class _LoadsState extends State<_Loads> {
  late final String loaded = widget.id; // what initState would have fetched

  @override
  Widget build(BuildContext context) => Text('loaded $loaded');
}

Future<GoRouter> _pump(WidgetTester tester, {required bool keyed}) async {
  final router = GoRouter(initialLocation: '/p/1', routes: [
    GoRoute(
      path: '/p/:id',
      builder: (_, state) => _Loads(
        key: keyed ? ValueKey(state.pathParameters['id']) : null,
        id: state.pathParameters['id']!,
      ),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('premise: without a key the page keeps the first id',
      (tester) async {
    final router = await _pump(tester, keyed: false);
    router.go('/p/2');
    await tester.pumpAndSettle();
    expect(find.text('loaded 1'), findsOne);
  });

  testWidgets('keyed by the id, the page loads the new member',
      (tester) async {
    final router = await _pump(tester, keyed: true);
    router.go('/p/2');
    await tester.pumpAndSettle();
    expect(find.text('loaded 2'), findsOne);
  });

  test("main.dart keys the member's ProfileScreen by the id", () {
    final main = File('lib/main.dart').readAsStringSync();
    final route = RegExp(r"path: ':id',\s*builder: \(_, state\) => ProfileScreen\(([\s\S]*?)\),\s*\),",
        multiLine: true);
    final m = route.firstMatch(main);
    expect(m, isNotNull, reason: "the ':id' profile route moved");
    expect(m!.group(1), contains("key: ValueKey(state.pathParameters['id'])"));
  });
}
