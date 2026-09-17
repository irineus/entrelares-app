// U-48 — the type floor. No text a screen paints reads under 11 sp, and the
// three places that do are EXCEPTIONS the owner kept on 17/09/2026, each with
// its measured reason, pinned here by name so a fourth cannot join them
// quietly and none of the three can drift lower.
//
// Cut to the same pattern as `no_color_literal_test`: a source scan over
// `lib/` for the literal a screen would write, plus a walk over the theme
// and the two typographic tables that carry sizes by another name.
import 'dart:io';

import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The floor: 11 logical pixels, scaled by the reader's setting.
const double floor = 11;

/// `fontSize: <number>` written inline. The regex reads the number, not the
/// line, so a `fontSize: TypeScale.label` (a token) is not a match and a
/// `fontSize: 9` is.
final _fontSizeLiteral = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)\b');

/// The PDF is a PRINT document set in Roboto in points (F-33): 8.5–10 pt in
/// a table on paper is the convention there, and nothing on a screen reads
/// it. The only file under `lib/` the scan does not read.
const _pdfFile = 'services/report_pdf.dart';

Iterable<File> _appSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.replaceAll('\\', '/').endsWith(_pdfFile));

List<String> _offenders(Iterable<File> files) {
  final out = <String>[];
  for (final file in files) {
    final content = file.readAsStringSync();
    for (final m in _fontSizeLiteral.allMatches(content)) {
      final size = double.parse(m.group(1)!);
      if (size >= floor) continue;
      final line = '\n'.allMatches(content.substring(0, m.start)).length + 1;
      out.add('${file.path}:$line (fontSize: ${m.group(1)})');
    }
  }
  return out;
}

