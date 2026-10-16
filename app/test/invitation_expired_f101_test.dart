// F-101 — the inviting admin is told once when an invitation expires. The row
// renders in the reader's language from `params`, offers "Compartilhar de
// novo" (which opens the Família page, where the card makes a new link), and
// the push lands on that page on both channels.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart';

final _pt = Localization(AppLanguage.ptBr);
final _en = Localization(AppLanguage.en);

AppNotification _expiredRow(int id) => AppNotification(
      id: id,
      recipientProfileId: ana.id,
      type: 'invitation_expired',
      title: 'O convite expirou',
      message: 'stored',
      params: {'kind': 'expired', 'name': 'Bruno Lima', 'invitation_id': 7},
      createdAt: DateTime.now().toIso8601String(),
    );

Widget _notifApp(FakeCustodyDataSource ds, Localization l,
        VoidCallback? onOpenFamily) =>
    AppL10n(
      l: l,
      setLanguage: (_) async {},
      child: MaterialApp(
        home: NotificationsScreen(
          dataSource: ds,
          badge: NotificationBadge(ds),
          onOpenFamily: onOpenFamily,
          landing: NotificationLanding.history,
          landingNonce: '1',
        ),
      ),
    );

void main() {
  testWidgets('the row renders in the reader language and opens Família',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [_expiredRow(31)];
    var opened = 0;
    await tester.pumpWidget(_notifApp(ds, _en, () => opened++));
    await tester.pumpAndSettle();

    expect(find.text(_en[K.notifRenderTitleInvitationExpired]), findsOneWidget);
    expect(find.text(_en.format(K.notifRenderInvitationExpired, ['Bruno Lima'])),
        findsOneWidget);
    expect(find.text('stored'), findsNothing);
    expect(find.text(_en[KApp.famShareAgain]), findsOneWidget);

    await tester.tap(find.byKey(NotificationsScreen.familyActionKey(31)));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('without a host door the row still renders, with no action',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [_expiredRow(32)];
    await tester.pumpWidget(_notifApp(ds, _pt, null));
    await tester.pumpAndSettle();

    expect(find.text(_pt[K.notifRenderTitleInvitationExpired]), findsOneWidget);
    expect(find.byKey(NotificationsScreen.familyActionKey(32)), findsNothing);
  });

  test('the push lands on the Família page, with or without a kind', () {
    expect(PushRouting.landingFor('invitation_expired', kind: 'expired'),
        NotificationLanding.family);
    expect(PushRouting.landingFor('invitation_expired'),
        NotificationLanding.family);
    expect(PushRouting.familyTypes, {'invitation_expired'});
  });
}
