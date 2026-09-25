// The owner's validation of phase 6 (25/09/2026), calendar half.
//
// 1. A day cited in the Conversa opens what a TAP on its cell opens — the
//    approval panel when a request is pending — and only from a month read
//    AFTER the citation was followed: the request is usually minutes old, and
//    the month on screen was read before it (the day opened editable).
// 2. A settings read that fails at start-up is retried by the next load: it
//    used to run once, from initState, and a cold start's first read racing
//    the session refresh hid every phase-6 module for the whole session.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/day_agenda.dart';

import 'calendar_slice_test.dart';

final l = Localization(AppLanguage.ptBr);

SwapRequest pendingOn(DateTime date) => SwapRequest.fromJson({
      'id': 10,
      'schedule_date': CareSchedule.isoDate(date),
      'requesting_profile_id': 2,
      'target_profile_id': 1,
      'proposed_actual_parent_id': 1,
      'status': 'pending',
    });

Widget calendar(FakeCustodyDataSource ds, ValueNotifier<DateTime?> dayRequest) =>
    AppL10n(
      l: l,
      setLanguage: (_) async {},
      child: MaterialApp(
        home: CalendarScreen(
          dataSource: ds,
          adminMode: AdminMode(),
          dayRequest: dayRequest,
        ),
      ),
    );

/// The first settings read fails, as a cold start's can; the rest answer.
class _SettingsFailOnce extends FakeCustodyDataSource {
  _SettingsFailOnce() : super(members: [ana, bruno], days: []);
  int settingsReads = 0;

  @override
  Future<Map<String, String>> fetchPublicSettings() async {
    settingsReads++;
    if (settingsReads == 1) throw Exception('Failed host lookup');
    return const {'feature.child_agenda': 'true'};
  }
}

/// The settings read keeps failing for a while — a cold start whose session
/// is still being refreshed — and nothing else happens on screen.
class _SettingsLate extends FakeCustodyDataSource {
  _SettingsLate(this.failures) : super(members: [ana, bruno], days: []);
  final int failures;
  int settingsReads = 0;

  @override
  Future<Map<String, String>> fetchPublicSettings() async {
    settingsReads++;
    if (settingsReads <= failures) return const {};
    return const {'feature.child_agenda': 'true'};
  }
}

void main() {
  testWidgets(
      'a cited day with a request that arrived after the month was read opens '
      'the approval panel, as a tap would', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    final request = ValueNotifier<DateTime?>(null);
    addTearDown(request.dispose);
    await tester.pumpWidget(calendar(ds, request));
    await tester.pumpAndSettle();

    // The swap was asked for in the Conversa after this month was on screen.
    ds.frozenRequests = [pendingOn(dayOfMonth(day))];
    request.value = dayOfMonth(day);
    await tester.pumpAndSettle();

    expect(find.textContaining(l[K.frozenSwapTitle]), findsOneWidget);
    expect(find.text(l[K.frozenApprove]), findsOneWidget);
    expect(find.text(l[K.commonSave]), findsNothing);
  });

  testWidgets('a cited day without a request opens the day, as a tap would',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    final request = ValueNotifier<DateTime?>(null);
    addTearDown(request.dispose);
    await tester.pumpWidget(calendar(ds, request));
    await tester.pumpAndSettle();

    request.value = dayOfMonth(day);
    await tester.pumpAndSettle();

    expect(find.textContaining(l[K.frozenSwapTitle]), findsNothing);
    expect(find.text(l[K.commonSave]), findsOneWidget);
  });

  testWidgets('a settings read that failed at start is retried by the next '
      'load, and the agenda appears', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = _SettingsFailOnce();
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    expect(ds.settingsReads, greaterThanOrEqualTo(1));

    // Any load retries: here, the app coming back to the foreground.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(ds.settingsReads, greaterThan(1));

    await openDay(tester, day);
    expect(find.byType(DayAgendaSection), findsOneWidget);
  });

  testWidgets('a settings read that keeps failing retries on its own clock, '
      'with no load and no resume to trigger it', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = _SettingsLate(3);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    final first = ds.settingsReads;

    // 2 s, 5 s, 10 s: the fourth read lands.
    for (final s in [2, 5, 10]) {
      await tester.pump(Duration(seconds: s));
      await tester.pumpAndSettle();
    }
    expect(ds.settingsReads, greaterThan(first));
    expect(ds.settingsReads, greaterThanOrEqualTo(4));

    await openDay(tester, day);
    expect(find.byType(DayAgendaSection), findsOneWidget);
  });
}
