// U-48 — a line that shrinks with a FLOOR, and the three sites that use it
// held at 1.3× on a 360 dp phone.
//
// `FittedBox.scaleDown` undid the reader's font setting without limit; the
// four sites (summary ×2, today card, login) shrink by at most 15 % now and
// past that wrap or ellipsize. This file proves the component's contract on
// bare boxes, then the sites at the scale the card names.
import 'dart:io';

import 'package:entrelares_app/screens/login_screen.dart';
import 'package:entrelares_app/screens/reports_summary_tab.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reports_summary_test.dart' as rep;
import 'today_card_test.dart' as today;

const _phone = Size(360, 740);

/// The product's own typeface. The test host's fallback font draws every
/// glyph as a SQUARE of the font size — "Quarta-feira, 19 de agosto" comes
/// out 370 px wide at 1.3× instead of ~205 — so every site measurement here
/// runs on Inter, the U-39 technique (`calendar_fits_u28_test`).
Future<void> _loadRealFonts() async {
  Future<ByteData> bytes(String file) async => ByteData.sublistView(
    Uint8List.fromList(await File('assets/fonts/$file').readAsBytes()),
  );
  final inter = FontLoader('Inter');
  for (final f in [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
  ]) {
    inter.addFont(bytes(f));
  }
  await inter.load();
}

Future<void> _usePhone(WidgetTester tester, {double scale = 1.0}) async {
  await tester.binding.setSurfaceSize(_phone);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// A fixed-width host for the component alone.
Widget _box(double width, Widget child) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: width, child: child),
    ),
  ),
);

/// A site under the product's theme (Inter, labelSmall 12), in PT-BR.
Widget _themed(Widget child) => AppL10n(
  l: Localization(AppLanguage.ptBr),
  setLanguage: (_) async {},
  child: MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(body: child),
  ),
);

/// The scale the render object applied — read from the transform the child
/// is painted through, which is also what a tap goes through.
double _appliedScale(WidgetTester tester, Finder fit) {
  final box = tester.renderObject<RenderBox>(fit);
  final child = tester.renderObject<RenderBox>(
    find.descendant(of: fit, matching: find.byType(Text)).first,
  );
  // The x scale, read from the matrix itself: `getMaxScaleOnAxis` would
  // answer 1.0 for any shrink, because the z axis is never scaled.
  return child.getTransformTo(box).entry(0, 0);
}

