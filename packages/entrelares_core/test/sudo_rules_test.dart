/// Mirror of the S-10 rules in `entrelares-app`
/// `Entrelares/Services/SudoService.cs` and of the console pilot's
/// `apps/console_app/test/rules_test.dart` group "S-10 elevation marker".
///
/// Three of these pin behaviours a naive port gets wrong, and each one was a
/// real defect somewhere: the 15 s safety margin (races the RPC at the
/// boundary), the ceiling on the cooldown (shows "0 s" while the gate is still
/// closed), and the attempt counter RESETTING on the third failure (a port that
/// keeps counting locks the user out permanently).
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 8, 19, 12, 0, 0);

  group('marker detection', () {
    test('detects the marker inside a wrapped PostgREST error', () {
      const raw = 'PostgrestException(message: ELEVATION_REQUIRED: Confirme sua '
          'senha para alterar permissões de administrador., code: 42501)';
      expect(SudoRules.isElevationRequired(raw), isTrue);
    });

    test('detects it in an Edge Function payload', () {
      const body = '{"error":"ELEVATION_REQUIRED: Confirme sua senha para '
          'alterar o e-mail de um participante."}';
      expect(SudoRules.isElevationRequired(body), isTrue);
    });

    test('an unrelated failure is not an elevation demand', () {
      expect(SudoRules.isElevationRequired('permission denied for function'),
          isFalse);
      expect(SudoRules.isElevationRequired('Falha de conexão'), isFalse);
    });

    test('null is not an elevation demand', () {
      expect(SudoRules.isElevationRequired(null), isFalse);
    });

    test('works on a thrown object, not just a string', () {
      expect(
          SudoRules.isElevationRequired(
              Exception('ELEVATION_REQUIRED: Confirme sua senha.')),
          isTrue);
    });
  });

  group('stripMarker', () {
    test('removes the marker and the ": " that follows it', () {
      expect(
        SudoRules.stripMarker(
            'ELEVATION_REQUIRED: Confirme sua senha para sair da família.'),
        'Confirme sua senha para sair da família.',
      );
    });

    test('leaves a message without the marker untouched', () {
      expect(SudoRules.stripMarker('Senha incorreta.'), 'Senha incorreta.');
    });
  });

  group('isElevated', () {
    test('never elevated is not elevated', () {
      expect(SudoRules.isElevated(null, now), isFalse);
    });

    test('a fresh window is elevated', () {
      expect(SudoRules.isElevated(now.add(const Duration(minutes: 5)), now),
          isTrue);
    });

    test('an expired window is not', () {
      expect(SudoRules.isElevated(now.subtract(const Duration(seconds: 1)), now),
          isFalse);
    });

    test('the last 15 s of the window already count as expired — the safety '
        'margin exists so the client does not race the RPC', () {
      expect(SudoRules.isElevated(now.add(const Duration(seconds: 14)), now),
          isFalse);
      expect(SudoRules.isElevated(now.add(const Duration(seconds: 16)), now),
          isTrue);
    });
  });

  group('cooldownSecondsRemaining', () {
    test('no cooldown reads zero', () {
      expect(SudoRules.cooldownSecondsRemaining(null, now), 0);
    });

    test('an elapsed cooldown reads zero, never negative', () {
      expect(
          SudoRules.cooldownSecondsRemaining(
              now.subtract(const Duration(seconds: 30)), now),
          0);
    });

    test('a whole number of seconds reads exactly', () {
      expect(
          SudoRules.cooldownSecondsRemaining(
              now.add(const Duration(seconds: 60)), now),
          60);
    });

    test('a fraction rounds UP — "0 s" while the gate is closed would be a lie',
        () {
      expect(
          SudoRules.cooldownSecondsRemaining(
              now.add(const Duration(milliseconds: 1)), now),
          1);
      expect(
          SudoRules.cooldownSecondsRemaining(
              now.add(const Duration(milliseconds: 1500)), now),
          2);
    });
  });

  group('registerFailedAttempt', () {
    test('the first two failures only count', () {
      expect(SudoRules.registerFailedAttempt(0),
          (failedAttempts: 1, cooldownStarts: false));
      expect(SudoRules.registerFailedAttempt(1),
          (failedAttempts: 2, cooldownStarts: false));
    });

    test('the third starts the cooldown AND resets the counter, so the wait '
        'buys three fresh attempts', () {
      expect(SudoRules.registerFailedAttempt(2),
          (failedAttempts: 0, cooldownStarts: true));
    });
  });

  group('elevatedUntilFrom', () {
    test('uses the server instant when it parses', () {
      expect(SudoRules.elevatedUntilFrom('2026-08-19T12:05:00Z', now),
          DateTime.utc(2026, 8, 19, 12, 5));
    });

    test('normalises a non-UTC server instant', () {
      expect(SudoRules.elevatedUntilFrom('2026-08-19T09:05:00-03:00', now),
          DateTime.utc(2026, 8, 19, 12, 5));
    });

    test('falls back to the local 5-minute estimate when absent or unparseable',
        () {
      expect(SudoRules.elevatedUntilFrom(null, now),
          now.add(SudoRules.serverWindow));
      expect(SudoRules.elevatedUntilFrom('not a date', now),
          now.add(SudoRules.serverWindow));
    });
  });

  // ── S-21: the e-mail code ──────────────────────────────────────────────────

  group('isCodeShaped', () {
    test('accepts exactly six digits', () {
      expect(SudoRules.isCodeShaped('246810'), isTrue);
    });

    test('accepts a code copied out of an e-mail with its spacing', () {
      // Selecting the bold digits in the message picks up whatever separator
      // the mail client rendered. Refusing that would be the client inventing
      // a rule the server does not have.
      expect(SudoRules.isCodeShaped('246 810'), isTrue);
      expect(SudoRules.isCodeShaped(' 246-810 '), isTrue);
      expect(SudoRules.normalizeCode('246 810'), '246810');
    });

    test('refuses anything that could not be a code', () {
      expect(SudoRules.isCodeShaped(''), isFalse);
      expect(SudoRules.isCodeShaped('2468'), isFalse, reason: 'too short');
      expect(SudoRules.isCodeShaped('2468109'), isFalse, reason: 'too long');
      expect(SudoRules.isCodeShaped('24681a'), isFalse, reason: 'not digits');
      // The one that matters: someone typing their password into the code
      // field must not spend a request, and must not spend an attempt.
      expect(SudoRules.isCodeShaped('minhasenha'), isFalse);
    });

    test('is a keyboard check, never a verdict', () {
      // A well-formed code the server has never issued is still well-formed.
      // Nothing here may be read as "this code is good".
      expect(SudoRules.isCodeShaped('000000'), isTrue);
      expect(SudoRules.isCodeShaped('999999'), isTrue);
    });
  });
}
