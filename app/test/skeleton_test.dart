// U-27 — the skeletons that replaced the centred spinners and the word
// "Carregando" at the app's content loads.
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('the shimmer runs and stops with the widget', (tester) async {
    await tester.pumpWidget(_host(const AppSkeleton(width: 100)));
    // A repeating controller that outlives its widget leaks a ticker; the
    // pumpWidget below disposes it, and the test framework fails the test if
    // a ticker is still alive at the end.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpWidget(_host(const SizedBox()));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the list skeleton announces itself ONCE, not row by row',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(
        const AppSkeletonList(rows: 4, semanticsLabel: 'Carregando...')));
    expect(find.bySemanticsLabel('Carregando...'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the calendar skeleton lays out six weeks of cells',
      (tester) async {
    await tester.pumpWidget(_host(
        const SingleChildScrollView(child: AppSkeletonCalendar())));
    // 42 cells and nothing else: U-28 removed the skeleton's own weekday row,
    // because the calendar screen prints the real initials right above it and
    // the loading state was showing a header the loaded state does not have.
    expect(find.byType(AppSkeleton), findsNWidgets(42));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card skeleton carries its label too', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(
        const AppSkeletonCards(count: 2, semanticsLabel: 'Carregando...')));
    expect(find.bySemanticsLabel('Carregando...'), findsOneWidget);
    expect(find.byType(AppSkeleton), findsNWidgets(2));
    handle.dispose();
  });

  // One test per theme, not a loop: swapping the theme inside a single test
  // starts MaterialApp's own theme animation, and the tokens are then read
  // mid-lerp — the first version of this test asserted against a colour
  // halfway between the two palettes.
  for (final (name, theme, tokens) in [
    ('light', AppTheme.light, AppTokens.light),
    ('dark', AppTheme.dark, AppTokens.dark),
  ]) {
    testWidgets('the shimmer reads its colours from the $name theme',
        (tester) async {
      await tester.pumpWidget(
          _host(const AppSkeleton(width: 80), theme: theme));
      await tester.pump(const Duration(milliseconds: 100));
      final box = tester.widget<DecoratedBox>(find.descendant(
        of: find.byType(AppSkeleton),
        matching: find.byType(DecoratedBox),
      ));
      final gradient =
          (box.decoration as BoxDecoration).gradient! as LinearGradient;
      expect(gradient.colors.first, tokens.skeletonBase);
      expect(gradient.colors[1], tokens.skeletonHighlight);
      await tester.pumpWidget(_host(const SizedBox()));
    });
  }
}
