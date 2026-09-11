/// U-27 — the single place in the app where a colour is spelled out.
///
/// The port carried 100% of the rules and ~0% of the visual layer: 79 `Color(`
/// literals across 13 files, the same `0xFF991B1B` decided over and over. This
/// file replaces all of them, and `no_color_literal_test` fails the build when
/// a new one appears anywhere else — without that gate the literals grow back.
///
/// Three decisions from the item shape what is here:
///
/// * **Neutral, institutional identity.** Greys carry the surfaces; colour is
///   reserved for DATA (the calendar) and the primary action. This is a family
///   calendar AND a near-evidentiary record used by people in conflict — a warm
///   surface reads as condescending exactly when the stakes are highest.
/// * **Dark ships with the tokens**, not later: it is nearly free while these
///   values are being written and nearly impossible against 79 literals.
/// * **Colour is never the only vector.** Every calendar slot carries a
///   [SlotPattern] as well as a hue, so a reader with deuteranopia or
///   protanopia reads the grid from the texture.
library;

import 'package:flutter/material.dart';

/// The pattern a calendar slot paints behind its fill.
///
/// **U-28 narrowed what a texture MEANS.** U-27 gave every slot its own hatch,
/// as the non-chromatic half of a member's identity. In use that read wrong: a
/// hatched cell looks like a cell in a special state, and the owner's review
/// found the mother and the third and fourth carers all appearing "marked" for
/// no reason a reader could name.
///
/// Texture now says ONE thing — this member is not here any more (slot 0). The
/// non-chromatic vector the U-27 decision was protecting is still there and was
/// always there: **every cell prints the carer's initial**, which distinguishes
/// members with no colour vision at all. Swapped days keep their dashed amber
/// border, which is a border and not a fill, so the two signals never collide.
///
/// The unused values stay in the enum: [SlotPatternPainter] draws them all and
/// is tested for them all, and this decision is exactly the kind that gets
/// revisited.
enum SlotPattern { none, verticalHatch, diagonalHatch, backDiagonalHatch, dots }

/// A semantic colour family: the solid, the text that sits ON the solid, the
/// soft container behind a badge or banner, the text on that container, and the
/// container's border. Every badge/banner/pill in the app is one of these.
@immutable
class ToneColors {
  final Color solid;
  final Color onSolid;
  final Color container;
  final Color onContainer;
  final Color border;

  const ToneColors({
    required this.solid,
    required this.onSolid,
    required this.container,
    required this.onContainer,
    required this.border,
  });

  ToneColors lerpTo(ToneColors other, double t) => ToneColors(
        solid: Color.lerp(solid, other.solid, t)!,
        onSolid: Color.lerp(onSolid, other.onSolid, t)!,
        container: Color.lerp(container, other.container, t)!,
        onContainer: Color.lerp(onContainer, other.onContainer, t)!,
        border: Color.lerp(border, other.border, t)!,
      );
}

/// One calendar identity — a `color_slot` or the swapped day. The tone carries
/// the colour; [pattern] carries the same information without it.
@immutable
class SlotColors {
  final ToneColors tone;
  final SlotPattern pattern;

  const SlotColors({required this.tone, required this.pattern});

  SlotColors lerpTo(SlotColors other, double t) => SlotColors(
        tone: tone.lerpTo(other.tone, t),
        pattern: t < 0.5 ? pattern : other.pattern,
      );
}

/// The app's colour tokens, reachable from any widget as
/// `Theme.of(context).extension<AppTokens>()!` — or, shorter,
/// `context.tokens` ([AppTokensContext]).
@immutable
class AppTokens extends ThemeExtension<AppTokens> {
  /// The page background.
  final Color surface;

  /// Cards, sheets, inputs — the layer that sits ON [surface].
  final Color surfaceAlt;

  final Color text;
  final Color textMuted;

  /// Hairline dividers and decorative borders. Deliberately light: WCAG 1.4.11
  /// is met by the persistent field label (see `AppTheme.inputDecorationTheme`),
  /// not by a heavy grey that would make every form look like a spreadsheet.
  final Color outline;

  final ToneColors accent;
  final ToneColors neutral;
  final ToneColors success;
  final ToneColors warning;
  final ToneColors danger;
  final ToneColors info;

  /// The solid admin-mode bar (F-14) — white text on a deep red.
  final Color dangerBar;

  /// The persistent family-deletion banner (S-11): louder than [dangerBar]
  /// because it outranks it — a countdown to losing the family's whole record.
  final Color dangerBarDeep;

