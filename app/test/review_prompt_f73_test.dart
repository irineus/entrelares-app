// F-73 — the Play review request. The floors themselves are core's
// (`review_prompt_rules_test.dart`); these pin what the app adds: the moment
// comes from the Notificações list (an unread approval addressed to ME), the
// service reads the keys and the device's last request, marks the window
// before asking, counts the request, and outside the store build does
// nothing at all.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/screens/notifications_screen.dart';
import 'package:entrelares_app/services/connectivity_status.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/services/review_prompt_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource, bruno;

const ana = Member(id: 1, fullName: 'Ana Souza', userId: 'u1', colorSlot: 1);
const vera = Member(
    id: 1, fullName: 'Vera', userId: 'u1', membershipType: 'viewer');

final now = DateTime(2026, 9, 28, 12);

class FakeReviewer implements InAppReviewer {
  bool available = true;
  int requests = 0;
  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<void> requestReview() async => requests++;
}

class MemoryPrefs implements ReviewPromptPrefs {
  @override
  DateTime? lastRequestedAt;
  @override
  Future<void> markRequested(DateTime at) async => lastRequestedAt = at;
}

({ReviewPromptService service, FakeReviewer reviewer, MemoryPrefs prefs})
    build({
  List<Member> members = const [ana, bruno],
  Map<String, String> settings = const {},
  bool store = true,
  bool offline = false,
  DateTime? created,
  DateTime? last,
}) {
  final ds = FakeCustodyDataSource(members: members, days: const [])
    ..publicSettings = settings;
  final connectivity = ConnectivityStatus();
  if (offline) connectivity.lostServer();
  final reviewer = FakeReviewer();
  final prefs = MemoryPrefs()..lastRequestedAt = last;
  return (
    service: ReviewPromptService(ds,
        reviewer: reviewer,
        prefs: prefs,
        connectivity: connectivity,
        isStoreBuild: store,
        accountCreatedAt: () =>
            created ?? now.subtract(const Duration(days: 60)),
        now: () => now),
    reviewer: reviewer,
    prefs: prefs,
  );
}

void main() {
  group('the service', () {
    test('asks once, marks the window first, and the window then holds',
        () async {
      final b = build();
      expect(await b.service.approvalSeen(), isTrue);
      expect(b.reviewer.requests, 1);
      expect(b.prefs.lastRequestedAt, now);
      // The same moment again (a second approval that day): the interval.
      expect(await b.service.approvalSeen(), isFalse);
      expect(b.reviewer.requests, 1);
    });

    test('outside the store build nothing is even asked', () async {
      final b = build(store: false);
      expect(await b.service.approvalSeen(), isFalse);
      expect(b.reviewer.requests, 0);
    });

    test('the key switches it off', () async {
      final b = build(settings: const {'review_prompt.enabled': 'false'});
      expect(await b.service.approvalSeen(), isFalse);
      expect(b.reviewer.requests, 0);
    });

    test('the keys move the floors', () async {
      final young = build(
          settings: const {'review_prompt.min_account_days': '90'});
      expect(await young.service.approvalSeen(), isFalse);
      final recent = build(
          settings: const {'review_prompt.interval_days': '30'},
          last: now.subtract(const Duration(days: 31)));
      expect(await recent.service.approvalSeen(), isTrue);
    });

    test('never a viewer, never offline', () async {
      expect(await build(members: const [vera]).service.approvalSeen(),
          isFalse);
      expect(await build(offline: true).service.approvalSeen(), isFalse);
    });

    test('Play saying the API is unavailable spends nothing', () async {
      final b = build();
      b.reviewer.available = false;
      expect(await b.service.approvalSeen(), isFalse);
      expect(b.prefs.lastRequestedAt, isNull);
    });
  });

  group('the moment, on the Notificações list', () {
    Future<int> seen(WidgetTester tester, List<AppNotification> rows) async {
      final ds = FakeCustodyDataSource(members: const [ana, bruno], days: [])
        ..notifications = rows;
      var calls = 0;
      await tester.pumpWidget(AppL10n(
        l: Localization(AppLanguage.ptBr),
        setLanguage: (_) async {},
        child: MaterialApp(
          home: NotificationsScreen(
              dataSource: ds,
              badge: NotificationBadge(ds),
              onApprovalSeen: () => calls++),
        ),
      ));
      await tester.pumpAndSettle();
      return calls;
    }

    AppNotification row(String type, {int to = 1, bool read = false}) =>
        AppNotification(
            id: 9,
            recipientProfileId: to,
            type: type,
            title: 'Troca aprovada!',
            message: 'x',
            isRead: read);

    testWidgets('an unread approval of MY request is the moment',
        (tester) async {
      expect(await seen(tester, [row('swap_approved')]), 1);
    });

    testWidgets('read already, auto-approved or someone else\'s is not',
        (tester) async {
      expect(await seen(tester, [row('swap_approved', read: true)]), 0);
      expect(await seen(tester, [row('auto_approved')]), 0);
      expect(await seen(tester, [row('swap_approved_self')]), 0);
      expect(await seen(tester, [row('swap_approved', to: 2)]), 0);
    });
  });
}
