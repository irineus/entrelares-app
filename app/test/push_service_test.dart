import 'dart:async';

import 'package:entrelares_app/services/push_messaging.dart';
import 'package:entrelares_app/services/push_service.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

/// A transport that answers whatever the test needs, and records what was
/// asked of it. The whole reason `PushMessaging` exists as a seam: before it,
/// every line below was unreachable from any suite.
class FakeMessaging implements PushMessaging {
  @override
  bool supported;
  bool initializes;
  PushPermission current;
  String? nextToken;

  int permissionRequests = 0;
  int deletedTokens = 0;

  /// A transport that refuses to hand out a token: no Play Services, an
  /// offline first run, iOS before its own registration completes.
  bool tokenThrows = false;

  final _refresh = StreamController<String>.broadcast();
  final _opened = StreamController<Map<String, String>>.broadcast();
  Map<String, String>? launchMessage;

  FakeMessaging({
    this.supported = true,
    this.initializes = true,
    this.current = PushPermission.notAsked,
    this.nextToken = 'tok-1',
  });

  @override
  String get platformName => 'android';

  @override
  Future<bool> initialize() async => initializes;

  @override
  Future<PushPermission> permission() async => current;

  @override
  Future<PushPermission> requestPermission() async {
    permissionRequests++;
    return current;
  }

  @override
  Future<String?> token() async {
    if (tokenThrows) throw StateError('SERVICE_NOT_AVAILABLE');
    return nextToken;
  }

  @override
  Future<void> deleteToken() async => deletedTokens++;

  @override
  Stream<String> get tokenRefreshes => _refresh.stream;

  @override
  Stream<Map<String, String>> get opened => _opened.stream;

  @override
  Future<Map<String, String>?> initialMessage() async => launchMessage;

  void rotateToken(String token) => _refresh.add(token);
  void tapNotification(Map<String, String> data) => _opened.add(data);
}

