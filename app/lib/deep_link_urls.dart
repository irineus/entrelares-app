import 'package:entrelares_core/entrelares_core.dart';

import 'env.dart';

/// The App Links surface — `https://web.entrelares.app` is the PRODUCT's web
/// origin (the Blazor PWA today, Flutter Web after the cutover; the apex
/// `entrelares.app` is the landing). It already serves
/// `.well-known/assetlinks.json` for the store shell (F-54); the lote-1 PR in
/// `entrelares-app` adds the dev flavor's statement. Recovery e-mails point
/// here for BOTH flavors: on a device with this app installed and the domain
/// verified, Android opens the app; anywhere else the link degrades
/// gracefully to the web page. The dev Supabase project must allow this URL
/// in its auth redirect allowlist.
abstract final class DeepLinkUrls {
  static const String webOrigin = 'https://web.entrelares.app';
  static const String updatePassword = '$webOrigin/update-password';

  /// The recovery landing, carrying the language of the SCREEN the reset was
  /// asked from (U-13, `AuthMail.languageQueryParam`). The plain constant
  /// above stays as the route's identity — this is what a `resetPasswordForEmail`
  /// call must send, and the mirror test asserts both call sites use it.
  static String updatePasswordFor(AppLanguage language) =>
      '$updatePassword?${AuthMail.languageQueryParam}=${language.code}';

  /// Where GoTrue sends the founder's confirmation e-mail. It lands on the web
  /// sign-in page by design: the account is not usable until the link is
  /// clicked, and that click happens in whatever mail client the person uses,
  /// often on another device.
  static const String login = '$webOrigin/login';

  /// F-57 — where GoTrue sends the OAuth redirect back on ANDROID. A custom
  /// scheme, not an App Link, and per FLAVOR on purpose:
  ///
  /// * custom scheme, because the OAuth round-trip happens inside a browser
  ///   custom tab, and an `https` App Link on a server-side redirect is the
  ///   handoff Android is historically flaky about — when it fails, the tab
  ///   consumes the PKCE code against a verifier only the APP holds and the
  ///   user strands on the web login. A scheme intent filter has no
  ///   verification step to lose.
  /// * per flavor (the scheme IS the `applicationId`), because both flavors
  ///   coexist on the owner's device — one shared scheme would open a chooser
  ///   and could hand dev's code to prod. The manifest registers it via the
  ///   `${applicationId}` placeholder, so the two cannot drift.
  ///
  /// Each Supabase project's Redirect URLs allowlist must carry ITS flavor's
  /// value (runbook §9-ter). On web this is unused: the page redirects to its
  /// own origin.
  static String get oauthCallback =>
      '${Env.current.androidPackage}://login-callback';

  /// The LANDING's origin. Legal pages live there, and that is not a detail of
  /// taste: `webOrigin` is the address changing hands in the cutover, and this
  /// app has no `/privacy` route of its own (lote 4: one copy of the legal
  /// text, opened in the browser). Pointed at `webOrigin`, these links worked
  /// only for as long as the BLAZOR app answered there — the moment the domain
  /// moved they would land on this app, which has nothing to show, and the
  /// policy would become unreachable from inside the product. The landing is a
  /// separate stack that is not moving.
  static const String landingOrigin = 'https://entrelares.app';
  static const String privacy = '$landingOrigin/privacidade';
  static const String terms = '$landingOrigin/termos';
}
