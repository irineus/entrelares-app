// A control byte in source is never intended, and in a regex it is invisible
// AND silent: `vocabulary_test` carried 0x08 (BACKSPACE) where `\b` was meant
// in three patterns — "agendado" until F-67, "despesa" and "conversa" until
// 28/09/2026 — and each "nothing else says this word" loop stayed green over
// nothing, because a pattern with a backspace in it matches no catalog string.
// The likely vehicle is a tool that turns a written `\\b` into `\b` on the way
// to disk; the file looks right in any editor that hides the byte.
//
// So every Dart, TypeScript and SQL source the gates read is scanned here, in
// the cheapest lane there is. Tab, LF and CR are the only control bytes allowed.
import 'dart:io';

import 'package:test/test.dart';

import 'mirrors/repo_files.dart';

void main() {
  test('no source file carries a control byte', () {
    const roots = [
      'app/lib',
      'app/test',
      'app/integration_test',
      'app/test_driver',
      'packages',
      'supabase/functions',
      'supabase/migrations',
    ];
    const extensions = ['.dart', '.ts', '.sql'];
    final root = repoRoot().path;
    var scanned = 0;
    final offenders = <String>[];
    for (final relative in roots) {
      final dir = Directory('$root/$relative');
      if (!dir.existsSync()) {
        fail('$relative not found under $root');
      }
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final path = entity.path.replaceAll('\\', '/');
        if (path.contains('/.dart_tool/') || path.contains('/build/')) continue;
        if (!extensions.any(path.endsWith)) continue;
        scanned++;
        final bytes = entity.readAsBytesSync();
        var line = 1;
        for (final byte in bytes) {
          if (byte == 0x0a) line++;
          if (byte < 0x20 && byte != 0x09 && byte != 0x0a && byte != 0x0d) {
            offenders.add('${path.substring(root.length + 1)}:$line '
                '(0x${byte.toRadixString(16).padLeft(2, '0')})');
          }
        }
      }
    }
    // A scan that read nothing would be green over nothing — the defect this
    // file exists for.
    expect(scanned, greaterThan(100));
    expect(offenders, isEmpty);
  });
}
