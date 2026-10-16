// U-65 (T-103 audit, 04/10/2026) — notifications that led nowhere.
//
// - An agenda notice or reminder in "Todas" opens its day ("Ver o dia").
// - The Conversa's rows are not "Todas"'s: one per text flooded the newest
//   100. One line at the top says how many are unread and opens the Conversa.
// - Settle-ups waiting for MY "Recebi / Não recebi" are counted: the badge on
//   the Despesas tab (NotificationBadge.settlementsToConfirm).
// The push side (Despesas and the day) is PushRouting's, in core, with the
// service-worker mirror.
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_db_contracts/models/chat_message.dart';
import 'package:entrelares_db_contracts/models/expense.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart';

final _pt = Localization(AppLanguage.ptBr);

AppNotification _row(int id, String type, Map<String, dynamic> params) =>
    AppNotification(
      id: id,
      recipientProfileId: ana.id,
      type: type,
      title: 'stored title $id',
      message: 'stored $id',
      params: params,
      createdAt: DateTime.now().toIso8601String(),
    );

Widget _notifApp(
  FakeCustodyDataSource ds,
  NotificationBadge badge, {
  ValueChanged<DateTime>? onOpenDay,
  VoidCallback? onOpenChat,
}) => AppL10n(
  l: _pt,
  setLanguage: (_) async {},
  child: MaterialApp(
    home: NotificationsScreen(
      dataSource: ds,
      badge: badge,
      onOpenDay: onOpenDay,
      onOpenChat: onOpenChat,
      landing: NotificationLanding.history,
      landingNonce: '1',
    ),
  ),
);

ChatMessage _text(int id) => ChatMessage(
  id: id,
  authorProfileId: bruno.id,
  body: 'texto $id',
  createdAt: DateTime.utc(2026, 9, 24, 12),
);

ExpenseSettlement _settlement(int id, {required int to, String status = 'pending'}) =>
    ExpenseSettlement(
      id: id,
      fromProfile: to == ana.id ? bruno.id : ana.id,
      toProfile: to,
      amountCents: 30000,
      status: status,
      createdAt: DateTime.utc(2026, 10, 1),
    );

void main() {
  testWidgets('an agenda row opens its day', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [
        _row(41, 'agenda_reminder', {'date': '2026-10-12', 'kind': 'medical'}),
      ];
    DateTime? asked;
    await tester.pumpWidget(
        _notifApp(ds, NotificationBadge(ds), onOpenDay: (d) => asked = d));
    await tester.pumpAndSettle();

    expect(find.text(_pt[KApp.notifAgendaSeeDay]), findsOneWidget);
    await tester.tap(find.byKey(NotificationsScreen.agendaActionKey(41)));
    await tester.pumpAndSettle();
    expect(asked, DateTime(2026, 10, 12));
  });

  testWidgets('an agenda row without a real day offers nothing and renders',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [_row(42, 'agenda_notice', {'kind': 'medical'})];
    await tester.pumpWidget(
        _notifApp(ds, NotificationBadge(ds), onOpenDay: (_) {}));
    await tester.pumpAndSettle();
    expect(find.byKey(NotificationsScreen.agendaActionKey(42)), findsNothing);
  });

  testWidgets(
      'the Conversa\'s rows leave "Todas"; one line counts the unread and '
      'opens the Conversa', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [
        _row(51, 'chat_message', {'name': 'Bruno'}),
        _row(52, 'chat_message', {'name': 'Bruno'}),
        _row(53, 'swap_approved', {'date': '2026-10-12', 'name': 'Bruno'}),
      ]
      ..chatMessages = [_text(1), _text(2), _text(3)];
    final badge = NotificationBadge(ds)..chatOn = true;
    var opened = 0;
    await tester.pumpWidget(
        _notifApp(ds, badge, onOpenChat: () => opened++));
    await tester.pumpAndSettle();

    expect(find.text('stored title 51'), findsNothing);
    expect(find.text('stored title 52'), findsNothing);
    expect(find.text(_pt.format(KApp.notifChatUnreadMany, [3])), findsOneWidget);
    await tester.tap(find.byKey(NotificationsScreen.chatPointerKey));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('no unread texts, or no Conversa here: no line', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [_row(53, 'swap_approved', {'date': '2026-10-12'})];
    final badge = NotificationBadge(ds)..chatOn = true;
    await tester.pumpWidget(_notifApp(ds, badge, onOpenChat: () {}));
    await tester.pumpAndSettle();
    expect(find.byKey(NotificationsScreen.chatPointerKey), findsNothing);

    ds.chatMessages = [_text(1)];
    await tester.pumpWidget(_notifApp(ds, NotificationBadge(ds)..chatOn = true));
    await tester.pumpAndSettle();
    expect(find.byKey(NotificationsScreen.chatPointerKey), findsNothing,
        reason: 'without onOpenChat the line has nowhere to go');
  });

  group('settle-ups waiting for me', () {
    test('counted while the Despesas module is on, mine and pending only',
        () async {
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
        ..settlements = [
          _settlement(1, to: ana.id),
          _settlement(2, to: ana.id),
          _settlement(3, to: bruno.id),
          _settlement(4, to: ana.id, status: 'confirmed'),
        ];
      final badge = NotificationBadge(ds);
      await badge.refresh();
      expect(badge.settlementsToConfirm, 0, reason: 'module off: no count');

      badge.expensesOn = true;
      await badge.refresh();
      expect(badge.settlementsToConfirm, 2);
      expect(badge.total, badge.count + badge.chatUnread,
          reason: 'the bell does not take the settle-ups — Despesas does');
    });
  });
}