void main() {
  late FakeCustodyDataSource data;

  setUp(() {
    data = FakeCustodyDataSource(members: const [], days: const []);
  });

  PushService serviceWith(FakeMessaging messaging) =>
      PushService(data, messaging: messaging);

  group('start — the silent path', () {
    test('never asks for the permission', () async {
      final messaging = FakeMessaging(current: PushPermission.notAsked);
      final push = serviceWith(messaging);

      await push.start(7);

      // The one guarantee the whole design rests on: Android shows the dialog
      // once per install, and opening the app must never be what spends it.
      expect(messaging.permissionRequests, 0);
      expect(push.state, PushState.off);
      expect(data.registeredPushTokens, isEmpty);
    });

    test('repairs a registration when the person already said yes', () async {
      final messaging = FakeMessaging(current: PushPermission.granted);
      final push = serviceWith(messaging);

      await push.start(7);

      expect(messaging.permissionRequests, 0);
      expect(data.registeredPushTokens, ['tok-1']);
      expect(push.state, PushState.on);
    });

    test('reports blocked when the OS refused, and registers nothing',
        () async {
      final messaging = FakeMessaging(current: PushPermission.denied);
      final push = serviceWith(messaging);

      await push.start(7);

      expect(push.state, PushState.blocked);
      expect(data.registeredPushTokens, isEmpty);
    });

    test('a transport that cannot start leaves the control unsupported',
        () async {
      final messaging = FakeMessaging(initializes: false);
      final push = serviceWith(messaging);

      await push.start(7);

      expect(push.state, PushState.unsupported);
    });

    test('the web stub never registers anything', () async {
      final messaging =
          FakeMessaging(supported: false, current: PushPermission.granted);
      final push = serviceWith(messaging);

      await push.start(7);

      expect(push.state, PushState.unsupported);
      expect(data.registeredPushTokens, isEmpty);
    });

    test('start awaits its own initialization', () async {
      // The race this closes: `initialize()` is fired at construction and
      // `start` arrives from the auth gate. If start did not await it, a
      // transport that took a moment longer would leave push silently off.
      final messaging = FakeMessaging(current: PushPermission.granted);
      final push = serviceWith(messaging);

      // No `await push.initialize()` here on purpose — start must be enough.
      await push.start(7);

      expect(push.state, PushState.on);
    });
  });

  group('enable — the gesture path', () {
    test('spends the prompt once and registers on a grant', () async {
      final messaging = FakeMessaging(current: PushPermission.notAsked);
      final push = serviceWith(messaging);
      await push.start(7);

      messaging.current = PushPermission.granted;
      final result = await push.enable();

      expect(messaging.permissionRequests, 1);
      expect(result, PushState.on);
      expect(data.registeredPushTokens, ['tok-1']);
    });

    test('a dismissed dialog leaves the state where it was', () async {
      final messaging = FakeMessaging(current: PushPermission.notAsked);
      final push = serviceWith(messaging);
      await push.start(7);

      final result = await push.enable();

      // The screen reads this result to choose its message. Announcing success
      // because a button was pressed is the lie the person discovers the next
      // time a swap goes unanswered.
      expect(result, PushState.off);
      expect(data.registeredPushTokens, isEmpty);
    });

    test('never re-raises a dialog the OS will not show', () async {
      final messaging = FakeMessaging(current: PushPermission.denied);
      final push = serviceWith(messaging);
      await push.start(7);

      final result = await push.enable();

      expect(messaging.permissionRequests, 0,
          reason: 'a prompt that cannot appear makes the app look broken');
      expect(result, PushState.blocked);
    });
  });

  group('the token is a moving target', () {
    test('a rotation re-registers and drops the previous token', () async {
      final messaging = FakeMessaging(current: PushPermission.granted);
      final push = serviceWith(messaging);
      await push.start(7);

      messaging.rotateToken('tok-2');
      await Future<void>.delayed(Duration.zero);

      // Missing this is the classic silent break: every layer keeps reporting
      // success while the server holds an address nobody answers.
      expect(data.registeredPushTokens, ['tok-2']);
    });

    test('sign-out unregisters this device', () async {
      final messaging = FakeMessaging(current: PushPermission.granted);
      final push = serviceWith(messaging);
      await push.start(7);
      expect(data.registeredPushTokens, ['tok-1']);

      await push.stop();

      // The phone may be handed to the other parent — a token left behind
      // would keep delivering the previous account's notices.
      expect(data.registeredPushTokens, isEmpty);
      expect(push.state, PushState.off);
    });

    test('sign-out still unregisters after a session that changed nothing',
        () async {
      // The state this app is in on EVERY launch after the first: the device is
      // already registered, so `start` has nothing to repair.
      data.registeredPushTokens.add('tok-1');
      final messaging = FakeMessaging(current: PushPermission.granted);
      final push = serviceWith(messaging);

      await push.start(7);
      expect(push.state, PushState.on);
      expect(data.registeredPushTokens, ['tok-1'], reason: 'nothing to repair');

      await push.stop();

      // The defect this pins, measured in production on 29/08/2026: a session
      // that found its row in place never learned the token, so sign-out
      // dropped NOTHING and the phone stayed pointed at the account that just
      // left. The next account to sign in on that phone then asked the server
      // to re-point a row it did not own, and was refused by RLS — the neutral
      // "não foi possível ativar os avisos agora", forever, on that device.
      expect(data.registeredPushTokens, isEmpty);
    });

    test('a second device registers though the profile already has one',
        () async {
      // The other phone's row. The question "does this PROFILE have a device?"
      // answers yes here and stops — which is how a second device ends up
      // showing `on` while the server was never told it exists.
      data.registeredPushTokens.add('tok-outro-aparelho');
      final messaging = FakeMessaging(current: PushPermission.granted);
      final push = serviceWith(messaging); // this device is `tok-1`

      await push.start(7);

      expect(data.deviceChecks, ['tok-1'],
          reason: 'the question must be about THIS device');
      expect(data.registeredPushTokens, ['tok-outro-aparelho', 'tok-1']);
      expect(push.state, PushState.on);
    });

    test('a transport that refuses a token leaves the control off, not broken',
        () async {
      final messaging = FakeMessaging(current: PushPermission.granted)
        ..tokenThrows = true;
      final push = serviceWith(messaging);

      // Reading the token moved to the top of `start`, so a transport that
      // throws there would take the whole authenticated session's push state
      // down with it. "Push is off" is the truth; "start failed" is not.
      await push.start(7);

      expect(push.state, PushState.off);
      expect(data.registeredPushTokens, isEmpty);
    });

    test('turning it off drops the row AND the transport token', () async {
      final messaging = FakeMessaging(current: PushPermission.granted);
      final push = serviceWith(messaging);
      await push.start(7);

      await push.disable();

      expect(data.registeredPushTokens, isEmpty);
      expect(messaging.deletedTokens, 1);
      expect(push.state, PushState.off);
    });
  });

  group('a tapped notification', () {
    test('reaches onOpen with the payload', () async {
      final messaging = FakeMessaging(current: PushPermission.granted);
      final push = serviceWith(messaging);
      Map<String, String>? seen;
      push.onOpen = (data) => seen = data;
      await push.start(7);

      messaging.tapNotification({'type': 'swap_requested', 'swapRequestId': '9'});
      await Future<void>.delayed(Duration.zero);

      expect(seen, {'type': 'swap_requested', 'swapRequestId': '9'});
    });

    test('a cold start delivers the launch message exactly once', () async {
      final messaging = FakeMessaging(current: PushPermission.granted)
        ..launchMessage = {'type': 'auto_reminder'};
      final push = serviceWith(messaging);
      var calls = 0;
      push.onOpen = (_) => calls++;

      await push.start(7);

      expect(calls, 1);
    });
  });
}
