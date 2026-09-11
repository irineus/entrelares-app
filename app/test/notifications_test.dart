// Lote 3 PR 4 — the Notifications page (3 tabs), the bell badge (⚠️ counts
// open requests awaiting me, NOT unread rows) and the F-23 safety poll, all
// against the fake data source.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart';
import 'frozen_day_test.dart' show swapReq;

final pt = Localization(AppLanguage.ptBr);

Widget notifApp(FakeCustodyDataSource ds, NotificationBadge badge,
        {AppLanguage language = AppLanguage.ptBr,
        NotificationLanding? landing,
        String? landingNonce}) =>
    AppL10n(
      l: Localization(language),
      setLanguage: (_) async {},
      child: MaterialApp(
        home: NotificationsScreen(
            dataSource: ds,
            badge: badge,
            landing: landing,
            landingNonce: landingNonce),
      ),
    );

void main() {
  _landingTests();

  testWidgets('opening the page marks everything read and shows the '
      'incoming requests', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..pendingForMe = [
        swapReq(10, dayOfMonth(today.day), message: 'Tenho consulta')
      ];
    final badge = NotificationBadge(ds);
    await tester.pumpWidget(notifApp(ds, badge));
    await tester.pumpAndSettle();

    expect(ds.markAllReadCalls, 1);
    // The incoming tab is the default and carries its count.
    expect(find.text('${pt[K.notifTabIncoming]} (1)'), findsOneWidget);
    expect(find.text('Bruno Lima'), findsOneWidget); // requester
    expect(find.text('Tenho consulta'), findsOneWidget); // F-44
    expect(find.text(pt[K.notifBtnApprove]), findsOneWidget);
    expect(find.text(pt[K.notifBtnReject]), findsOneWidget);
  });

  testWidgets('approving from the page records the F-44 note and refreshes '
      'the badge', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..pendingForMe = [swapReq(10, dayOfMonth(today.day))];
    final badge = NotificationBadge(ds);
    await badge.refresh();
    expect(badge.count, 1);

    await tester.pumpWidget(notifApp(ds, badge));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Busco às 18h');
    ds.pendingForMe = []; // the approval resolves it server-side
    await tester.tap(find.text(pt[K.notifBtnApprove]));
    await tester.pumpAndSettle();

    expect(ds.approvedSwaps, [(id: 10, note: 'Busco às 18h')]);
    expect(badge.count, 0);
    expect(find.text(pt[K.toastSwapApproved]), findsOneWidget);
  });

  testWidgets('the sent tab shows status, the 🤖 auto badge and cancels '
      'pending requests', (tester) async {
    final autoApproved = SwapRequest.fromJson({
      'id': 20,
      'schedule_date': CareSchedule.isoDate(dayOfMonth(today.day)),
      'requesting_profile_id': 1,
      'target_profile_id': 2,
      'proposed_actual_parent_id': 2,
      'status': 'approved',
      'resolved_by': 'system',
      'resolved_at': '2026-08-18T12:00:00+00:00',
      'approval_note': 'Combinado',
    });
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..sentRequests = [
        swapReq(21, dayOfMonth(today.day), requesting: 1, target: 2,
            proposed: 2),
        autoApproved,
      ];
    final badge = NotificationBadge(ds);
    await tester.pumpWidget(notifApp(ds, badge));
    await tester.pumpAndSettle();

    await tester.tap(find.text(pt[K.notifTabSent]));
    await tester.pumpAndSettle();

    expect(find.text(pt[K.notifStatusPending]), findsOneWidget);
    expect(find.text(pt[K.notifStatusApproved]), findsOneWidget);
    expect(find.text(pt[K.notifAutoBadge]), findsOneWidget); // F-24
    expect(find.text('Combinado'), findsOneWidget); // approver's note

    await tester.tap(find.text(pt[K.notifBtnCancelRequest]));
    await tester.pumpAndSettle();
    expect(ds.cancelledSwaps, [21]);
  });

  testWidgets('the history tab rebuilds rows through the renderer in the '
      'reader\'s language', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [
        AppNotification.fromJson({
          'id': 1,
          'recipient_profile_id': 1,
          'type': 'swap_approved',
          'title': 'Troca aprovada! ✅',
          'message':
              'Bruno Lima aceitou ficar com a criança no dia 05/09/2026.',
          'params': {
            'date': '2026-09-05',
            'name': 'Bruno Lima',
            'proposed': 'target'
          },
          'is_read': false,
        }),
      ];
    final badge = NotificationBadge(ds);

    // English reader: the SAME row renders in English (U-13), date per U-24.
    await tester.pumpWidget(notifApp(ds, badge, language: AppLanguage.en));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();

    expect(find.text('✅'), findsOneWidget);
    expect(find.textContaining('Bruno Lima'), findsOneWidget);
    expect(find.textContaining('05/09/2026'), findsNothing,
        reason: 'an English reader never sees the Brazilian numeric date');
  });

  testWidgets('the bell badge counts pending-for-me and caps at 99+',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..pendingForMe = [
        for (var i = 0; i < 120; i++) swapReq(100 + i, dayOfMonth(today.day))
      ];
    final badge = NotificationBadge(ds);
    await badge.refresh();
    expect(badge.count, 120);
    expect(bellBadgeText(badge.count), '99+');
  });

  testWidgets('F-23: the safety poll reloads the month on its cadence',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    final initialFetches = ds.monthFetches;

    // Socket never connected → the 25 s degraded cadence.
    await tester.pump(const Duration(seconds: 26));
    await tester.pumpAndSettle();
    expect(ds.monthFetches, greaterThan(initialFetches));

    // A healthy socket relaxes the poll: 30 s brings nothing…
    ds.statusCallback!(true);
    final afterFirstPoll = ds.monthFetches;
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(ds.monthFetches, afterFirstPoll);

    // …but the 120 s tick still fires (the safety net stays).
    await tester.pump(const Duration(seconds: 100));
    await tester.pumpAndSettle();
    expect(ds.monthFetches, greaterThan(afterFirstPoll));
  });
}