void main() {
  test('no inline fontSize under 11 in lib/ (the PDF excepted)', () {
    expect(
      _offenders(_appSources()),
      isEmpty,
      reason:
          'a screen wrote text under the 11 sp floor. The three '
          'exceptions the owner kept are below, by name; anything else '
          'is a token or a wrap, never a smaller font.',
    );
  });

  // A scanner pointed at nothing would make the gate above pass forever:
  // the PDF is the one file that DOES carry sizes under the floor, so it is
  // the proof the regex reads what it claims to.
  test('the scanner reads the sizes it excludes on purpose', () {
    final pdf = File('lib/$_pdfFile');
    expect(pdf.existsSync(), isTrue);
    expect(
      _offenders([pdf]),
      isNotEmpty,
      reason:
          'the PDF no longer carries a fontSize under 11 — drop the '
          'exclusion, the gate can read it now',
    );
  });

  test('every theme text style is at or above the floor, in both themes', () {
    for (final (name, theme) in [
      ('light', AppTheme.light),
      ('dark', AppTheme.dark),
    ]) {
      final t = theme.textTheme;
      final styles = <String, TextStyle?>{
        'displayLarge': t.displayLarge,
        'displayMedium': t.displayMedium,
        'displaySmall': t.displaySmall,
        'headlineLarge': t.headlineLarge,
        'headlineMedium': t.headlineMedium,
        'headlineSmall': t.headlineSmall,
        'titleLarge': t.titleLarge,
        'titleMedium': t.titleMedium,
        'titleSmall': t.titleSmall,
        'bodyLarge': t.bodyLarge,
        'bodyMedium': t.bodyMedium,
        'bodySmall': t.bodySmall,
        'labelLarge': t.labelLarge,
        'labelMedium': t.labelMedium,
        'labelSmall': t.labelSmall,
      };
      var named = 0;
      for (final entry in styles.entries) {
        // The theme names the styles the screens use (U-27); a slot it
        // leaves null falls back to Material's own, which is never under 11.
        final size = entry.value?.fontSize;
        if (size == null) continue;
        named++;
        expect(
          size,
          greaterThanOrEqualTo(floor),
          reason: '$name ${entry.key} is $size, under the floor',
        );
      }
      expect(
        named,
        greaterThanOrEqualTo(10),
        reason:
            '$name: the theme stopped naming its styles — the walk '
            'above read almost nothing',
      );
    }
    expect(TypeScale.label, greaterThanOrEqualTo(floor));
  });

  // The other way a screen turns the reader's font DOWN: a FittedBox that
  // scales a line to fit with no floor. The four sites are AppShrinkToFit
  // now (0.85× floor, then wrap or ellipsis); a fifth would be a regression.
  test('no FittedBox.scaleDown in lib/ — a one-liner that must fit uses '
      'AppShrinkToFit', () {
    final scaleDown = RegExp(r'BoxFit\.scaleDown');
    final offenders = <String>[];
    for (final file in _appSources()) {
      final content = file.readAsStringSync();
      for (final m in scaleDown.allMatches(content)) {
        final line = '\n'.allMatches(content.substring(0, m.start)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'a shrink with no floor undoes the reader\'s font setting '
          'silently (U-48); wrap it in AppShrinkToFit instead: $offenders',
    );
  });

  // ── The three exceptions, by name ──────────────────────────────────────
  //
  // Owner, 17/09/2026: all three STAY. The gate pins them at exactly what
  // was measured, so a change in either direction is a decision, not a
  // drift — lower is a regression, higher wants the card that re-measures
  // the cell (A, B) or the circle (C).

  test('exception A — the day cell\'s compact step keeps the U-28 floor: '
      'initial 9, time 9', () {
    // A cell under 60 dp at the reader's scale (a six-week month on a small
    // phone, the admin strip on): 50 dp holds number 12 + avatar r9 with a
    // 9 px initial + a 9 px time, and nothing larger. U-39 measured it.
    expect(DayCellType.compact.initial, 9);
    expect(DayCellType.compact.time, 9);
    expect(DayCellType.compact.number, greaterThanOrEqualTo(floor));
  });

  test('exception B — the comfortable step steps only the TIME down, to the '
      'compact size, where the reader\'s language does not fit', () {
    // "12:00 PM" at 11 px does not fit the ~41 dp inside a phone cell's
    // today ring (U-39, owner 16/09/2026): the time line alone falls back to
    // the compact 9 px; number, avatar and initial keep the comfortable
    // sizes. Everything comfortable is at or above the floor.
    final c = DayCellType.comfortable;
    expect(c.number, greaterThanOrEqualTo(floor));
    expect(c.initial, greaterThanOrEqualTo(floor));
    expect(c.time, greaterThanOrEqualTo(floor));
    final narrow = DayCellType.resolve(
      width: 41,
      height: 76,
      scale: 1,
      timeWidth: (size) => size * 4.2,
    );
    expect(
      narrow.number,
      c.number,
      reason: 'the number keeps the comfortable step',
    );
    expect(
      narrow.time,
      DayCellType.compact.time,
      reason: 'only the time line steps down, and only to the compact size',
    );
  });

  test('exception C — AppAvatar\'s initials are 0.7 × radius, and no call '
      'site goes under radius 14 (9.8 px)', () {
    final controls = File('lib/widgets/ui/controls.dart').readAsStringSync();
    expect(
      controls,
      contains('fontSize: radius * 0.7'),
      reason: 'the formula moved — re-read exception C',
    );
    final callSites = RegExp(
      r'AppAvatar\((?:[^()]|\([^()]*\))*?radius:\s*(\d+(?:\.\d+)?)',
    );
    final under = <String>[];
    for (final file in _appSources()) {
      final content = file.readAsStringSync();
      for (final m in callSites.allMatches(content)) {
        final radius = double.parse(m.group(1)!);
        if (radius * 0.7 < 9.8 - 1e-9) {
          under.add('${file.path}: radius $radius → ${radius * 0.7} px');
        }
      }
    }
    expect(
      under,
      isEmpty,
      reason:
          'an AppAvatar smaller than the account button\'s r14 '
          '(initials at 9.8 px) — the exception covers 14, not less',
    );
    // And the exception is real: at least one r14 exists.
    final r14 = _appSources().any(
      (f) => callSites
          .allMatches(f.readAsStringSync())
          .any((m) => m.group(1) == '14'),
    );
    expect(
      r14,
      isTrue,
      reason: 'no AppAvatar at r14 any more — exception C can be retired',
    );
  });
}
