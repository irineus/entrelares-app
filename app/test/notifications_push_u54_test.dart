// U-54 — a reader whose device has no push is walked to it, one step chosen
// by what THAT device can do (PushNudgeRules, core).
//
// Origin: family 19's father reads the app in Safari on an iPhone, with no
// device registered, and the Notificações screen told him only that
// notifications "work in the installed app" — no action, and no way back to
// the U-51 install sheet once its strip was dismissed.
//
// Placement is measured by RECT, like U-43: an actionable step sits over the
// list it promises, a step with no button is the line after the list.
import 'dart:convert';

import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/services/analytics_service.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/services/push_messaging.dart';
import 'package:entrelares_app/services/push_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'calendar_slice_test.dart';
import 'frozen_day_test.dart' show swapReq;
import 'push_service_test.dart' show FakeMessaging;

final _pt = Localization(AppLanguage.ptBr);

// Real user agents, as the U-51 core tests use them.
const _iphoneSafariUa =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 '
    'Safari/604.1';
const _chromeIosUa =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) '
    'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/140.0.0.0 Mobile/15E148 '
    'Safari/604.1';
const _windowsChromeUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

const _iphoneTab =
    BrowserInstallFacts(userAgent: _iphoneSafariUa, maxTouchPoints: 5);
const _iphoneInstalled = BrowserInstallFacts(
    userAgent: _iphoneSafariUa, maxTouchPoints: 5, navigatorStandalone: true);
const _chromeIos =
    BrowserInstallFacts(userAgent: _chromeIosUa, maxTouchPoints: 5);
const _desktop = BrowserInstallFacts(userAgent: _windowsChromeUa);

late List<Map<String, dynamic>> _events;

AnalyticsService _analytics() {
  _events = [];
  return AnalyticsService(
    websiteId: 'site-1',
    host: 'https://cloud.umami.is',
    hostname: 'web.entrelares.app',
    client: MockClient((request) async {
      final payload = (jsonDecode(request.body)
          as Map<String, dynamic>)['payload'] as Map<String, dynamic>;
      _events.add(payload);
      return http.Response('', 200);
    }),
  );
}

List<Map<String, dynamic>> _named(String name) =>
    _events.where((e) => e['name'] == name).toList();

Widget _app(FakeCustodyDataSource ds,
        {PushService? push,
        BrowserInstallFacts? facts,
        AnalyticsService? analytics}) =>
    AppL10n(
      l: _pt,
      setLanguage: (_) async {},
      child: MaterialApp(
        home: NotificationsScreen(
          dataSource: ds,
          badge: NotificationBadge(ds),
          push: push,
          installFacts: facts,
          analytics: analytics,
        ),
      ),
    );

FakeCustodyDataSource _source() =>
    FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..pendingForMe = [swapReq(10, dayOfMonth(today.day), message: 'Consulta')];

Future<PushService> _pushIn(
    FakeCustodyDataSource ds, FakeMessaging messaging) async {
  final push = PushService(ds, messaging: messaging);
  await push.start(1);
  return push;
}

final _firstRow = find.byKey(const ValueKey('swap-request-10'));
final _install = find.byKey(NotificationsScreen.pushInstallKey);
final _footer = find.byKey(NotificationsScreen.pushFooterKey);

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // The analytics beacons are real futures on a MockClient.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
}

