// F-77 — the Premium trial's end. A `premium_trial` row in "Todas" offers
// "Ver o plano", and tapping it hands the host the plan page — the same place
// the push itself lands on (PushRouting → NotificationLanding.plan).
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart';

final _pt = Localization(AppLanguage.ptBr);

AppNotification _trialRow(int id, String kind) => AppNotification(
      id: id,
      recipientProfileId: ana.id,
      type: 'premium_trial',
      title: 'A avaliação Premium termina em breve',
      message: 'stored',
      params: {'kind': kind, 'date': '2026-10-09'},
      createdAt: DateTime.now().toIso8601String(),
    );

Widget _notifApp(FakeCustodyDataSource ds, VoidCallback? onOpenPlan) =>
    AppL10n(
      l: _pt,
      setLanguage: (_) async {},
      child: MaterialApp(
        home: NotificationsScreen(
          dataSource: ds,
          badge: NotificationBadge(ds),
          onOpenPlan: onOpenPlan,
          landing: NotificationLanding.history,
          landingNonce: '1',
        ),
      ),
    );

void main() {
  for (final (kind, titleKey) in [
    ('ending', K.notifRenderTitleTrialEnding),
    ('ended', K.notifRenderTitleTrialEnded),
  ]) {
    testWidgets('a "$kind" row renders from params and opens the plan page',
        (tester) async {
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
        ..notifications = [_trialRow(9, kind)];
      var opened = 0;
      await tester.pumpWidget(_notifApp(ds, () => opened++));
      await tester.pumpAndSettle();

      expect(find.text(_pt[titleKey]), findsOneWidget);
      await tester.tap(find.byKey(NotificationsScreen.trialActionKey(9)));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });
  }

  testWidgets('without a host to open the page, the row offers nothing',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [_trialRow(10, 'ending')];
    await tester.pumpWidget(_notifApp(ds, null));
    await tester.pumpAndSettle();

    expect(find.text(_pt[K.notifTrialAction]), findsNothing);
  });

  test('the push lands on the plan page, never on a tab', () {
    expect(PushRouting.landingFor('premium_trial', kind: 'ending'),
        NotificationLanding.plan);
  });
}
