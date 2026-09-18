// U-43 — the push control keeps its home on Notificações (F-09: one door to
// the OS dialog) and changes SHAPE with its state: a card above the list only
// while push is OFF, an app-bar icon + sheet once it is ON, a quiet line after
// the list when it is blocked or unsupported.
//
// Placement is measured by RECT, not by presence: the defect was never a
// missing control, it was a settings card holding the first fold of a screen
// whose purpose is the list.
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/services/push_messaging.dart';
import 'package:entrelares_app/services/push_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart';
import 'frozen_day_test.dart' show swapReq;
import 'push_service_test.dart' show FakeMessaging;

final _pt = Localization(AppLanguage.ptBr);

Future<PushService> _pushIn(
    FakeCustodyDataSource ds, FakeMessaging messaging) async {
  final push = PushService(ds, messaging: messaging);
  await push.start(1);
  return push;
}

Widget _app(FakeCustodyDataSource ds, PushService? push) => AppL10n(
      l: _pt,
      setLanguage: (_) async {},
      child: MaterialApp(
        home: NotificationsScreen(
            dataSource: ds, badge: NotificationBadge(ds), push: push),
      ),
    );

FakeCustodyDataSource _source() =>
    FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..pendingForMe = [swapReq(10, dayOfMonth(today.day), message: 'Consulta')];

final _tabs = find.byWidgetPredicate((w) => w is AppSegmented);
final _firstRow = find.byKey(const ValueKey('swap-request-10'));
final _status = find.byKey(NotificationsScreen.pushStatusKey);
final _footer = find.byKey(NotificationsScreen.pushFooterKey);

/// The list starts right under the tab strip: nothing sits between them.
void _expectListOwnsTheFirstFold(WidgetTester tester) {
  final gap =
      tester.getRect(_firstRow).top - tester.getRect(_tabs).bottom;
  expect(gap, lessThan(24),
      reason: 'with no card, the first row follows the tab strip');
}

