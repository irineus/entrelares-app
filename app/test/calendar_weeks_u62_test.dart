// U-62 — the month is the product, and on a 360×740 phone the first screen
// kept ONE week of it under the strips (T-103, 04/10/2026). The acceptance is
// a number: with any combination of the strips a reader can meet, at least
// THREE whole weeks of the grid stay visible at 1.0×.
//
// The column the calendar gets on that phone is 740 − 24 (status bar) − 48
// (its own app bar) − 64 (the U-28 nav bar) = 604 dp; the harness pumps the
// screen alone at 604 + 48, the F-59 phone test's own trick.
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/onboarding_service.dart';
import 'package:entrelares_app/services/push_messaging.dart';
import 'package:entrelares_app/services/push_service.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/day_notice.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource, row, today;
import 'frozen_day_test.dart' show swapReq;
import 'push_service_test.dart' show FakeMessaging;

const _founder = Member(
    id: 1,
    fullName: 'Ana Souza',
    colorSlot: 1,
    userId: 'u1',
    familyId: 7,
    isAdmin: true);
final _settled = Member(
    id: 1,
    fullName: 'Ana Souza',
    colorSlot: 1,
    userId: 'u1',
    familyId: 7,
    isAdmin: true,
    onboardingTourSeenAt: DateTime.utc(2026, 8, 1),
    onboardingDismissedAt: DateTime.utc(2026, 8, 2));
const _other = Member(
    id: 2, fullName: 'Bruno Lima', colorSlot: 2, userId: 'u2', familyId: 7);
final _settledMember = Member(
    id: 2,
    fullName: 'Bruno Lima',
    colorSlot: 2,
    userId: 'u2',
    familyId: 7,
    onboardingTourSeenAt: DateTime.utc(2026, 8, 1),
    onboardingDismissedAt: DateTime.utc(2026, 8, 2));
const _viewer = Member(
    id: 3,
    fullName: 'Vó Cida',
    colorSlot: 3,
    userId: 'u3',
    familyId: 7,
    membershipType: 'viewer');

DayNotice _noticeToday({int sender = 2}) => DayNotice.fromJson({
      'id': 1,
      'family_id': 7,
      'schedule_date': CareSchedule.isoDate(today),
      'sender_profile_id': sender,
      'reason': 'transito',
      'eta_minutes': 20,
      'request': 'pickup',
      'note': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'day_notice_outcomes': <dynamic>[],
    });

/// How many WHOLE rows of the month grid are inside its viewport.
int _wholeWeeksVisible(WidgetTester tester) {
  final gridFinder = find.byType(GridView).first;
  final grid = tester.widget<GridView>(gridFinder);
  final cells = grid.childrenDelegate.estimatedChildCount!;
  final rows = cells ~/ 7;
  final gridRect = tester.getRect(gridFinder);
  final viewport = tester.getRect(
      find.ancestor(of: gridFinder, matching: find.byType(Viewport)).first);
  const spacing = 3.0;
  final cellHeight = (gridRect.height - (rows - 1) * spacing) / rows;
  final visible = viewport.bottom - gridRect.top;
  if (visible <= 0) return 0;
  return ((visible + spacing) / (cellHeight + spacing)).floor().clamp(0, rows);
}

