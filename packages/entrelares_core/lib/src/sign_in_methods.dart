/// U-30 — the doors an account actually has, read from the session.
///
/// GoTrue links a Google sign-in onto an existing password account when the
/// addresses match (the F-57 posture), and from then on the account has TWO
/// ways in. Nothing on the server has to be asked: `app_metadata.providers`
/// names every linked provider and `identities` carries the address each one
/// signs in under. This is the pure part — what to list, in what order, with
/// which address — so the profile screen only renders it.
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
  /// else in alphabetical order — one row per provider, whichever of the two
  /// session facts named it.
  ///
  /// [providers] is `app_metadata.providers`; [identities] is `identities`.
  /// Both are read because the SDK does not promise the second on every
  /// session shape, and a door listed without its address is still a door.
  /// An empty result means the session said nothing, not "no doors".
  static List<SignInMethod> methods({
    required List<String> providers,
    required List<SignInIdentity> identities,
    required String? accountEmail,
  }) {
    final names = <String>{
      ...providers.map(_normalize).where((p) => p.isNotEmpty),
      ...identities.map((i) => _normalize(i.provider)).where((p) => p.isNotEmpty),
    };
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

  /// Whether the password card belongs on the screen. The F-57 predicate,
  /// unchanged: a session that named its providers and left `email` out has no
  /// password; a session that named NOTHING keeps the form, because refusing a
  /// form on missing information would hide a real credential.
  static bool hasPassword(List<SignInMethod> methods) =>
      methods.isEmpty ||
      methods.any((m) => m.kind == SignInMethodKind.password);

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
