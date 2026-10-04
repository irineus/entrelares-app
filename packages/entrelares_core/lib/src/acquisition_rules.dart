/// T-101 — where a new family came from, as the client decides it.
///
/// The first real cohort (L-31, owner 04/10/2026) is bought with ads and
/// counted WITHOUT a pixel: the source is recorded on our side, once, when the
/// family is created (`families.acquisition_source`, migration
/// `20261004120000_t101_acquisition_source.sql`). The client reads the signal
/// the existing doors already carry — the Play Install Referrer on Android
/// (F-80's channel), the `/register` query on the web — and hands the server
/// ONE word of a closed vocabulary plus an optional short campaign token. The
/// server re-checks both (an unknown word becomes `unknown`, a misshaped token
/// is dropped), so this rule only decides; it never grants anything.
///
/// Precedence, the same on both doors:
///   1. a referral code (`ref`) of the right shape → `referral`;
///   2. an ad signal — Google Ads auto-tagging (`gclid` / `gbraid`) on an
///      install, or one of OUR source words (`utm_source` on the Play
///      referrer, `src` on the web link) → that source;
///   3. no signal at all (or only an organic marker Play or our own pages
///      write) → `organic`;
///   4. a signal that is present but none of the above → `unknown`.
///
/// Nothing here reaches analytics: the pageview path drops the query
/// (`sanitizeAnalyticsPath`) and no event declares a prop for the source.
library;

import 'referral_rules.dart';

/// The answer: a word of [AcquisitionRules.sources] and, maybe, a campaign.
final class Acquisition {
  const Acquisition(this.source, [this.campaign]);

  final String source;

  /// A short token of our own campaign naming (`primeira-turma`), already
  /// shaped by [AcquisitionRules.campaignToken]; null when there is none.
  final String? campaign;

  static const Acquisition organic = Acquisition(AcquisitionRules.organic);
  static const Acquisition unknown = Acquisition(AcquisitionRules.unknown);
  static const Acquisition referral = Acquisition(AcquisitionRules.referral);

  @override
  bool operator ==(Object other) =>
      other is Acquisition &&
      other.source == source &&
      other.campaign == campaign;

  @override
  int get hashCode => Object.hash(source, campaign);

  @override
  String toString() => 'Acquisition($source, $campaign)';
}

abstract final class AcquisitionRules {
  static const String googleApp = 'google_app';
  static const String googleSearch = 'google_search';
  static const String meta = 'meta';
  static const String referral = 'referral';
  static const String organic = 'organic';
  static const String unknown = 'unknown';

  /// The closed vocabulary — the migration's CHECK, pinned by
  /// `acquisition_rules_test`.
  static const List<String> sources = [
    googleApp,
    googleSearch,
    meta,
    referral,
    organic,
    unknown,
  ];

  /// The words OUR ads put on a link (`utm_source` on the Play referrer,
  /// `src` on the web link). `referral`, `organic` and `unknown` are verdicts
  /// of this rule, never something a link may claim.
  static const Set<String> adSources = {googleApp, googleSearch, meta};

  /// The web link's query keys: `/register?src=meta&cmp=primeira-turma`.
  static const String sourceQueryKey = 'src';
  static const String campaignQueryKey = 'cmp';

  /// The sign-up metadata keys the e-mail founder sends (stripped by the
  /// server before the auth row is stored, like F-80's).
  static const String sourceMetadataKey = 'acquisition_source';
  static const String campaignMetadataKey = 'acquisition_campaign';

  /// What Play and our own pages write on an install that no ad bought:
  /// Play's organic default (`utm_source=google-play&utm_medium=organic`), the
  /// `(not set)` Play reports for a listing opened with no referrer, and the
  /// F-72 / F-80 links from our own app and landing.
  static const Set<String> organicMarkers = {
    'google-play',
    '(not set)',
    'not set',
    'entrelares.app',
    'web.entrelares.app',
  };

  static final RegExp _campaign = RegExp(r'^[a-z0-9][a-z0-9_-]{0,39}$');

  /// [raw] as a campaign token the server keeps, or null: lower case, 1–40
  /// symbols of `a-z 0-9 _ -`, starting with a letter or digit. Anything else
  /// (a space, an accent, a URL, an e-mail) is no campaign — the token is our
  /// own naming, never free text a stranger could put in a family's row.
  static String? campaignToken(String? raw) {
    if (raw == null) return null;
    final token = raw.trim().toLowerCase();
    return _campaign.hasMatch(token) ? token : null;
  }

  /// The source a Play Install Referrer string carries. The string is the
  /// listing's `referrer` value as Play stored it — `key=value&…`, each part
  /// URL-encoded (Google's Install Referrer API, `getInstallReferrer()`); an
  /// install bought by a Google Ads app campaign carries the click id
  /// `gclid` (or the privacy-preserving `gbraid`) — Google's
  /// *Privacy-compliant app attribution* guide reads it from this same field.
  /// A string encoded once more (`utm_source%3D…`) is unwrapped once, the
  /// F-80 way. Never throws.
  static Acquisition fromInstallReferrer(String? referrer) {
    if (referrer == null) return Acquisition.organic;
    var raw = referrer.trim();
    if (raw.isEmpty) return Acquisition.organic;
    final Map<String, String> params;
    try {
      if (!raw.contains('=') && raw.toLowerCase().contains('%3d')) {
        raw = Uri.decodeComponent(raw);
      }
      if (!raw.contains('=')) return Acquisition.unknown;
      params = Uri.splitQueryString(raw);
    } catch (_) {
      return Acquisition.unknown;
    }

    final campaign = campaignToken(params['utm_campaign']);
    final ref = params[ReferralRules.queryKey];
    if (ReferralRules.parseCode(ref) != null) return Acquisition.referral;

    if (_present(params['gclid']) || _present(params['gbraid'])) {
      return Acquisition(googleApp, campaign);
    }

    final source = params['utm_source']?.trim().toLowerCase();
    final medium = params['utm_medium']?.trim().toLowerCase();
    if (source != null && adSources.contains(source)) {
      return Acquisition(source, campaign);
    }
    // Google Ads with auto-tagging off still names itself.
    if (source == 'google' && (medium == 'cpc' || medium == 'paid')) {
      return Acquisition(googleApp, campaign);
    }
    if (_present(ref)) return Acquisition.unknown;
    if (source == null || source.isEmpty || organicMarkers.contains(source)) {
      return Acquisition.organic;
    }
    return Acquisition.unknown;
  }

  /// The source a web sign-up link carries. Only `/register` speaks for a
  /// founder; an invitation link is an invitee joining a family that exists,
  /// so it carries no source (null — nothing to record).
  static Acquisition? fromUri(Uri uri) {
    if (uri.path != ReferralRules.registerPath) return null;
    final invite = uri.queryParameters['invite'];
    if (invite != null && invite.trim().isNotEmpty) return null;
    return fromLink(
      ref: uri.queryParameters[ReferralRules.queryKey],
      src: uri.queryParameters[sourceQueryKey],
      campaign: uri.queryParameters[campaignQueryKey],
    );
  }

  /// The precedence over the web link's three values.
  static Acquisition fromLink({String? ref, String? src, String? campaign}) {
    if (ReferralRules.parseCode(ref) != null) return Acquisition.referral;
    final source = src?.trim().toLowerCase();
    if (source != null && adSources.contains(source)) {
      return Acquisition(source, campaignToken(campaign));
    }
    if (_present(ref) || _present(src)) return Acquisition.unknown;
    return Acquisition.organic;
  }

  static bool _present(String? value) =>
      value != null && value.trim().isNotEmpty;
}
