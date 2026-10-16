// F-80 PR 3 — the referral reward. A `referral_reward` row in "Todas" renders
// from params (it names no family and states no day), offers "Ver o plano",
// and the push lands on the plan page, like F-77's trial notice.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart';

final _en = Localization(AppLanguage.en);

AppNotification _rewardRow(int id) => AppNotification(
  id: id,
  recipientProfileId: ana.id,
  type: 'referral_reward',
  title: 'Um mês de Premium pela indicação',
  message: 'stored',
  params: {'kind': 'granted'},
  createdAt: DateTime.now().toIso8601String(),
);

Widget _notifApp(FakeCustodyDataSource ds, VoidCallback? onOpenPlan) => AppL10n(
  l: _en,
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
  testWidgets(
    'the row renders in the reader language and opens the plan page',
    (tester) async {
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
        ..notifications = [_rewardRow(21)];
      var opened = 0;
      await tester.pumpWidget(_notifApp(ds, () => opened++));
      await tester.pumpAndSettle();

      expect(find.text(_en[K.notifRenderTitleReferralReward]), findsOneWidget);
      expect(find.text(_en[K.notifRenderReferralReward]), findsOneWidget);
      expect(find.text('stored'), findsNothing);
      await tester.tap(find.byKey(NotificationsScreen.trialActionKey(21)));
      await tester.pumpAndSettle();
      expect(opened, 1);
    },
  );

  test('the push lands on the plan page and has its own icon', () {
    expect(
      PushRouting.landingFor('referral_reward', kind: 'granted'),
      NotificationLanding.plan,
    );
    expect(notifIcon('referral_reward'), Icons.card_giftcard_outlined);
  });
}
