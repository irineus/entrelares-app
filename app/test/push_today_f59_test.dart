// F-59 — the *Ativar notificações* strip under the Hoje card: shown to a
// device whose push can be turned on, pointing to Notificações (the one door
// to the OS dialog, F-09), dismissed with U-54's rhythm — and back, whatever
// the rhythm says, once a notice reached nobody (owner, 02/10/2026).
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/push_messaging.dart';
import 'package:entrelares_app/services/push_service.dart';
import 'package:entrelares_app/services/push_today_prefs.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource, row, today;
import 'push_service_test.dart' show FakeMessaging;

final _pt = Localization(AppLanguage.ptBr);

const _me = Member(
    id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', familyId: 7);
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
}
