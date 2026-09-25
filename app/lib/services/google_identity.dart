import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
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
/// **No nonce, on purpose.** `google_sign_in` 7 does not expose one, and GoTrue
/// accepts a token when neither side carries it (Fulcrum 01.8). A nonce on one
/// side only fails with "Passed nonce and nonce in id_token should either both
/// exist or not", and nothing in the app could fix that.
class GoogleIdentity {
  GoogleIdentity._();

  static Future<void>? _initialized;

  /// Initializes the plugin once per process. Lazy on purpose: on the web it
  /// loads Google's GIS script, which a page that never shows the button has
  /// no reason to fetch.
  static Future<void> ensureInitialized() {
    return _initialized ??= GoogleSignIn.instance.initialize(
      // The web client identifies the GIS button; on Android the same id is
      // the AUDIENCE the device mints the token for — `serverClientId`.
      clientId: kIsWeb ? Env.current.googleWebClientId : null,
      serverClientId: kIsWeb ? null : Env.current.googleWebClientId,
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
