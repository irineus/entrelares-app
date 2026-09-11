// Port of the web's `NoToast_CarriesALiteralString` gate (LocalizationTests):
// snack text must come from the catalog — a literal reads in Portuguese to an
// English session. The gate was deliberately deferred until the first snack
// helper existed (see localization_test in core); this delivery brings both.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A `showAppSnack(<ctx>, '...')` / `"..."` call — the message argument
/// starting as a string literal. dotAll so a line break between the arguments
/// hides nothing.
final _literalCall =
    RegExp('showAppSnack\\(\\s*[\\w.]+\\s*,\\s*[\'"]', dotAll: true);

final _anyCall = RegExp(r'showAppSnack\(');

/// Every Dart source of the app package, minus the helper's own declaration.
Iterable<File> appSources() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .where((f) => !f.path.endsWith('app_snack.dart'));

void main() {
  test('no snack carries a literal string', () {
    final offenders = <String>[];
    for (final file in appSources()) {
      final content = file.readAsStringSync();
      for (final match in _literalCall.allMatches(content)) {
        final line =
            '\n'.allMatches(content.substring(0, match.start)).length + 1;
        offenders.add('${file.path}:$line');
      }
    }
    expect(offenders, isEmpty,
        reason: 'Snack text written as a literal — an English session reads '
            'it in Portuguese: $offenders');
  });

  // A scanner that matched nothing would make the gate above pass forever.
  test('the snack scanner reads real call sites', () {
    final found = appSources()
        .any((f) => _anyCall.hasMatch(f.readAsStringSync()));
    expect(found, isTrue,
        reason: 'No showAppSnack call found at all — the literal gate would '
            'be vacuous.');
  });
}
