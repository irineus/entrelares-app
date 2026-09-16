// U-31's gate, cut to the same pattern as `no_color_literal_test`: the closed
// alpha (09/09/2026) read the interface as homemade, and the owner chose the
// strict rule on 16/09/2026 — NO emoji in the text this app writes. A mark
// that says something is a vector icon placed by the call site; an emoji at
// the end of a sentence is simply gone. The convention had existed for weeks
// as a code comment in `frozen_day_sheet.dart`, and the screenshot that
// started the item broke it twice. A rule nothing checks is a rule that
// grows back.
//
// What the gate does NOT cover, on purpose: a family's own data. A custom
// role's emoji (F-41, `roles.emoji`) is chosen by the family, like the role's
// name that the catalog refuses to translate, and it renders wherever the
// role renders. The palette the editor offers lives in core
// (`CustomRoleRules.emojiPalette`), outside every path scanned here.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A pictograph, a dingbat mark (✓ ✕ ✉ ✨), a clock (⌛ ⏰ ⏳), ℹ, the
/// full-width plus the create button once carried, or the emoji
/// presentation selector. Arrows are NOT in the set: `de → para` is the
/// audit diff's typography, not a mark.
final _emoji = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
  r'\u{231A}-\u{23FF}\u{2139}\u{FE0F}\u{FF0B}]',
  unicode: true,
);

/// The part of a line a reader could ever see: comments may name a glyph
/// ("the ✕ closes the sheet"), code may not. A `//` inside an open string
/// literal is kept as code.
String _codeOf(String line) {
  var single = 0;
  var double = 0;
  for (var i = 0; i < line.length - 1; i++) {
    final c = line[i];
    if (c == "'" && double.isEven) single++;
    if (c == '"' && single.isEven) double++;
    if (c == '/' && line[i + 1] == '/' && single.isEven && double.isEven) {
      return line.substring(0, i);
    }
  }
  return line;
}

List<String> _offendersIn(Iterable<File> files) {
  final offenders = <String>[];
  for (final file in files) {
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final code = _codeOf(lines[i]);
      if (_emoji.hasMatch(code)) {
        offenders.add('${file.path}:${i + 1}: ${code.trim()}');
      }
    }
  }
  return offenders;
}

Iterable<File> _appSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

/// The words every screen renders, in both languages.
const _catalogs = [
  '../packages/entrelares_core/lib/src/localization/strings_pt_br.dart',
  '../packages/entrelares_core/lib/src/localization/strings_en.dart',
];

/// Every Edge Function source: the push catalog (`_shared/push.ts`, held
/// string for string against the Dart one by the F-09 mirror), the e-mail
/// copy (`_shared/i18n.ts`), the e-mail layout's wordmark, and whatever the
/// next function writes to a lock screen or an inbox (U-31 PR 2).
Iterable<File> _functionSources() => Directory('../supabase/functions')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.ts'));

void main() {
  test('no emoji in the app\'s own code', () {
    expect(_offendersIn(_appSources()), isEmpty,
        reason: 'U-31: a mark is a vector Icon placed by the call site, and a '
            'sentence carries no emoji at all.');
  });

  test('no emoji in the catalogs the screens render', () {
    final files = [for (final path in _catalogs) File(path)];
    for (final file in files) {
      expect(file.existsSync(), isTrue,
          reason: '${file.path} moved — the gate would pass over nothing');
    }
    expect(_offendersIn(files), isEmpty,
        reason: 'U-31: the catalog owns the WORDS; an icon, when the line '
            'needs one, is placed by the widget that renders it.');
  });

  test('no emoji in what the server writes to a lock screen or an inbox', () {
    final files = _functionSources().toList();
    expect(
        files.map((f) => f.path.replaceAll(r'\', '/')),
        containsAll([
          endsWith('_shared/push.ts'),
          endsWith('_shared/i18n.ts'),
          endsWith('_shared/email_layout.ts'),
        ]),
        reason: 'the function tree moved — the gate would pass over nothing');
    expect(_offendersIn(files), isEmpty,
        reason: 'U-31: a push title, an e-mail subject and an e-mail heading '
            'are sentences too, and a sentence carries no emoji.');
  });

  // A scanner pointed at nothing would make the gates above pass forever.
  test('the scanner finds the glyphs it is looking for', () {
    const palette =
        '../packages/entrelares_core/lib/src/custom_role_rules.dart';
    expect(_offendersIn([File(palette)]), isNotEmpty,
        reason: 'The F-41 palette is made of emoji; if the scanner sees none '
            'there it would see none anywhere.');
    for (final glyph in ['✅', '⚠️', '🔔', '⏰', '✉️', '✨', '✓', '✕', '＋']) {
      expect(_emoji.hasMatch(glyph), isTrue, reason: glyph);
    }
    expect(_emoji.hasMatch('de → para'), isFalse);
    expect(_codeOf("  // the ✕ closes the sheet"), '  ');
    expect(_codeOf("  text: 'a // b ✕',"), "  text: 'a // b ✕',");
  });
}
