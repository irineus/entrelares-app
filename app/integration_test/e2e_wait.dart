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

/// The other direction (T-71, measured 13/09/2026): pumps until [finder]
/// matches NOTHING, or fails after [timeout] naming what stayed on screen.
///
/// Run 371 (`main`, same tree as the green run 372 beside it) died on the
/// DATABASE assertion after the revoke tap: `tapVisible` had settled the
/// frames, the test read `open invitations` from the server, and the row was
/// still open — because `_revokeInvite` → `await revokeInvitation()` was
/// still in flight. A still screen with a pending request returns from
/// `pumpAndSettle` at once; under contention on the shared dev project (the
/// db-gate had started 23 s earlier and a second web-e2e was running) the
/// request took longer than the frames, and the test asserted a state the app
/// had not been given the time to produce. The page refetches after the RPC
/// (`_load()`), so the card leaving the screen is the signal that BOTH the
/// request and the refetch completed — wait for that, then read the database.
Future<void> pumpUntilGone(
  WidgetTester tester,
  Finder finder, {
  required String reason,
  Duration timeout = const Duration(seconds: 20),
  Duration step = const Duration(milliseconds: 250),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isNotEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      final onScreen = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .whereType<String>()
          .toList();
      fail('$reason — ${finder.describeMatch(Plurality.one)} still on screen '
          'after ${timeout.inSeconds}s | texts on screen: $onScreen');
    }
    await tester.pump(step);
  }
  await tester.pumpAndSettle();
}
