/// U-27 — the two `ThemeData`s, built by hand from [AppTokens].
///
/// `ColorScheme.fromSeed` is NOT used, and that is a decision, not an
/// omission: seeding from the brand indigo bleeds it into every grey and
/// destroys the neutrality the identity is built on. Both schemes are spelled
/// out slot by slot from the tokens instead.
library;

import 'package:flutter/material.dart';

import 'tokens.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(AppTokens.light, Brightness.light);
  static ThemeData get dark => _build(AppTokens.dark, Brightness.dark);

  static ThemeData _build(AppTokens t, Brightness brightness) {
    final scheme = _scheme(t, brightness);
    final textTheme = _textTheme(t);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [t],
      // Inter, subset to the four weights the scale uses. `fontFamily` alone
      // covers everything the app draws; Material's own surfaces inherit it.
      fontFamily: 'Inter',
      scaffoldBackgroundColor: t.surface,
      canvasColor: t.surface,
      textTheme: textTheme,
      hintColor: t.textMuted,
      dividerColor: t.outline,
      dividerTheme: DividerThemeData(color: t.outline, space: 1, thickness: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: t.surfaceAlt,
        foregroundColor: t.text,
        surfaceTintColor: Colors.transparent,
        elevation: Elevations.flat,
        scrolledUnderElevation: Elevations.appBar,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: t.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        elevation: Elevations.flat,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          side: BorderSide(color: t.outline),
        ),
      ),
      // Bordered surfaces, not floated ones: elevation is reserved for the
      // few layers that genuinely sit above the page.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        elevation: Elevations.sheet,
        showDragHandle: true,
        dragHandleColor: t.outline,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Radii.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        elevation: Elevations.sheet,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
      // U-28: the active destination takes the brand colour, in its icon AND
      // its label. The web's bar carried colour and the port's was uniformly
      // grey — the owner read the difference as the app having lost its life.
      // Colour lands HERE and nowhere else in the bar: one destination at a
      // time, so the greys still carry the surface and the hues stay reserved
      // for data.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.surfaceAlt,
        surfaceTintColor: Colors.transparent,
        indicatorColor: t.accent.container,
        elevation: Elevations.bottomNav,
        // U-28 QA: 64 instead of Material's 80. The calendar is a fixed grid
        // that has to fit above this bar, and 16 dp of bottom chrome is a
        // quarter of a week of calendar. The labels stay — a bar of unlabelled
        // icons is not a saving, it is a guessing game.
        height: 64,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? IconThemeData(color: t.accent.onContainer)
              : IconThemeData(color: t.textMuted),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? textTheme.labelSmall?.copyWith(
                  color: t.accent.onContainer, fontWeight: FontWeight.w600)
              : textTheme.labelSmall?.copyWith(color: t.textMuted),
        ),
      ),
      // U-27, WCAG 1.4.11: the field border stays a light hairline, and the
      // 3:1 the norm asks for is satisfied the other way it allows — a label
      // that is ALWAYS visible, never a bare placeholder that vanishes the
      // moment someone types.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surfaceAlt,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: textTheme.bodySmall?.copyWith(color: t.textMuted),
        floatingLabelStyle: textTheme.bodySmall?.copyWith(color: t.textMuted),
        hintStyle: textTheme.bodyMedium?.copyWith(color: t.textMuted),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm + Spacing.xs),
        border: _inputBorder(t.outline),
        enabledBorder: _inputBorder(t.outline),
        focusedBorder: _inputBorder(scheme.primary, width: 2),
        errorBorder: _inputBorder(t.danger.solid),
        focusedErrorBorder: _inputBorder(t.danger.solid, width: 2),
        errorStyle: textTheme.labelMedium?.copyWith(color: t.danger.onContainer),
      ),
      filledButtonTheme: FilledButtonThemeData(style: _primaryButton(textTheme)),
      elevatedButtonTheme:
          ElevatedButtonThemeData(style: _primaryButton(textTheme)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          textStyle: textTheme.labelLarge,
          side: BorderSide(color: t.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.md, vertical: Spacing.sm + Spacing.xs),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
      ),
      // U-28: the UNSELECTED segment used to inherit `colorScheme.primary`, so
      // every option read as chosen and the fill was the only difference. The
      // unselected label is muted and the selected one is bold — the control
      // now says which option is active from two vectors, not half of one.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          foregroundColor: t.textMuted,
          selectedBackgroundColor: t.accent.container,
          selectedForegroundColor: t.accent.onContainer,
          side: BorderSide(color: t.outline),
          textStyle: textTheme.labelMedium,
        ).copyWith(
          textStyle: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)
                : textTheme.labelMedium,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: t.surfaceAlt,
        side: BorderSide(color: t.outline),
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.textMuted,
        titleTextStyle: textTheme.bodyLarge,
        subtitleTextStyle: textTheme.bodySmall?.copyWith(color: t.textMuted),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: t.outline,
        circularTrackColor: t.outline,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: textTheme.bodySmall,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: t.textMuted,
        indicatorColor: scheme.primary,
        dividerColor: t.outline,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      }),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: color, width: width),
      );

  static ButtonStyle _primaryButton(TextTheme textTheme) => FilledButton.styleFrom(
        textStyle: textTheme.labelLarge,
        elevation: Elevations.flat,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm + Spacing.xs),
      );

  /// Every slot written out. The greys come from the tokens and ONLY from the
  /// tokens — no derivation, so nothing can tint them.
  static ColorScheme _scheme(AppTokens t, Brightness brightness) => ColorScheme(
        brightness: brightness,
        primary: t.accent.solid,
        onPrimary: t.accent.onSolid,
        primaryContainer: t.accent.container,
        onPrimaryContainer: t.accent.onContainer,
        secondary: t.neutral.solid,
        onSecondary: t.neutral.onSolid,
        secondaryContainer: t.neutral.container,
        onSecondaryContainer: t.neutral.onContainer,
        tertiary: t.info.solid,
        onTertiary: t.info.onSolid,
        tertiaryContainer: t.info.container,
        onTertiaryContainer: t.info.onContainer,
        error: t.danger.solid,
        onError: t.danger.onSolid,
        errorContainer: t.danger.container,
        onErrorContainer: t.danger.onContainer,
        surface: t.surface,
        onSurface: t.text,
        onSurfaceVariant: t.textMuted,
        surfaceContainerLowest: t.surfaceAlt,
        surfaceContainerLow: t.surfaceAlt,
        surfaceContainer: t.surfaceAlt,
        surfaceContainerHigh: t.surfaceAlt,
        surfaceContainerHighest: t.surfaceAlt,
        surfaceTint: Colors.transparent,
        outline: t.outline,
        outlineVariant: t.outline,
        scrim: t.scrim,
        inverseSurface: t.text,
        onInverseSurface: t.surface,
        inversePrimary: t.accent.container,
      );

  /// 32/700 · 20/600 · 16/500 · 16/400 (1.5) · 14/400 (1.4) · 12/500 uppercase.
  static TextTheme _textTheme(AppTokens t) => TextTheme(
        headlineLarge: TextStyle(
            fontSize: TypeScale.display,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: t.text),
        headlineMedium: TextStyle(
            fontSize: TypeScale.display,
            fontWeight: FontWeight.w700,
            height: 1.2,
            color: t.text),
        headlineSmall: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            height: 1.25,
            color: t.text),
        titleLarge: TextStyle(
            fontSize: TypeScale.title,
            fontWeight: FontWeight.w600,
            height: 1.3,
            color: t.text),
        titleMedium: TextStyle(
            fontSize: TypeScale.subtitle,
            fontWeight: FontWeight.w500,
            height: 1.4,
            color: t.text),
        titleSmall: TextStyle(
            fontSize: TypeScale.bodySmall,
            fontWeight: FontWeight.w600,
            height: 1.4,
            color: t.text),
        bodyLarge: TextStyle(
            fontSize: TypeScale.body,
            fontWeight: FontWeight.w400,
            height: 1.5,
            color: t.text),
        bodyMedium: TextStyle(
            fontSize: TypeScale.bodySmall,
            fontWeight: FontWeight.w400,
            height: 1.4,
            color: t.text),
        bodySmall: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 1.4,
            color: t.textMuted),
        labelLarge: TextStyle(
            fontSize: TypeScale.bodySmall,
            fontWeight: FontWeight.w600,
            height: 1.2,
            color: t.text),
        labelMedium: TextStyle(
            fontSize: TypeScale.label,
            fontWeight: FontWeight.w500,
            height: 1.3,
            color: t.text),
        labelSmall: TextStyle(
            fontSize: TypeScale.label,
            fontWeight: FontWeight.w500,
            height: 1.3,
            letterSpacing: 0.5,
            color: t.textMuted),
      );
}
