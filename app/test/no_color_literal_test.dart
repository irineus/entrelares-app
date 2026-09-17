// U-27's gate, cut to the same pattern as `no_literal_snack_test`: the visual
// layer only stays a layer if there is exactly ONE place a colour may be
// spelled out. Before this delivery there were 79 `Color(0x…)` literals across
// 13 files — the same `0xFF991B1B` decided over and over, and dark mode
// impossible because of it. Without a gate they grow back.
import 'dart:io';

import 'package:entrelares_app/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hex colour written inline: `Color(0xFF…)`.
final _colorLiteral = RegExp(r'Color\(0x');

/// The one file allowed to carry them.
const _tokenFile = 'tokens.dart';

Iterable<File> appSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.endsWith(_tokenFile));

void main() {
  test('no colour literal outside the token file', () {
    final offenders = <String>[];
    for (final file in appSources()) {
      final content = file.readAsStringSync();
      for (final match in _colorLiteral.allMatches(content)) {
        final line =
            '\n'.allMatches(content.substring(0, match.start)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }
    expect(offenders, isEmpty,
        reason: 'A colour was decided outside lib/theme/tokens.dart — it will '
            'be wrong in dark mode and it will drift: $offenders');
  });

  // A scanner pointed at nothing would make the gate above pass forever.
  test('the colour scanner reads the token file itself', () {
    final tokens = File('lib/theme/$_tokenFile');
    expect(tokens.existsSync(), isTrue);
    expect(_colorLiteral.hasMatch(tokens.readAsStringSync()), isTrue,
        reason: 'The token file carries no colour literal at all — the gate '
            'would be scanning for something that never exists.');
  });

  // U-49: the third gate. A `Card` or `Material` painted with a
  // `colorScheme` container is a component's job — three gate cards, the
  // profile's frozen notice and the onboarding strip each did it by hand,
  // and each was a banner or a tinted strip the component set already had.
  // The regex tolerates the formatter's line breaks (`Theme.of(context)`,
  // `.colorScheme`, `.surfaceContainerHighest` on three lines) and up to two
  // named arguments before `color:` (`margin:`, `key:`).
  final tintedSurface = RegExp(
    r'\b(?:Card|Material)\(\s*(?:[a-zA-Z]+:\s*(?:[^,()]|\([^()]*\))*,\s*){0,2}'
    r'color:\s*(?:Theme\.of\(context\)|theme)\s*\.\s*colorScheme\s*\.',
  );
  const componentDir = 'widgets/ui/';

  test('no Card or Material is painted with a colorScheme surface outside '
      'widgets/ui/ (U-49)', () {
    final offenders = <String>[];
    for (final file in appSources()) {
      final path = file.path.replaceAll('\\', '/');
      if (path.contains(componentDir) || path.contains('/theme/')) continue;
      final content = file.readAsStringSync();
      for (final match in tintedSurface.allMatches(content)) {
        final line =
            '\n'.allMatches(content.substring(0, match.start)).length + 1;
        offenders.add('$path:$line');
      }
    }
    expect(offenders, isEmpty,
        reason: 'A screen painted a surface by hand. A tinted block with a '
            'message is an AppBanner; a tinted strip takes a token '
            '(`context.tokens.<tone>.container`): $offenders');
  });

  test('the tinted-surface scanner recognises the shapes it retired', () {
    // The real shapes this gate replaced, verbatim — a scanner that matched
    // none of them would be green over the defect it exists for.
    const retired = [
      'Card(\n  color: Theme.of(context).colorScheme.surfaceContainerHighest,',
      'Card(\n  color: Theme.of(context)\n      .colorScheme\n'
          '      .surfaceContainerHighest,',
      'Material(\n  color: theme.colorScheme.secondaryContainer,',
      'Card(\n  margin: const EdgeInsets.only(bottom: 8),\n'
          '  color: Theme.of(context).colorScheme.errorContainer,',
    ];
    for (final sample in retired) {
      expect(tintedSurface.hasMatch(sample), isTrue, reason: sample);
    }
    // A Card whose CHILD carries a colorScheme colour is not a tinted card.
    expect(
        tintedSurface.hasMatch(
            'Card(\n  child: Icon(Icons.x, color: theme.colorScheme.error),'),
        isFalse);
  });

  group('tokens', () {
    test('both themes define every calendar slot', () {
      expect(AppTokens.light.slots.length, 5);
      expect(AppTokens.dark.slots.length, AppTokens.light.slots.length);
    });

    test('an unknown slot falls back to slot 0 instead of throwing', () {
      // A family carrying a slot the client does not know renders grey. It
      // must never crash the calendar — the DB is the authority on slots.
      expect(AppTokens.light.slot(null), AppTokens.light.slots[0]);
      expect(AppTokens.light.slot(9), AppTokens.light.slots[0]);
      expect(AppTokens.light.slot(-1), AppTokens.light.slots[0]);
      expect(AppTokens.light.slot(2), AppTokens.light.slots[2]);
    });

    test('U-28: a texture marks the departed member and nothing else', () {
      // This SUPERSEDES U-27's "a pattern per slot". Hatching every active
      // carer made the mother and the third and fourth carers look flagged for
      // something; the owner's review named it. The non-chromatic vector the
      // U-27 decision was protecting did not go away — every cell prints the
      // carer's INITIAL, which is pinned in calendar_slice_test.
      expect(AppTokens.light.slots[0].pattern, SlotPattern.verticalHatch,
          reason: 'slot 0 is the member who left — that is what a texture '
              'means now');
      for (var i = 1; i < AppTokens.light.slots.length; i++) {
        expect(AppTokens.light.slots[i].pattern, SlotPattern.none,
            reason: 'an ACTIVE carer wears colour and an initial, never a '
                'hatch (slot $i)');
      }
      expect(AppTokens.light.swapped.pattern, SlotPattern.none,
          reason: 'the swapped day is a dashed BORDER, so a fill texture '
              'would be a second signal saying the same thing');
      expect(AppTokens.dark.slots.map((s) => s.pattern).toList(),
          AppTokens.light.slots.map((s) => s.pattern).toList(),
          reason: "The texture is the slot's identity; it cannot change with "
              'the theme.');
    });

    test('the swap does not reuse a role colour', () {
      // The rose #E11D48 was the swap colour before U-27 and is a ROLE now.
      final roleSolids =
          AppTokens.light.slots.map((s) => s.tone.solid).toSet();
      expect(roleSolids.contains(AppTokens.light.swapped.tone.solid), isFalse);
    });

    test('amber carries dark text in both themes', () {
      // White on #D97706 measures 3.18:1 — large text only, and every warning
      // the app writes is body text.
      // The dark ink, in BOTH themes — an amber light enough to take white
      // text would not be amber any more.
      expect(AppTokens.light.warning.onSolid, AppTokens.light.text);
      expect(AppTokens.dark.warning.onSolid, AppTokens.light.text);
    });

    test('lerp between the themes stays well-formed', () {
      final mid = AppTokens.light.lerp(AppTokens.dark, 0.5);
      expect(mid.slots.length, AppTokens.light.slots.length);
      expect(mid.surface, isNot(AppTokens.light.surface));
    });

    testWidgets('context.tokens falls back to light with no theme extension',
        (tester) async {
      // Widget tests build screens under a bare MaterialApp. Reading a token
      // there must return the light set, never throw.
      late AppTokens seen;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          seen = context.tokens;
          return const SizedBox();
        }),
      ));
      expect(seen.surface, AppTokens.light.surface);
    });
  });
}