// ── F-09: where a tapped push lands ──────────────────────────────────────────
//
// Found on the first real device round (29/08/2026): tapping "Troca aprovada"
// opened the page on "Para você", which lists OPEN requests and is therefore
// EMPTY for exactly that notice — the person taps a notification and lands on
// "nada pendente para você", which reads as the app having lost what it just
// told them. `PushRouting` decides the tab; these prove the screen obeys it.
void _landingTests() {
  testWidgets('a receipt lands on Histórico, where its row always is',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..notifications = [
        AppNotification(
          id: 1,
          recipientProfileId: ana.id,
          type: 'swap_approved',
          title: 'Troca aprovada! ✅',
          message: 'Bruno Lima aceitou ficar com a criança no dia 31/08/2026.',
          createdAt: DateTime.now().toIso8601String(),
        ),
      ];
    final badge = NotificationBadge(ds);

    await tester.pumpWidget(notifApp(ds, badge,
        landing: NotificationLanding.history, landingNonce: '1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('aceitou ficar com a criança'), findsOneWidget,
        reason: 'the tapped notice must be on screen, not one tab away');
  });

  testWidgets('a request awaiting me lands on Para você', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..pendingForMe = [swapReq(10, dayOfMonth(today.day))];
    final badge = NotificationBadge(ds);

    await tester.pumpWidget(notifApp(ds, badge,
        landing: NotificationLanding.incoming, landingNonce: '2'));
    await tester.pumpAndSettle();

    expect(find.text(pt[K.notifBtnApprove]), findsOneWidget);
  });

  testWidgets('a SECOND tap re-applies the tab', (tester) async {
    // The screen lives in a shell branch, so its State survives the second
    // navigation. Without the nonce, someone who taps a notice, browses to
    // another tab, then taps a second notice of the same kind would stay put.
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..pendingForMe = [swapReq(10, dayOfMonth(today.day))]
      ..notifications = [
        AppNotification(
          id: 7,
          recipientProfileId: ana.id,
          type: 'swap_approved',
          title: 'Troca aprovada! ✅',
          message: 'Bruno Lima aceitou ficar com a criança no dia 31/08/2026.',
          createdAt: DateTime.now().toIso8601String(),
        ),
      ];
    final badge = NotificationBadge(ds);

    await tester.pumpWidget(notifApp(ds, badge,
        landing: NotificationLanding.history, landingNonce: '7'));
    await tester.pumpAndSettle();

    // The person wanders back to the incoming tab by hand.
    // The label carries its count once something is pending — "Para você (1)".
    await tester.tap(find.text('${pt[K.notifTabIncoming]} (1)'));
    await tester.pumpAndSettle();
    expect(find.text(pt[K.notifBtnApprove]), findsOneWidget);

    // A second receipt arrives and is tapped: same landing, new notification.
    await tester.pumpWidget(notifApp(ds, badge,
        landing: NotificationLanding.history, landingNonce: '8'));
    await tester.pumpAndSettle();

    expect(find.textContaining('aceitou ficar com a criança'), findsOneWidget);
  });
}
