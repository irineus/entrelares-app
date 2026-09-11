// Lote 1 PR2 — the hull and the auth surfaces: the four-destination shell
// with placeholders, S-01 login throttling, and the recovery pair
// (reset-password / update-password) against fake callbacks.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:entrelares_app/screens/home_shell.dart';
import 'package:entrelares_app/screens/login_screen.dart';
import 'package:entrelares_app/services/account_identity.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'calendar_slice_test.dart' show FakeCustodyDataSource;
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/screens/placeholder_screen.dart';
import 'package:entrelares_app/screens/reset_password_screen.dart';
import 'package:entrelares_app/screens/update_password_screen.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

final pt = Localization(AppLanguage.ptBr);

Widget wrap(Widget child, {AppLanguage language = AppLanguage.ptBr}) =>
    AppL10n(
      l: Localization(language),
      setLanguage: (_) async {},
      child: MaterialApp(home: child),
    );

void main() {
  group('HomeShell', () {
    Widget shellApp({AdminMode? adminMode, AccountIdentity? identity,
        Future<void> Function()? onSignOut}) {
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (_, _, shell) =>
                HomeShell(
                    shell: shell,
                    adminMode: adminMode ?? AdminMode(),
                    identity: identity ?? AccountIdentity(),
                    onSignOut: onSignOut ?? () async {},
                    onOpenProfile: () {},
                    badge: NotificationBadge(
                        FakeCustodyDataSource(members: const [], days: []))),
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/',
                    builder: (_, _) =>
                        const Scaffold(body: Text('CALENDARIO'))),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/family',
                    builder: (_, _) =>
                        const PlaceholderScreen(titleKey: K.navFamily)),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/notifications',
                    builder: (_, _) =>
                        const PlaceholderScreen(titleKey: K.navNotifications)),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                    path: '/reports',
                    builder: (_, _) =>
                        const PlaceholderScreen(titleKey: K.navReports)),
              ]),
            ],
          ),
        ],
      );
      return AppL10n(
        l: pt,
        setLanguage: (_) async {},
        child: MaterialApp.router(routerConfig: router),
      );
    }

    testWidgets('shows the same four destinations as the web NavMenu',
        (tester) async {
      await tester.pumpWidget(shellApp());
      await tester.pumpAndSettle();

      expect(find.text(pt[K.navCalendar]), findsOneWidget);
      expect(find.text(pt[K.navFamily]), findsOneWidget);
      expect(find.text(pt[K.navNotificationsShort]), findsOneWidget);
      expect(find.text(pt[K.navReports]), findsOneWidget);
      expect(find.text('CALENDARIO'), findsOneWidget);
    });

    testWidgets('an unported destination shows its placeholder',
        (tester) async {
      await tester.pumpWidget(shellApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text(pt[K.navNotificationsShort]));
      await tester.pumpAndSettle();

      expect(find.text(pt[K.navNotifications]), findsOneWidget);
      expect(
          find.text(pt[KApp.shellUnderConstructionTitle]), findsOneWidget);

      await tester.tap(find.text(pt[K.navCalendar]));
      await tester.pumpAndSettle();
      expect(find.text('CALENDARIO'), findsOneWidget);
    });

    testWidgets('F-14: the admin banner is persistent while the mode is on '
        'and its Sair exits', (tester) async {
      final adminMode = AdminMode();
      await tester.pumpWidget(shellApp(adminMode: adminMode));
      await tester.pumpAndSettle();
      expect(find.textContaining(pt[K.layoutAdminActive]), findsNothing);

      adminMode.toggle();
      await tester.pumpAndSettle();
      expect(find.textContaining(pt[K.layoutAdminActive]), findsOneWidget);

      // Persistent across tabs, like the web's MainLayout strip.
      await tester.tap(find.text(pt[K.navReports]));
      await tester.pumpAndSettle();
      expect(find.textContaining(pt[K.layoutAdminActive]), findsOneWidget);

      await tester.tap(find.text(pt[K.layoutAdminExit]));
      await tester.pumpAndSettle();
      expect(adminMode.isActive, isFalse);
      expect(find.textContaining(pt[K.layoutAdminActive]), findsNothing);
    });
  });

  group('LoginScreen — S-01 throttling', () {
    testWidgets('three failures lock the button for 15 s and persist',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(wrap(LoginScreen(
        onSignIn: (_, _) async =>
            throw Exception('Invalid login credentials'),
        onForgotPassword: () {},
        onSignUp: () {},
        prefs: prefs,
      )));
      await tester.pumpAndSettle();

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text(pt[K.loginSubmit]));
        await tester.pumpAndSettle();
      }
      // No lockout yet at 2 failures.
      expect(find.text(pt[K.loginSubmit]), findsOneWidget);

      await tester.tap(find.text(pt[K.loginSubmit]));
      await tester.pump();
      await tester.pump();

      // 3 failures → attempts × 5 = 15 s, button disabled with the countdown.
      expect(find.text(pt.format(K.loginLockout, [15])), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.byType(FilledButton))
              .onPressed,
          isNull);
      expect(prefs.getInt('login_fails'), 3);
      expect(prefs.getInt('login_lockout_until'), isNotNull);

      // The countdown releases the button.
      await tester.pump(const Duration(seconds: 16));
      expect(find.text(pt[K.loginSubmit]), findsOneWidget);
      expect(
          tester
              .widget<FilledButton>(find.byType(FilledButton))
              .onPressed,
          isNotNull);
    });

    testWidgets('a persisted lockout is restored on mount', (tester) async {
      final until =
          DateTime.now().toUtc().add(const Duration(seconds: 40));
      SharedPreferences.setMockInitialValues({
        'login_fails': 5,
        'login_lockout_until': until.millisecondsSinceEpoch ~/ 1000,
      });
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(wrap(LoginScreen(
        onSignIn: (_, _) async {},
        onForgotPassword: () {},
        onSignUp: () {},
        prefs: prefs,
      )));
      await tester.pump();

      expect(
          tester
              .widget<FilledButton>(find.byType(FilledButton))
              .onPressed,
          isNull);
      await tester.pump(const Duration(seconds: 41));
      expect(
          tester
              .widget<FilledButton>(find.byType(FilledButton))
              .onPressed,
          isNotNull);
    });

    testWidgets('the inactivity reason renders its own banner',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(wrap(LoginScreen(
        onSignIn: (_, _) async {},
        onForgotPassword: () {},
        onSignUp: () {},
        prefs: prefs,
        expiredReason: SessionExpiredReason.inactivity,
      )));
      await tester.pumpAndSettle();

      expect(find.text(pt[K.loginExpiredInactivity]), findsOneWidget);
    });

    testWidgets('the forgot link calls back', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var forgot = false;
      await tester.pumpWidget(wrap(LoginScreen(
        onSignIn: (_, _) async {},
        onForgotPassword: () => forgot = true,
        onSignUp: () {},
        prefs: prefs,
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text(pt[K.loginForgot]));
      expect(forgot, isTrue);
    });
  });

  group('ResetPasswordScreen', () {
    testWidgets('sends the trimmed e-mail and shows the sent view',
        (tester) async {
      String? sentTo;
      await tester.pumpWidget(wrap(ResetPasswordScreen(
        onSendReset: (email) async => sentTo = email,
        onBackToLogin: () {},
      )));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byType(TextField), '  owner@example.com  ');
      await tester.tap(find.text(pt[K.resetSubmit]));
      await tester.pumpAndSettle();

      expect(sentTo, 'owner@example.com');
      expect(find.text(pt[K.resetSentTitle]), findsOneWidget);
    });

    testWidgets('a send failure shows the catalog error and stays on the form',
        (tester) async {
      await tester.pumpWidget(wrap(ResetPasswordScreen(
        onSendReset: (_) async => throw Exception('boom'),
        onBackToLogin: () {},
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'owner@example.com');
      await tester.tap(find.text(pt[K.resetSubmit]));
      await tester.pumpAndSettle();

      expect(find.text(pt[K.authErrResetSend]), findsOneWidget);
      expect(find.text(pt[K.resetSentTitle]), findsNothing);
    });
  });

  group('UpdatePasswordScreen', () {
    testWidgets('mirrors the web validation: short first, then mismatch',
        (tester) async {
      var updated = false;
      await tester.pumpWidget(wrap(UpdatePasswordScreen(
        onUpdatePassword: (_) async => updated = true,
        hasSession: true,
        onDone: () {},
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '12345');
      await tester.enterText(find.byType(TextField).last, 'different');
      await tester.tap(find.text(pt[K.updatePwdSubmit]));
      await tester.pump();
      expect(find.text(pt[K.updatePwdErrorShort]), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.enterText(find.byType(TextField).last, '123457');
      await tester.tap(find.text(pt[K.updatePwdSubmit]));
      await tester.pump();
      expect(find.text(pt[K.updatePwdErrorMismatch]), findsOneWidget);
      expect(updated, isFalse);
    });

    testWidgets('a valid pair updates and shows the success view',
        (tester) async {
      String? received;
      var done = false;
      await tester.pumpWidget(wrap(UpdatePasswordScreen(
        onUpdatePassword: (p) async => received = p,
        hasSession: true,
        onDone: () => done = true,
      )));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'nova-senha');
      await tester.enterText(find.byType(TextField).last, 'nova-senha');
      await tester.tap(find.text(pt[K.updatePwdSubmit]));
      await tester.pumpAndSettle();

      expect(received, 'nova-senha');
      expect(find.text(pt[K.updatePwdDoneTitle]), findsOneWidget);

      await tester.tap(find.text(pt[K.updatePwdGoToCalendar]));
      expect(done, isTrue);
    });

    testWidgets('without a session the form refuses, same as the web',
        (tester) async {
      await tester.pumpWidget(wrap(UpdatePasswordScreen(
        onUpdatePassword: (_) async {},
        hasSession: false,
        onDone: () {},
      )));
      await tester.pumpAndSettle();

      expect(find.text(pt[K.updatePwdErrorSession]), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('an English session renders the recovery form in English',
        (tester) async {
      final en = Localization(AppLanguage.en);
      await tester.pumpWidget(wrap(
          UpdatePasswordScreen(
            onUpdatePassword: (_) async {},
            hasSession: true,
            onDone: () {},
          ),
          language: AppLanguage.en));
      await tester.pumpAndSettle();

      expect(find.text(en[K.updatePwdTitle]), findsOneWidget);
      expect(find.text(pt[K.updatePwdTitle]), findsNothing);
    });
  });

  group('reasonForSignedOut', () {
    test('pressing Sair never announces an expired session', () {
      // The defect the web QA found: the auth event can land after `_signOut`
      // already reset the reason, and the login screen greeted a deliberate
      // logout with "sua sessão anterior expirou".
      expect(
        reasonForSignedOut(
            userInitiated: true,
            current: SessionExpiredReason.none,
            wasAuthed: true),
        SessionExpiredReason.none,
      );
    });

    test('a session dying mid-use still says so', () {
      expect(
        reasonForSignedOut(
            userInitiated: false,
            current: SessionExpiredReason.none,
            wasAuthed: true),
        SessionExpiredReason.restored,
      );
    });

    test('a reason already decided is never overwritten', () {
      // The inactivity timer sets its own reason before signing out; the
      // event that follows must not downgrade it to the generic one.
      expect(
        reasonForSignedOut(
            userInitiated: false,
            current: SessionExpiredReason.inactivity,
            wasAuthed: true),
        SessionExpiredReason.inactivity,
      );
    });

    test('a sign-out while already anonymous says nothing', () {
      expect(
        reasonForSignedOut(
            userInitiated: false,
            current: SessionExpiredReason.none,
            wasAuthed: false),
        SessionExpiredReason.none,
      );
    });
  });
}
