// U-45 — the "Sign in with Google" button, against Google's own spec.
//
// The button had NO test at all before this item: F-57 shipped it and the
// suite only ever saw the screens that host it. That is why the generic
// `Icons.account_circle_outlined` survived three months on the surface a brand
// review looks at first. Every number below is the guideline's, measured from
// the official `signin-assets.zip` (Square button, @4x) — a test that agreed
// with whatever the widget happened to draw would be worth nothing here.
import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:entrelares_app/screens/login_screen.dart';
import 'package:entrelares_app/screens/register_screen.dart';
import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/google_sign_in_button.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource, ana, bruno;

final pt = Localization(AppLanguage.ptBr);
final en = Localization(AppLanguage.en);

Future<void> pumpButton(
  WidgetTester tester, {
  required Future<bool> enabled,
  Future<void> Function()? onPressed,
  Brightness brightness = Brightness.light,
  AppLanguage language = AppLanguage.ptBr,
}) async {
  await tester.pumpWidget(AppL10n(
    l: Localization(language),
    setLanguage: (_) async {},
    child: MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Center(
          child: GoogleSignInButton(
            enabled: enabled,
            onPressed: onPressed ?? () async {},
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The button's own `OutlinedButton`, resolved through its styleFrom.
ButtonStyle styleOf(WidgetTester tester) =>
    tester.widget<OutlinedButton>(find.byType(OutlinedButton)).style!;

void main() {
  group('the fail-closed switch', () {
    testWidgets('nothing renders while the provider is not enabled',
        (tester) async {
      await pumpButton(tester, enabled: Future.value(false));
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.text(pt[KApp.authGoogle]), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('a failed lookup looks exactly like a disabled provider',
        (tester) async {
      // The lookup fails the way a real one does — after the widget is
      // already listening, not before it can subscribe.
      await pumpButton(tester,
          enabled: Future<bool>.delayed(
              Duration.zero, () => throw Exception('offline')));
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('the sentence and the mark appear when GoTrue says yes',
        (tester) async {
      await pumpButton(tester, enabled: Future.value(true));
      expect(find.text(pt[KApp.authGoogle]), findsOneWidget);
      final logo = tester.widget<Image>(find.byType(Image));
      expect((logo.image as AssetImage).assetName, GoogleBrand.logoAsset);
      // The sentence is the accessible name; a labelled image would make the
      // reader hear the button twice.
      expect(logo.excludeFromSemantics, isTrue);
    });

    testWidgets('the sentence follows the reader language', (tester) async {
      await pumpButton(tester,
          enabled: Future.value(true), language: AppLanguage.en);
      expect(find.text(en[KApp.authGoogle]), findsOneWidget);
    });
  });

  group('the guideline', () {
    testWidgets('light: white surface, #747775 stroke, dark ink',
        (tester) async {
      await pumpButton(tester, enabled: Future.value(true));
      final style = styleOf(tester);
      const enabledState = <WidgetState>{};
      expect(style.backgroundColor!.resolve(enabledState),
          GoogleBrand.lightSurface);
      expect(style.foregroundColor!.resolve(enabledState),
          GoogleBrand.lightText);
      expect(style.side!.resolve(enabledState)!.color, GoogleBrand.lightStroke);
      expect(style.side!.resolve(enabledState)!.width,
          GoogleBrand.strokeWidth);
    });

    testWidgets('dark: #131314 surface, #8E918F stroke, light ink',
        (tester) async {
      await pumpButton(tester,
          enabled: Future.value(true), brightness: Brightness.dark);
      final style = styleOf(tester);
      const enabledState = <WidgetState>{};
      expect(style.backgroundColor!.resolve(enabledState),
          GoogleBrand.darkSurface);
      expect(
          style.foregroundColor!.resolve(enabledState), GoogleBrand.darkText);
      expect(style.side!.resolve(enabledState)!.color, GoogleBrand.darkStroke);
    });

    testWidgets('40 dp tall, 4 dp corners, 20 dp mark', (tester) async {
      await pumpButton(tester, enabled: Future.value(true));
      expect(tester.getSize(find.byType(OutlinedButton)).height,
          GoogleBrand.height,
          reason: "Material's padded tap target grows the box to 48 and "
              'breaks the height the guideline asks for.');
      expect(tester.getSize(find.byType(Image)).height, GoogleBrand.logoSize);
      expect(tester.getSize(find.byType(Image)).width, GoogleBrand.logoSize);
      final shape =
          styleOf(tester).shape!.resolve(const <WidgetState>{})
              as RoundedRectangleBorder;
      expect(shape.borderRadius,
          BorderRadius.circular(GoogleBrand.radius));
    });

    testWidgets('the sentence is medium 14/20', (tester) async {
      await pumpButton(tester, enabled: Future.value(true));
      final text = styleOf(tester).textStyle!.resolve(const <WidgetState>{})!;
      expect(text.fontSize, GoogleBrand.fontSize);
      expect(text.fontWeight, FontWeight.w500);
      expect(text.height, GoogleBrand.lineHeight / GoogleBrand.fontSize);
    });

    test('the mark ships as an image, at three densities', () {
      // It may not be recoloured or redrawn, so it can never become an icon
      // font or a painter — and a 1x-only asset would be mush on a phone.
      for (final path in const [
        'assets/brand/google-g.png',
        'assets/brand/2.0x/google-g.png',
        'assets/brand/3.0x/google-g.png',
      ]) {
        expect(File(path).existsSync(), isTrue, reason: '$path is missing');
      }
    });
  });

  group('the failure that is ours to report', () {
    testWidgets('a redirect that cannot launch shows the catalog snack',
        (tester) async {
      await pumpButton(tester,
          enabled: Future.value(true),
          onPressed: () async => throw Exception('no browser'));
      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();
      expect(find.text(pt[KApp.authGoogleErr]), findsOneWidget);
    });
  });

  group('both doors carry it', () {
    testWidgets('login shows it when the provider is enabled, and only then',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      Widget login({required Future<bool> enabled}) => AppL10n(
            l: pt,
            setLanguage: (_) async {},
            child: MaterialApp(
              home: LoginScreen(
                onSignIn: (_, _) async {},
                onForgotPassword: () {},
                onSignUp: () {},
                prefs: prefs,
                googleEnabled: enabled,
                onSignInWithGoogle: () async {},
              ),
            ),
          );

      await tester.pumpWidget(login(enabled: Future.value(true)));
      await tester.pumpAndSettle();
      expect(find.byType(GoogleSignInButton), findsOneWidget);
      expect(find.text(pt[KApp.authGoogle]), findsOneWidget);

      await tester.pumpWidget(login(enabled: Future.value(false)));
      await tester.pumpAndSettle();
      expect(find.text(pt[KApp.authGoogle]), findsNothing);
    });

    testWidgets('register shows it when the provider is enabled, and only then',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Widget register({required Future<bool> enabled}) => AppL10n(
            l: pt,
            setLanguage: (_) async {},
            child: MaterialApp(
              home: RegisterScreen(
                dataSource:
                    FakeCustodyDataSource(members: const [ana, bruno], days: []),
                onSignIn: (_, _) async {},
                onBackToLogin: () {},
                googleEnabled: enabled,
                onSignInWithGoogle: ({String? inviteToken}) async {},
              ),
            ),
          );

      await tester.pumpWidget(register(enabled: Future.value(true)));
      await tester.pumpAndSettle();
      expect(find.byType(GoogleSignInButton), findsOneWidget);
      expect(find.text(pt[KApp.authGoogle]), findsOneWidget);

      await tester.pumpWidget(register(enabled: Future.value(false)));
      await tester.pumpAndSettle();
      expect(find.text(pt[KApp.authGoogle]), findsNothing);
    });
  });
}
