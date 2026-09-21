import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('SupportRules.isValidMessage', () {
    test('counts the trimmed text', () {
      expect(SupportRules.isValidMessage('  123456789  '), isFalse);
      expect(SupportRules.isValidMessage('  1234567890  '), isTrue);
    });

    test('refuses beyond the maximum', () {
      expect(SupportRules.isValidMessage('a' * 2000), isTrue);
      expect(SupportRules.isValidMessage('a' * 2001), isFalse);
    });
  });

  group('SupportRules.isValidEmail', () {
    test('takes an ordinary address, trimmed', () {
      expect(SupportRules.isValidEmail(' ana@exemplo.com.br '), isTrue);
    });

    test('refuses what the function refuses', () {
      expect(SupportRules.isValidEmail('ana@exemplo'), isFalse);
      expect(SupportRules.isValidEmail('ana exemplo@x.com'), isFalse);
      expect(SupportRules.isValidEmail(''), isFalse);
      expect(SupportRules.isValidEmail('${'a' * 250}@x.com'), isFalse);
    });
  });

  test('privacy goes to privacidade@, everything else to suporte@', () {
    for (final c in SupportCategory.values) {
      expect(SupportRules.inboxFor(c),
          c == SupportCategory.privacy ? 'privacidade@entrelares.app' : 'suporte@entrelares.app');
    }
  });

  group('SupportRules.outcomeOf', () {
    test('2xx is sent', () {
      expect(SupportRules.outcomeOf(200, null), SupportOutcome.sent);
    });

    test('each error the function returns has its outcome', () {
      expect(SupportRules.outcomeOf(400, 'invalid_message'), SupportOutcome.invalidMessage);
      expect(SupportRules.outcomeOf(400, 'invalid_email'), SupportOutcome.invalidEmail);
      expect(SupportRules.outcomeOf(429, 'rate_limited'), SupportOutcome.rateLimited);
      expect(SupportRules.outcomeOf(502, 'send_failed'), SupportOutcome.sendFailed);
      expect(SupportRules.outcomeOf(500, 'failed'), SupportOutcome.failed);
    });

    test('a 429 without a body is still the limit', () {
      expect(SupportRules.outcomeOf(429, null), SupportOutcome.rateLimited);
    });
  });
}
