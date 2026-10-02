/// F-80 — the family referral code, as the client may handle it.
///
/// The code is OPAQUE: ten symbols the server draws at random
/// (`referral_new_code`, migration `20261002200000_f80_referral_model.sql`)
/// from a 32-symbol alphabet with no `0`/`O` and no `1`/`I`, so it says
/// nothing about whose it is and survives being read aloud. The server is the
/// authority — it re-checks the shape with `referral_code_is_shaped` — and
/// this mirror exists so the client never sends what the server would only
/// drop: a link with a mangled `ref` simply carries no code.
///
/// The code travels in the query of the sign-up link
/// (`/register?ref=XXXXXXXXXX`). The analytics sanitizer cuts every query
/// before a pageview leaves (`sanitizeAnalyticsPath`), and no event declares a
/// prop that could carry it — the code never reaches Umami.
library;

abstract final class ReferralRules {
  /// The symbols a code is drawn from — the same 32 as the migration's
  /// `referral_new_code`, pinned by `referral_rules_test`.
  static const String alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  /// Every code has exactly this many symbols.
  static const int length = 10;

  /// The query key of the sign-up link.
  static const String queryKey = 'ref';

  /// The route a referral link opens.
  static const String registerPath = '/register';

  static final RegExp _shape = RegExp('^[$alphabet]{$length}\$');

  /// [raw] as a code the server could know, or null. Case and the spaces a
  /// person pastes around it are forgiven; anything else is not a code.
  static String? parseCode(String? raw) {
    if (raw == null) return null;
    final code = raw.trim().toUpperCase();
    return _shape.hasMatch(code) ? code : null;
  }

  /// The code a sign-up link carries, or null. Only `/register` is a referral
  /// link, and a link that ALSO carries an invitation is an invitation — the
  /// invitee joins a family that already exists, so there is no new family to
  /// attribute.
  static String? codeFromUri(Uri uri) {
    if (uri.path != registerPath) return null;
    final invite = uri.queryParameters['invite'];
    if (invite != null && invite.trim().isNotEmpty) return null;
    return parseCode(uri.queryParameters[queryKey]);
  }

  /// The `channel` the server records (its CHECK: `web` | `android`).
  static String channel({required bool isWeb}) => isWeb ? 'web' : 'android';

  /// What `attribute_referral` answered when it recorded the referral. The
  /// other answer, `ignored`, covers an unknown code and a family already
  /// attributed alike — on purpose.
  static const String attributed = 'attributed';
}