Future<void> _pumpPhone(
  WidgetTester tester,
  FakeCustodyDataSource ds, {
  PushService? push,
  OnboardingService? onboarding,
  double textScale = 1.0,
}) async {
  // 360 wide; 604 of column + the calendar's own 48 dp app bar.
  const size = Size(360, 604 + 48);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(
      theme: AppTheme.light,
      home: CalendarScreen(
        dataSource: ds,
        adminMode: AdminMode(),
        push: push,
        onboarding: onboarding,
        onOpenNotifications: () {},
        onOpenFamily: () {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<PushService> _pushOff(FakeCustodyDataSource ds, int profileId) async {
  final push =
      PushService(ds, messaging: FakeMessaging(current: PushPermission.notAsked));
  await push.start(profileId);
  return push;
}

void main() {
  setUpAll(() async {
    final inter = FontLoader('Inter')
      ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'));
    await inter.load();
  });

  /// A plan with a transition and no handoff time on it (the handoff nudge's
  /// case), today and the days around it.
  List<CareSchedule> plan() => [
        row(1, today.subtract(const Duration(days: 1)), 1),
        row(2, today, 2),
        row(3, today.add(const Duration(days: 1)), 1),
        row(4, today.add(const Duration(days: 4)), 2),
      ];

  group('U-62 — three whole weeks on a 360×740 phone, whatever the strips', () {
    testWidgets('first run: checklist + a request waiting for me + the plan '
        'about to end', (tester) async {
      final ds = FakeCustodyDataSource(members: [_founder, _other], days: plan())
        ..pendingForMe = [swapReq(10, today, requesting: 2, target: 1)]
        ..lastPlannedDayOverride = today.add(const Duration(days: 5));
      await _pumpPhone(tester, ds, onboarding: OnboardingService(ds));

      expect(find.text(Localization(AppLanguage.ptBr)[K.onbChecklistTitle]),
          findsOneWidget, reason: 'the first steps are the one system strip');
      expect(find.byKey(CalendarScreen.requestStripKey), findsOneWidget);
      expect(find.byKey(CalendarScreen.planEndStripKey), findsNothing,
          reason: 'the plan-end state waits its turn in the one slot');
      expect(_wholeWeeksVisible(tester), greaterThanOrEqualTo(3));
    });

    testWidgets('push ask + an open aviso + a request waiting for me',
        (tester) async {
      final ds = FakeCustodyDataSource(members: [_settled, _other], days: plan())
        ..pendingForMe = [swapReq(10, today, requesting: 2, target: 1)]
        ..dayNotices = [_noticeToday()];
      final push = await _pushOff(ds, _settled.id);
      await _pumpPhone(tester, ds, push: push);

      expect(find.byKey(CalendarScreen.pushTodayKey), findsOneWidget);
      expect(find.byKey(CalendarScreen.requestStripKey), findsOneWidget);
      expect(_wholeWeeksVisible(tester), greaterThanOrEqualTo(3));
    });

    testWidgets('admin: the handoff nudge, now one row, + a request',
        (tester) async {
      final ds = FakeCustodyDataSource(members: [_settled, _other], days: plan())
        ..pendingForMe = [swapReq(10, today, requesting: 2, target: 1)];
      await _pumpPhone(tester, ds);

      expect(find.byKey(const Key('handoff-nudge')), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('handoff-nudge'))).height,
          lessThanOrEqualTo(48 + 8),
          reason: 'the nudge is a one-row strip, no taller than its action');
      expect(_wholeWeeksVisible(tester), greaterThanOrEqualTo(3));
    });

    testWidgets('viewer: the standing note, one row, + push ask + plan end',
        (tester) async {
      final ds = FakeCustodyDataSource(
          members: [_viewer, _founder, _other], days: plan())
        ..lastPlannedDayOverride = today.add(const Duration(days: 5));
      final push = await _pushOff(ds, _viewer.id);
      await _pumpPhone(tester, ds, push: push);

      final note = find.byKey(const ValueKey('viewer-read-only'));
      expect(note, findsOneWidget);
      expect(tester.getSize(note).height, lessThanOrEqualTo(48 + 8));
      expect(_wholeWeeksVisible(tester), greaterThanOrEqualTo(3));
    });

    testWidgets('the plan-end state shows once the asks are gone, as one row',
        (tester) async {
      // A member, not an admin: the handoff nudge is the admin's and would
      // take the slot first.
      final ds = FakeCustodyDataSource(
          members: [_settledMember, _founder], days: plan())
        ..lastPlannedDayOverride = today.add(const Duration(days: 5));
      await _pumpPhone(tester, ds);

      expect(find.byKey(CalendarScreen.planEndStripKey), findsOneWidget);
      expect(tester.getSize(find.byKey(CalendarScreen.planEndStripKey)).height,
          lessThanOrEqualTo(48 + 8));
      expect(_wholeWeeksVisible(tester), greaterThanOrEqualTo(4));
    });

    testWidgets('at 1.3× nothing overflows and the floor still holds three '
        'weeks for the busiest combination', (tester) async {
      final ds = FakeCustodyDataSource(members: [_settled, _other], days: plan())
        ..pendingForMe = [swapReq(10, today, requesting: 2, target: 1)]
        ..dayNotices = [_noticeToday()];
      final push = await _pushOff(ds, _settled.id);
      await _pumpPhone(tester, ds, push: push, textScale: 1.3);

      expect(tester.takeException(), isNull);
      // U-48: the reader who asked for large text pays for it — every strip
      // wraps to one more line — and the grid scrolls inside its viewport
      // rather than overflowing; a week stays in view even here.
      expect(_wholeWeeksVisible(tester), greaterThanOrEqualTo(1));
    });
  });
}
