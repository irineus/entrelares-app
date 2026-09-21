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

  group('SupportDiagnostics', () {
    const iphoneSafari =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
    const iphoneChrome =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 '
        '(KHTML, like Gecko) CriOS/129.0 Mobile/15E148 Safari/604.1';
    const androidChrome =
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/129.0 Mobile Safari/537.36';
    const windowsEdge =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/129.0 Safari/537.36 Edg/129.0';
    const samsung =
        'Mozilla/5.0 (Linux; Android 14; SM-S911B) AppleWebKit/537.36 (KHTML, like Gecko) '
        'SamsungBrowser/25.0 Chrome/121.0 Mobile Safari/537.36';

    test('an OS family and a browser family, never versions', () {
      expect(SupportDiagnostics.platformLabel(userAgent: iphoneSafari), 'iOS · Safari');
      expect(SupportDiagnostics.platformLabel(userAgent: iphoneChrome), 'iOS · Chrome');
      expect(SupportDiagnostics.platformLabel(userAgent: androidChrome), 'Android · Chrome');
      expect(SupportDiagnostics.platformLabel(userAgent: windowsEdge), 'Windows · Edge');
      expect(SupportDiagnostics.platformLabel(userAgent: samsung),
          'Android · Samsung Internet');
    });

    test('the native app names the OS alone', () {
      expect(SupportDiagnostics.platformLabel(nativeOs: 'android'), 'Android');
    });

    test('the channel tells an installed web app apart', () {
      expect(SupportDiagnostics.channel(isWeb: false, standalone: false), 'store');
      expect(SupportDiagnostics.channel(isWeb: true, standalone: false), 'web');
      expect(SupportDiagnostics.channel(isWeb: true, standalone: true), 'web-installed');
    });

    test('the route loses query, fragment and ids', () {
      final d = SupportDiagnostics.build(
        appVersion: '2.7.5+125',
        channel: 'web',
        platform: 'iOS · Safari',
        language: 'pt-BR',
        route: '/register?invite=SEGREDO#access_token=abc',
      );
      expect(d['route'], '/register');
      expect(
          SupportDiagnostics.build(
            appVersion: '',
            channel: '',
            platform: '',
            language: '',
            route: '/family/members/42',
          )['route'],
          '/family/members/:id');
    });

    test('it carries exactly the five keys the function keeps', () {
      final d = SupportDiagnostics.build(
          appVersion: 'v', channel: 'c', platform: 'p', language: 'l', route: '/');
      expect(d.keys.toList(),
          ['appVersion', 'channel', 'platform', 'language', 'route']);
    });
  });
}
