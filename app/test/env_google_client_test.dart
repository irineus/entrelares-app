// F-71 (Fulcrum 02.3) — the Google Web client each flavour mints its ID token
// for. A dev build holding the production id (or the reverse) asks Google for a
// token whose audience the OTHER project's GoTrue does not list, and the refusal
// says nothing about why — so the pairing is pinned here, not left to review.
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/env.dart';

void main() {
  test('each flavour names its OWN project\'s Web client', () {
    // The client lives in the same Cloud project as the flavour's push, so its
    // numeric prefix IS that project's number — the sender id beside it.
    for (final env in const [Env.dev, Env.prod]) {
      expect(env.googleWebClientId,
          startsWith('${env.webPush.messagingSenderId}-'),
          reason: '${env.name}: the client must come from the same project');
      expect(env.googleWebClientId, endsWith('.apps.googleusercontent.com'));
    }
    expect(Env.dev.googleWebClientId, isNot(Env.prod.googleWebClientId));
  });

  test('both flavours exchange an ID token (F-71 PR 2)', () {
    // PR 1 turned dev on; PR 2 turned production on. PR 3 removes the switch
    // together with the redirect it guarded.
    expect(Env.dev.nativeGoogleSignIn, isTrue);
    expect(Env.prod.nativeGoogleSignIn, isTrue);
  });
}
