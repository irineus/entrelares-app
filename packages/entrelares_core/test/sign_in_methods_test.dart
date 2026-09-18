/// U-30 — the doors an account has, as the profile screen lists them.
///
/// U-50 — the password door comes from the SERVER's answer, so every case
/// below states that answer explicitly: a helper that derived it from the
/// providers would be the retired guess, living on in the tests.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

List<SignInMethod> methods({
  List<String> providers = const [],
  List<SignInIdentity> identities = const [],
  String? accountEmail = 'ana@example.com',
  required bool? hasPassword,
}) =>
    SignInMethodRules.methods(
      providers: providers,
      identities: identities,
      accountEmail: accountEmail,
      hasPassword: hasPassword,
    );

void main() {
  group('SignInMethodRules.methods', () {
    test('a password-only account has one door, under its own address', () {
      expect(methods(providers: ['email'], hasPassword: true), [
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
          hasPassword: false,
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
          hasPassword: true,
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
        hasPassword: true,
      );
      expect(doors.map((d) => d.email), ['nova@example.com', 'antiga@gmail.com']);
    });

    test('a provider named by only one of the two session facts is still a door',
        () {
      expect(
        methods(providers: ['apple'], identities: const [
          SignInIdentity('google', email: 'ana@gmail.com'),
        ], hasPassword: false)
            .map((d) => d.provider),
        ['google', 'apple'],
      );
      expect(
        methods(providers: ['email', 'google'], hasPassword: true)
            .map((d) => d.email),
        ['ana@example.com', null],
        reason: 'no identity, no address — the door is still listed',
      );
    });

    test('an unknown provider is kept, named, after the known ones', () {
      expect(
        methods(providers: ['apple', 'google', 'email'], hasPassword: true)
            .map((d) => d.kind),
        [
          SignInMethodKind.password,
          SignInMethodKind.google,
          SignInMethodKind.other,
        ],
      );
      expect(methods(providers: ['apple'], hasPassword: false).single.provider,
          'apple');
    });

    test('provider names are normalised and blanks are dropped', () {
      expect(
        methods(providers: [' Email ', '', 'GOOGLE'], identities: const [
          SignInIdentity('google', email: '  '),
        ], hasPassword: true),
        [
          const SignInMethod(SignInMethodKind.password,
              provider: 'email', email: 'ana@example.com'),
          const SignInMethod(SignInMethodKind.google,
              provider: 'google', email: null),
        ],
      );
      expect(
          methods(providers: ['email'], accountEmail: ' ', hasPassword: true)
              .single
              .email,
          isNull);
    });

    test('a session that said nothing yields nothing', () {
      expect(methods(hasPassword: null), isEmpty);
      expect(methods(hasPassword: false), isEmpty);
    });
  });

  group('U-50 — the password door is what the server answers, never the '
      'providers',
      () {
    const google = [SignInIdentity('google', email: 'ana@gmail.com')];

    test('the production account: providers name google ALONE, and the server '
        'says there is a password — both doors are listed', () {
      // Measured on 10/09/2026 (S-21). Until this item the screen told this
      // person "there is no password to change here".
      final doors = methods(
        providers: ['google'],
        identities: google,
        accountEmail: 'ana@gmail.com',
        hasPassword: true,
      );
      expect(doors, [
        const SignInMethod(SignInMethodKind.password,
            provider: 'email', email: 'ana@gmail.com'),
        const SignInMethod(SignInMethodKind.google,
            provider: 'google', email: 'ana@gmail.com'),
      ]);
      expect(SignInMethodRules.showsPasswordCard(doors), isTrue);
      expect(SignInMethodRules.googleNote(methods: doors, hasPassword: true),
          GoogleDoorNote.linked);
    });

    test('the mirror image: the `email` provider with NO password lists no '
        'password door', () {
      // The shape the DB gate builds (an invited user signed in by magic
      // link): naming the provider is not having the credential.
      final alone = methods(providers: ['email'], hasPassword: false);
      expect(alone, isEmpty);
      expect(SignInMethodRules.showsPasswordCard(alone), isFalse);

      final withGoogle = methods(
          providers: ['email', 'google'],
          identities: google,
          hasPassword: false);
      expect(withGoogle.map((d) => d.kind), [SignInMethodKind.google]);
      expect(
          SignInMethodRules.googleNote(methods: withGoogle, hasPassword: false),
          GoogleDoorNote.noPassword);
    });

    test('a silent server is not rounded to the guess from providers — in either '
        'direction', () {
      // No answer (offline, a refused call): the card is hidden even though
      // the providers name `email`, and the Google row claims nothing about
      // a password it knows nothing about.
      for (final providers in [
        ['email', 'google'],
        ['google'],
      ]) {
        final doors = methods(
            providers: providers, identities: google, hasPassword: null);
        expect(doors.map((d) => d.kind), [SignInMethodKind.google],
            reason: '$providers');
        expect(SignInMethodRules.showsPasswordCard(doors), isFalse,
            reason: '$providers');
        expect(SignInMethodRules.googleNote(methods: doors, hasPassword: null),
            GoogleDoorNote.neutral,
            reason: '$providers');
      }
      expect(
          SignInMethodRules.showsPasswordCard(
              methods(providers: ['email'], hasPassword: null)),
          isFalse);
    });

    test('Google alone says "no password here" ONLY when the server said false',
        () {
      final doors = methods(
          providers: ['google'], identities: google, hasPassword: false);
      expect(SignInMethodRules.googleNote(methods: doors, hasPassword: false),
          GoogleDoorNote.noPassword);
    });
  });
}
