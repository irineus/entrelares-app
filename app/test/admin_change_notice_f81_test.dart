// F-81 — an admin's direct change of the reader's days. A `day_admin_change`
// row in "Todas" renders from params and offers the matching action: "Ver o
// dia" for one day (the calendar with that day's sheet), "Ver o Histórico"
// for several (Relatórios → Histórico). The push lands on the same places.
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/screens/reports_screen.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart';
import 'reports_summary_test.dart' as reports;

final _pt = Localization(AppLanguage.ptBr);
final _en = Localization(AppLanguage.en);

AppNotification _row(int id, Map<String, dynamic> params) => AppNotification(
  id: id,
  recipientProfileId: ana.id,
  type: 'day_admin_change',
  title: 'stored title',
  message: 'stored',
  params: params,
  createdAt: DateTime.now().toIso8601String(),
);

Widget _notifApp(
  FakeCustodyDataSource ds, {
  required Localization l,
  ValueChanged<DateTime>? onOpenDay,
  ValueChanged<int>? onOpenAuditTrail,
}) => AppL10n(
  l: l,
  setLanguage: (_) async {},
  child: MaterialApp(
    home: NotificationsScreen(
      dataSource: ds,
      badge: NotificationBadge(ds),
      onOpenDay: onOpenDay,
      onOpenAuditTrail: onOpenAuditTrail,
      landing: NotificationLanding.history,
      landingNonce: '1',
    ),
  ),
);

void main() {
  testWidgets('one day: the row names it and "Ver o dia" hands it over', (
    tester,
  ) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [
        _row(31, {'kind': 'single', 'date': '2026-10-12', 'name': 'Bruno'}),
      ];
    DateTime? asked;
    await tester.pumpWidget(_notifApp(ds, l: _pt, onOpenDay: (d) => asked = d));
    await tester.pumpAndSettle();

    expect(find.text('Dia alterado no calendário'), findsOneWidget);
    expect(
      find.text('Bruno alterou o dia 12/10/2026 no calendário.'),
      findsOneWidget,
    );
    expect(find.text('stored'), findsNothing);
    expect(find.text(_pt[K.notifDayAdminChangeDayAction]), findsOneWidget);
    await tester.tap(find.byKey(NotificationsScreen.adminChangeActionKey(31)));
    await tester.pumpAndSettle();
    expect(asked, DateTime(2026, 10, 12));
  });

  testWidgets('several days: the row counts them and opens the Histórico', (
    tester,
  ) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [
        _row(32, {
          'kind': 'batch',
          'date': '2026-10-12',
          'to': '2026-11-30',
          'count': '14',
          'name': 'Bruno',
        }),
      ];
    int? opened;
    await tester.pumpWidget(
      _notifApp(ds, l: _en, onOpenAuditTrail: (id) => opened = id),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(_en[K.notifRenderTitleDayAdminChangeBatch]),
      findsOneWidget,
    );
    expect(find.textContaining('Bruno changed 14 days'), findsOneWidget);
    expect(find.text(_en[K.notifDayAdminChangeTrailAction]), findsOneWidget);
    await tester.tap(find.byKey(NotificationsScreen.adminChangeActionKey(32)));
    await tester.pumpAndSettle();
    expect(opened, 32);
  });

  testWidgets('a row the rule cannot read, or no host, offers nothing', (
    tester,
  ) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [
        _row(33, {'kind': 'undone', 'date': '2026-10-12', 'name': 'Bruno'}),
        _row(34, {'kind': 'single', 'date': '2026-10-12', 'name': 'Bruno'}),
      ];
    await tester.pumpWidget(_notifApp(ds, l: _pt));
    await tester.pumpAndSettle();

    expect(find.text('stored'), findsOneWidget, reason: 'unknown kind');
    expect(
      find.byKey(NotificationsScreen.adminChangeActionKey(33)),
      findsNothing,
    );
    expect(
      find.byKey(NotificationsScreen.adminChangeActionKey(34)),
      findsNothing,
      reason: 'no onOpenDay host',
    );
  });

  test('the push lands on the day or the Histórico, with its own icon', () {
    expect(
      PushRouting.landingFor('day_admin_change', kind: 'single'),
      NotificationLanding.day,
    );
    expect(
      PushRouting.landingFor('day_admin_change', kind: 'batch'),
      NotificationLanding.auditTrail,
    );
    expect(notifIcon('day_admin_change'), Icons.edit_calendar_outlined);
    expect(
      AnalyticsCatalog.notificationType('day_admin_change'),
      'day_admin_change',
    );
  });

  testWidgets('Relatórios opens on the Histórico when the landing asks', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      AppL10n(
        l: _pt,
        setLanguage: (_) async {},
        child: MaterialApp(
          theme: AppTheme.light,
          home: ReportsScreen(
            dataSource: reports.source(),
            initialTab: ReportsScreen.historyTab,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(_pt[K.auditHeading]), findsOneWidget);
    expect(find.text(_pt[K.sumHeading]), findsNothing);
  });
}
