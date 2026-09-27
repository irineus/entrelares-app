import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:google_sign_in/google_sign_in.dart';

import '../env.dart';

/// F-71 (Fulcrum 02.3) — the ONE place the app talks to `google_sign_in`.
///
/// Its only product is an ID token for [Env.googleWebClientId]; exchanging it
/// for a session (`signInWithIdToken`) is `main.dart`'s, beside the password
/// door, so the Supabase client stays where it already was.
///
/// **Two platforms, two shapes.** Android asks Credential Manager
/// interactively ([idTokenFromDevice]). The web cannot: GIS only hands a
/// credential to its OWN button, so the button is Google's (`renderButton`,
/// owner's decision) and its tokens arrive on [webIdTokens].
///
/// **A nonce on BOTH sides.** GoTrue refuses a token when only one side
/// carries a nonce ("Passed nonce and nonce in id_token should either both
/// exist or not"), and the web's GIS button, in FedCM mode, mints tokens WITH
/// one even when the app asks for none — that is how every Google sign-in on
/// web.entrelares.app failed from 25/09 to 27/09/2026 (the "no nonce" of
/// Fulcrum 01.8 held only on paper). So the app makes one per process: Google
/// stamps [_hashedNonce] into the token (`initialize(nonce:)`, which
/// `google_sign_in` 7.2 does expose), and [rawNonce] goes to
/// `signInWithIdToken`, where GoTrue hashes it and compares.
class GoogleIdentity {
  GoogleIdentity._();

  static Future<void>? _initialized;

  /// The value GoTrue receives. Per process, like [_initialized]: the plugin
  /// takes the nonce once, at initialization, so every token this process
  /// mints carries the same one.
  static final String rawNonce = _newRawNonce();

  /// What Google writes into the token's `nonce` claim: SHA-256 of [rawNonce],
  /// lowercase hex — the exact form GoTrue computes before comparing.
  @visibleForTesting
  static String get hashedNonce =>
      sha256.convert(utf8.encode(rawNonce)).toString();

  static String _newRawNonce() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  /// Initializes the plugin once per process. Lazy on purpose: on the web it
  /// loads Google's GIS script, which a page that never shows the button has
  /// no reason to fetch.
  static Future<void> ensureInitialized() {
    return _initialized ??= GoogleSignIn.instance.initialize(
      // The web client identifies the GIS button; on Android the same id is
      // the AUDIENCE the device mints the token for — `serverClientId`.
      clientId: kIsWeb ? Env.current.googleWebClientId : null,
      serverClientId: kIsWeb ? null : Env.current.googleWebClientId,
      nonce: hashedNonce,
    );
  }

  /// Android: the interactive account picker. `null` when the person backed
  /// out — that is a choice, not an error, and nobody should be told off for
  /// it. Any other failure is thrown for the button to report.
  static Future<String?> idTokenFromDevice() async {
    await ensureInitialized();
    final GoogleSignInAccount account;
    try {
      account = await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (isBackOut(e.code)) return null;
      rethrow;
    }
    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw StateError('Google returned no ID token');
    }
    return idToken;
  }

  /// Whether a failure is the person closing the picker rather than a fault.
  static bool isBackOut(GoogleSignInExceptionCode code) =>
      code == GoogleSignInExceptionCode.canceled ||
      code == GoogleSignInExceptionCode.interrupted;

  /// Web: every ID token the GIS button produces. Listening does NOT load the
  /// SDK — the stream exists before [ensureInitialized] — so a screen may
  /// subscribe while the button is still deciding whether to render.
  static Stream<String> webIdTokens() => GoogleSignIn
      .instance.authenticationEvents
      .where((e) => e is GoogleSignInAuthenticationEventSignIn)
      .map((e) =>
          (e as GoogleSignInAuthenticationEventSignIn)
              .user
              .authentication
              .idToken ??
          '')
      .where((token) => token.isNotEmpty);
}