  /// Calendar `color_slot` 0..4. Slot 0 is the inactive/departed member: a
  /// single grey identity with vertical hatching, exactly as the web paints it
  /// — and, since U-28, the ONLY slot that carries a texture at all.
  final List<SlotColors> slots;

  /// An approved swap. Amber with a DASHED border, the web's "Trocado"
  /// convention — and the reason the rose `#E11D48` is free to be a role again.
  final SlotColors swapped;

  final Color skeletonBase;
  final Color skeletonHighlight;

  /// The onboarding spotlight dim.
  final Color scrim;

  const AppTokens({
    required this.surface,
    required this.surfaceAlt,
    required this.text,
    required this.textMuted,
    required this.outline,
    required this.accent,
    required this.neutral,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.dangerBar,
    required this.dangerBarDeep,
    required this.slots,
    required this.swapped,
    required this.skeletonBase,
    required this.skeletonHighlight,
    required this.scrim,
  });

  /// The slot's colours, with slot 0 as the fallback for anything unknown —
  /// a family that somehow carries slot 7 renders grey, never crashes.
  SlotColors slot(int? index) =>
      (index != null && index >= 0 && index < slots.length)
          ? slots[index]
          : slots[0];

  // ---------------------------------------------------------------- light ---

  static const light = AppTokens(
    surface: Color(0xFFF9FAFB),
    surfaceAlt: Color(0xFFFFFFFF),
    text: Color(0xFF111827),
    textMuted: Color(0xFF6B7280),
    outline: Color(0xFFE5E7EB),
    accent: ToneColors(
      solid: Color(0xFF4F46E5),
      onSolid: Color(0xFFFFFFFF),
      container: Color(0xFFEEF2FF),
      onContainer: Color(0xFF3730A3),
      border: Color(0xFFC7D2FE),
    ),
    neutral: ToneColors(
      solid: Color(0xFF6B7280),
      onSolid: Color(0xFFFFFFFF),
      container: Color(0xFFE5E7EB),
      onContainer: Color(0xFF374151),
      border: Color(0xFFD1D5DB),
    ),
    success: ToneColors(
      solid: Color(0xFF16A34A),
      onSolid: Color(0xFFFFFFFF),
      container: Color(0xFFECFDF5),
      onContainer: Color(0xFF065F46),
      border: Color(0xFF6EE7B7),
    ),
    // Amber takes DARK text, in both themes: white on `#D97706` measures
    // 3.18:1 — large-text only, and a banner is body text.
    warning: ToneColors(
      solid: Color(0xFFD97706),
      onSolid: Color(0xFF111827),
      container: Color(0xFFFEF3C7),
      onContainer: Color(0xFF92400E),
      border: Color(0xFFFDE68A),
    ),
    danger: ToneColors(
      solid: Color(0xFFDC2626),
      onSolid: Color(0xFFFFFFFF),
      container: Color(0xFFFEE2E2),
      onContainer: Color(0xFF991B1B),
      border: Color(0xFFFECACA),
    ),
    info: ToneColors(
      solid: Color(0xFF2563EB),
      onSolid: Color(0xFFFFFFFF),
      container: Color(0xFFDBEAFE),
      onContainer: Color(0xFF1E40AF),
      border: Color(0xFF93C5FD),
    ),
    dangerBar: Color(0xFFB91C1C),
    dangerBarDeep: Color(0xFF7F1D1D),
    slots: [
      // 0 — inactive / departed / unknown.
      SlotColors(
        tone: ToneColors(
          solid: Color(0xFF9CA3AF),
          onSolid: Color(0xFFFFFFFF),
          container: Color(0xFFF3F4F6),
          onContainer: Color(0xFF6B7280),
          border: Color(0xFFD1D5DB),
        ),
        pattern: SlotPattern.verticalHatch,
      ),
      // 1 — blue. The web's slot 1, kept because that pair (with slot 2) was
      // chosen to survive deuteranopia and protanopia.
      SlotColors(
        tone: ToneColors(
          solid: Color(0xFF1D4ED8),
          onSolid: Color(0xFFFFFFFF),
          container: Color(0xFFDBEAFE),
          onContainer: Color(0xFF1E3A8A),
          border: Color(0xFF93C5FD),
        ),
        pattern: SlotPattern.none,
      ),
      // 2 — rose.
      SlotColors(
        tone: ToneColors(
          solid: Color(0xFFE11D48),
          onSolid: Color(0xFFFFFFFF),
          container: Color(0xFFFFE4E6),
          onContainer: Color(0xFF881337),
          border: Color(0xFFFDA4AF),
        ),
        pattern: SlotPattern.none,
      ),
      // 3 — teal.
      SlotColors(
        tone: ToneColors(
          solid: Color(0xFF0F766E),
          onSolid: Color(0xFFFFFFFF),
          container: Color(0xFFCCFBF1),
          onContainer: Color(0xFF115E59),
          border: Color(0xFF5EEAD4),
        ),
        pattern: SlotPattern.none,
      ),
      // 4 — orange (the web moved it off purple: too close to slot 1 in
      // pastels, and it has to stay distinct from the swapped amber too).
      //
      // U-28 QA: deepened TWO steps, container and border. At `#FFEDD5` the
      // third carer's cell measured 1.03:1 against the `#FEF3C7` swapped day —
      // a lighter version of the swap key rather than a colour of its own,
      // which is what the owner saw as the third carer losing the standing the
      // web gives them. `#FDBA74` takes that separation to 1.51:1 and still
      // holds `#7C2D12` text at 5.6:1, well clear of the 4.5 the norm asks.
      // One step further (`#FCA35C`) would buy 1.79:1 at 4.7:1 text — too
      // little margin for a product that also renders this in dark mode.
      SlotColors(
        tone: ToneColors(
          solid: Color(0xFFEA580C),
          onSolid: Color(0xFFFFFFFF),
          container: Color(0xFFFDBA74),
          onContainer: Color(0xFF7C2D12),
          border: Color(0xFFF97316),
        ),
        pattern: SlotPattern.none,
      ),
    ],
    swapped: SlotColors(
      tone: ToneColors(
        solid: Color(0xFFD97706),
        onSolid: Color(0xFF111827),
        container: Color(0xFFFEF3C7),
        onContainer: Color(0xFF92400E),
        border: Color(0xFFF59E0B),
      ),
      pattern: SlotPattern.none,
    ),
    skeletonBase: Color(0xFFE5E7EB),
    skeletonHighlight: Color(0xFFF3F4F6),
    scrim: Color(0xB3000000),
  );

