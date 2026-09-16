/// U-26 — the e-mail layer keeps its dark-mode rules, or the build goes red.
///
/// The defect this guards was reported from the closed alpha with a screenshot:
/// the invitation's near-black (#212529) header band and "Criar minha conta"
/// button vanished on a mail client in dark theme. A dark client repaints the
/// light surfaces and leaves a near-black one alone, so the button ended up
/// black on black. And the same fix had three homes, because every sender
/// (`send-swap-email`, `send-account-email`, `send-auth-email`) wrote its own
/// HTML — the one with no fallback behind it carried exactly the failing button.
///
/// Since U-26 every e-mail is built from `_shared/email_layout.ts`. Nothing in
/// the Flutter lane covers it: U-27's `no_color_literal_test` reads `lib/` only,
/// the templates are Deno, and the core lane cannot run Deno. So this suite
/// reads the SOURCE, the way the mirrors next door do, and refuses:
///
///   * a style anywhere but the layout's literal `S` table;
///   * a style that does not set BOTH `color` and `background-color`, a pair
///     under WCAG AA (4.5:1), or a dark surface;
///   * a table cell without `bgcolor`, or a fix that leans on
///     `prefers-color-scheme` (Gmail ignores it);
///   * a sender that stops composing from the layer, or writes its own markup.
///
/// What it cannot see is a real mail client. The manual matrix on the card
/// (Gmail Android dark, Gmail web, Apple Mail on iPhone, light) is the proof;
/// this is what keeps that proof from rotting.
library;

import 'dart:math' as math;

import 'package:test/test.dart';

import 'mirrors/repo_files.dart';

const _layoutPath = 'supabase/functions/_shared/email_layout.ts';

const _senders = [
  'supabase/functions/send-swap-email/index.ts',
  'supabase/functions/send-account-email/index.ts',
  'supabase/functions/send-auth-email/index.ts',
];

/// WCAG AA for body text. Every pair in the layer clears it, headings included,
/// so no size exception has to be reasoned about per entry.
const _minContrast = 4.5;

/// A surface darker than this is the defect's shape. `#212529` measures ~0.017;
/// the brand indigo under the call to action measures ~0.12.
const _minSurfaceLuminance = 0.05;

final _hex = RegExp(r'#[0-9a-fA-F]{6}\b|#[0-9a-fA-F]{3}\b');

/// The source without its comments, so the prose that NAMES the old colours
/// (and explains why they left) is not read as code.
String _code(String source) => source
    .split('\n')
    .where((line) {
      final t = line.trimLeft();
      return !(t.startsWith('//') || t.startsWith('*') || t.startsWith('/**'));
    })
    .join('\n');

/// The entries of a `const NAME = { key: "value", … } as const;` block.
Map<String, String> _literalTable(String source, String name) {
  final start = source.indexOf('const $name = {');
  if (start == -1) {
    throw StateError('`const $name = {` not found in $_layoutPath.');
  }
  final end = source.indexOf('} as const;', start);
  final block = source.substring(start, end);
  return {
    for (final m in RegExp(r'^\s*(\w+):\s*"([^"]*)",?\s*$', multiLine: true)
        .allMatches(block))
      m.group(1)!: m.group(2)!,
  };
}

String? _property(String style, String property) {
  // `(^|;)` so `color` never matches the tail of `background-color`.
  final m = RegExp('(?:^|;)$property:(#[0-9a-fA-F]{6})\\b').firstMatch(style);
  return m?.group(1);
}

