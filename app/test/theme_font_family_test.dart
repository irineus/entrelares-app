// The Inter drift found during F-65 (15/09/2026): `ThemeData(fontFamily:)`
// applies the family to the theme's MERGED text theme, but every component
// theme in `app_theme.dart` was built from the RAW one, whose styles carried
// no family. A button's label replaces the inherited DefaultTextStyle with its
// own resolved `textStyle`, so a family-less style there falls back to the
// platform font (Roboto on Android, the system font on the web) while the body
// text around it renders in Inter. Nothing failed; the buttons just looked
// like someone else's app.
//
// The probe reads the style the label is PAINTED with — the RenderParagraph's
// span, which is what Text resolves after merging with every ancestor — not
// the theme's declaration, so it cannot agree with a style that never reaches
// the screen.
import 'dart:io';

import 'package:entrelares_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

const _family = 'Inter';

String? _paintedFamily(WidgetTester tester, String text) => tester
    .renderObject<RenderParagraph>(find.text(text))
    .text
    .style
    ?.fontFamily;

void main() {
  test('the theme family is the one pubspec.yaml bundles', () {
    // A family name the asset manifest does not declare is silently the
    // platform font everywhere — the same symptom, for the whole app.
    expect(AppTheme.fontFamily, _family);
    expect(
        RegExp(r'^\s*- family:\s*(\S+)\s*$', multiLine: true)
            .allMatches(File('pubspec.yaml').readAsStringSync())
            .map((m) => m.group(1)),
        contains(_family));
  });

  for (final (name, theme) in [
    ('light', AppTheme.light),
    ('dark', AppTheme.dark),
  ]) {
    group('$name theme', () {
      testWidgets('every button label is painted in Inter', (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ListView(children: [
              const Text('corpo'),
              FilledButton(onPressed: () {}, child: const Text('filled')),
              ElevatedButton(onPressed: () {}, child: const Text('elevated')),
              OutlinedButton(onPressed: () {}, child: const Text('outlined')),
              TextButton(onPressed: () {}, child: const Text('text')),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.check),
                label: const Text('filled-icon'),
              ),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('selected')),
                  ButtonSegment(value: 1, label: Text('unselected')),
                ],
                selected: const {0},
                onSelectionChanged: (_) {},
              ),
            ]),
          ),
        ));

        // Positive control: the probe sees Inter where the drift never was,
        // so a failure below is the button, not the probe.
        expect(_paintedFamily(tester, 'corpo'), _family);

        for (final label in [
          'filled',
          'elevated',
          'outlined',
          'text',
          'filled-icon',
          'selected',
          'unselected',
        ]) {
          expect(_paintedFamily(tester, label), _family,
              reason: 'the "$label" button label fell back to the platform '
                  'font — a component theme in app_theme.dart was built from '
                  'a text style that carries no fontFamily');
        }
      });

      // The same defect, one layer up: any component theme that REPLACES the
      // inherited text style (instead of merging into it) paints in the
      // platform font if its style has no family. Sweep every one the app sets.
      test('every text style a component theme declares names Inter', () {
        TextStyle? resolve(WidgetStateProperty<TextStyle?>? prop,
                [Set<WidgetState> states = const {}]) =>
            prop?.resolve(states);

        final declared = <String, TextStyle?>{
          'appBar.title': theme.appBarTheme.titleTextStyle,
          'dialog.title': theme.dialogTheme.titleTextStyle,
          'dialog.content': theme.dialogTheme.contentTextStyle,
          'navigationBar.label':
              resolve(theme.navigationBarTheme.labelTextStyle),
          'navigationBar.label.selected': resolve(
              theme.navigationBarTheme.labelTextStyle, {WidgetState.selected}),
          'input.label': theme.inputDecorationTheme.labelStyle,
          'input.floatingLabel': theme.inputDecorationTheme.floatingLabelStyle,
          'input.hint': theme.inputDecorationTheme.hintStyle,
          'input.error': theme.inputDecorationTheme.errorStyle,
          'filledButton': resolve(theme.filledButtonTheme.style?.textStyle),
          'elevatedButton': resolve(theme.elevatedButtonTheme.style?.textStyle),
          'outlinedButton': resolve(theme.outlinedButtonTheme.style?.textStyle),
          'textButton': resolve(theme.textButtonTheme.style?.textStyle),
          'segmentedButton':
              resolve(theme.segmentedButtonTheme.style?.textStyle),
          'segmentedButton.selected': resolve(
              theme.segmentedButtonTheme.style?.textStyle,
              {WidgetState.selected}),
          'chip.label': theme.chipTheme.labelStyle,
          'listTile.title': theme.listTileTheme.titleTextStyle,
          'listTile.subtitle': theme.listTileTheme.subtitleTextStyle,
          'snackBar.content': theme.snackBarTheme.contentTextStyle,
        };
        final offenders = [
          for (final MapEntry(:key, :value) in declared.entries)
            if (value == null || value.fontFamily != _family)
              '$key → ${value?.fontFamily}',
        ];
        expect(offenders, isEmpty,
            reason: 'these component text styles would paint in the platform '
                'font: $offenders');
      });
    });
  }
}
