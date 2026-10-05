import 'localization/k.dart';
import 'settings_rules.dart';

/// S-01 — progressive client-side login throttling, the mirror of
/// `Login.razor`'s rule in the web app. The server is not involved: this
/// exists to slow a keyboard attacker down on THIS device, and the numbers
/// must match the web so QA reads one behaviour.
/// F-87 — ONE password minimum, on every screen that sets a password, in
/// `register-invitee` and in GoTrue's own `minimum_password_length`. The
/// recovery screen used to accept 6 while the sign-up refused under 8, so a
/// reset could set a password the next sign-up form would call too short.
/// Existing passwords are not affected: the minimum is judged when one is SET.
abstract final class PasswordRules {
  static const int minLength = 8;
}

/// F-87 — what went wrong with an auth call, read from GoTrue's `code` and
/// HTTP status (never from the English message alone, which is what turned
/// "e-mail not confirmed" and a 429 into "check your internet").
enum AuthFailure {
  invalidCredentials,
  emailNotConfirmed,
  rateLimited,
  samePassword,
  weakPassword,
  expiredLink,
  network,
  other,
}

AuthFailure classifyAuthFailure({String? code, int? status, String? message}) {
  final c = code ?? '';
  final m = (message ?? '').toLowerCase();
  if (c == 'invalid_credentials' || m.contains('invalid login credentials')) {
    return AuthFailure.invalidCredentials;
  }
  if (c == 'email_not_confirmed' || m.contains('email not confirmed')) {
    return AuthFailure.emailNotConfirmed;
  }
  if (status == 429 ||
      c == 'over_request_rate_limit' ||
      c == 'over_email_send_rate_limit' ||
      c == 'over_sms_send_rate_limit') {
    return AuthFailure.rateLimited;
  }
  if (c == 'same_password') return AuthFailure.samePassword;
  if (c == 'weak_password') return AuthFailure.weakPassword;
  if (c == 'otp_expired' ||
      c == 'flow_state_expired' ||
      c == 'flow_state_not_found' ||
      m.contains('expired')) {
    return AuthFailure.expiredLink;
  }
  // No HTTP answer at all: the request never reached the server.
  if (status == null &&
      (m.contains('socketexception') ||
          m.contains('clientexception') ||
          m.contains('failed to fetch') ||
          m.contains('xmlhttprequest') ||
          m.contains('connection') ||
          m.contains('network'))) {
    return AuthFailure.network;
  }
  return AuthFailure.other;
}

/// F-87 — the auth error a reader may land with: GoTrue sends an expired or
/// used confirmation link back to the redirect with `#error=…&error_code=…`
/// in the fragment (the query, on some flows). Null when the URI carries none.
String? authLinkErrorCode(Uri uri) {
  Map<String, String> read(String raw) {
    try {
      return Uri.splitQueryString(raw);
    } catch (_) {
      return const {};
    }
  }

  final fromFragment = read(uri.fragment);
  final fromQuery = uri.queryParameters;
  final code = fromFragment['error_code'] ?? fromQuery['error_code'];
  final error = fromFragment['error'] ?? fromQuery['error'];
  if (code != null && code.isNotEmpty) return code;
  if (error != null && error.isNotEmpty) return error;
  return null;
}

abstract final class LoginThrottle {
  /// Failed attempts → lockout seconds. Under 3 failures there is no lockout
  /// (the count is still persisted); 3–4 failures cost `attempts × 5` seconds;
  /// 5 or more cost a flat 60.
  static int lockoutSecondsFor(int failedAttempts) {
    if (failedAttempts >= 5) return 60;
    if (failedAttempts >= 3) return failedAttempts * 5;
    return 0;
  }

  /// Seconds left of a persisted lockout, floored at zero — the restore path
  /// (the web keeps `login_lockout_until` in sessionStorage; the app keeps it
  /// in local prefs so a process restart does not reset the clock).
  static int remainingSeconds(DateTime lockoutUntil, DateTime now) {
    final seconds = lockoutUntil.difference(now).inSeconds;
    return seconds > 0 ? seconds : 0;
  }

  /// F-87: only a WRONG PASSWORD counts — a dropped connection or an
  /// unconfirmed e-mail used to lock the button too.
  static bool counts(AuthFailure failure) =>
      failure == AuthFailure.invalidCredentials;

