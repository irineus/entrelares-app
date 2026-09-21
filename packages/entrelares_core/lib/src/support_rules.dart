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
  static bool isValidMessage(String raw) {
    final length = raw.trim().length;
    return length >= messageMinChars && length <= messageMaxChars;
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
