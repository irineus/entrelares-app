// T-18 — what the reader SEES when the network goes: the shell's strip, and a
// calendar that keeps the plan it already had.
//
// The transport and the session gate are proven on the real stack in
// `offline_transport_test.dart`. Here the data source is the shared fake, and
// that is legitimate for one reason worth writing down (the 01/09/2026 trap):
// the fake reimplements nothing under test. It only THROWS the real exception
// class the real client throws, and every decision — keep the month, which
// sentence, when to reload — is the screen's own code.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/screens/home_shell.dart';
import 'package:entrelares_app/services/account_identity.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/connectivity_status.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'calendar_slice_test.dart'
    show FakeCustodyDataSource, ana, bruno, dayOfMonth, row;

final pt = Localization(AppLanguage.ptBr);
final en = Localization(AppLanguage.en);

/// The class `package:http` throws when the socket fails — the same shape the
/// transport test reads off a refused port.
final noNetwork = http.ClientException(
    'Connection refused', Uri.parse('https://x.supabase.co/rest/v1/profiles'));

void main() {
  group('the strip', () {
    Widget shellApp(ValueListenable<ConnectivitySnapshot> connectivity,
        {AppLanguage language = AppLanguage.ptBr}) {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => HomeShell(
                shell: shell,
                adminMode: AdminMode(),
                identity: AccountIdentity(),
                onSignOut: () async {},
                onOpenProfile: () {},
                connectivity: connectivity,
                badge: NotificationBadge(
                    FakeCustodyDataSource(members: const [], days: []))),
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/',
                    builder: (_, _) =>
                        const Scaffold(body: Text('CALENDARIO'))),
              ]),
            ],
          ),
        ],
      );
      return AppL10n(
        l: Localization(language),
        setLanguage: (_) async {},
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('online, there is none — even with the socket down',
        (tester) async {
      // Two states, by decision: reads that succeed mean what is on screen is
      // current, and a strip over current data teaches the reader to ignore it.
      final status = ConnectivityStatus()..loadedData(DateTime.now());
      await tester.pumpWidget(shellApp(status));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('offline-strip')), findsNothing);
    });

    testWidgets('offline, it says how OLD the plan on screen is',
        (tester) async {
      final asOf = DateTime.now().subtract(const Duration(minutes: 3));
      final status = ConnectivityStatus()
        ..loadedData(asOf)
        ..lostServer();
      await tester.pumpWidget(shellApp(status));
      await tester.pumpAndSettle();

      expect(
          find.text(offlineStripText(pt, dataAsOf: asOf, now: DateTime.now())),
          findsOneWidget);
      expect(find.textContaining(pt.formatTime(asOf)), findsOneWidget);
      // It sits above the app, never over it.
      expect(find.text('CALENDARIO'), findsOneWidget);
    });

    testWidgets('it follows the reader\'s language (U-13/U-24)', (tester) async {
      final asOf = DateTime.now();
      final status = ConnectivityStatus()
        ..loadedData(asOf)
        ..lostServer();
      await tester.pumpWidget(shellApp(status, language: AppLanguage.en));
      await tester.pumpAndSettle();

      expect(
          find.text(offlineStripText(en, dataAsOf: asOf, now: DateTime.now())),
          findsOneWidget);
    });

    testWidgets('a loss AFTER the shell mounted paints, and a reply removes it',
        (tester) async {
      // The T-65 trap in this item's shape: the network drops long after the
      // go_router builder ran, so only a listenable can reach the shell.
      final status = ConnectivityStatus()..loadedData(DateTime.now());
      await tester.pumpWidget(shellApp(status));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offline-strip')), findsNothing);

      status.lostServer();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offline-strip')), findsOneWidget);

      status.reachedServer();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offline-strip')), findsNothing);
    });

    testWidgets('the status-bar inset is taken ONCE, by the strip',
        (tester) async {
      // T-18 device measurement (14/09/2026): the strip wrapped itself in a
      // SafeArea and the tab below STILL received the status bar as top
      // padding, so its app bar pushed down a second time — a band of empty
      // chrome under the strip, on a real phone and in no test.
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 40);
      addTearDown(tester.view.reset);
      double? tabTop;
      final status = ConnectivityStatus()..loadedData(DateTime.now());
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) => HomeShell(
                shell: shell,
                adminMode: AdminMode(),
                identity: AccountIdentity(),
                onSignOut: () async {},
                onOpenProfile: () {},
                connectivity: status,
                badge: NotificationBadge(
                    FakeCustodyDataSource(members: const [], days: []))),
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/',
                    builder: (_, _) => Scaffold(body: Builder(builder: (c) {
                          tabTop = MediaQuery.paddingOf(c).top;
                          return const Text('CALENDARIO');
                        }))),
              ]),
            ],
          ),
        ],
      );
      await tester.pumpWidget(AppL10n(
          l: pt,
          setLanguage: (_) async {},
          child: MaterialApp.router(routerConfig: router)));
      await tester.pumpAndSettle();
      expect(tabTop, 40, reason: 'no strip: the tab owns the status bar');

      status.lostServer();
      await tester.pumpAndSettle();
      expect(tabTop, 0, reason: 'the strip took the inset; the tab must not');
      final strip = tester.getRect(find.byKey(const Key('offline-strip')));
      expect(strip.top, 0);
      expect(strip.height, greaterThan(40));

      status.reachedServer();
      await tester.pumpAndSettle();
      expect(tabTop, 40);
    });

    testWidgets('nothing loaded yet names no time', (tester) async {
      final status = ConnectivityStatus()..lostServer();
      await tester.pumpWidget(shellApp(status));
      await tester.pumpAndSettle();

      expect(find.text(pt[KApp.offlineStripNoData]), findsOneWidget);
    });
  });

  group('the calendar with no network', () {
    Widget calendarApp(FakeCustodyDataSource ds, ConnectivityStatus status) =>
        AppL10n(
          l: pt,
          setLanguage: (_) async {},
          child: MaterialApp(
            home: CalendarScreen(
                dataSource: ds, adminMode: AdminMode(), connectivity: status),
          ),
        );

    FakeCustodyDataSource family() => FakeCustodyDataSource(
          members: [ana, bruno],
          days: [row(1, dayOfMonth(10), 1), row(2, dayOfMonth(11), 2)],
        );

    testWidgets('a load dates what it read, for the strip to name',
        (tester) async {
      final status = ConnectivityStatus();
      final before = DateTime.now();
      await tester.pumpWidget(calendarApp(family(), status));
      await tester.pumpAndSettle();

      expect(status.value.dataAsOf, isNotNull);
      expect(status.value.dataAsOf!.isBefore(before), isFalse);
    });

    testWidgets('the poll failing offline KEEPS the month on screen',
        (tester) async {
      // The defect: the F-23 poll's first failure replaced a good month with
      // an error banner — the calendar went blank at the school door.
      final ds = family();
      final status = ConnectivityStatus();
      await tester.pumpWidget(calendarApp(ds, status));
      await tester.pumpAndSettle();
      expect(find.text('A'), findsWidgets);
      final asOf = status.value.dataAsOf;

      ds.throwOnMembers = noNetwork;
      status.lostServer();
      ds.realtimeCallback!(); // the silent reload a change or the poll fires
      await tester.pumpAndSettle();

      expect(find.text('A'), findsWidgets);
      expect(find.text('B'), findsWidgets);
      expect(find.textContaining(pt[KApp.errCalendarLoad]), findsNothing);
      expect(find.textContaining(pt[KApp.offlineMonthNotLoaded]), findsNothing);
      // The age is still the last REAL read — a failed load dates nothing.
      expect(status.value.dataAsOf, asOf);
    });

    testWidgets('the server refusing is still an error, not "offline"',
        (tester) async {
      // Only the transport keeps the old month. A server that answers with a
      // failure has told us the month is NOT what is on screen.
      final ds = family();
      await tester.pumpWidget(calendarApp(ds, ConnectivityStatus()));
      await tester.pumpAndSettle();

      ds.throwOnMembers = Exception(
          'PostgrestException(message: boom, code: XX000, details: null, hint: null)');
      ds.realtimeCallback!();
      await tester.pumpAndSettle();

      expect(find.textContaining(pt[KApp.errCalendarLoad]), findsOneWidget);
    });

    testWidgets('a month never read on this device says so, with a retry',
        (tester) async {
      final ds = family()..throwOnMembers = noNetwork;
      await tester.pumpWidget(
          calendarApp(ds, ConnectivityStatus()..lostServer()));
      await tester.pumpAndSettle();

      expect(find.textContaining(pt[KApp.offlineMonthNotLoaded]), findsOneWidget);
      expect(find.text(pt[K.layoutErrorReload]), findsOneWidget);
      expect(find.textContaining(pt[KApp.errCalendarLoad]), findsNothing);
    });

    testWidgets('the server answering again reloads the plan at once',
        (tester) async {
      final ds = family()..throwOnMembers = noNetwork;
      final status = ConnectivityStatus()..lostServer();
      await tester.pumpWidget(calendarApp(ds, status));
      await tester.pumpAndSettle();
      expect(find.textContaining(pt[KApp.offlineMonthNotLoaded]), findsOneWidget);

      ds.throwOnMembers = null;
      final fetchesBefore = ds.monthFetches;
      // Any response anywhere in the app — the badge, another tab.
      status.reachedServer();
      await tester.pumpAndSettle();

      expect(ds.monthFetches, greaterThan(fetchesBefore));
      expect(find.textContaining(pt[KApp.offlineMonthNotLoaded]), findsNothing);
      expect(find.text('A'), findsWidgets);
    });
  });
}
