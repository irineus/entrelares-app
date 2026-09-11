// U-28 — the splash and the brand mark it shares with the login screen.
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/app_splash.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {bool reduceMotion = false, ThemeData? theme}) =>
    AppL10n(
      l: Localization(AppLanguage.ptBr),
      setLanguage: (_) async {},
      child: MaterialApp(
        theme: theme ?? AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('the splash names the product and its question', (tester) async {
    await tester.pumpWidget(_host(const AppSplash()));
    await tester.pump(const Duration(milliseconds: 100));

    final l = Localization(AppLanguage.ptBr);
    expect(find.text(l[K.loginHeading]), findsOneWidget);
    expect(find.text(l[K.splashTagline]), findsOneWidget);
    expect(find.byType(AppBrandMark), findsOneWidget,
        reason: 'the first frame carries the mark, not a bare spinner');
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('it keeps animating without throwing', (tester) async {
    await tester.pumpWidget(_host(const AppSplash()));
    // Across the whole 5.4 s loop, including both flips.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 450));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduce-motion holds the mark still', (tester) async {
    await tester.pumpWidget(_host(const AppSplash(), reduceMotion: true));
    await tester.pump(const Duration(milliseconds: 100));
    final first = tester.getTopLeft(find.byType(AppBrandMark));
    await tester.pump(const Duration(milliseconds: 2100));
    expect(tester.getTopLeft(find.byType(AppBrandMark)), first,
        reason: 'the card must not float when the platform asks for stillness');
  });

  testWidgets('the mark stands still on its own, with no animation given',
      (tester) async {
    await tester.pumpWidget(_host(const Scaffold(body: AppBrandMark())));
    // Nothing is loading on the login screen, so nothing runs there: a mark
    // with no animation given must SETTLE. A repeating controller would make
    // this time out, which is the failure this pins.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AppBrandMark), findsOneWidget);
  });

  testWidgets('it paints on the dark surface too', (tester) async {
    await tester.pumpWidget(
        _host(const AppSplash(), theme: AppTheme.dark));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(AppBrandMark), findsOneWidget);
  });
}