void main() {
  testWidgets('off: the card is above the list, with the enable button',
      (tester) async {
    final ds = _source();
    final push =
        await _pushIn(ds, FakeMessaging(current: PushPermission.notAsked));
    expect(push.state, PushState.off);
    await tester.pumpWidget(_app(ds, push));
    await tester.pumpAndSettle();

    final enable = find.widgetWithText(FilledButton, _pt[KApp.pushEnable]);
    expect(enable, findsOneWidget);
    expect(find.text(_pt[KApp.pushHintOff]), findsOneWidget);
    expect(tester.getRect(enable).bottom,
        lessThan(tester.getRect(_firstRow).top));
    expect(_status, findsNothing);
    expect(_footer, findsNothing);
  });

  testWidgets('off → enable: the card leaves and the icon takes over',
      (tester) async {
    final ds = _source();
    final messaging = FakeMessaging(current: PushPermission.notAsked);
    final push = await _pushIn(ds, messaging);
    await tester.pumpWidget(_app(ds, push));
    await tester.pumpAndSettle();

    messaging.current = PushPermission.granted; // the person says yes
    await tester.tap(find.widgetWithText(FilledButton, _pt[KApp.pushEnable]));
    await tester.pumpAndSettle();

    expect(messaging.permissionRequests, 1);
    expect(push.state, PushState.on);
    expect(find.text(_pt[KApp.pushHintOff]), findsNothing);
    expect(_status, findsOneWidget);
    _expectListOwnsTheFirstFold(tester);
  });

  testWidgets('on: no card — the first fold is the list, and the app bar '
      'carries a named icon', (tester) async {
    final ds = _source();
    final push =
        await _pushIn(ds, FakeMessaging(current: PushPermission.granted));
    expect(push.state, PushState.on);
    await tester.pumpWidget(_app(ds, push));
    await tester.pumpAndSettle();

    expect(find.text(_pt[KApp.pushTitle]), findsNothing);
    expect(find.text(_pt[KApp.pushHintOn]), findsNothing);
    expect(_footer, findsNothing);
    _expectListOwnsTheFirstFold(tester);

    expect(_status, findsOneWidget);
    expect(tester.widget<IconButton>(_status).tooltip,
        _pt[KApp.pushStatusOnTooltip]);
  });

  testWidgets('on: disabling is two taps away, and the card comes back',
      (tester) async {
    final ds = _source();
    final messaging = FakeMessaging(current: PushPermission.granted);
    final push = await _pushIn(ds, messaging);
    await tester.pumpWidget(_app(ds, push));
    await tester.pumpAndSettle();

    await tester.tap(_status); // tap 1
    await tester.pumpAndSettle();
    expect(find.text(_pt[KApp.pushTitle]), findsOneWidget);
    expect(find.text(_pt[KApp.pushHintOn]), findsOneWidget);

    await tester.tap(find.byKey(NotificationsScreen.pushDisableKey)); // tap 2
    await tester.pumpAndSettle();

    expect(push.state, PushState.off);
    expect(messaging.deletedTokens, 1);
    expect(find.text(_pt[KApp.pushToastOff]), findsOneWidget);
    expect(_status, findsNothing);
    expect(find.widgetWithText(FilledButton, _pt[KApp.pushEnable]),
        findsOneWidget);
  });

  testWidgets('on: closing the sheet changes nothing', (tester) async {
    final ds = _source();
    final push =
        await _pushIn(ds, FakeMessaging(current: PushPermission.granted));
    await tester.pumpWidget(_app(ds, push));
    await tester.pumpAndSettle();

    await tester.tap(_status);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppSheetFrame.closeKey));
    await tester.pumpAndSettle();

    expect(push.state, PushState.on);
    expect(_status, findsOneWidget);
  });

  for (final (name, messaging, hintKey) in [
    (
      'blocked',
      () => FakeMessaging(current: PushPermission.denied),
      KApp.pushHintBlocked
    ),
    (
      'unsupported',
      () => FakeMessaging(supported: false),
      KApp.pushHintUnsupported
    ),
  ]) {
    testWidgets('$name: the explanation is the LAST item of the list, with no '
        'button', (tester) async {
      final ds = _source();
      final push = await _pushIn(ds, messaging());
      await tester.pumpWidget(_app(ds, push));
      await tester.pumpAndSettle();

      _expectListOwnsTheFirstFold(tester);
      expect(_status, findsNothing);
      expect(_footer, findsOneWidget);
      expect(find.descendant(of: _footer, matching: find.text(_pt[hintKey])),
          findsOneWidget);
      expect(tester.getRect(_footer).top,
          greaterThanOrEqualTo(tester.getRect(_firstRow).bottom));
      expect(find.text(_pt[KApp.pushEnable]), findsNothing);
      expect(find.text(_pt[KApp.pushDisable]), findsNothing);
    });
  }

  testWidgets('an EMPTY tab still explains itself (no transport at all)',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(_app(ds, null));
    await tester.pumpAndSettle();

    expect(find.text(_pt[K.notifEmptyIncoming]), findsOneWidget);
    expect(_footer, findsOneWidget);
    expect(find.text(_pt[KApp.pushHintUnsupported]), findsOneWidget);
  });

  testWidgets('a state that settles AFTER the screen mounted moves the control',
      (tester) async {
    final ds = _source();
    final push =
        PushService(ds, messaging: FakeMessaging(current: PushPermission.granted));
    await tester.pumpWidget(_app(ds, push));
    await tester.pumpAndSettle();
    expect(_footer, findsOneWidget); // not started yet: unsupported

    await tester.runAsync(() => push.start(1));
    await tester.pumpAndSettle();

    expect(push.state, PushState.on);
    expect(_footer, findsNothing);
    expect(_status, findsOneWidget);
  });
}
