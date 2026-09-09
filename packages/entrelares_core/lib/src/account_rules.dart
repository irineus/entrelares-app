/// Lote 4 — the pure validations of the account surfaces: sign-up
/// (`Register.razor.Validate`) and the family invite form
/// (`FamilyPage.razor.SendInvitation`).
///
/// All of these are UX mirrors. `handle_new_user`, `register-invitee` and
/// `create_invitation` refuse the same inputs server-side and their messages
/// propagate verbatim — these exist so the user is not charged a round-trip to
/// learn that a field is blank.
library;

import 'localization/k.dart';
import 'localization/k_app.dart';

abstract final class RegisterRules {
  /// GoTrue's own minimum is configured server-side; 8 is what the web refuses
  /// upfront, and the `register-invitee` Edge Function repeats it.
  static const int minPasswordLength = 8;

  /// The web's `maxlength` on both free-text fields.
  static const int maxNameLength = 80;

  /// The sign-up form's first violation, as a catalog KEY, or null when the
  /// input may be submitted.
  ///
  /// The ORDER is part of the mirror: the family/role checks come before the
  /// password checks, and both are skipped entirely on the invited branch —
  /// an invitee has no family to name (they are joining one) and no role to
  /// pick (the invitation carries it).
  static String? validationErrorKey({
    required String fullName,
    required String email,
    required String? familyName,
    required String? role,
    required String password,
    required String confirmPassword,
    required bool acceptedTerms,
    required bool isInvited,
  }) {
    if (fullName.trim().isEmpty) return K.registerErrorNameRequired;
    if (email.trim().isEmpty) return K.registerErrorEmailRequired;
    if (!isInvited && (familyName ?? '').trim().isEmpty) {
      return K.registerErrorFamilyRequired;
    }
    if (!isInvited && role == null) return K.registerErrorRoleRequired;
    if (password.length < minPasswordLength) {
      return K.registerErrorPasswordShort;
    }
    if (password != confirmPassword) return K.registerErrorPasswordMismatch;
    if (!acceptedTerms) return K.registerErrorConsentRequired;
    return null;
  }

  /// The founder's family name when they leave the field to the trigger's
  /// default. `handle_new_user` builds `'Família ' || meta_name` from the
  /// person's own name — mirrored here only to render the hint, never sent.
  static String defaultFamilyName(String fullName) =>
      'Família ${fullName.trim()}';

  /// Mirror of `AuthService.TranslateSignUpError`. GoTrue answers in ENGLISH
  /// regardless of the reader, so the signatures below are matched against its
  /// text and mapped to a catalog key. They are a contract with GoTrue, not
  /// with our own server — reviewed on every Supabase upgrade.
  ///
  /// `Database error` is the interesting one: it is how GoTrue wraps ANY
  /// exception raised by the `handle_new_user` trigger (a dead invitation, the
  /// seat cap, an invalid role), so it gets its own message instead of the
  /// generic one.
  static String signUpErrorKey(String rawMessage) {
    if (rawMessage.contains('429') ||
        rawMessage.toLowerCase().contains('rate')) {
      return K.authErrRateLimited;
    }
    if (rawMessage.contains('already registered')) {
      return K.authErrAlreadyRegistered;
    }
    if (rawMessage.contains('Password should be')) {
      return K.authErrPasswordWeak;
    }
    if (rawMessage.contains('invalid format') ||
        rawMessage.contains('Unable to validate email')) {
      return K.authErrEmailFormat;
    }
    if (rawMessage.contains('Database error')) return K.authErrDatabaseSignUp;
    return K.authErrSignUpGeneric;
  }

  /// The anti-enumeration guard: GoTrue answers a sign-up for an EXISTING
  /// address with a success-shaped user carrying no identities, precisely so an
  /// attacker cannot probe which e-mails are registered. The web turns that
  /// shape into the "already registered" message for the legitimate user who is
  /// simply signing up twice.
  static bool isSilentDuplicate({required bool hasUser, required int identityCount}) =>
      hasUser && identityCount == 0;
}

