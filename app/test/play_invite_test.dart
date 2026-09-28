// F-72 — the invitation to install the Play app, on the side a VM test can
// reach: the strip the shell paints. The decision is `PlayInstallRules`
// (core, with its own suite); what the browser answers is measured on a
// device, and the four sources it depends on are pinned in `web_channel_test`.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';
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
  Widget shellApp({
    ValueListenable<PlayInviteBanner?>? invite,
    AppLanguage language = AppLanguage.ptBr,
  }) {
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
              playInvite: invite,
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

  PlayInviteBanner banner({VoidCallback? onOpen, VoidCallback? onDismiss}) =>
      PlayInviteBanner(onOpen: onOpen ?? () {}, onDismiss: onDismiss ?? () {});

  testWidgets('there is none unless the shell is given one', (tester) async {
    await tester.pumpWidget(shellApp(invite: ValueNotifier(null)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('play-invite-strip')), findsNothing);
    expect(find.text(pt[KApp.playInviteOpen]), findsNothing);
  });

  testWidgets('it invites in the reader\'s language, above the app',
      (tester) async {
    await tester.pumpWidget(shellApp(invite: ValueNotifier(banner())));
    await tester.pumpAndSettle();

    expect(find.text(pt[KApp.playInviteBanner]), findsOneWidget);
    expect(find.text(pt[KApp.playInviteOpen]), findsOneWidget);
    expect(find.text('CALENDARIO'), findsOneWidget);

    await tester.pumpWidget(shellApp(
        language: AppLanguage.en, invite: ValueNotifier(banner())));
    await tester.pumpAndSettle();
    expect(find.text(en[KApp.playInviteBanner]), findsOneWidget);
  });

  testWidgets('both of its actions answer', (tester) async {
    var opened = 0;
    var dismissed = 0;
    await tester.pumpWidget(shellApp(
        invite: ValueNotifier(banner(
            onOpen: () => opened++, onDismiss: () => dismissed++))));
    await tester.pumpAndSettle();

    await tester.tap(find.text(pt[KApp.playInviteOpen]));
    await tester.pumpAndSettle();
    expect(opened, 1);

    await tester.tap(find.byTooltip(pt[KApp.playInviteDismiss]));
    await tester.pumpAndSettle();
    expect(dismissed, 1);
  });

  testWidgets('an answer that arrives AFTER the shell mounted still paints',
      (tester) async {
    // T-65's device lesson, for the invitation: the browser answers after
    // the shell is on screen, and go_router never re-runs the route builder.
    final invite = ValueNotifier<PlayInviteBanner?>(null);
    await tester.pumpWidget(shellApp(invite: invite));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('play-invite-strip')), findsNothing);

    invite.value = banner();
    await tester.pump();
    expect(find.byKey(const Key('play-invite-strip')), findsOneWidget);

    invite.value = null;
    await tester.pump();
    expect(find.byKey(const Key('play-invite-strip')), findsNothing);
  });

  test('the listing is the production package\'s — a dev build never invites',
      () {
    expect(PlayInstallRules.listingUri(Env.prod.androidPackage)
        .queryParameters['id'], 'com.entrelares.app');
  });
}
