import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:entrelares_app/services/google_identity.dart';
import 'package:flutter_test/flutter_test.dart';

/// 27/09/2026 — every Google sign-in on web.entrelares.app answered 400
/// "Passed nonce and nonce in id_token should either both exist or not": the
/// GIS button (FedCM) mints tokens WITH a nonce and the app sent none. GoTrue
/// accepts the pair only when it carries both halves, in this exact relation.
void main() {
  test('Google gets the SHA-256 hex of the nonce GoTrue receives', () {
    final raw = GoogleIdentity.rawNonce;
    expect(raw.length, greaterThanOrEqualTo(32),
        reason: 'a guessable nonce protects nothing');
    expect(GoogleIdentity.hashedNonce,
        sha256.convert(utf8.encode(raw)).toString(),
        reason: 'GoTrue hashes the raw value and compares it, as lowercase '
            'hex, with the token claim');
    expect(GoogleIdentity.hashedNonce, isNot(raw));
  });

  test('the nonce is the same for the whole process', () {
    // The plugin takes it once, at initialize(); a second value would make
    // every token after the first fail the comparison.
    expect(GoogleIdentity.rawNonce, GoogleIdentity.rawNonce);
  });

  test('both halves are wired: initialize() and signInWithIdToken', () {
    final identity =
        File('lib/services/google_identity.dart').readAsStringSync();
    expect(identity, contains('nonce: hashedNonce'),
        reason: 'without it Google mints the token with no nonce, or its own');
    final main = File('lib/main.dart').readAsStringSync();
    expect(main, contains('nonce: GoogleIdentity.rawNonce'),
        reason: 'without it GoTrue sees a nonce in the token only — the 400 '
            'of 27/09/2026');
  });
}
