// U-51 — the iPhone install hint, on the two sides a VM test can reach: the
// strip the shell paints and the sheet it opens, and the core rule that
// decides whether there is one (its own suite lives in entrelares_core).
//
// What is NOT here, and cannot be: what Safari on a real iPhone answers for
// `navigator.standalone` and `maxTouchPoints`. Nobody on the project owns an
// iPhone; the acceptance was an emulated user agent in Chrome plus these
// tests, with that caveat written on the card (owner, 15/09/2026).
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:entrelares_app/screens/home_shell.dart';
import 'package:entrelares_app/services/account_identity.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/connectivity_status.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'calendar_slice_test.dart' show FakeCustodyDataSource;

final pt = Localization(AppLanguage.ptBr);
final en = Localization(AppLanguage.en);

void main() {
  Widget shellApp({
    ValueListenable<InstallHintBanner?>? hint,
    ValueListenable<AppHandoffBanner?>? handoff,
    ConnectivityStatus? connectivity,
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
              installHint: hint,
              appHandoff: handoff,
              connectivity: connectivity,
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

  InstallHintBanner offer({VoidCallback? onOpen, VoidCallback? onDismiss}) =>
      InstallHintBanner(
          onOpen: onOpen ?? () {}, onDismiss: onDismiss ?? () {});

  final strip = find.byKey(const Key('install-hint-strip'));

  group('the strip', () {
    testWidgets('there is none unless the shell is given one', (tester) async {
      // The overwhelmingly common case: every native build, Android, desktop,
      // every browser but Safari, and an app already on the Home Screen.
      await tester.pumpWidget(shellApp(hint: ValueNotifier(null)));
      await tester.pumpAndSettle();

      expect(strip, findsNothing);
      expect(find.text(pt[KApp.installHintBanner]), findsNothing);
    });

    testWidgets('it invites in the reader\'s language', (tester) async {
      await tester.pumpWidget(shellApp(hint: ValueNotifier(offer())));
      await tester.pumpAndSettle();

      expect(strip, findsOneWidget);
      expect(find.text(pt[KApp.installHintBanner]), findsOneWidget);
      expect(find.text(pt[KApp.installHintHow]), findsOneWidget);
      expect(find.byIcon(Icons.ios_share), findsOneWidget);

      await tester.pumpWidget(
          shellApp(language: AppLanguage.en, hint: ValueNotifier(offer())));
      await tester.pumpAndSettle();

      expect(find.text(en[KApp.installHintBanner]), findsOneWidget);
      expect(find.text(en[KApp.installHintHow]), findsOneWidget);
    });

    testWidgets('it never covers the app it sits above', (tester) async {
      await tester.pumpWidget(shellApp(hint: ValueNotifier(offer())));
      await tester.pumpAndSettle();

      expect(find.text('CALENDARIO'), findsOneWidget);
    });

    testWidgets('an answer that arrives AFTER the shell mounted still paints',
        (tester) async {
      // The T-65 trap: go_router caches the pages a route builder produced,
      // so a value decided after the shell mounts has to reach it as a
      // listenable — driven here in the real order, shell first, answer
      // second, no navigation in between.
      final hint = ValueNotifier<InstallHintBanner?>(null);
      await tester.pumpWidget(shellApp(hint: hint));
      await tester.pumpAndSettle();
      expect(strip, findsNothing);

      hint.value = offer();
      await tester.pump();

      expect(strip, findsOneWidget);
      expect(find.text('CALENDARIO'), findsOneWidget);

      // And a dismissal takes it away by the same road.
      hint.value = null;
      await tester.pump();
      expect(strip, findsNothing);
    });

    testWidgets('dismissing answers once and is the only way to close it',
        (tester) async {
      var dismissed = 0;
      await tester.pumpWidget(shellApp(
          hint: ValueNotifier(offer(onDismiss: () => dismissed++))));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(dismissed, 1);
    });

    testWidgets('it takes its place below the handoff and above the offline strip',
        (tester) async {
      // Both T-65 and U-51 cannot happen in one browser (Chrome on Android
      // vs Safari on iOS), but the shell orders them all the same, and the
      // offline strip must stay the last one: the age of the plan is the
      // sentence that matters most.
      final connectivity = ConnectivityStatus();
      await tester.pumpWidget(shellApp(
          hint: ValueNotifier(offer()),
          handoff: ValueNotifier(
              AppHandoffBanner(onOpen: () {}, onDismiss: () {})),
          connectivity: connectivity));
      await tester.pumpAndSettle();
      connectivity.lostServer();
      await tester.pump();

      final handoffY = tester.getTopLeft(find.text(pt[KApp.handoffBanner])).dy;
      final hintY = tester.getTopLeft(strip).dy;
      final offlineY =
          tester.getTopLeft(find.byKey(const Key('offline-strip'))).dy;
      expect(handoffY, lessThan(hintY));
      expect(hintY, lessThan(offlineY));
      expect(offlineY, lessThan(tester.getTopLeft(find.text('CALENDARIO')).dy));
    });
  });

  group('the sheet', () {
    testWidgets('"Como fazer" records the tap and opens the two steps',
        (tester) async {
      var opened = 0;
      await tester.pumpWidget(
          shellApp(hint: ValueNotifier(offer(onOpen: () => opened++))));
      await tester.pumpAndSettle();

      await tester.tap(find.text(pt[KApp.installHintHow]));
      await tester.pumpAndSettle();

      expect(opened, 1);
      expect(find.text(pt[KApp.installHintTitle]), findsOneWidget);
      expect(find.text(pt[KApp.installHintSubtitle]), findsOneWidget);
      // The steps carry inline emphasis; the semantics carry the sentence.
      expect(find.text(stripRichText(pt[KApp.installHintStepShare])),
          findsOneWidget);
      expect(find.text(stripRichText(pt[KApp.installHintStepAdd])),
          findsOneWidget);
      expect(find.text(pt[KApp.installHintNote]), findsOneWidget);
      // No `<strong>` reaches a reader.
      expect(find.textContaining('<strong>'), findsNothing);

      // Fechar closes it and the strip is still there: reading the steps is
      // not a dismissal — the reader may need them again after the sheet is
      // gone.
      await tester.tap(find.text(pt[K.commonClose]));
      await tester.pumpAndSettle();
      expect(find.text(pt[KApp.installHintTitle]), findsNothing);
      expect(strip, findsOneWidget);
    });

    testWidgets('the steps are the landing\'s L-19 steps, in both languages',
        (tester) async {
      // The landing's guide was checked against Apple's iOS 26 guide
      // (11/09/2026); the app mirrors its three load-bearing facts rather than
      // the inherited Blazor fragments: the Share button may be hidden behind
      // ⋯, the list must be SCROLLED, and the flow ends on Adicionar.
      for (final l in [pt, en]) {
        final share = l[KApp.installHintStepShare];
        final add = l[KApp.installHintStepAdd];
        expect(share, contains('⋯'));
        expect(add, contains(l == pt ? 'Role a lista' : 'Scroll the list'));
        expect(add,
            contains(l == pt ? 'Adicionar à Tela de Início' : 'Add to Home Screen'));
        expect(add, endsWith(l == pt ? '<strong>Adicionar</strong>.' : '<strong>Add</strong>.'));
        // U-54 (21/09/2026): Apple's current guide (iOS 27 and 26) turns on
        // "Open as Web App" before Add — without it the icon opens Safari,
        // not the standalone app, and web push never exists there.
        expect(add,
            contains(l == pt ? 'Abrir como App da Web' : 'Open as Web App'));
      }
    });
  });
}