double _luminance(String hex) {
  final v = int.parse(hex.substring(1), radix: 16);
  double channel(int c) {
    final s = c / 255;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel((v >> 16) & 0xFF) +
      0.7152 * channel((v >> 8) & 0xFF) +
      0.0722 * channel(v & 0xFF);
}

double _contrast(String a, String b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final layout = repoFile(_layoutPath);
  final layoutCode = _code(layout);
  final styles = _literalTable(layout, 'S');
  final surfaces = _literalTable(layout, 'BG');

  group('U-26 · the style table', () {
    // Without this, a renamed table would make every loop below pass over an
    // empty map — the failure mode the mirror family exists to prevent.
    test('is actually being read', () {
      expect(styles.length, greaterThanOrEqualTo(20));
      expect(surfaces.length, greaterThanOrEqualTo(4));
      expect(styles.keys, containsAll(['button', 'body', 'headingNeutral', 'code']));
    });

    test('every style sets BOTH color and background-color, as literal hex', () {
      for (final MapEntry(:key, :value) in styles.entries) {
        expect(_property(value, 'color'), isNotNull,
            reason: 'S.$key sets no `color:#rrggbb`. Text on an inherited colour '
                'is what a dark client repaints out of sight: $value');
        expect(_property(value, 'background-color'), isNotNull,
            reason: 'S.$key sets no `background-color:#rrggbb`. What vanishes '
                'in dark mode is text on an INHERITED background: $value');
        expect(value, isNot(contains('background:')),
            reason: 'S.$key uses the `background` shorthand; the guard (and '
                'some clients) read `background-color` only: $value');
      }
    });

    test('every pair of text and background clears WCAG AA', () {
      for (final MapEntry(:key, :value) in styles.entries) {
        final fg = _property(value, 'color')!;
        final bg = _property(value, 'background-color')!;
        expect(_contrast(fg, bg), greaterThanOrEqualTo(_minContrast),
            reason: 'S.$key: $fg on $bg measures '
                '${_contrast(fg, bg).toStringAsFixed(2)}:1, under AA. The old '
                'footnote greys (#9ca3af, #868e96) failed exactly here.');
      }
    });

    test('no surface is dark — the shape of the U-26 defect', () {
      final all = {
        for (final MapEntry(:key, :value) in styles.entries)
          'S.$key': _property(value, 'background-color')!,
        for (final MapEntry(:key, :value) in surfaces.entries) 'BG.$key': value,
      };
      for (final MapEntry(:key, :value) in all.entries) {
        expect(_luminance(value), greaterThanOrEqualTo(_minSurfaceLuminance),
            reason: '$key paints $value, a near-black surface. A dark client '
                'leaves it alone and darkens everything around it — the '
                'invitation button that disappeared was #212529.');
      }
    });

    test('every bgcolor attribute value is a background the table declares', () {
      final declared = styles.values.map((s) => _property(s, 'background-color')).toSet();
      for (final MapEntry(:key, :value) in surfaces.entries) {
        expect(declared, contains(value),
            reason: 'BG.$key ($value) matches no `background-color` in S — the '
                'attribute and the style of one cell would disagree.');
      }
    });
  });

  group('U-26 · the layout markup', () {
    test('every style attribute is one entry of the table, never inline', () {
      final attributes = RegExp(r'style="([^"]*)"').allMatches(layoutCode).toList();
      expect(attributes, isNotEmpty);
      for (final m in attributes) {
        expect(m.group(1), matches(RegExp(r'^\$\{[^}]+\}$')),
            reason: 'an inline style in the layout bypasses the table the '
                'guard checks: ${m.group(0)}');
      }
    });

    test('no colour literal lives outside the two tables', () {
      final start = layoutCode.indexOf('const S = {');
      final end = layoutCode.indexOf('} as const;', layoutCode.indexOf('const BG = {'));
      final outside = layoutCode.substring(0, start) + layoutCode.substring(end);
      expect(_hex.allMatches(outside).map((m) => m.group(0)), isEmpty);
    });

    test('every table cell carries bgcolor', () {
      final cells = RegExp(r'<td\b[^>]*>').allMatches(layoutCode).toList();
      expect(cells, isNotEmpty);
      for (final m in cells) {
        expect(m.group(0), contains('bgcolor='),
            reason: 'a cell without bgcolor loses its surface in the clients '
                'that strip styles: ${m.group(0)}');
      }
    });

    test('nothing depends on prefers-color-scheme', () {
      expect(layoutCode, isNot(contains('prefers-color-scheme')),
          reason: 'Gmail ignores the query and applies its own inversion — a '
              'fix that needs it is a fix for one client.');
    });
  });

  group('U-26 · the senders compose from the layer', () {
    for (final path in _senders) {
      test(path, () {
        final code = _code(repoFile(path));
        expect(code, contains('from "../_shared/email_layout.ts"'),
            reason: '$path no longer imports the shared e-mail layer.');
        expect(code, isNot(contains('style=')),
            reason: '$path writes its own style again — the fix would have '
                'to land in more than one place, which is how U-26 happened.');
        expect(code, isNot(contains('bgcolor')));
        expect(_hex.allMatches(code).map((m) => m.group(0)), isEmpty,
            reason: '$path carries a colour literal.');
        // Inline emphasis (`<strong>`, `<br/>`) is text; anything that could
        // carry a surface or a colour belongs to the layer.
        expect(
            RegExp(r'<(p|h[1-6]|a|div|span|table|tr|td|ul|ol|li|body|html)\b')
                .allMatches(code)
                .map((m) => m.group(0)),
            isEmpty,
            reason: '$path writes structural markup of its own.');
      });
    }

    test('the e-mail catalogue carries no style either', () {
      final catalogue = i18nSource();
      expect(catalogue, isNot(contains('style=')));
      expect(catalogue, isNot(contains('bgcolor')));
    });
  });
}
