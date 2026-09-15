// T-18 PR 2 — the calendar serving the device's copy, and refusing to write
// with no connection.
//
// The cache is the REAL `OfflineCache`; only its bytes sit in memory (the file
// store is proven on disk in `offline_cache_test.dart`). The data source is the shared fake, which only throws the real
// `package:http` exception class — every decision under test (when to serve
// the copy, what fills the grid, which actions disappear) is the screen's own.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/connectivity_status.dart';
import 'package:entrelares_app/services/offline_cache.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'calendar_slice_test.dart'
    show FakeCustodyDataSource, ana, bruno, dayOfMonth, futureDay, row, today;
import 'frozen_day_test.dart' show swapReq;

final pt = Localization(AppLanguage.ptBr);

final noNetwork = http.ClientException(
    'Connection refused', Uri.parse('https://x.supabase.co/rest/v1/profiles'));

class _MemoryStore implements OfflineCacheStore {
  final Map<String, String> files = {};

  @override
  Future<String?> read(String account) async => files[account];

  @override
  Future<void> write(String account, String contents) async =>
      files[account] = contents;

  @override
  Future<void> delete(String account) async => files.remove(account);

  @override
  Future<void> deleteAll() async => files.clear();
}

void main() {
  late _MemoryStore store;

  setUp(() => store = _MemoryStore());

  OfflineCache cacheFor(String uid) =>
      OfflineCache(store, userId: () => uid, enabled: true);

  Widget calendarApp(FakeCustodyDataSource ds, ConnectivityStatus status,
          OfflineCache cache) =>
      AppL10n(
        l: pt,
        setLanguage: (_) async {},
        child: MaterialApp(
          home: CalendarScreen(
              dataSource: ds,
              adminMode: AdminMode(),
              connectivity: status,
              offlineCache: cache),
        ),
      );

  /// A copy of THIS month as a previous, online session would have left it.
  Future<DateTime> seedCopy(OfflineCache cache,
      {DateTime? month, int ownerOfDay10 = 2}) async {
    final savedAt = DateTime.now().subtract(const Duration(hours: 2));
    final m = month ?? DateTime(today.year, today.month, 1);
    await cache.save(OfflineCalendarSnapshot(
      savedAt: savedAt,
      month: m,
      members: [ana, bruno],
      roles: const [],
      days: [row(1, DateTime(m.year, m.month, 10), ownerOfDay10)],
      frozen: const [],
      ownProfile: ana,
      upcoming: [row(2, today, 1)],
    ));
    return savedAt;
  }

  group('serving the copy', () {
    testWidgets('a good load of the current month leaves a copy behind',
        (tester) async {
      final cache = cacheFor('u1');
      final ds = FakeCustodyDataSource(
          members: [ana, bruno], days: [row(1, dayOfMonth(10), 1)]);
      await tester.pumpWidget(calendarApp(ds, ConnectivityStatus(), cache));
      await tester.pumpAndSettle();

      final copy = await cache.read();
      expect(copy, isNotNull);
      expect(copy!.isFor(today), isTrue);
      expect(copy.days.single.scheduleDate, dayOfMonth(10));
      expect(copy.ownProfile!.id, ana.id);
    });

    testWidgets('opening OFFLINE paints the copy, dated by the copy',
        (tester) async {
      // The school door: the session opened offline, the network never answers.
      final cache = cacheFor('u1');
      final savedAt = await seedCopy(cache);
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
        ..throwOnMembers = noNetwork;
      final status = ConnectivityStatus()..lostServer();

      await tester.pumpWidget(calendarApp(ds, status, cache));
      // A few frames — the copy is one async read away — and still long before
      // postgrest's retries would have given up.
      await tester.pump();
      await tester.pump();

      expect(find.text('B'), findsWidgets, reason: 'day 10 is Bruno\'s');
      await tester.pumpAndSettle();
      expect(find.text('B'), findsWidgets);
      expect(find.textContaining(pt[KApp.offlineMonthNotLoaded]), findsNothing);
      expect(find.textContaining(pt[KApp.errCalendarLoad]), findsNothing);
      expect(status.value.dataAsOf, savedAt);
    });

    testWidgets('online, the copy is never shown in place of the server',
        (tester) async {
      // An old plan painted as current, with no strip, is the opposite
      // mistake — the copy exists for the offline case only.
      final cache = cacheFor('u1');
      await seedCopy(cache, ownerOfDay10: 2);
      final ds = FakeCustodyDataSource(
          members: [ana, bruno], days: [row(1, dayOfMonth(10), 1)]);

      await tester.pumpWidget(calendarApp(ds, ConnectivityStatus(), cache));
      await tester.pump();
      expect(find.text('B'), findsNothing);
      await tester.pumpAndSettle();
      expect(find.text('B'), findsNothing);
    });

    testWidgets('a copy of ANOTHER month fills the today card, not the grid',
        (tester) async {
      // The turn of the month: yesterday's copy is September, today is
      // October. The card still answers "who has them today".
      final cache = cacheFor('u1');
      await seedCopy(cache,
          month: DateTime(today.year, today.month - 1, 1));
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
        ..throwOnMembers = noNetwork;

      await tester.pumpWidget(
          calendarApp(ds, ConnectivityStatus()..lostServer(), cache));
      await tester.pumpAndSettle();

      expect(find.textContaining(pt[KApp.offlineMonthNotLoaded]),
          findsOneWidget);
      expect(find.textContaining('Ana'), findsWidgets);
    });

    testWidgets('another account\'s copy is never served', (tester) async {
      await seedCopy(cacheFor('someone-else'));
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
        ..throwOnMembers = noNetwork;

      await tester.pumpWidget(
          calendarApp(ds, ConnectivityStatus()..lostServer(), cacheFor('u1')));
      await tester.pumpAndSettle();

      expect(find.text('B'), findsNothing);
      expect(find.textContaining(pt[KApp.offlineMonthNotLoaded]),
          findsOneWidget);
    });
  });

  group('no write starts offline', () {
    Future<(FakeCustodyDataSource, ConnectivityStatus)> loadedThenOffline(
        WidgetTester tester,
        {List<CareSchedule> days = const []}) async {
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: [...days]);
      final status = ConnectivityStatus();
      await tester.pumpWidget(calendarApp(ds, status, cacheFor('u1')));
      await tester.pumpAndSettle();
      status.lostServer();
      await tester.pumpAndSettle();
      return (ds, status);
    }

    testWidgets('a day opens to READ, without Salvar, and says why',
        (tester) async {
      final day = futureDay;
      if (day == null) return;
      await loadedThenOffline(tester);

      final cell = find.text('$day').last;
      await tester.ensureVisible(cell);
      await tester.pumpAndSettle();
      await tester.tap(cell);
      await tester.pumpAndSettle();

      expect(find.textContaining(pt[KApp.offlineWriteBlocked]), findsOneWidget);
      expect(find.text(pt[K.commonSave]), findsNothing);
    });

    testWidgets('online, the same day still offers Salvar', (tester) async {
      // The counter-case: the block is the connection's, not the day's.
      final day = futureDay;
      if (day == null) return;
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
      await tester.pumpWidget(
          calendarApp(ds, ConnectivityStatus(), cacheFor('u1')));
      await tester.pumpAndSettle();

      final cell = find.text('$day').last;
      await tester.ensureVisible(cell);
      await tester.pumpAndSettle();
      await tester.tap(cell);
      await tester.pumpAndSettle();

      expect(find.text(pt[K.commonSave]), findsOneWidget);
      expect(find.textContaining(pt[KApp.offlineWriteBlocked]), findsNothing);
    });

    testWidgets('a request awaiting me shows, and offers no answer',
        (tester) async {
      final day = futureDay;
      if (day == null) return;
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
        ..frozenRequests = [swapReq(10, dayOfMonth(day))];
      final status = ConnectivityStatus();
      await tester.pumpWidget(calendarApp(ds, status, cacheFor('u1')));
      await tester.pumpAndSettle();
      status.lostServer();
      await tester.pumpAndSettle();

      await tester.tap(find.text('🔔'));
      await tester.pumpAndSettle();

      expect(find.textContaining(pt[KApp.offlineWriteBlocked]), findsOneWidget);
      expect(find.text(pt[K.frozenApprove]), findsNothing);
      expect(find.text(pt[K.frozenRejectAction]), findsNothing);
    });

    testWidgets('the wizard does not open, and the snack says why',
        (tester) async {
      await loadedThenOffline(tester);

      // U-36: the wizard is an item of the ⋮ menu.
      await tester.tap(find.byTooltip(pt[K.calActionsMenu]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(pt[K.calWizard]));
      await tester.pumpAndSettle();

      expect(find.text(pt[KApp.offlineWriteBlocked]), findsOneWidget);
    });
  });
}
