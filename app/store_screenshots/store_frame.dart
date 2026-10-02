// T-97 — the frame every Play phone screenshot is composed in: a caption band
// on top and the app's screen below it, inside a plain phone outline.
//
// Nothing in the phone is drawn here. [StoreFrame.app] is the app's REAL
// widget tree, pumped against a fake data source by
// `store_screenshots_test.dart`; this file only decides where it sits on the
// 1080×1920 canvas and writes the caption above it.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:entrelares_app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The canvas in logical pixels. Rendered at [canvasPixelRatio] it is Play's
/// 9∶16 phone size, 1080×1920.
const canvas = Size(360, 640);
const double canvasPixelRatio = 3;

/// The app's own screen: the phone the U-32 accessibility suite measures
/// every screen on. The frame scales it down to fit under the caption, so the
/// app lays out exactly as it does on a 360 dp phone.
const phone = Size(360, 740);

/// The caption's height on the canvas, the same on every screenshot.
const double captionBand = 160;

/// Every font the app bundle declares — Inter, the Material icons and the
/// Cupertino icons — read from the test bundle's `FontManifest.json`. Without
/// it the test host draws text as boxes and every `Icon` as a square.
Future<void> loadBundleFonts() async {
  final manifest =
      json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// What a screenshot says above the phone.
class Caption {
  final String headline;
  final String detail;

  /// The scene shows a Premium feature: the band carries the word, so no
  /// screenshot can sell a Premium feature as free.
  final bool premium;

  const Caption(this.headline, this.detail, {this.premium = false});
}

class StoreFrame extends StatelessWidget {
  final Caption caption;

  /// "Premium" in the scene's language.
  final String premiumLabel;
  final Widget app;

  const StoreFrame({
    super.key,
    required this.caption,
    required this.premiumLabel,
    required this.app,
  });

  static const _font = 'Inter';

  /// The caption band — the harness checks no line of it was cut.
  static const captionKey = Key('store-caption');

  @override
  Widget build(BuildContext context) {
    const t = AppTokens.light;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(
          size: canvas,
          devicePixelRatio: canvasPixelRatio,
        ),
        child: ColoredBox(
          color: t.accent.solid,
          child: Column(
            children: [
              // A FIXED band, so the phone is the same size and in the same
              // place on every screenshot of the set.
              SizedBox(
                key: captionKey,
                height: captionBand,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (caption.premium) ...[
                        _PremiumPill(label: premiumLabel),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        caption.headline,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          fontFamily: _font,
                          fontWeight: FontWeight.w700,
                          fontSize: 22,
                          height: 1.18,
                          color: t.accent.onSolid,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        caption.detail,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: TextStyle(
                          fontFamily: _font,
                          fontWeight: FontWeight.w500,
                          fontSize: 13.5,
                          height: 1.3,
                          color: t.accent.container,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Center(child: _Phone(app: app)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PremiumPill extends StatelessWidget {
  final String label;

  const _PremiumPill({required this.label});

  @override
  Widget build(BuildContext context) {
    final tone = AppTokens.light.warning;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tone.container,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 12, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome, size: 14, color: tone.onContainer),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: StoreFrame._font,
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: tone.onContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The phone: a dark outline with rounded corners around the app, scaled as
/// one piece to fit what the caption left.
class _Phone extends StatelessWidget {
  final Widget app;

  const _Phone({required this.app});

  static const double _bezel = 10;

  @override
  Widget build(BuildContext context) {
    const t = AppTokens.light;
    return FittedBox(
      child: Container(
        width: phone.width + 2 * _bezel,
        height: phone.height + 2 * _bezel,
        padding: const EdgeInsets.all(_bezel),
        decoration: BoxDecoration(
          color: t.text,
          borderRadius: BorderRadius.circular(44),
          boxShadow: [
            BoxShadow(
              color: t.scrim.withValues(alpha: 0.35),
              blurRadius: 30,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(34),
          child: SizedBox.fromSize(
            size: phone,
            child: MediaQuery(
              data: const MediaQueryData(
                size: phone,
                devicePixelRatio: canvasPixelRatio,
              ),
              child: app,
            ),
          ),
        ),
      ),
    );
  }
}

/// Sets the test view to the canvas, so the frame lays out at 360×640.
Future<void> useCanvas(WidgetTester tester) async {
  tester.view.physicalSize = canvas * canvasPixelRatio;
  tester.view.devicePixelRatio = canvasPixelRatio;
  addTearDown(tester.view.reset);
}

/// Writes what is under [boundary] as a 1080×1920 PNG at [path].
Future<void> capture(WidgetTester tester, GlobalKey boundary, String path) =>
    tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: canvasPixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final file = File(path)..parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
