/// F-68 — Help & contact: the client's half of `send-support-request`.
///
/// The SERVER decides: it validates the message, resolves the reply address of
/// a signed-in person from the account itself, and applies the limit in the
/// same transaction that records the request. Everything here exists so the
/// form can refuse a message the server would refuse without a round-trip, say
/// how many a person may send, and turn the function's answer into one outcome
/// the screen can word. The numbers are the FUNCTION's —
/// `support_constants_mirror_test` reads
/// `supabase/functions/send-support-request/index.ts` and fails when these
/// copies drift.
library;

import 'analytics_rules.dart';

/// What a message is about. [wire] is the value the function and the
/// `support_requests.category` CHECK accept; renaming one orphans nothing in
/// the database, but the function would answer `invalid_category`.
enum SupportCategory {
  question('question'),
  problem('problem'),
  suggestion('suggestion'),

  /// Goes to `privacidade@` — the LGPD channel the policy already names — and
  /// not to `suporte@`.
  privacy('privacy'),
  other('other');

  const SupportCategory(this.wire);
  final String wire;
}

/// How a send ended, as far as the screen needs to know.
enum SupportOutcome {
  sent,
  invalidMessage,
  invalidEmail,

  /// The limit refused it. The screen says when to try again, in words.
  rateLimited,

  /// Recorded, but the e-mail to the team did not go. The screen offers the
  /// mailto instead of claiming success.
  sendFailed,

  /// No request reached the server (T-18: no signal is a state).
  offline,

  failed,
}

abstract final class SupportRules {
  static const int messageMinChars = 10;
  static const int messageMaxChars = 2000;
  static const int emailMaxChars = 254;

  /// Signed out: per typed e-mail and per caller IP (owner, 21/09/2026).
  static const int anonHourlyLimit = 3;
  static const int anonDailyLimit = 10;

  /// Signed in: per profile.
  static const int memberHourlyLimit = 5;
  static const int memberDailyLimit = 20;

  /// The fallback the screen always shows beside the form.
  static const String supportEmail = 'suporte@entrelares.app';
  static const String privacyEmail = 'privacidade@entrelares.app';

  /// The mailbox a category's mailto opens.
  static String inboxFor(SupportCategory category) =>
      category == SupportCategory.privacy ? privacyEmail : supportEmail;

  /// Whether [raw] is a message the server would take — counted TRIMMED, as
  /// the function counts it.
  /// T-83: [max] is `support.message_max_chars` when the screen could read it
  /// (a signed-in person); the constant otherwise.
  static bool isValidMessage(String raw, {int max = messageMaxChars}) {
    final length = raw.trim().length;
    return length >= messageMinChars && length <= max;
  }

  /// The function's own test, deliberately loose: an address with one `@`, a
  /// dot after it, and no spaces.
  static bool isValidEmail(String raw) {
    final value = raw.trim();
    return value.length <= emailMaxChars &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value);
  }

  /// The function's answer as one outcome. [status] is the HTTP status, [error]
  /// the `error` field of the body when there is one.
  static SupportOutcome outcomeOf(int status, String? error) {
    if (status >= 200 && status < 300) return SupportOutcome.sent;
    return switch (error) {
      'invalid_message' => SupportOutcome.invalidMessage,
      'invalid_email' => SupportOutcome.invalidEmail,
      'rate_limited' => SupportOutcome.rateLimited,
      'send_failed' => SupportOutcome.sendFailed,
      _ => status == 429 ? SupportOutcome.rateLimited : SupportOutcome.failed,
    };
  }
}

/// F-68 — the technical block a support request carries when the person keeps
/// *Incluir informações técnicas* ticked. The form previews EXACTLY this map,
/// and the function keeps these five keys and drops anything else.
///
/// Coarse on purpose: an OS family and a browser family ("iOS · Safari"), never
/// a user-agent string, a model or a version — enough to reproduce a layout
/// defect, too little to fingerprint anybody. The route goes through the
/// analytics sanitizer, so an invite token or a recovery hash in the address
/// never reaches an inbox, and ids become `:id`.
abstract final class SupportDiagnostics {
  static const String channelStore = 'store';
  static const String channelWeb = 'web';

  /// The web channel opened from the Home Screen (U-51's door on an iPhone).
  static const String channelWebInstalled = 'web-installed';

  static String channel({required bool isWeb, required bool standalone}) =>
      !isWeb ? channelStore : (standalone ? channelWebInstalled : channelWeb);

  /// "OS · browser" from a web user agent, or the OS alone for the native app
  /// ([nativeOs] = Flutter's target platform name, e.g. `android`).
  static String platformLabel({String? userAgent, String? nativeOs}) {
    if (userAgent == null || userAgent.isEmpty) {
      return switch ((nativeOs ?? '').toLowerCase()) {
        'android' => 'Android',
        'ios' => 'iOS',
        _ => nativeOs == null || nativeOs.isEmpty ? '—' : nativeOs,
      };
    }
    final ua = userAgent;
    final os = ua.contains('iPhone') || ua.contains('iPad')
        ? 'iOS'
        : ua.contains('Android')
            ? 'Android'
            : ua.contains('CrOS')
                ? 'ChromeOS'
                : ua.contains('Windows')
                    ? 'Windows'
                    : ua.contains('Macintosh')
                        ? 'macOS'
                        : ua.contains('Linux')
                            ? 'Linux'
                            : null;
    final browser = ua.contains('Edg/') || ua.contains('EdgiOS')
        ? 'Edge'
        : ua.contains('SamsungBrowser')
            ? 'Samsung Internet'
            : ua.contains('Firefox/') || ua.contains('FxiOS')
                ? 'Firefox'
                : ua.contains('CriOS') || ua.contains('Chrome/')
                    ? 'Chrome'
                    : ua.contains('Safari/')
                        ? 'Safari'
                        : null;
    return [os ?? '—', ?browser].join(' · ');
  }

  /// The block, in the order the preview lists it. Keys are the function's
  /// `DIAGNOSTIC_KEYS`.
  static Map<String, String> build({
    required String appVersion,
    required String channel,
    required String platform,
    required String language,
    required String route,
  }) =>
      {
        'appVersion': appVersion,
        'channel': channel,
        'platform': platform,
        'language': language,
        'route': sanitizeAnalyticsPath(route),
      };
}