  // ----------------------------------------------------------------- dark ---

  static const dark = AppTokens(
    surface: Color(0xFF111827),
    surfaceAlt: Color(0xFF1F2937),
    text: Color(0xFFF9FAFB),
    textMuted: Color(0xFF9CA3AF),
    outline: Color(0xFF374151),
    // The brand indigo LIGHTENS here and nowhere else: `#4F46E5` on `#111827`
    // measures 2.3:1, so keeping the light value would make every accented
    // label unreadable. Same hue, readable tone — the identity survives, which
    // is what "the brand colour lives in one place" was protecting.
    accent: ToneColors(
      solid: Color(0xFF818CF8),
      onSolid: Color(0xFF111827),
      container: Color(0xFF312E81),
      onContainer: Color(0xFFC7D2FE),
      border: Color(0xFF4F46E5),
    ),
    neutral: ToneColors(
      solid: Color(0xFF9CA3AF),
      onSolid: Color(0xFF111827),
      container: Color(0xFF374151),
      onContainer: Color(0xFFE5E7EB),
      border: Color(0xFF4B5563),
    ),
    success: ToneColors(
      solid: Color(0xFF22C55E),
      onSolid: Color(0xFF111827),
      container: Color(0xFF064E3B),
      onContainer: Color(0xFFA7F3D0),
      border: Color(0xFF047857),
    ),
    warning: ToneColors(
      solid: Color(0xFFF59E0B),
      onSolid: Color(0xFF111827),
      container: Color(0xFF452F0C),
      onContainer: Color(0xFFFDE68A),
      border: Color(0xFFB45309),
    ),
    danger: ToneColors(
      solid: Color(0xFFEF4444),
      onSolid: Color(0xFF111827),
      container: Color(0xFF4C1D1D),
      onContainer: Color(0xFFFECACA),
      border: Color(0xFFB91C1C),
    ),
    info: ToneColors(
      solid: Color(0xFF3B82F6),
      onSolid: Color(0xFF111827),
      container: Color(0xFF1E3A5F),
      onContainer: Color(0xFFBFDBFE),
      border: Color(0xFF2563EB),
    ),
    // The two solid bars keep WHITE text in dark: a red light enough to carry
    // dark text would read as an error state, not as a mode.
    dangerBar: Color(0xFF991B1B),
    dangerBarDeep: Color(0xFF7F1D1D),
    slots: [
      SlotColors(
        tone: ToneColors(
          solid: Color(0xFF6B7280),
          onSolid: Color(0xFFF9FAFB),
          container: Color(0xFF273244),
          onContainer: Color(0xFF9CA3AF),
          border: Color(0xFF4B5563),
        ),
        pattern: SlotPattern.verticalHatch,
      ),
      SlotColors(
        tone: ToneColors(
          solid: Color(0xFF3B82F6),
          onSolid: Color(0xFF111827),
          container: Color(0xFF1E3A5F),
          onContainer: Color(0xFFBFDBFE),
          border: Color(0xFF2563EB),
        ),
        pattern: SlotPattern.none,
      ),
      SlotColors(
        tone: ToneColors(
          solid: Color(0xFFFB7185),
          onSolid: Color(0xFF111827),
          container: Color(0xFF4C1D2B),
          onContainer: Color(0xFFFECDD3),
          border: Color(0xFFE11D48),
        ),
        pattern: SlotPattern.none,
      ),
      SlotColors(
        tone: ToneColors(
          solid: Color(0xFF2DD4BF),
          onSolid: Color(0xFF111827),
          container: Color(0xFF134E4A),
          onContainer: Color(0xFF99F6E4),
          border: Color(0xFF0D9488),
        ),
        pattern: SlotPattern.none,
      ),
      SlotColors(
        tone: ToneColors(
          solid: Color(0xFFFB923C),
          onSolid: Color(0xFF111827),
          // U-28 QA, the dark half of the same decision: lifted away from the
          // `#452F0C` swapped container it used to sit almost on top of.
          container: Color(0xFF5C2A10),
          onContainer: Color(0xFFFED7AA),
          border: Color(0xFFF97316),
        ),
        pattern: SlotPattern.none,
      ),
    ],
    swapped: SlotColors(
      tone: ToneColors(
        solid: Color(0xFFF59E0B),
        onSolid: Color(0xFF111827),
        container: Color(0xFF452F0C),
        onContainer: Color(0xFFFDE68A),
        border: Color(0xFFD97706),
      ),
      pattern: SlotPattern.none,
    ),
    skeletonBase: Color(0xFF374151),
    skeletonHighlight: Color(0xFF4B5563),
    scrim: Color(0xB3000000),
  );

