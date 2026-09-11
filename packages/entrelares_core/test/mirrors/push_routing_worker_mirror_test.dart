/// T-62 — where a tapped push LANDS, on a channel where the tap never reaches
/// Dart.
///
/// **Why this duplication exists.** On Android the payload arrives in the app,
/// `main.dart` asks [PushRouting] which tab the notice belongs on, and routes.
/// On the web there is no app to arrive at: a notification shown by a service
/// worker is clicked against the WORKER, and FlutterFire has no web
/// implementation of `onMessageOpenedApp` at all (nor of `getInitialMessage`,
/// which is hard-coded to null). So `web/firebase-messaging-sw.js` re-states
/// the landing rule in JavaScript and opens the URL itself — the same
/// `/notifications?tab=…&n=…` the Dart side builds, which is what makes the two
/// channels agree on the destination.
///
/// **Why it needs a gate.** The failure is silent and one-directional. Move a
/// type from "Histórico" to "Para você" in Dart and the web keeps opening the
/// old tab: a real screen, with real rows, that simply is not the one the
/// notice was about — the exact complaint that produced [PushRouting] in the
/// first place (owner, on the first device round of F-09). Nothing throws,
/// nothing logs, and the person just finds "nada pendente para você" under a
/// notice that said something needed them.
///
/// The sixth crossing of a language boundary this product mirrors on purpose,
/// and the first that is not Dart↔Deno: the other five read `_shared/*.ts` and
/// the migrations, this one reads a service worker.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'repo_files.dart';

const _worker = 'app/web/firebase-messaging-sw.js';
const _sender = 'supabase/functions/_shared/push.ts';

/// The quoted strings of an array literal, found by the declaration that opens
/// it.
///
/// Deliberately a narrow parser over a shape both files are written to keep,
/// rather than anything that could quietly match a comment: a mirror whose
/// reader is lenient stops being a mirror the first time it reads the wrong
/// thing and passes anyway.
List<String> _stringList(String source, RegExp declaration, String where) {
  final match = declaration.firstMatch(source);
  if (match == null) {
    throw StateError('$where no longer declares ${declaration.pattern}.');
  }
  final values = RegExp('''["']([^"']+)["']''')
      .allMatches(match.group(1)!)
      .map((m) => m.group(1)!)
      .toList();
  if (values.isEmpty) throw StateError('$where: the list read as empty.');
  return values;
}

void main() {
  late String worker;
  late List<String> actionableInJs;

  setUp(() {
    worker = repoFile(_worker);
    actionableInJs = _stringList(
      worker,
      RegExp(r'const ACTIONABLE_TYPES = \[([^\]]*)\]'),
      _worker,
    );
  });

  test('the worker sends every pushable type to the tab Dart would', () {
    // The authority on WHICH types can arrive at all. Reading it here rather
    // than hard-coding a list is what makes a new pushable type fail this
    // suite instead of silently defaulting to Histórico on one channel only.
    final pushTypes = _stringList(
      repoFile(_sender),
      RegExp(r'PUSH_TYPES: readonly string\[\] = \[([^\]]*)\]'),
      _sender,
    );

    for (final type in pushTypes) {
      final dart = PushRouting.landingFor(type);
      final js = actionableInJs.contains(type)
          ? NotificationLanding.incoming
          : NotificationLanding.history;
      expect(js, dart,
          reason: 'the web worker lands `$type` on $js and the app lands it '
              'on $dart — one of the two channels opens the wrong tab, and '
              'neither of them errors while doing it');
    }
  });

  test('an unknown type falls to Histórico on both sides', () {
    // The rule that makes a future writer's notice harmless: the wrong guess
    // in this direction shows a full list instead of an empty one.
    const unknown = 'some_type_no_release_has_shipped_yet';
    expect(PushRouting.landingFor(unknown), NotificationLanding.history);
    expect(actionableInJs, isNot(contains(unknown)));
  });

  test('the worker builds the URL the Notificações route actually reads', () {
    // `main.dart` routes to `/notifications?tab=…&n=…` and the route reads both
    // parameters off the URI. The worker opens a URL instead of routing, so
    // the query string IS the contract between them.
    expect(worker, contains('/notifications'));
    expect(worker, contains('tab='));
    expect(worker, contains('n='));
  });

  test('the click handler is installed before the SDK takes the event', () {
    // Order is load bearing and invisible: the Firebase SDK installs its own
    // `notificationclick` listener when `firebase.messaging()` runs, and that
    // listener calls `stopImmediatePropagation()`. Registered after it, the
    // handler above would never run — the notification would close and the tap
    // would go nowhere, on every browser, with nothing logged.
    //
    // Read from the CODE, never from the prose: the worker's own comments name
    // both of these in order to EXPLAIN the ordering, and a reader that counts
    // those would have reported this rule broken while it held (it did, on the
    // first run of this suite).
    final code = worker
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    final ourListener = code.indexOf("addEventListener('notificationclick'");
    final firstImport = code.indexOf('importScripts(');
    expect(ourListener, greaterThan(-1),
        reason: '$_worker must handle the tap itself: without a link in the '
            'payload the SDK\'s own handler opens nothing');
    expect(firstImport, greaterThan(-1));
    // Before the IMPORTS, not merely before `firebase.messaging()`. The SDK
    // registers its listener when its component is instantiated, and which call
    // does that is an internal detail an upgrade may move. `addEventListener`
    // needs nothing from the SDK, so putting it above the imports makes "ours is
    // first" true by construction rather than by a reading of somebody else's
    // instantiation mode.
    expect(ourListener, lessThan(firstImport),
        reason: 'the SDK stops propagation, so our listener has to be first — '
            'and the only order that cannot be invalidated by an SDK upgrade '
            'is being above the imports');
  });
}