/// F-57 — the onboarding form of a deferred (social-login) sign-up: the
/// founder half of [RegisterRules.validationErrorKey] without the fields the
/// OAuth session already settled (e-mail belongs to the provider account,
/// password does not exist). Same keys, same order, so the two forms refuse
/// with the same sentences.
abstract final class OauthOnboardingRules {
  /// The form's first violation, as a catalog KEY, or null when the input may
  /// be submitted. On the invited branch only name and consent apply — the
  /// invitation carries family and role.
  static String? validationErrorKey({
    required String fullName,
    required String? familyName,
    required String? role,
    required bool acceptedTerms,
    required bool isInvited,
  }) {
    if (fullName.trim().isEmpty) return K.registerErrorNameRequired;
    if (!isInvited && (familyName ?? '').trim().isEmpty) {
      return K.registerErrorFamilyRequired;
    }
    if (!isInvited && role == null) return K.registerErrorRoleRequired;
    if (!acceptedTerms) return K.registerErrorConsentRequired;
    return null;
  }
}

abstract final class InviteFormRules {
  /// The invite form's first violation, as a catalog KEY, or null when it may
  /// be sent. The e-mail test is deliberately the web's shallow one (non-blank
  /// and contains "@"): `create_invitation` normalises and the address either
  /// receives the message or it does not — a stricter client regex would only
  /// refuse addresses the server accepts.
  ///
  /// F-56: the form names the person first — the name is what the placeholder
  /// is made of — and the e-mail became OPTIONAL: given, the invitation goes
  /// out now; blank, the admin plans alone and invites later.
  static String? validationErrorKey({
    required String fullName,
    required String email,
    required String? myEmail,
    required int roleId,
  }) {
    final name = fullName.trim();
    if (name.length < 2) return KApp.inviteErrNameRequired;
    final emailError = emailErrorKey(email: email, myEmail: myEmail);
    if (emailError != null) return emailError;
    if (roleId == 0) return KApp.inviteErrRoleRequired;
    return null;
  }

  /// The e-mail half alone — what the F-56 "invite this placeholder" sheet
  /// asks, where name and role are already the member's. A blank address is
  /// not an error here either; the CALLER decides whether blank is allowed.
  static String? emailErrorKey({
    required String email,
    required String? myEmail,
  }) {
    final clean = email.trim();
    if (clean.isNotEmpty && !clean.contains('@')) return K.famErrInvalidEmail;
    if (myEmail != null && clean.toLowerCase() == myEmail.trim().toLowerCase()) {
      return K.famErrOwnEmail;
    }
    return null;
  }

  /// The invite link a pending invitation resolves to — the same string the
  /// e-mail carries, so the copyable fallback and the message cannot diverge.
  /// It is an App Link: on a device with the app installed and the domain
  /// verified, Android opens `/register?invite=…` in the app; anywhere else it
  /// degrades to the web page.
  static String inviteLink(String webOrigin, String token) =>
      '$webOrigin/register?invite=$token';

  /// The `invite` query parameter of an incoming deep link, or null when the
  /// URI is not an invitation. Kept here so the router and the register screen
  /// read the token the same way.
  static String? inviteTokenFrom(Uri uri) {
    final token = uri.queryParameters['invite'];
    return (token == null || token.trim().isEmpty) ? null : token.trim();
  }

  /// Whether a token even has the shape of the `uuid` the column holds. Mirror
  /// of the web's `Guid.TryParse` guard: a malformed token is answered locally,
  /// because sending it would make the RPC fail on a cast rather than answer
  /// the honest "this invitation is not valid" the screen wants.
  static bool isTokenShaped(String token) => _uuid.hasMatch(token.trim());

  static final RegExp _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
      r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
}
