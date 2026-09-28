import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

// F-72 — the invitation to install the Play app, as a pure decision.
void main() {
  const chromeAndroid = 'Mozilla/5.0 (Linux; Android 14; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile '
      'Safari/537.36';
  const chromeDesktop = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';
  const iPhoneSafari = 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) '
      'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.7 Mobile/15E148 '
      'Safari/604.1';
  final now = DateTime(2026, 9, 27, 12);

  bool invite({
    bool isProduction = true,
    String userAgent = chromeAndroid,
    bool standalone = false,
    StoreAppPresence presence = StoreAppPresence.notInstalled,
    bool confirmedBefore = false,
    InstallHintDismissals dismissals = InstallHintDismissals.none,
  }) =>
      PlayInstallRules.shouldInvite(
        isProduction: isProduction,
        facts: BrowserInstallFacts(
            userAgent: userAgent, displayModeStandalone: standalone),
        presence: presence,
        appConfirmedBefore: confirmedBefore,
        dismissals: dismissals,
        now: now,
      );

  group('who is invited', () {
    test('Chrome on Android, the browser answered, the app is not listed', () {
      expect(invite(), isTrue);
    });

    test('never when the app IS listed — that reader gets the T-65 handoff',
        () {
      expect(invite(presence: StoreAppPresence.installed), isFalse);
    });

    test('never when the browser could not answer (no API, rejected promise)',
        () {
      // The T-38 shape: a service that cannot answer never becomes an offer.
      expect(invite(presence: StoreAppPresence.unknown), isFalse);
    });

    test('never on a browser that once confirmed the app (owner, 27/09/2026)',
        () {
      // After a confirmed install, an empty list is likelier a broken source
      // (T-65's four silent failures) than an uninstall.
      expect(invite(confirmedBefore: true), isFalse);
    });

    test('never off Android — desktop Chrome answers an empty list too', () {
      expect(invite(userAgent: chromeDesktop), isFalse);
      expect(invite(userAgent: iPhoneSafari), isFalse);
    });

    test('never in a web app already on the Home Screen (owner, 27/09/2026)',
        () {
      expect(invite(standalone: true), isFalse);
    });

    test('never in a dev build — it has no listing to point at', () {
      expect(invite(isProduction: false), isFalse);
    });
  });

  group('dismissals follow the U-54 rhythm', () {
    test('a dismissal snoozes for 14 days, then the invitation returns', () {
      final once = InstallHintDismissals.none.next(now);
      expect(invite(dismissals: once), isFalse);
      final later = InstallHintDismissals(
          count: 1, last: now.subtract(InstallHintRules.snooze));
      expect(invite(dismissals: later), isTrue);
    });

    test('the third dismissal is final', () {
      final longAgo = now.subtract(const Duration(days: 365));
      expect(
          invite(
              dismissals: InstallHintDismissals(
                  count: InstallHintRules.maxDismissals, last: longAgo)),
          isFalse);
    });
  });

  group('the address it opens', () {
    test('the public listing, with the campaign the Play Console reads', () {
      final uri = PlayInstallRules.listingUri('com.entrelares.app');
      expect(uri.scheme, 'https');
      expect(uri.host, 'play.google.com');
      expect(uri.path, '/store/apps/details');
      expect(uri.queryParameters['id'], 'com.entrelares.app');
      // Play reads `referrer` as a query string of its own.
      expect(Uri.splitQueryString(uri.queryParameters['referrer']!), {
        'utm_source': 'web.entrelares.app',
        'utm_medium': 'shell-banner',
        'utm_campaign': 'play-invite',
      });
    });
  });

  group('isAndroid', () {
    test('reads the token every Android browser carries', () {
      expect(PlayInstallRules.isAndroid(chromeAndroid), isTrue);
      expect(PlayInstallRules.isAndroid(chromeDesktop), isFalse);
      expect(PlayInstallRules.isAndroid(iPhoneSafari), isFalse);
    });
  });
}
