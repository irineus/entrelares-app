// T-78 — the shell touches generously (phase, resume, every pointer-down);
// the tracker is what keeps that to one server call per day, and what keeps a
// call made without signal from being queued or from closing the day.
import 'dart:async';

import 'package:entrelares_app/services/activity_tracker.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> sent;
  late DateTime now;
  late bool fail;

  ActivityTracker tracker({ActivityChannel channel = ActivityChannel.web}) =>
      ActivityTracker((c) async {
        if (fail) throw Exception('no signal');
        sent.add(c);
      }, channel: channel, clock: () => now);

  setUp(() {
    sent = [];
    now = DateTime(2026, 9, 23, 8);
    fail = false;
  });

  test('sends the channel wire value, once per day however often it is asked',
      () async {
    final t = tracker(channel: ActivityChannel.webInstalled);
    await t.touch();
    await t.touch();
    now = DateTime(2026, 9, 23, 23, 59);
    await t.touch();
    expect(sent, ['web-installed']);
  });

  test('a new local day asks again — the tab left open overnight', () async {
    final t = tracker();
    await t.touch();
    now = DateTime(2026, 9, 24, 7);
    await t.touch();
    expect(sent, ['web', 'web']);
  });

  test('a failed call is dropped, never thrown, and leaves the day open',
      () async {
    final t = tracker();
    fail = true;
    await t.touch(); // must not throw
    expect(sent, isEmpty);
    fail = false;
    await t.touch();
    expect(sent, ['web']);
  });

  test('taps while a call is in flight do not stack calls', () async {
    final gate = Completer<void>();
    var calls = 0;
    final t = ActivityTracker((c) async {
      calls++;
      await gate.future;
    }, channel: ActivityChannel.android, clock: () => now);
    final first = t.touch();
    await t.touch();
    await t.touch();
    gate.complete();
    await first;
    expect(calls, 1);
  });

  test('reset (leaving the authenticated phase) lets the next member record '
      'the same day', () async {
    final t = tracker();
    await t.touch();
    t.reset();
    await t.touch();
    expect(sent, ['web', 'web']);
  });
}
