// U-28 — the account entry point and the month bar.
//
// The first group pins a real defect and not a preference: `onSignOut` was a
// `CalendarScreen` parameter, so a reader on any other tab had no way out of
// the app. These tests fail if it ever goes back to living on one screen.
import 'package:entrelares_app/services/account_identity.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/account_button.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _l = Localization(AppLanguage.ptBr);

Widget _scoped({
  AccountIdentity? identity,
  Future<void> Function()? onSignOut,
  VoidCallback? onOpenProfile,
  AppLanguage language = AppLanguage.ptBr,
  Future<void> Function(AppLanguage)? setLanguage,
}) =>
    AppL10n(
      l: Localization(language),
      setLanguage: setLanguage ?? (_) async {},
      child: MaterialApp(
        theme: AppTheme.light,
        home: AccountScope(
          identity: identity ?? AccountIdentity(),
          onSignOut: onSignOut ?? () async {},
          onOpenProfile: onOpenProfile ?? () {},
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Tab'),
              actions: const [AppAccountButton()],
            ),
          ),
        ),
      ),
    );

void main() {
  group('AppAccountButton', () {
    testWidgets('offers profile, both languages and sign-out', (tester) async {
      await tester.pumpWidget(_scoped());
      await tester.tap(find.byType(AppAccountButton));
      await tester.pumpAndSettle();

      expect(find.text(_l[K.navProfile]), findsOneWidget);
      expect(find.text(_l[K.navLogout]), findsOneWidget);
      expect(find.text(_l[K.languagePtBr]), findsOneWidget);
      expect(find.text(_l[K.languageEn]), findsOneWidget);
    });

    testWidgets('sign-out is reachable from a tab that is not the calendar',
        (tester) async {
      var signedOut = false;
      await tester.pumpWidget(_scoped(onSignOut: () async {
        signedOut = true;
      }));
      await tester.tap(find.byType(AppAccountButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l[K.navLogout]));
      await tester.pumpAndSettle();
      expect(signedOut, isTrue);
    });

    testWidgets('opens the profile', (tester) async {
      var opened = false;
      await tester.pumpWidget(_scoped(onOpenProfile: () => opened = true));
      await tester.tap(find.byType(AppAccountButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l[K.navProfile]));
      await tester.pumpAndSettle();
      expect(opened, isTrue);
    });

    testWidgets('switching language goes through the app-level setter',
        (tester) async {
      AppLanguage? chosen;
      await tester.pumpWidget(_scoped(setLanguage: (lang) async {
        chosen = lang;
      }));
      await tester.tap(find.byType(AppAccountButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(_l[K.languageEn]));
      await tester.pumpAndSettle();
      expect(chosen, AppLanguage.en);
    });

    testWidgets('the avatar wears the reader initial and slot once published',
        (tester) async {
      final identity = AccountIdentity();
      await tester.pumpWidget(_scoped(identity: identity));
      // Before any screen has loaded: a placeholder, never an empty circle.
      expect(find.text('?'), findsOneWidget);

      identity.adopt(fullName: 'Fernanda Daroit', colorSlot: 2);
      await tester.pump();

      expect(find.text('F'), findsOneWidget);
      final avatar = tester.widget<AppAvatar>(find.byType(AppAvatar));
      expect(avatar.slot?.tone.solid, AppTokens.light.slots[2].tone.solid);
    });

    testWidgets('adopting the same identity twice notifies once',
        (tester) async {
      final identity = AccountIdentity();
      var notifications = 0;
      identity.addListener(() => notifications++);
      identity.adopt(fullName: 'Irineu', colorSlot: 1);
      identity.adopt(fullName: 'Irineu', colorSlot: 1);
      expect(notifications, 1,
          reason: 'the calendar and the family screen both publish on every '
              'refresh — four app bars must not rebuild for nothing');
    });

    testWidgets('sign-out clears it, so the next session shows no stale letter',
        (tester) async {
      final identity = AccountIdentity()
        ..adopt(fullName: 'Irineu', colorSlot: 1);
      await tester.pumpWidget(_scoped(identity: identity));
      expect(find.text('I'), findsOneWidget);

      identity.clear();
      await tester.pump();
      expect(find.text('?'), findsOneWidget);
    });

    testWidgets('renders nothing where there is no account — the login screens',
        (tester) async {
      await tester.pumpWidget(AppL10n(
        l: Localization(AppLanguage.ptBr),
        setLanguage: (_) async {},
        child: const MaterialApp(
          home: Scaffold(body: AppAccountButton()),
        ),
      ));
      expect(find.byType(PopupMenuButton<dynamic>), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
