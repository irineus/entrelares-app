// T-60 — `cupertino_icons` left the app (24/11/2026). It came with the Flutter
// project template, nothing in lib/ ever drew one of its glyphs, and all it
// did was ship a font nobody used. The trap it leaves behind is the silent
// kind: `CupertinoIcons.*` still COMPILES without the package — the class
// lives in cupertino_ui, which material_ui pulls in — but the glyph renders as
// an empty box at runtime, on Android and on the web alike, with no error.
//
// So the first `CupertinoIcons` in the app's own sources goes red here, and the
// fix is the one line this test names: put `cupertino_icons` back in
// pubspec.yaml in the same change (and delete this test).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no CupertinoIcons glyph without the cupertino_icons font', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared =
        RegExp(r'^\s+cupertino_icons:', multiLine: true).hasMatch(pubspec);

    final users = <String>[];
    for (final dir in ['lib', 'store_screenshots', 'store_ads']) {
      final root = Directory(dir);
      if (!root.existsSync()) continue;
      for (final file in root.listSync(recursive: true).whereType<File>()) {
        if (!file.path.endsWith('.dart')) continue;
        if (file.readAsStringSync().contains('CupertinoIcons.')) {
          users.add(file.path);
        }
      }
    }

    expect(declared || users.isEmpty, isTrue,
        reason: 'These files draw CupertinoIcons, but pubspec.yaml no longer '
            'ships the font, so each glyph renders as an empty box: $users. '
            'Add `cupertino_icons` back to pubspec.yaml in the same change.');
  });
}
