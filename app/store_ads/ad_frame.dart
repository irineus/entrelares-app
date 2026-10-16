// T-102 — the frame every ad image is composed in: the angle's words and the
// app's REAL screen, at each placement size Google and Meta ask for.
//
// Like T-97's `store_frame.dart`, nothing in the phone is drawn here: the
// phone holds the app's real widget tree, pumped against the fictional demo
// family by `store_ads_test.dart`. This file only decides where the words and
// the phone sit on a canvas of the format's proportion, every colour a
// `tokens.dart` token.
import 'package:entrelares_app/theme/tokens.dart';
import 'package:flutter/material.dart';

import '../store_screenshots/store_frame.dart' show phone;

/// One placement size. The canvas is laid out in logical pixels at
/// [pixelRatio] 3, so a 1200 px wide image is 400 logical pixels wide.
class AdFormat {
  final String network;
  final int width;
  final int height;

  const AdFormat(this.network, this.width, this.height);

  static const double pixelRatio = 3;

  Size get logical => Size(width / pixelRatio, height / pixelRatio);
  String get name => '${width}x$height';

  bool get landscape => width / height > 1.4;

  /// Meta's Stories/Reels draw their own bars over the top and bottom of a
  /// 9:16 image; the words keep out of those bands.
  bool get tall => height / width > 1.6;
}

/// Google app campaign (landscape, square, portrait) and Meta (square, 4:5,
/// 9:16) — the sizes the T-102 card fixes.
const adFormats = [
  AdFormat('google', 1200, 628),
  AdFormat('google', 1200, 1200),
  AdFormat('google', 1200, 1500),
  AdFormat('meta', 1080, 1080),
  AdFormat('meta', 1080, 1350),
  AdFormat('meta', 1080, 1920),
];

/// What an ad says beside the phone.
class AdWords {
  final String headline;
  final String detail;

  const AdWords(this.headline, this.detail);
}

/// The brand line and the call to action every image carries. True of the
/// product (S-15): the essentials are free, with no end date.
const adBrand = 'Entrelares';
const adCallToAction = 'Comece grátis';

class AdFrame extends StatelessWidget {
  final AdFormat format;
  final AdWords words;

  /// The app's screen, or null for the closing card of the video.
  final Widget? app;

  const AdFrame({
    super.key,
    required this.format,
    required this.words,
    this.app,
  });

  static const _font = 'Inter';

  /// The words block — the harness checks no line of it was cut.
  static const wordsKey = Key('ad-words');

  @override
  Widget build(BuildContext context) {
    const t = AppTokens.light;
    final size = format.logical;
    final phoneWidget = app == null ? null : _Phone(app: app!);
    final Widget body;
    if (format.landscape) {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 14, 14),
        child: Row(
          children: [
            Expanded(child: _Words(words: words, scale: 0.86)),
            if (phoneWidget != null) ...[
              const SizedBox(width: 12),
              SizedBox(height: size.height - 28, child: phoneWidget),
            ],
          ],
        ),
      );
    } else {
      final top = format.tall ? size.height * 0.13 : 18.0;
      final bottom = format.tall ? size.height * 0.12 : 14.0;
      body = Padding(
        padding: EdgeInsets.fromLTRB(20, top, 20, bottom),
        child: phoneWidget == null
            ? Center(child: _Words(words: words, scale: 1.25, centered: true))
            : Column(
                children: [
                  // Square and 4:5 leave the phone less room than 9:16, so
                  // their words run a step smaller.
                  _Words(
                    words: words,
                    scale: format.tall
                        ? 1
                        : format.height / format.width < 1.1
                        ? 0.78
                        : 0.88,
                    centered: true,
                  ),
                  SizedBox(height: format.tall ? 18 : 12),
                  Expanded(child: Center(child: phoneWidget)),
                ],
              ),
      );
    }
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: AdFormat.pixelRatio,
        ),
        child: SizedBox.fromSize(
          size: size,
          child: ColoredBox(color: t.accent.solid, child: body),
        ),
      ),
    );
  }
}

class _Words extends StatelessWidget {
  final AdWords words;
  final double scale;
  final bool centered;

  const _Words({required this.words, required this.scale, this.centered = false});

  @override
  Widget build(BuildContext context) {
    const t = AppTokens.light;
    final align = centered ? TextAlign.center : TextAlign.start;
    return Column(
      key: AdFrame.wordsKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          adBrand,
          textAlign: align,
          maxLines: 1,
          style: TextStyle(
            fontFamily: AdFrame._font,
            fontWeight: FontWeight.w700,
            fontSize: 13 * scale,
            letterSpacing: 0.4,
            color: t.accent.container,
          ),
        ),
        SizedBox(height: 6 * scale),
        Text(
          words.headline,
          textAlign: align,
          maxLines: 3,
          style: TextStyle(
            fontFamily: AdFrame._font,
            fontWeight: FontWeight.w700,
            fontSize: 24 * scale,
            height: 1.15,
            color: t.accent.onSolid,
          ),
        ),
        SizedBox(height: 8 * scale),
        Text(
          words.detail,
          textAlign: align,
          maxLines: 3,
          style: TextStyle(
            fontFamily: AdFrame._font,
            fontWeight: FontWeight.w500,
            fontSize: 13.5 * scale,
            height: 1.3,
            color: t.accent.container,
          ),
        ),
        SizedBox(height: 12 * scale),
        DecoratedBox(
          decoration: BoxDecoration(
            color: t.accent.onSolid,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 16 * scale,
              vertical: 7 * scale,
            ),
            child: Text(
              adCallToAction,
              maxLines: 1,
              style: TextStyle(
                fontFamily: AdFrame._font,
                fontWeight: FontWeight.w700,
                fontSize: 13.5 * scale,
                color: t.accent.solid,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The phone: T-97's outline around the app, scaled as one piece to fit.
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
                devicePixelRatio: AdFormat.pixelRatio,
              ),
              child: app,
            ),
          ),
        ),
      ),
    );
  }
}