  /// F-87: failures forget themselves. On a shared tablet one parent's
  /// mistyped password locked the other out for good; after [decay] with no
  /// new failure the count starts over.
  static const Duration decay = Duration(minutes: 15);

  static int countAfterDecay(int count, DateTime? lastFailure, DateTime now) {
    if (lastFailure == null) return count;
    return now.difference(lastFailure) >= decay ? 0 : count;
  }
}

/// S-04 — the 30-minute inactivity timeout, mirror of `MainLayout.razor`.
/// Only the threshold decision is a rule; WHAT counts as interaction (pointer
/// events, app resume) is the shell's business.
abstract final class InactivityPolicy {
  /// The seed. T-83 (24/09/2026): the live number is
  /// `session.idle_timeout_minutes` (5–240), read through [timeoutFor]; this
  /// applies before the settings load and whenever they cannot.
  static const Duration timeout = Duration(minutes: 30);

  /// The timeout the operator set, or the seed.
  static Duration timeoutFor(PublicSettings settings) =>
      Duration(minutes: settings.idleTimeoutMinutes);

  /// How often the shell re-checks — same 30 s cadence as the web's poll.
  static const Duration pollInterval = Duration(seconds: 30);

  /// F-92 (owner, 04/10/2026): the idle sign-out exists for the WEB channel
  /// only — a browser on a shared computer. On Android the device lock
  /// protects the session (T-18's spirit), and signing out on a warm resume
  /// wiped the offline copy and dropped the tapped push: the parent opening
  /// the app at pickup could not see who had the child.
  static bool appliesTo({required bool isWeb}) => isWeb;

  static bool expired(DateTime lastInteraction, DateTime now,
          [Duration limit = timeout]) =>
      !now.difference(lastInteraction).isNegative &&
      now.difference(lastInteraction) >= limit;
}

/// The `/update-password` form's validation, mirror of `UpdatePassword.razor`
/// (GoTrue enforces its own minimum server-side; this mirrors the web's
/// upfront refusal so the two clients speak with one voice).
abstract final class UpdatePasswordRules {
  static const int minLength = PasswordRules.minLength;

  /// Returns the catalog KEY of the violation, or null when valid — the
  /// screen renders it per reader language.
  static String? validationErrorKey(String newPassword, String confirmation) {
    if (newPassword.length < minLength) return K.updatePwdErrorShort;
    if (newPassword != confirmation) return K.updatePwdErrorMismatch;
    return null;
  }
}

/// U-13 — the one field a password-reset request can carry across into the
/// e-mail that answers it.
///
/// `send-auth-email` normally addresses a reader in the language their PROFILE
/// declares. A reset, though, is by definition asked for by someone who cannot
/// sign in, and the profile only learns a person's language when they DO sign
/// in — an account that has not been back since the column shipped is silent,
/// so the reader gets PT-BR while their screen says English. That is not a
/// hypothesis: it is what the pre-production QA round of Aug 2026 found.
///
/// `redirect_to` is the only field the client controls that survives the round
/// trip into GoTrue's hook payload, and what it carries here is exactly the
/// right datum — the language the person was looking at when they asked. It
/// ranks BELOW an explicit `profiles.language` and above everything else
/// (`langFromRedirect` in `supabase/functions/_shared/i18n.ts`).
///
/// The key is a Dart constant on this side and a Deno constant on the other,
/// in different deployment units, with nothing in either toolchain connecting
/// them: rename one and the other keeps compiling, keeps deploying, keeps
/// passing every other test, and every locked-out English reader silently
/// starts receiving Portuguese — invisible precisely because the fallback is a
/// perfectly valid language. `test/mirrors/auth_mail_mirror_test.dart` reads
/// both files and makes that red.
///
/// Worst case if a project's Redirect URLs allow-list does not match a query
/// string: GoTrue falls back to the Site URL, i.e. the app root. Checked
/// against the code, not assumed — `AuthChangeEvent.passwordRecovery` routes
/// to `/update-password` from wherever the app happens to be, so the reset
/// still works and only the landing route differs.
abstract final class AuthMail {
  static const String languageQueryParam = 'lang';
}
