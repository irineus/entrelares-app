// F-71 (Fulcrum 02.3) — the Google door is native only. The browser redirect
// (`signInWithOAuth` → `GET /auth/v1/authorize`) is answered 410 behind the
// Fulcrum gateway (BLOCK_OAUTH_REDIRECT), and even unblocked it is a top-level
// navigation with no `apikey` → 401. A stray call would fail in production the
// day the app points at `api.entrelares.app`, so it is refused here, in the
// source, where the gateway's own 410 would only catch it after shipping.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no OAuth redirect anywhere in lib/', () {
    final hits = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (code.contains('signInWithOAuth') ||
            code.contains('getOAuthSignInUrl') ||
            code.contains('/auth/v1/authorize')) {
          hits.add('${file.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(hits, isEmpty,
        reason: 'Google sign-in goes through signInWithIdToken only '
            '(GoogleIdentity + main.dart). The redirect is 410 behind the '
            'Fulcrum gateway.');
  });

  test('the native exchange is still there (the gate must not pass on empty)',
      () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('signInWithIdToken'));
    expect(File('lib/services/google_identity.dart').existsSync(), isTrue);
  });
}
