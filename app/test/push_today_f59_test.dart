// F-59 — the *Ativar notificações* strip under the Hoje card: shown to a
// device whose push can be turned on, pointing to Notificações (the one door
// to the OS dialog, F-09), dismissed with U-54's rhythm — and back, whatever
// the rhythm says, once a notice reached nobody (owner, 02/10/2026).
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/push_messaging.dart';
import 'package:entrelares_app/services/push_service.dart';
import 'package:entrelares_app/services/push_today_prefs.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource, row, today;
import 'push_service_test.dart' show FakeMessaging;

final _pt = Localization(AppLanguage.ptBr);

const _me = Member(
    id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', familyId: 7);
const _admin = Member(
    id: 1,
    fullName: 'Ana Souza',
    colorSlot: 1,
    userId: 'u1',
    familyId: 7,
    isAdmin: true);
const _other = Member(
    id: 2, fullName: 'Bruno Lima', colorSlot: 2, userId: 'u2', familyId: 7);

class _MemoryPrefs implements PushTodayPrefs {
  InstallHintDismissals stored = InstallHintDismissals.none;
  @override
  InstallHintDismissals read() => stored;
  @override
  Future<void> dismiss(DateTime now) async => stored = stored.next(now);
}

FakeCustodyDataSource _source() => FakeCustodyDataSource(
    members: [_me, _other], days: [row(100, today, 1)]);

Future<PushService> _push(FakeCustodyDataSource ds, PushPermission permission) async {
  final push = PushService(ds, messaging: FakeMessaging(current: permission));
  await push.start(_me.id);
  return push;
}

Widget _app(FakeCustodyDataSource ds,
        {PushService? push, PushTodayPrefs? prefs, VoidCallback? onOpen}) =>
    AppL10n(
      l: _pt,
      setLanguage: (_) async {},
      child: MaterialApp(
        home: CalendarScreen(
          dataSource: ds,
          adminMode: AdminMode(),
          push: push,
          pushTodayPrefs: prefs,
          onOpenNotifications: onOpen ?? () {},
        ),
      ),
    );

Finder get _strip => find.byKey(CalendarScreen.pushTodayKey);

void main() {
  testWidgets('push off on this device: the strip, pointing to Notificações',
      (tester) async {
    final ds = _source();
    final push = await _push(ds, PushPermission.notAsked);
    expect(push.state, PushState.off);
    var opened = 0;
    await tester.pumpWidget(_app(ds, push: push, onOpen: () => opened++));
    await tester.pumpAndSettle();

    expect(_strip, findsOneWidget);
    expect(find.text(_pt[KApp.pushTodayMessage]), findsOneWidget);
    await tester.tap(find.text(_pt[KApp.pushTodayAction]));
    await tester.pumpAndSettle();
    expect(opened, 1, reason: 'the strip only points to the one door');
  });

  testWidgets('push on, or no push service at all: no strip', (tester) async {
    final ds = _source();
    final on = await _push(ds, PushPermission.granted);
    expect(on.state, PushState.on);
    await tester.pumpWidget(_app(ds, push: on));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);

    await tester.pumpWidget(_app(_source()));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
  });

  testWidgets('dismissed: gone, and it stays gone while nothing new arrives',
      (tester) async {
    final ds = _source();
    final push = await _push(ds, PushPermission.notAsked);
    final prefs = _MemoryPrefs();
    await tester.pumpWidget(_app(ds, push: push, prefs: prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(_pt[KApp.pushTodayDismiss]));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
    expect(prefs.stored.count, 1);

    // A new opening, an older unread notification: still quiet.
    ds.newestUnreadAt = prefs.stored.last!.subtract(const Duration(hours: 1));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(ds, push: push, prefs: prefs));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
  });

  testWidgets('a notice that reached nobody brings it back, past the third '
      'dismissal', (tester) async {
    final ds = _source()
      ..accountHasPush = false
      ..newestUnreadAt = DateTime.now().add(const Duration(minutes: 1));
    final push = await _push(ds, PushPermission.notAsked);
    final prefs = _MemoryPrefs()
      ..stored = InstallHintDismissals(
          count: InstallHintRules.maxDismissals,
          last: DateTime.now().subtract(const Duration(days: 2)));
    await tester.pumpWidget(_app(ds, push: push, prefs: prefs));
    await tester.pumpAndSettle();
    expect(_strip, findsOneWidget);
  });

  testWidgets("...but not when the reader's other phone rings", (tester) async {
    final ds = _source()
      ..accountHasPush = true
      ..newestUnreadAt = DateTime.now().add(const Duration(minutes: 1));
    final push = await _push(ds, PushPermission.notAsked);
    final prefs = _MemoryPrefs()
      ..stored = InstallHintDismissals(
          count: 1, last: DateTime.now().subtract(const Duration(days: 2)));
    await tester.pumpWidget(_app(ds, push: push, prefs: prefs));
    await tester.pumpAndSettle();
    expect(_strip, findsNothing);
  });

  // 03/10/2026 — the strip is a STATE line, and the calendar holds with it on.
  // As an AppBanner it measured 146 dp on a Pixel 6: the Android E2E lane
  // (run 37124944050) had the founder — admin, push not asked, one day planned
  // three days ahead, so the U-55 nudge and the F-70 strip on too — type the
  // swap message, and with the keyboard up the column behind the editor
  // overflowed by 20 px. Measured with Inter and the product theme: the test
  // font draws every glyph as a square, and a line height is the question.
  group('on a phone', () {
    setUpAll(() async {
      final inter = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'));
      await inter.load();
    });

    /// [body] is what the shell leaves the calendar's Scaffold under its own
    /// 48 dp app bar; 411.4 x 729.5 is the Pixel 6 the lane runs on.
    Future<void> pumpPhone(WidgetTester tester, Size body,
        {Member me = _me,
        double keyboard = 0,
        AppLanguage language = AppLanguage.ptBr}) async {
      final size = Size(body.width, body.height + 48);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final ds = FakeCustodyDataSource(
          members: [me, _other],
          days: [row(100, today.add(const Duration(days: 3)), 1)]);
      final push = await _push(ds, PushPermission.notAsked);
      await tester.pumpWidget(AppL10n(
        l: Localization(language),
        setLanguage: (_) async {},
        child: MaterialApp(
          theme: AppTheme.light,
          home: CalendarScreen(
            dataSource: ds,
            adminMode: AdminMode(),
            push: push,
            onOpenNotifications: () {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      if (keyboard > 0) {
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
      }
    }

    for (final language in AppLanguage.values) {
      for (final width in [360.0, 411.4]) {
        testWidgets('one row, no taller than its 48 dp action, at $width dp '
            '(${language.name})', (tester) async {
          await pumpPhone(tester, Size(width, 729.5), language: language);
          expect(_strip, findsOneWidget);
          // The row plus its 4 dp above and below.
          expect(tester.getSize(_strip).height, lessThanOrEqualTo(48 + 8),
              reason: 'the strip sits between the Hoje card and the month; '
                  'every point it takes is a point the month does not get');
        });
      }
    }

    testWidgets("the E2E founder's calendar holds with the editor's keyboard "
        'up', (tester) async {
      await pumpPhone(tester, const Size(411.4, 729.5),
          me: _admin, keyboard: 250);
      // Every strip the lane had on — otherwise this holds about nothing.
      expect(_strip, findsOneWidget);
      expect(find.byKey(const Key('handoff-nudge')), findsOneWidget);
      expect(find.byKey(CalendarScreen.planEndStripKey), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'the column behind the editor overflowed (run 37124944050)');
    });
  });
}
