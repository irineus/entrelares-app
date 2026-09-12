// T-58 (hypothesis 4, measured 12/09/2026) — waiting for a widget that a
// NETWORK round trip will put on screen.
//
// `pumpAndSettle` waits for scheduled FRAMES, not for pending futures. The
// Família page refetches its list after an RPC (`_sendInvite` → `await _load()`
// → `fetchOpenInvitations`), and while that request is in flight the screen
// can be perfectly still — so `pumpAndSettle(8 s)` returns at once, the test
// looks for the new card, and `find.text('Revogar').first` throws
// `Bad state: No element` AFTER the database assertions passed. That is run
// 355 attempt 1 on `main` (11/09/2026): the server did the right thing and the
// screen had not caught up yet. The remedy is to wait for the WIDGET, with a
// ceiling, and to say what was on screen when the ceiling hit.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps until [finder] matches at least one widget, or fails after [timeout]
/// naming the texts that WERE on screen — the diagnosis, not just the symptom.
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  required String reason,
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      final onScreen = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .toList();
      fail('$reason — nothing matched ${finder.describeMatch(Plurality.zero)} '
          'after ${timeout.inSeconds}s | texts on screen: $onScreen');
    }
    await tester.pump(step);
  }
  await tester.pumpAndSettle();
}
