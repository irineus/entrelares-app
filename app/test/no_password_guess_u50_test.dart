// U-50 — "has a password" is the server's answer, and nothing in the client
// may grow a second opinion.
//
// The provider list (`app_metadata.providers`) was read as that answer twice:
// by the sudo sheet until S-21, and by the profile screen until this item.
// Production carries the counter-proof (providers `google` alone, and a
// password), so the list names DOORS and nothing else. This scan keeps it that
// way: the session's providers have ONE reader, the profile's door list, and
// the `email` provider name is compared in ONE place, the core rule that maps
// a provider to a row — where the server's answer, not the name, decides
// whether the password row exists (pinned by `sign_in_methods_test`).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Iterable<File> _dartFiles(String root) => Directory(root)
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

String _relative(File f) => f.path.replaceAll('\\', '/');

void main() {
  test('the session providers have one reader: the profile door list', () {
    final readers = [
      for (final file in _dartFiles('lib'))
        if (RegExp(r'\.authProviders\(\)').hasMatch(file.readAsStringSync()))
          _relative(file),
    ];
    expect(readers, ['lib/screens/profile_screen.dart'],
        reason: 'a new reader of the provider list is one step from deciding '
            'something by it — ask `sessionHasPassword()` (U-50) or let the '
            'server decide (S-21)');
  });

  test('no screen or service spells the "providers contain email" guess', () {
    final guess = RegExp(
        r'''providers[^;\n]*\.(contains|any|where)\([^)]*['"]email['"]''');
    final offenders = [
      for (final root in ['lib', '../packages/entrelares_core/lib'])
        for (final file in _dartFiles(root))
          if (guess.hasMatch(file.readAsStringSync())) _relative(file),
    ];
    expect(offenders, isEmpty);
  });
}