  @override
  AppTokens copyWith({
    Color? surface,
    Color? surfaceAlt,
    Color? text,
    Color? textMuted,
    Color? outline,
    ToneColors? accent,
    ToneColors? neutral,
    ToneColors? success,
    ToneColors? warning,
    ToneColors? danger,
    ToneColors? info,
    Color? dangerBar,
    Color? dangerBarDeep,
    List<SlotColors>? slots,
    SlotColors? swapped,
    Color? skeletonBase,
    Color? skeletonHighlight,
    Color? scrim,
  }) =>
      AppTokens(
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        text: text ?? this.text,
        textMuted: textMuted ?? this.textMuted,
        outline: outline ?? this.outline,
        accent: accent ?? this.accent,
        neutral: neutral ?? this.neutral,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        info: info ?? this.info,
        dangerBar: dangerBar ?? this.dangerBar,
        dangerBarDeep: dangerBarDeep ?? this.dangerBarDeep,
        slots: slots ?? this.slots,
        swapped: swapped ?? this.swapped,
        skeletonBase: skeletonBase ?? this.skeletonBase,
        skeletonHighlight: skeletonHighlight ?? this.skeletonHighlight,
        scrim: scrim ?? this.scrim,
      );

  @override
  AppTokens lerp(ThemeExtension<AppTokens>? other, double t) {
    if (other is! AppTokens) return this;
    return AppTokens(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      accent: accent.lerpTo(other.accent, t),
      neutral: neutral.lerpTo(other.neutral, t),
      success: success.lerpTo(other.success, t),
      warning: warning.lerpTo(other.warning, t),
      danger: danger.lerpTo(other.danger, t),
      info: info.lerpTo(other.info, t),
      dangerBar: Color.lerp(dangerBar, other.dangerBar, t)!,
      dangerBarDeep: Color.lerp(dangerBarDeep, other.dangerBarDeep, t)!,
      slots: [
        for (var i = 0; i < slots.length; i++)
          slots[i].lerpTo(other.slots[i], t),
      ],
      swapped: swapped.lerpTo(other.swapped, t),
      skeletonBase: Color.lerp(skeletonBase, other.skeletonBase, t)!,
      skeletonHighlight:
          Color.lerp(skeletonHighlight, other.skeletonHighlight, t)!,
      scrim: Color.lerp(scrim, other.scrim, t)!,
    );
  }
}

