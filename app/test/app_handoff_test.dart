// T-65 — the web→app handoff, on the two sides a VM test can reach: the
// banner the shell paints, and the address the core rule builds for it.
//
// What is NOT here, and cannot be: whether the browser answers
// `getInstalledRelatedApps()` at all. That is measured on a device, and the
// three sources it depends on are pinned in `web_channel_test`.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:entrelares_app/env.dart';
import 'package:entrelares_app/screens/home_shell.dart';
import 'package:entrelares_app/services/account_identity.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'calendar_slice_test.dart' show FakeCustodyDataSource;

final pt = Localization(AppLanguage.ptBr);
final en = Localization(AppLanguage.en);

void main() {
  Widget shellApp(
      {AppHandoffBanner? handoff, AppLanguage language = AppLanguage.ptBr}) {
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
              appHandoff: handoff,
              badge: NotificationBadge(
                  FakeCustodyDataSource(members: const [], days: []))),
          branches: [
            StatefulShellBranch(routes: [
              GoRoute(
                  path: '/',
                  builder: (_, _) => const Scaffold(body: Text('CALENDARIO'))),
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

  group('the banner', () {
    testWidgets('there is none unless the shell is given one', (tester) async {
      // The overwhelmingly common case: every native build, and every browser
      // that did not confirm the app is on this device.
      await tester.pumpWidget(shellApp());
      await tester.pumpAndSettle();

      expect(find.text(pt[KApp.handoffBanner]), findsNothing);
      expect(find.text(pt[KApp.handoffOpen]), findsNothing);
    });

    testWidgets('it offers the crossing in the reader\'s language',
        (tester) async {
      await tester.pumpWidget(shellApp(
          handoff: AppHandoffBanner(onOpen: () {}, onDismiss: () {})));
      await tester.pumpAndSettle();

      expect(find.text(pt[KApp.handoffBanner]), findsOneWidget);
      expect(find.text(pt[KApp.handoffOpen]), findsOneWidget);

      await tester.pumpWidget(shellApp(
          language: AppLanguage.en,
          handoff: AppHandoffBanner(onOpen: () {}, onDismiss: () {})));
      await tester.pumpAndSettle();

      expect(find.text(en[KApp.handoffBanner]), findsOneWidget);
    });

    testWidgets('it never covers the app it sits above', (tester) async {
      // A banner that pushed the calendar off the screen would be a worse
      // defect than the one this item fixes.
      await tester.pumpWidget(shellApp(
          handoff: AppHandoffBanner(onOpen: () {}, onDismiss: () {})));
      await tester.pumpAndSettle();

      expect(find.text('CALENDARIO'), findsOneWidget);
    });

    testWidgets('both of its actions answer', (tester) async {
      var opened = 0;
      var dismissed = 0;
      await tester.pumpWidget(shellApp(
          handoff: AppHandoffBanner(
              onOpen: () => opened++, onDismiss: () => dismissed++)));
      await tester.pumpAndSettle();

      await tester.tap(find.text(pt[KApp.handoffOpen]));
      await tester.pumpAndSettle();
      expect(opened, 1);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(dismissed, 1);
    });
  });

  group('the address the banner opens', () {
    test('it is built from the running flavor, not from a literal', () {
      // The web build of one environment must never wake the app of the
      // other, and the scheme is the only thing standing between them.
      final uri = ChannelHandoffRules.handoffUri(
        androidPackage: Env.prod.androidPackage,
        location: '/notifications',
      );
      expect(uri.toString(),
          '${Env.prod.androidPackage}://open/notifications');
      expect(Env.dev.androidPackage, isNot(Env.prod.androidPackage));
    });
  });
}
