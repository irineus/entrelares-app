/// U-30 — the doors an account has, as the profile screen lists them.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

List<SignInMethod> methods({
  List<String> providers = const [],
  List<SignInIdentity> identities = const [],
  String? accountEmail = 'ana@example.com',
}) =>
    SignInMethodRules.methods(
      providers: providers,
      identities: identities,
      accountEmail: accountEmail,
    );

void main() {
  group('SignInMethodRules.methods', () {
    test('a password-only account has one door, under its own address', () {
      expect(methods(providers: ['email']), [
        const SignInMethod(SignInMethodKind.password,
            provider: 'email', email: 'ana@example.com'),
      ]);
    });

    test('a Google-only account has one door, under the identity address', () {
      expect(
        methods(
          providers: ['google'],
          identities: const [
            SignInIdentity('google', email: 'ana@gmail.com'),
          ],
        ),
        [
          const SignInMethod(SignInMethodKind.google,
              provider: 'google', email: 'ana@gmail.com'),
        ],
      );
    });

    test('the linked case lists BOTH doors, password first', () {
      // The situation the item was opened for: Google signed in with the
      // address of a password account, GoTrue linked the two.
      expect(
        methods(
          providers: ['google', 'email'],
          identities: const [
            SignInIdentity('google', email: 'ana@gmail.com'),
            SignInIdentity('email', email: 'ana@gmail.com'),
          ],
          accountEmail: 'ana@gmail.com',
        ),
        [
          const SignInMethod(SignInMethodKind.password,
              provider: 'email', email: 'ana@gmail.com'),
          const SignInMethod(SignInMethodKind.google,
              provider: 'google', email: 'ana@gmail.com'),
        ],
      );
    });

    test('after an e-mail change the Google door keeps the OLD address', () {
      // `users.email` moved (and `profiles.email` followed by trigger); the
      // Google identity did not. The password row shows the new address, the
      // Google row the one it still opens under.
      final doors = methods(
        providers: ['email', 'google'],
        identities: const [
          SignInIdentity('email', email: 'nova@example.com'),
          SignInIdentity('google', email: 'antiga@gmail.com'),
        ],
        accountEmail: 'nova@example.com',
      );
      expect(doors.map((d) => d.email), ['nova@example.com', 'antiga@gmail.com']);
    });

    test('a provider named by only one of the two session facts is still a door',
        () {
      expect(
        methods(providers: ['email'], identities: const [
          SignInIdentity('google', email: 'ana@gmail.com'),
        ]).map((d) => d.provider),
        ['email', 'google'],
      );
      expect(
        methods(providers: ['email', 'google']).map((d) => d.email),
        ['ana@example.com', null],
        reason: 'no identity, no address — the door is still listed',
      );
    });

    test('an unknown provider is kept, named, after the known ones', () {
      expect(
        methods(providers: ['apple', 'google', 'email']).map((d) => d.kind),
        [
          SignInMethodKind.password,
          SignInMethodKind.google,
          SignInMethodKind.other,
        ],
      );
      expect(methods(providers: ['apple']).single.provider, 'apple');
    });

    test('provider names are normalised and blanks are dropped', () {
      expect(
        methods(providers: [' Email ', '', 'GOOGLE'], identities: const [
          SignInIdentity('google', email: '  '),
        ]),
        [
          const SignInMethod(SignInMethodKind.password,
              provider: 'email', email: 'ana@example.com'),
          const SignInMethod(SignInMethodKind.google,
              provider: 'google', email: null),
        ],
      );
      expect(methods(providers: ['email'], accountEmail: ' ').single.email,
          isNull);
    });

    test('a session that said nothing yields nothing', () {
      expect(methods(), isEmpty);
    });
  });

  group('SignInMethodRules.hasPassword — the F-57 predicate', () {
    test('a password door keeps the form', () {
      expect(SignInMethodRules.hasPassword(methods(providers: ['email'])),
          isTrue);
      expect(
          SignInMethodRules.hasPassword(
              methods(providers: ['google', 'email'])),
          isTrue);
    });

    test('a Google-only session has no form to fill', () {
      expect(SignInMethodRules.hasPassword(methods(providers: ['google'])),
          isFalse);
    });

    test('no information keeps the form rather than hiding a credential', () {
      expect(SignInMethodRules.hasPassword(const []), isTrue);
    });
  });
}
