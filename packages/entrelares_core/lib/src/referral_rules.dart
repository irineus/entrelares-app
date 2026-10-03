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

  // ── F-80 PR 2: the Android door (Install Referrer) and the shared link ──

  /// The campaign the Play Console groups referral installs under. The
  /// `utm_*` keys are what the Console reads into its acquisition report;
  /// the code rides in [queryKey] (`ref`) and NOT in `utm_content` on
  /// purpose — a `utm_*` value becomes a dimension in Google's report, and a
  /// per-family code has no business being one there.
  static const String installCampaign =
      'utm_source=entrelares.app&utm_medium=referral'
      '&utm_campaign=family-referral';

  /// The value of the Play listing's `referrer` parameter for [code] — what
  /// the landing's `/i/<code>` page will put on the listing link it sends an
  /// Android reader to (`PlayInstallRules.listingUri(…, referrer: …)`). Play
  /// hands this string back, verbatim, to the installed app through the
  /// Install Referrer API, where [codeFromInstallReferrer] reads it.
  static String installReferrer(String code) =>
      '$installCampaign&$queryKey=$code';

  /// The code an Install Referrer string carries, or null. The string is the
  /// listing's `referrer` value as Play stored it: `key=value&…`, each part
  /// URL-encoded. Only `ref` is read (see [installCampaign] for why not
  /// `utm_content`); an organic install (`utm_source=google-play&
  /// utm_medium=organic`) carries none. A referrer that arrives encoded once
  /// more (`ref%3D…`, as some link builders double-encode) is unwrapped once.
  /// Anything malformed is simply no code — this never throws.
  static String? codeFromInstallReferrer(String? referrer) {
    if (referrer == null) return null;
    var raw = referrer.trim();
    if (raw.isEmpty) return null;
    try {
      if (!raw.contains('=') && raw.toLowerCase().contains('%3d')) {
        raw = Uri.decodeComponent(raw);
      }
      return parseCode(Uri.splitQueryString(raw)[queryKey]);
    } catch (_) {
      return null;
    }
  }

  /// The origin of the family's shareable link — the LANDING, not the app:
  /// one link for every reader, which the landing routes (web sign-up with
  /// `?ref=`, or the Play listing with [installReferrer] for Android).
  static const String shareOrigin = 'https://entrelares.app';

  /// The path prefix of the shareable link.
  static const String sharePathPrefix = '/i/';

  /// The link the Família card shows and shares. NOTE (02/10/2026): the
  /// landing serves `/i/<code>` only from the flip delivery on — while the
  /// module is dark no card shows it, so nobody can follow it early.
  static String shareLink(String code) => '$shareOrigin$sharePathPrefix$code';

  /// The `channel` the server records (its CHECK: `web` | `android`).
  static String channel({required bool isWeb}) => isWeb ? 'web' : 'android';

  /// What `attribute_referral` answered when it recorded the referral. The
  /// other answer, `ignored`, covers an unknown code and a family already
  /// attributed alike — on purpose.
  static const String attributed = 'attributed';
}