void main() {
  group('AppShrinkToFit', () {
    // A 100 px-wide "word" (a SizedBox stands in: the contract is about
    // widths, not glyphs).
    Widget word(double width, {String text = 'x'}) => AppShrinkToFit(
      child: SizedBox(
        width: width,
        height: 20,
        child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );

    testWidgets('a child that fits is not scaled at all', (tester) async {
      await tester.pumpWidget(_box(200, word(100)));
      final fit = find.byType(AppShrinkToFit);
      expect(_appliedScale(tester, fit), 1.0);
      expect(
        tester.getSize(fit).width,
        200,
        reason: 'the box takes the width offered, the child sits in it',
      );
    });

    testWidgets('a child up to 15 % too wide is shrunk to fit exactly', (
      tester,
    ) async {
      await tester.pumpWidget(_box(90, word(100)));
      final fit = find.byType(AppShrinkToFit);
      expect(_appliedScale(tester, fit), closeTo(0.9, 1e-9));
      expect(tester.getSize(fit).width, closeTo(90, 1e-9));
    });

    testWidgets('past the floor the scale stops at 0.85 and the child gets '
        'the width it has AT the floor', (tester) async {
      // Natural width 100 into 50: scaleDown would paint at 0.5. This stops
      // at 0.85 and re-lays the child out at 50 / 0.85 ≈ 58.8 wide.
      Size? childSize;
      await tester.pumpWidget(
        _box(
          50,
          AppShrinkToFit(
            child: LayoutBuilder(
              builder: (context, c) {
                childSize = Size(c.maxWidth, 20);
                return SizedBox(
                  width: c.maxWidth.isFinite ? c.maxWidth : 100,
                  height: 20,
                  child: const Text('x'),
                );
              },
            ),
          ),
        ),
      );
      final fit = find.byType(AppShrinkToFit);
      expect(_appliedScale(tester, fit), closeTo(0.85, 1e-9));
      expect(
        childSize!.width,
        closeTo(50 / 0.85, 1e-6),
        reason:
            'the child is told the width it has at the floor, so a '
            'Text ellipsizes and a Wrap wraps on its own terms',
      );
      expect(tester.getSize(fit).width, closeTo(50, 1e-6));
    });

    testWidgets('a Text past the floor ellipsizes instead of shrinking on', (
      tester,
    ) async {
      await tester.pumpWidget(
        _box(
          60,
          const AppShrinkToFit(
            child: Text(
              'Uma frase comprida demais para caber',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
      final fit = find.byType(AppShrinkToFit);
      expect(_appliedScale(tester, fit), closeTo(0.85, 1e-9));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: fit, matching: find.byType(RichText)),
      );
      expect(
        paragraph.didExceedMaxLines,
        isTrue,
        reason:
            'at the floor the sentence is cut with an ellipsis, not '
            'painted at 0.3×',
      );
    });

    testWidgets('a Wrap past the floor breaks into a second line', (
      tester,
    ) async {
      await tester.pumpWidget(
        _box(
          100,
          AppShrinkToFit(
            child: Wrap(
              children: [
                for (var i = 0; i < 3; i++)
                  SizedBox(width: 50, height: 20, child: Text('$i')),
              ],
            ),
          ),
        ),
      );
      final fit = find.byType(AppShrinkToFit);
      expect(_appliedScale(tester, fit), closeTo(0.85, 1e-9));
      // 150 natural → at the floor the Wrap gets 117.6 and breaks: 2 + 1.
      expect(
        tester.getSize(find.byType(Wrap)).height,
        40,
        reason: 'two runs, the second line is the honest answer',
      );
      expect(
        tester.getSize(fit).height,
        closeTo(34, 1e-6),
        reason: 'and the box reports the scaled height',
      );
    });

    testWidgets('a tap lands through the transform', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _box(
          90,
          AppShrinkToFit(
            child: SizedBox(
              width: 100,
              height: 40,
              child: GestureDetector(
                onTap: () => taps++,
                child: const Text('toque'),
              ),
            ),
          ),
        ),
      );
      // The child is painted at 0.9 and 90 wide; tapping its far end must
      // still reach it (a hit test through the scale, not the natural box).
      final fit = find.byType(AppShrinkToFit);
      final rect = tester.getRect(fit);
      await tester.tapAt(Offset(rect.left + 85, rect.top + 10));
      expect(taps, 1);
    });
  });

  group('the sites at 1.3× on 360 dp', () {
    setUpAll(_loadRealFonts);

    testWidgets('summary: a stat label stays one line, never under 0.85×', (
      tester,
    ) async {
      await _usePhone(tester, scale: 1.3);
      await tester.pumpWidget(
        AppL10n(
          l: Localization(AppLanguage.ptBr),
          setLanguage: (_) async {},
          child: MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: ReportsSummaryTab(
                dataSource: rep.source(),
                now: () => rep.today,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fits = find.byType(AppShrinkToFit);
      expect(fits, findsWidgets);
      for (final e in fits.evaluate()) {
        final scale = _appliedScale(tester, find.byWidget(e.widget));
        expect(scale, greaterThanOrEqualTo(AppShrinkToFit.defaultFloor - 1e-9));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('today card: the date arrives whole, at ≥ 0.85×', (
      tester,
    ) async {
      await _usePhone(tester, scale: 1.3);
      await tester.pumpWidget(
        _themed(
          today.card(
            glance: todayGlance(
              userProfileId: 1,
              scheduledParentId: 2,
              actualParentId: null,
              handoffTime: null,
              members: const [today.ana, today.bruno],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final fit = find.byType(AppShrinkToFit);
      expect(fit, findsOneWidget);
      expect(
        _appliedScale(tester, fit),
        greaterThanOrEqualTo(AppShrinkToFit.defaultFloor - 1e-9),
      );
      final date = tester.renderObject<RenderParagraph>(
        find.descendant(of: fit, matching: find.byType(RichText)),
      );
      expect(
        date.didExceedMaxLines,
        isFalse,
        reason:
            'quarta-feira, 19 de agosto arrives whole at 1.3× on a '
            'phone — the ellipsis is the floor\'s answer, not the norm',
      );
      expect(tester.takeException(), isNull);
    });

    Future<void> pumpLogin(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        AppL10n(
          l: Localization(AppLanguage.ptBr),
          setLanguage: (_) async {},
          child: MaterialApp(
            theme: AppTheme.light,
            home: LoginScreen(
              onSignIn: (_, _) async {},
              onForgotPassword: () {},
              onSignUp: () {},
              prefs: prefs,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    final l = Localization(AppLanguage.ptBr);
    Rect link(WidgetTester tester, String key) =>
        tester.getRect(find.widgetWithText(TextButton, l[key]));

    testWidgets('login at 1.3×: the pair shrinks to ≥ 0.85× and each link '
        'still measures 48 dp on screen', (tester) async {
      await _usePhone(tester, scale: 1.3);
      await pumpLogin(tester);
      final fit = find.byType(AppShrinkToFit);
      expect(fit, findsOneWidget);
      expect(
        _appliedScale(tester, fit),
        greaterThanOrEqualTo(AppShrinkToFit.defaultFloor - 1e-9),
      );
      for (final key in [K.commonPrivacyPolicy, K.commonTermsOfUse]) {
        expect(
          link(tester, key).height,
          greaterThanOrEqualTo(48 - 1e-9),
          reason: 'a shrunken target is still a 48 dp target (U-32 gate)',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('login at 2.0×: the pair wraps into two lines rather than '
        'shrinking below the floor', (tester) async {
      await _usePhone(tester, scale: 2.0);
      await pumpLogin(tester);
      final fit = find.byType(AppShrinkToFit);
      expect(
        _appliedScale(tester, fit),
        closeTo(AppShrinkToFit.defaultFloor, 1e-9),
      );
      expect(
        link(tester, K.commonTermsOfUse).top,
        greaterThan(link(tester, K.commonPrivacyPolicy).top),
        reason: 'the second link moved to its own line',
      );
      for (final key in [K.commonPrivacyPolicy, K.commonTermsOfUse]) {
        expect(link(tester, key).height, greaterThanOrEqualTo(48 - 1e-9));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('login at 1.0× on a 320 dp phone: the pair is ONE line — the '
        'promise U-28 made', (tester) async {
      const narrow = Size(320, 640);
      await tester.binding.setSurfaceSize(narrow);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      tester.view.physicalSize = narrow;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await pumpLogin(tester);
      expect(
        link(tester, K.commonTermsOfUse).top,
        closeTo(link(tester, K.commonPrivacyPolicy).top, 1e-6),
        reason: 'both links on the same line at the default scale',
      );
      expect(tester.takeException(), isNull);
    });
  });
}