/// `context.tokens` — the whole point of the extension is that reaching a
/// colour must be shorter than writing one.
extension AppTokensContext on BuildContext {
  AppTokens get tokens => Theme.of(this).extension<AppTokens>() ?? AppTokens.light;
}

/// The 4-point spacing scale. Every gap in the app is one of these five.
abstract final class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

/// Corner radii. `none` is not decoration — the calendar's dividers depend on
/// square cells.
abstract final class Radii {
  static const double none = 0;
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 16;
}

/// Elevation is scarce on purpose: surfaces are bordered, not floated.
abstract final class Elevations {
  static const double flat = 0;
  static const double appBar = 1;
  static const double bottomNav = 2;
  static const double sheet = 3;
}

/// Motion. Three durations, three curves — anything else is decoration.
abstract final class Motion {
  /// Micro-interactions: a press, a toggle, a colour change.
  static const micro = Duration(milliseconds: 150);
  static const microCurve = Curves.easeOut;

  /// Sheets and segmented buttons.
  static const sheet = Duration(milliseconds: 300);
  static const sheetCurve = Curves.easeInOut;

  /// Page transitions and the admin banner.
  static const page = Duration(milliseconds: 400);
  static const pageCurve = Curves.fastOutSlowIn;

  /// One sweep of the skeleton shimmer.
  static const skeleton = Duration(milliseconds: 1500);
  static const skeletonCurve = Curves.easeInOutSine;
}

/// The type scale. Sizes and weights live here so a screen never invents one.
abstract final class TypeScale {
  static const double display = 32;
  static const double title = 20;
  static const double subtitle = 16;
  static const double body = 16;
  static const double bodySmall = 14;
  static const double label = 12;
}

/// The widest the app ever draws itself.
///
/// The product is phone-shaped, and the web channel inherits a promise the
/// Blazor PWA always kept: pages lived in a centred column
/// (`.page-container { max-width: 500px }`), never edge to edge. 600 instead of
/// 500 by owner decision (23/08/2026) — the calendar carries seven columns and
/// breathes better with the extra hundred. On a phone the constraint never
/// binds, so this changes nothing on the store channel.
const double maxAppWidth = 600;

/// U-45 — the "Sign in with Google" button's own spec.
///
/// This is a THIRD PARTY's design, not part of this design system: the values
/// below are Google's *Sign in with Google* branding guidelines, measured
/// against the official `signin-assets.zip` (the 40 dp "Square" button, @4x),
/// and they are the one thing on screen that must NOT follow our tokens. They
/// never lerp with the theme, they are not tinted, and the light/dark pair is
/// chosen by [Brightness] alone — the guideline names those two surfaces and
/// no other. They live in this file for one reason: it is the only place a
/// colour may be spelled out, and `no_color_literal_test` is what keeps that
/// true. The mark itself ships as an IMAGE (`logoAsset`) because it may not be
/// recoloured or redrawn.
///
/// The one deliberate divergence is the typeface: the guideline asks for
/// Google Sans Medium, and the app renders the sentence in **Inter** at the
/// same 14/20 medium — registering a second font family for one button costs
/// more than it buys, and the sentence is ours (it is written in the reader's
/// language, which the pre-rendered official buttons cannot be).
abstract final class GoogleBrand {
  /// The G, 20 dp square, at 1x/2x/3x. Declared file-by-file in `pubspec.yaml`
  /// so the launcher-icon masters next to it stay out of the bundle.
  static const String logoAsset = 'assets/brand/google-g.png';

  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightStroke = Color(0xFF747775);
  static const Color lightText = Color(0xFF1F1F1F);

  static const Color darkSurface = Color(0xFF131314);
  static const Color darkStroke = Color(0xFF8E918F);
  static const Color darkText = Color(0xFFE3E3E3);

  static const double height = 40;
  static const double logoSize = 20;

  /// 12 dp before the logo and after the sentence, 10 dp between them.
  static const double padding = 12;
  static const double logoGap = 10;

  static const double strokeWidth = 1;

  /// The guideline's "Square" shape. It happens to be [Radii.sm] exactly —
  /// written as the token so the coincidence is visible rather than a second
  /// unexplained 4.
  static const double radius = Radii.sm;

  /// 14/20, medium.
  static const double fontSize = 14;
  static const double lineHeight = 20;
}
