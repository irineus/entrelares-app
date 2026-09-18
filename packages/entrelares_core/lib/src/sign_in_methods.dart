/// U-30 — the doors an account actually has.
///
/// GoTrue links a Google sign-in onto an existing password account when the
/// addresses match (the F-57 posture), and from then on the account has TWO
/// ways in. The PROVIDER doors are session facts: `app_metadata.providers`
/// names every linked provider and `identities` carries the address each one
/// signs in under. This is the pure part — what to list, in what order, with
/// which address — so the profile screen only renders it.
///
/// U-50 — the PASSWORD door is not a session fact. "`email` is among the
/// providers" was read as "has a password" until production showed an account
/// whose providers are `google` alone and which has one (S-21, 10/09/2026);
/// the reverse — `email` named, no credential stored — can be built too. Only
/// the server reads
/// `auth.users.encrypted_password`, so the password door is listed from its
/// answer (`session_has_password()`) and from nothing else — the `email`
/// provider name never stands in for it, not even when the server is silent.
///
/// Two misreadings this exists to prevent, both found on a real device
/// (27/08/2026): "I changed my password, so the account is locked" (the
/// Google identity still opens it) and "I changed my e-mail, so I sign in with
/// the new one" (the Google identity still opens it under the OLD address —
/// which is why the address rides on the row, per identity, and not once at
/// the top).
library;

/// The kinds the screen knows how to explain. Anything GoTrue may add later
/// (`apple`, `phone`, …) lands in [other] with its provider name, rather than
/// being dropped from a list whose whole point is to be complete.
enum SignInMethodKind { password, google, other }

/// U-50 — the sentence under the Google row (see
/// [SignInMethodRules.googleNote]).
enum GoogleDoorNote {
  /// Another door stands beside it: "opens this login on its own — even after
  /// you change the password or the e-mail".
  linked,

  /// The server said the account has no password: "there is no password to
  /// change here".
  noPassword,

  /// The server did not answer: only what is true either way.
  neutral,
}

/// One identity as the session reports it: the provider and the address it
/// signs in under, when the provider sent one.
class SignInIdentity {
  final String provider;
  final String? email;

  const SignInIdentity(this.provider, {this.email});
}

/// One door of the account, ready to render.
class SignInMethod {
  final SignInMethodKind kind;

  /// The provider as GoTrue names it — what the [SignInMethodKind.other] row
  /// prints, since the catalog has no word for it.
  final String provider;

  /// The address this door opens under. For the password door it is the
  /// account's own e-mail (the one `users.email` holds NOW); for a provider
  /// it is the identity's, which does NOT follow an e-mail change.
  final String? email;

  const SignInMethod(this.kind, {required this.provider, this.email});

  @override
  bool operator ==(Object other) =>
      other is SignInMethod &&
      other.kind == kind &&
      other.provider == provider &&
      other.email == email;

  @override
  int get hashCode => Object.hash(kind, provider, email);

  @override
  String toString() => 'SignInMethod($kind, $provider, $email)';
}

abstract final class SignInMethodRules {
  /// GoTrue's name for the password identity.
  static const String passwordProvider = 'email';
  static const String googleProvider = 'google';

  /// The doors of the account, password first, then Google, then anything
  /// else in alphabetical order — one row per door.
  ///
  /// [providers] is `app_metadata.providers`; [identities] is `identities`.
  /// Both are read because the SDK does not promise the second on every
  /// session shape, and a door listed without its address is still a door.
  ///
  /// [hasPassword] is the SERVER's answer (U-50): `true` lists the password
  /// door whatever the providers say, `false` and `null` (the server did not
  /// answer) list none. `null` is not rounded to either side here — see
  /// [googleNote] for the one sentence that has to know the difference.
  ///
  /// An empty result means nothing is known, not "no doors".
  static List<SignInMethod> methods({
    required List<String> providers,
    required List<SignInIdentity> identities,
    required String? accountEmail,
    required bool? hasPassword,
  }) {
    final names = <String>{
      ...providers.map(_normalize).where((p) => p.isNotEmpty),
      ...identities.map((i) => _normalize(i.provider)).where((p) => p.isNotEmpty),
    }
      // The `email` provider is GoTrue's name for an identity, not evidence
      // of a credential: the door comes from the server's answer alone.
      ..remove(passwordProvider);
    if (hasPassword == true) names.add(passwordProvider);
    final emailByProvider = <String, String>{};
    for (final identity in identities) {
      final email = identity.email?.trim();
      if (email != null && email.isNotEmpty) {
        emailByProvider.putIfAbsent(_normalize(identity.provider), () => email);
      }
    }

    final methods = names.map((provider) {
      final kind = kindOf(provider);
      final email = kind == SignInMethodKind.password
          ? _blankToNull(accountEmail)
          : emailByProvider[provider];
      return SignInMethod(kind, provider: provider, email: email);
    }).toList()
      ..sort(_byRank);
    return methods;
  }

  static SignInMethodKind kindOf(String provider) => switch (_normalize(provider)) {
        passwordProvider => SignInMethodKind.password,
        googleProvider => SignInMethodKind.google,
        _ => SignInMethodKind.other,
      };

  /// Whether the password card belongs on the screen: only when the password
  /// door was listed, which only the server's `true` does (U-50). A silent
  /// server hides the card — offline nothing is written anyway (T-18), and a
  /// form that may submit against nothing is the one thing not to guess into.
  static bool showsPasswordCard(List<SignInMethod> methods) =>
      methods.any((m) => m.kind == SignInMethodKind.password);

  /// Which sentence the Google row carries. Beside another door it is the one
  /// that survives a password or e-mail change (U-30). Alone, "there is no
  /// password to change here" is a claim about the account, so it is made only
  /// on the server's `false`; while the server is silent the row says what is
  /// true either way.
  static GoogleDoorNote googleNote({
    required List<SignInMethod> methods,
    required bool? hasPassword,
  }) {
    if (methods.length > 1) return GoogleDoorNote.linked;
    return hasPassword == false
        ? GoogleDoorNote.noPassword
        : GoogleDoorNote.neutral;
  }

  static String _normalize(String provider) => provider.trim().toLowerCase();

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  static int _byRank(SignInMethod a, SignInMethod b) {
    final rank = a.kind.index.compareTo(b.kind.index);
    return rank != 0 ? rank : a.provider.compareTo(b.provider);
  }
}
