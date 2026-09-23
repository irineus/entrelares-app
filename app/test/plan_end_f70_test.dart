// F-70 — the plan-end notification's one action. A `plan_ending` row in
// "Todas" offers "Planejar os próximos meses"; tapping it hands the host the
// first day with no plan, and the calendar, given that day through its
// listenable, opens the wizard on it. Rows of other types offer nothing.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart';

final _pt = Localization(AppLanguage.ptBr);

String _iso(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

AppNotification _planRow(int id, String kind, DateTime lastDay) =>
    AppNotification(
      id: id,
      recipientProfileId: ana.id,
      type: 'plan_ending',
      title: 'O planejamento termina em breve',
      message: 'stored',
      params: {'kind': kind, 'date': _iso(lastDay)},
      createdAt: DateTime.now().toIso8601String(),
    );

Widget _notifApp(FakeCustodyDataSource ds, ValueChanged<DateTime> onPlanFrom) =>
    AppL10n(
      l: _pt,
      setLanguage: (_) async {},
      child: MaterialApp(
        home: NotificationsScreen(
          dataSource: ds,
          badge: NotificationBadge(ds),
          onPlanFrom: onPlanFrom,
          landing: NotificationLanding.history,
          landingNonce: '1',
        ),
      ),
    );

Finder _wizardStart(DateTime date) => find.descendant(
    of: find.byKey(const Key('wizStartDate')),
    matching: find.text(_pt.formatDate(date)));

void main() {
  final day = dateOnly(today);

  testWidgets('a plan still ahead: the row offers the action and hands over '
      'the day after the last planned one', (tester) async {
    final lastDay = DateTime(day.year, day.month, day.day + 20);
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [_planRow(5, 'ending', lastDay)];
    DateTime? asked;
    await tester.pumpWidget(_notifApp(ds, (d) => asked = d));
    await tester.pumpAndSettle();

    expect(find.text(_pt[K.notifRenderTitlePlanEnding]), findsOneWidget);
    await tester.tap(find.byKey(NotificationsScreen.planActionKey(5)));
    await tester.pumpAndSettle();
    expect(asked, DateTime(lastDay.year, lastDay.month, lastDay.day + 1));
  });

  testWidgets('a plan that already ended hands over TODAY, never the past',
      (tester) async {
    final lastDay = DateTime(day.year, day.month, day.day - 10);
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [_planRow(6, 'ended', lastDay)];
    DateTime? asked;
    await tester.pumpWidget(_notifApp(ds, (d) => asked = d));
    await tester.pumpAndSettle();

    expect(find.text(_pt[K.notifRenderTitlePlanEnded]), findsOneWidget);
    await tester.tap(find.byKey(NotificationsScreen.planActionKey(6)));
    await tester.pumpAndSettle();
    expect(asked, day);
  });

  testWidgets('other rows, and a plan row the rule cannot read, offer nothing',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [
        AppNotification(
          id: 7,
          recipientProfileId: ana.id,
          type: 'billing',
          title: 'Seu Premium está prestes a ser interrompido',
          message: 'stored',
          params: {'kind': 'grace_warning', 'date': _iso(day)},
          createdAt: DateTime.now().toIso8601String(),
        ),
        AppNotification(
          id: 8,
          recipientProfileId: ana.id,
          type: 'plan_ending',
          title: 'O planejamento termina em breve',
          message: 'stored',
          params: {'kind': 'something_new', 'date': _iso(day)},
          createdAt: DateTime.now().toIso8601String(),
        ),
      ];
    await tester.pumpWidget(_notifApp(ds, (_) {}));
    await tester.pumpAndSettle();

    expect(find.text(_pt[K.notifPlanAction]), findsNothing);
  });

  testWidgets('the calendar opens the wizard on the requested day and '
      'consumes the request', (tester) async {
    final start = DateTime(day.year, day.month, day.day + 40);
    final request = ValueNotifier<DateTime?>(null);
    addTearDown(request.dispose);
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(AppL10n(
      l: _pt,
      setLanguage: (_) async {},
      child: MaterialApp(
        home: CalendarScreen(
            dataSource: ds, adminMode: AdminMode(), planRequest: request),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text(_pt[K.wizTitle]), findsNothing);

    request.value = start;
    await tester.pumpAndSettle();

    expect(find.text(_pt[K.wizTitle]), findsOneWidget);
    expect(_wizardStart(start), findsOneWidget);
    expect(request.value, isNull,
        reason: 'a second visit to the calendar must not reopen the wizard');
  });

  group('the calendar strip (a state, whatever door the reader came through)',
      () {
    Future<void> pumpCalendar(WidgetTester tester, List<DateTime> planned) async {
      final ds = FakeCustodyDataSource(
          members: [ana, bruno],
          days: [
            for (final (i, d) in planned.indexed) row(900 + i, d, ana.id)
          ]);
      await tester.pumpWidget(AppL10n(
        l: _pt,
        setLanguage: (_) async {},
        child: MaterialApp(
          home: CalendarScreen(dataSource: ds, adminMode: AdminMode()),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Finder strip() => find.byKey(CalendarScreen.planEndStripKey);

    testWidgets('a plan that ended says so and plans from today',
        (tester) async {
      final last = DateTime(day.year, day.month, day.day - 5);
      await pumpCalendar(tester, [DateTime(day.year, day.month, day.day - 6), last]);

      expect(
          find.text(_pt.format(K.calPlanEnded, [_pt.formatDate(last)])),
          findsOneWidget);
      await tester.tap(find.descendant(
          of: strip(), matching: find.text(_pt[K.notifPlanAction])));
      await tester.pumpAndSettle();
      expect(find.text(_pt[K.wizTitle]), findsOneWidget);
      expect(_wizardStart(day), findsOneWidget);
    });

    testWidgets('a plan ending within 30 days plans from the day after',
        (tester) async {
      final last = DateTime(day.year, day.month, day.day + 12);
      await pumpCalendar(tester, [last]);

      expect(
          find.text(_pt.format(K.calPlanEnding, [_pt.formatDate(last)])),
          findsOneWidget);
      await tester.tap(find.descendant(
          of: strip(), matching: find.text(_pt[K.notifPlanAction])));
      await tester.pumpAndSettle();
      expect(_wizardStart(DateTime(last.year, last.month, last.day + 1)),
          findsOneWidget);
    });

    testWidgets('a plan further than 30 days, or none at all, shows nothing',
        (tester) async {
      await pumpCalendar(tester, [DateTime(day.year, day.month, day.day + 31)]);
      expect(strip(), findsNothing);

      await pumpCalendar(tester, const []);
      expect(strip(), findsNothing);
    });
  });
}
