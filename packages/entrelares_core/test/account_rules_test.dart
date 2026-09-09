/// Mirror of the sign-up validation in `entrelares-app`
/// `Entrelares/Pages/Register.razor.Validate()` and of the invite form's checks
/// in `FamilyPage.razor.SendInvitation()`.
///
/// The ORDER of the sign-up checks is asserted explicitly: it is what decides
/// which single message a form with several problems shows, and the two clients
/// must pick the same one.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

String? founder({
  String fullName = 'Ana Souza',
  String email = 'ana@example.com',
  String? familyName = 'Souza',
  String? role = 'mother',
  String password = 'segredo123',
  String? confirmPassword,
  bool acceptedTerms = true,
}) =>
    RegisterRules.validationErrorKey(
      fullName: fullName,
      email: email,
      familyName: familyName,
      role: role,
      password: password,
      confirmPassword: confirmPassword ?? password,
      acceptedTerms: acceptedTerms,
      isInvited: false,
    );

String? invited({
  String fullName = 'Bruno Souza',
  String email = 'bruno@example.com',
  String password = 'segredo123',
  String? confirmPassword,
  bool acceptedTerms = true,
}) =>
    RegisterRules.validationErrorKey(
      fullName: fullName,
      email: email,
      familyName: null,
      role: null,
      password: password,
      confirmPassword: confirmPassword ?? password,
      acceptedTerms: acceptedTerms,
      isInvited: true,
    );