void main() {
  group('an iPhone in Safari, not installed', () {
    testWidgets('the install step sits ABOVE the list and opens the sheet',
        (tester) async {
      final ds = _source();
      // No PushManager in a Safari tab: the web transport never comes up.
      final push = await _pushIn(ds, FakeMessaging(supported: false));
      expect(push.state, PushState.unsupported);
      await tester.pumpWidget(
          _app(ds, push: push, facts: _iphoneTab, analytics: _analytics()));
      await _settle(tester);

      expect(_install, findsOneWidget);
      expect(find.descendant(
              of: _install, matching: find.text(_pt[KApp.pushHintInstallIos])),
          findsOneWidget);
      expect(tester.getRect(_install).bottom,
          lessThan(tester.getRect(_firstRow).top));
      expect(_footer, findsNothing,
          reason: 'the old mute line is replaced, not doubled');
      expect(find.text(_pt[KApp.pushHintUnsupported]), findsNothing);

      await tester.tap(find.text(_pt[KApp.pushInstallHow]));
      await _settle(tester);
      expect(find.text(_pt[KApp.installHintTitle]), findsOneWidget);
    });

    testWidgets('the impression is counted once, the tap every time',
        (tester) async {
      final ds = _source();
      final analytics = _analytics();
      await tester
          .pumpWidget(_app(ds, facts: _iphoneTab, analytics: analytics));
      await _settle(tester);

      await tester.tap(find.text(_pt[KApp.pushInstallHow]));
      await _settle(tester);
      Navigator.of(tester.element(find.text(_pt[KApp.installHintTitle])))
          .pop();
      await _settle(tester);
      await tester.tap(find.text(_pt[KApp.pushInstallHow]));
      await _settle(tester);

      final views = _named('push-nudge-view');
      expect(views, hasLength(1));
      expect(views.single['data'],
          {'channel': analytics.channel, 'platform': 'ios-safari', 'step': 'install'});
      expect(_named('push-nudge-click'), hasLength(2));
    });
  });

  testWidgets('another iOS browser is told to use Safari, with no button',
      (tester) async {
    final ds = _source();
    await tester.pumpWidget(_app(ds, facts: _chromeIos));
    await _settle(tester);

    expect(_install, findsNothing);
    expect(find.descendant(
            of: _footer, matching: find.text(_pt[KApp.pushHintNeedsSafari])),
        findsOneWidget);
    expect(tester.getRect(_footer).top,
        greaterThanOrEqualTo(tester.getRect(_firstRow).bottom));
  });

  group('refused — the way back, per platform, never a button', () {
    for (final (name, facts, key) in [
      ('installed iPhone', _iphoneInstalled, KApp.pushHintReallowIos),
      ('desktop browser', _desktop, KApp.pushHintReallowBrowser),
      ('Android app', null, KApp.pushHintReallowApp),
    ]) {
      testWidgets(name, (tester) async {
        final ds = _source();
        final push =
            await _pushIn(ds, FakeMessaging(current: PushPermission.denied));
        expect(push.state, PushState.blocked);
        await tester.pumpWidget(_app(ds, push: push, facts: facts));
        await _settle(tester);

        expect(find.descendant(of: _footer, matching: find.text(_pt[key])),
            findsOneWidget);
        expect(find.text(_pt[KApp.pushEnable]), findsNothing);
        expect(_install, findsNothing);
      });
    }
  });

  testWidgets('an installed iPhone not asked yet keeps the U-43 card',
      (tester) async {
    // Kept on purpose (owner, 21/09/2026): it is Apple's documented path, and
    // T-75 needs this very button to measure delivery on a real iPhone.
    final ds = _source();
    final analytics = _analytics();
    final messaging = FakeMessaging(current: PushPermission.notAsked);
    final push = await _pushIn(ds, messaging);
    await tester.pumpWidget(_app(ds,
        push: push, facts: _iphoneInstalled, analytics: analytics));
    await _settle(tester);

    final enable = find.widgetWithText(FilledButton, _pt[KApp.pushEnable]);
    expect(enable, findsOneWidget);
    expect(_install, findsNothing);

    messaging.current = PushPermission.granted;
    await tester.tap(enable);
    await _settle(tester);

    expect(_named('push-nudge-view').single['data'], {
      'channel': analytics.channel,
      'platform': 'ios-standalone',
      'step': 'enable',
    });
    expect(_named('push-enable-result').single['data'], {
      'channel': analytics.channel,
      'platform': 'ios-standalone',
      'outcome': 'granted',
    });
  });

  testWidgets('a desktop browser with no push keeps the old line',
      (tester) async {
    final ds = _source();
    final analytics = _analytics();
    await tester.pumpWidget(_app(ds, facts: _desktop, analytics: analytics));
    await _settle(tester);

    expect(find.text(_pt[KApp.pushHintUnsupported]), findsOneWidget);
    expect(_install, findsNothing);
    // `unsupported` is also the state BEFORE the service settles, so it is
    // never counted as an impression.
    expect(_named('push-nudge-view'), isEmpty);
  });
}