void main() {
  group('sign-up — founder branch', () {
    test('a complete form passes', () {
      expect(founder(), isNull);
    });

    test('name first', () {
      expect(founder(fullName: '   '), K.registerErrorNameRequired);
    });

    test('then e-mail', () {
      expect(founder(email: ''), K.registerErrorEmailRequired);
    });

    test('then the family name', () {
      expect(founder(familyName: '  '), K.registerErrorFamilyRequired);
    });

    test('then the role', () {
      expect(founder(role: null), K.registerErrorRoleRequired);
    });

    test('then the password length', () {
      expect(founder(password: '1234567'), K.registerErrorPasswordShort);
    });

    test('exactly the minimum length is accepted', () {
      expect(founder(password: '12345678'), isNull);
    });

    test('then the confirmation', () {
      expect(founder(password: 'segredo123', confirmPassword: 'segredo124'),
          K.registerErrorPasswordMismatch);
    });

    test('consent last — the F-18 gate', () {
      expect(founder(acceptedTerms: false), K.registerErrorConsentRequired);
    });

    test('the family/role checks come BEFORE the password ones', () {
      expect(
        founder(familyName: '', password: '1'),
        K.registerErrorFamilyRequired,
      );
    });
  });

  group('sign-up — invited branch', () {
    test('a complete form passes without family or role', () {
      expect(invited(), isNull);
    });

    test('the family and role checks are skipped entirely', () {
      expect(
        RegisterRules.validationErrorKey(
          fullName: 'Bruno',
          email: 'bruno@example.com',
          familyName: null,
          role: null,
          password: 'segredo123',
          confirmPassword: 'segredo123',
          acceptedTerms: true,
          isInvited: true,
        ),
        isNull,
      );
    });

    test('but the password and consent rules still apply', () {
      expect(invited(password: 'curta'), K.registerErrorPasswordShort);
      expect(invited(acceptedTerms: false), K.registerErrorConsentRequired);
    });
  });

  test('defaultFamilyName mirrors the trigger\'s fallback', () {
    expect(RegisterRules.defaultFamilyName('  Ana Souza '), 'Família Ana Souza');
  });

  group('signUpErrorKey — GoTrue answers in English, the reader does not', () {
    test('an address already in use', () {
      expect(RegisterRules.signUpErrorKey('User already registered'),
          K.authErrAlreadyRegistered);
    });

    test('a password GoTrue considers weak', () {
      expect(
          RegisterRules.signUpErrorKey(
              'Password should be at least 6 characters'),
          K.authErrPasswordWeak);
    });

    test('both malformed-address signatures', () {
      expect(RegisterRules.signUpErrorKey('Email address is invalid format'),
          K.authErrEmailFormat);
      expect(RegisterRules.signUpErrorKey('Unable to validate email address'),
          K.authErrEmailFormat);
    });

    test('a trigger refusal arrives wrapped as "Database error"', () {
      expect(
          RegisterRules.signUpErrorKey(
              'Database error saving new user: Convite inválido, expirado ou '
              'emitido para outro e-mail.'),
          K.authErrDatabaseSignUp);
    });

    test('rate limiting wins over everything — it is checked first', () {
      expect(RegisterRules.signUpErrorKey('429 Too Many Requests'),
          K.authErrRateLimited);
      expect(RegisterRules.signUpErrorKey('email rate limit exceeded'),
          K.authErrRateLimited);
    });

    test('anything unrecognised falls back to the generic sign-up error', () {
      expect(RegisterRules.signUpErrorKey('something new from GoTrue'),
          K.authErrSignUpGeneric);
    });
  });

  group('isSilentDuplicate — the anti-enumeration guard', () {
    test('a user with no identities is an address already registered', () {
      expect(RegisterRules.isSilentDuplicate(hasUser: true, identityCount: 0),
          isTrue);
    });

    test('a genuine new sign-up carries an identity', () {
      expect(RegisterRules.isSilentDuplicate(hasUser: true, identityCount: 1),
          isFalse);
    });

    test('no user at all is not this case', () {
      expect(RegisterRules.isSilentDuplicate(hasUser: false, identityCount: 0),
          isFalse);
    });
  });

  group('invite form', () {
    String? check({
      String fullName = 'Vovó Lurdes',
      String email = 'vovo@example.com',
      String? myEmail = 'ana@example.com',
      int roleId = 3,
    }) =>
        InviteFormRules.validationErrorKey(
            fullName: fullName, email: email, myEmail: myEmail, roleId: roleId);

    test('a complete form passes', () {
      expect(check(), isNull);
    });

    test('F-56: the name is what the placeholder is made of — required', () {
      expect(check(fullName: ''), KApp.inviteErrNameRequired);
      expect(check(fullName: ' A '), KApp.inviteErrNameRequired);
      expect(check(fullName: 'Al'), isNull);
    });

    test('F-56: a blank e-mail is fine (plan now, invite later); an '
        '"@"-less one is not', () {
      expect(check(email: '   '), isNull);
      expect(check(email: 'vovo.example.com'), K.famErrInvalidEmail);
    });

    test('inviting yourself is refused, case-insensitively', () {
      expect(check(email: 'ANA@example.com'), K.famErrOwnEmail);
      expect(check(email: '  ana@example.com  '), K.famErrOwnEmail);
    });

    test('the role placeholder is refused', () {
      expect(check(roleId: 0), KApp.inviteErrRoleRequired);
    });

    test('the name and e-mail checks come before the role check', () {
      expect(check(fullName: '', roleId: 0), KApp.inviteErrNameRequired);
      expect(check(email: 'x', roleId: 0), K.famErrInvalidEmail);
    });

    test('F-62: the name half alone — what the attach sheet asks', () {
      expect(InviteFormRules.nameErrorKey(''), KApp.inviteErrNameRequired);
      expect(InviteFormRules.nameErrorKey(' A '), KApp.inviteErrNameRequired);
      expect(InviteFormRules.nameErrorKey(' Al '), isNull);
    });
  });

  group('invite link', () {
    test('builds the same URL the e-mail carries', () {
      expect(
        InviteFormRules.inviteLink(
            'https://web.entrelares.app', '11111111-2222-3333-4444-555555555555'),
        'https://web.entrelares.app/register?invite='
            '11111111-2222-3333-4444-555555555555',
      );
    });

    test('reads the token back out of a deep link', () {
      expect(
        InviteFormRules.inviteTokenFrom(Uri.parse(
            'https://web.entrelares.app/register?invite=abc-123')),
        'abc-123',
      );
    });

    test('only a uuid-shaped token is worth a round-trip', () {
      expect(
          InviteFormRules.isTokenShaped(
              '11111111-2222-3333-4444-555555555555'),
          isTrue);
      expect(
          InviteFormRules.isTokenShaped(
              '  11111111-2222-3333-4444-555555555555  '),
          isTrue,
          reason: 'a pasted link often brings blanks along');
      expect(
          InviteFormRules.isTokenShaped(
              '11111111-2222-3333-4444-55555555555'),
          isFalse);
      expect(InviteFormRules.isTokenShaped('abc-123'), isFalse);
      expect(InviteFormRules.isTokenShaped(''), isFalse);
    });

    test('a register link with no token is not an invitation', () {
      expect(
          InviteFormRules.inviteTokenFrom(
              Uri.parse('https://web.entrelares.app/register')),
          isNull);
      expect(
          InviteFormRules.inviteTokenFrom(
              Uri.parse('https://web.entrelares.app/register?invite=')),
          isNull);
    });
  });

  // F-57 — the onboarding form of a deferred OAuth sign-up: the founder half
  // of RegisterRules without e-mail/password, refusing with the SAME keys in
  // the SAME order so the two forms speak identically.
  group('OauthOnboardingRules', () {
    String? validate({
      String fullName = 'Ana',
      String? familyName = 'Família Ana',
      String? role = 'mother',
      bool acceptedTerms = true,
      bool isInvited = false,
    }) =>
        OauthOnboardingRules.validationErrorKey(
          fullName: fullName,
          familyName: familyName,
          role: role,
          acceptedTerms: acceptedTerms,
          isInvited: isInvited,
        );

    test('a complete founder form passes', () {
      expect(validate(), isNull);
    });

    test('refusals come in the register form order, with its keys', () {
      expect(validate(fullName: '  '), K.registerErrorNameRequired);
      expect(validate(familyName: ''), K.registerErrorFamilyRequired);
      expect(validate(role: null), K.registerErrorRoleRequired);
      expect(validate(acceptedTerms: false), K.registerErrorConsentRequired);
    });

    test('the invited branch skips family and role — the invitation carries '
        'both', () {
      expect(validate(isInvited: true, familyName: null, role: null), isNull);
      expect(validate(isInvited: true, familyName: null, role: null, acceptedTerms: false),
          K.registerErrorConsentRequired);
    });
  });
}
