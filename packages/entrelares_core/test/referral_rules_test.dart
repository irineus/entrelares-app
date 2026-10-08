import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'mirrors/repo_files.dart';

/// F-80 — the referral code as the client handles it, and the two promises
/// around it: the client's shape is the server's, and the code never reaches
/// Umami.
void main() {
  const migration = 'supabase/migrations/20261002200000_f80_referral_model.sql';

  group('ReferralRules.parseCode', () {
    test('a code of the alphabet and the length is a code', () {
      expect(ReferralRules.parseCode('ABCDEFGH23'), 'ABCDEFGH23');
      expect(ReferralRules.parseCode('ZZZZZZZZZZ'), 'ZZZZZZZZZZ');
    });

    test('case and surrounding spaces are forgiven', () {
      expect(ReferralRules.parseCode('  abcdefgh23 '), 'ABCDEFGH23');
    });

    test('a wrong length is not a code', () {
      expect(ReferralRules.parseCode('ABCDEFGH2'), isNull);
      expect(ReferralRules.parseCode('ABCDEFGH234'), isNull);
      expect(ReferralRules.parseCode(''), isNull);
      expect(ReferralRules.parseCode(null), isNull);
    });

    test('the ambiguous symbols are not in the alphabet', () {
      for (final bad in ['0', 'O', '1', 'I']) {
        expect(ReferralRules.parseCode('ABCDEFGH2$bad'), isNull, reason: bad);
      }
    });

    test('nothing but the alphabet passes — no URL, no e-mail, no space', () {
      expect(ReferralRules.parseCode('ABCDE FGH2'), isNull);
      expect(ReferralRules.parseCode('ABCD@FGH23'), isNull);
      expect(ReferralRules.parseCode('ABCD/FGH23'), isNull);
      expect(ReferralRules.parseCode('ABCDEFGH2-'), isNull);
    });
  });

  group('ReferralRules.codeFromUri', () {
    test('reads ref from the sign-up link', () {
      expect(
        ReferralRules.codeFromUri(
          Uri.parse('https://web.entrelares.app/register?ref=abcdefgh23'),
        ),
        'ABCDEFGH23',
      );
    });

    test('only /register is a referral link', () {
      expect(
        ReferralRules.codeFromUri(
          Uri.parse('https://web.entrelares.app/login?ref=ABCDEFGH23'),
        ),
        isNull,
      );
      expect(
        ReferralRules.codeFromUri(
          Uri.parse('https://web.entrelares.app/?ref=ABCDEFGH23'),
        ),
        isNull,
      );
    });

    test('an invitation wins — the invitee founds no family', () {
      expect(
        ReferralRules.codeFromUri(
          Uri.parse(
            'https://web.entrelares.app/register?invite=x&ref=ABCDEFGH23',
          ),
        ),
        isNull,
      );
    });

    test('a mangled ref is no code', () {
      expect(
        ReferralRules.codeFromUri(
          Uri.parse('https://web.entrelares.app/register?ref=ABC'),
        ),
        isNull,
      );
      expect(
        ReferralRules.codeFromUri(
          Uri.parse('https://web.entrelares.app/register'),
        ),
        isNull,
      );
    });
  });

  test('the channel is the server CHECK vocabulary', () {
    expect(ReferralRules.channel(isWeb: true), 'web');
    expect(ReferralRules.channel(isWeb: false), 'android');
    expect(
      repoFile(migration),
      contains("CHECK (channel IN ('web', 'android'))"),
    );
  });

  test('the code never reaches Umami: the pageview path drops the query', () {
    expect(sanitizeAnalyticsPath('/register?ref=ABCDEFGH23'), '/register');
    expect(
      sanitizeAnalyticsPath(
        'https://web.entrelares.app/register?ref=ABCDEFGH23#x',
      ),
      '/register',
    );
    // And no event declares a key a code could ride in.
    expect(AnalyticsCatalog.props[AnalyticsEvents.referralSignup], {'channel'});
    expect(
      AnalyticsCatalog.filterProps(AnalyticsEvents.referralSignup, {
        'channel': 'web',
        'code': 'ABCDEFGH23',
        'ref': 'ABCDEFGH23',
      }),
      {'channel': 'web'},
    );
  });

  group('mirror — the server draws and checks the same shape', () {
    // The server's generator and its shape check are duplicated here on
    // purpose (the client must not send what the server would drop). A drift
    // would make every link look mangled to one side and valid to the other.
    final sql = repoFile(migration);

    test('the generator draws from the same 32 symbols', () {
      expect(
        ReferralRules.alphabet.length,
        32,
        reason: '`get_byte & 31` needs exactly 32 symbols to be unbiased',
      );
      expect(ReferralRules.alphabet.split('').toSet(), hasLength(32));
      expect(
        sql,
        contains("alphabet constant text := '${ReferralRules.alphabet}';"),
      );
      expect(sql, contains('gen_random_bytes(${ReferralRules.length})'));
      expect(sql, contains('FOR i IN 0..${ReferralRules.length - 1} LOOP'));
    });

    test('the shape check is the same regex', () {
      expect(
        sql,
        contains("'^[${ReferralRules.alphabet}]{${ReferralRules.length}}\$'"),
      );
    });
  });

  test('the flag is dark by default on the client too', () {
    expect(PublicSettings.unloaded.referralEnabled, isFalse);
    expect(
      const PublicSettings({'feature.referral': 'true'}).referralEnabled,
      isTrue,
    );
    expect(
      repoFile(migration),
      contains("('feature.referral', 'false', 'bool', 'features',"),
    );
  });

  group('U-61 — ReferralRules.offerCard', () {
    test('a complete, active family is offered the card', () {
      expect(
          ReferralRules.offerCard(
              enabled: true,
              isActiveMember: true,
              isViewer: false,
              hasOtherActiveMember: true,
              hasAnyPlannedDay: true),
          isTrue);
    });

    test('a founder alone, or a family with no plan, is not — nor a viewer, '
        'a departed member, or anyone while the flag is dark', () {
      bool offer({
        bool enabled = true,
        bool active = true,
        bool viewer = false,
        bool other = true,
        bool plan = true,
      }) =>
          ReferralRules.offerCard(
              enabled: enabled,
              isActiveMember: active,
              isViewer: viewer,
              hasOtherActiveMember: other,
              hasAnyPlannedDay: plan);
      expect(offer(other: false), isFalse,
          reason: 'the audit saw the card on a one-member family that had '
              'not even invited the co-parent');
      expect(offer(plan: false), isFalse);
      expect(offer(viewer: true), isFalse);
      expect(offer(active: false), isFalse);
      expect(offer(enabled: false), isFalse);
    });
  });

  group('F-80 PR 2 — ReferralRules.codeFromInstallReferrer', () {
    test('reads ref from the referrer string Play hands back', () {
      expect(
        ReferralRules.codeFromInstallReferrer(
          'utm_source=entrelares.app&utm_medium=referral'
          '&utm_campaign=family-referral&ref=abcdefgh23',
        ),
        'ABCDEFGH23',
      );
      expect(ReferralRules.codeFromInstallReferrer('ref=ABCDEFGH23'),
          'ABCDEFGH23');
    });

    test('an organic install and the shell banner carry no code', () {
      expect(
        ReferralRules.codeFromInstallReferrer(
            'utm_source=google-play&utm_medium=organic'),
        isNull,
      );
      expect(
        ReferralRules.codeFromInstallReferrer(PlayInstallRules.referrer),
        isNull,
      );
    });

    test('the code is read from ref only — never from utm_content', () {
      expect(
        ReferralRules.codeFromInstallReferrer('utm_content=ABCDEFGH23'),
        isNull,
      );
    });

    test('a referrer encoded once more is unwrapped once', () {
      expect(
        ReferralRules.codeFromInstallReferrer(
            'utm_source%3Dentrelares.app%26ref%3DABCDEFGH23'),
        'ABCDEFGH23',
      );
    });

    test('nothing, garbage and a mangled code are no code — and never throw',
        () {
      for (final raw in [
        null,
        '',
        '   ',
        'ref=',
        'ref=ABC',
        'ref=ABCDEFGH2O', // the letter O is not in the alphabet
        '%%%',
        'ref=%E0%A4%A',
        'not a query at all',
      ]) {
        expect(ReferralRules.codeFromInstallReferrer(raw), isNull,
            reason: '$raw');
      }
    });

    test('what the builder writes, the reader reads — through the Play link',
        () {
      final listing = PlayInstallRules.listingUri('com.entrelares.app',
          referrer: ReferralRules.installReferrer('ABCDEFGH23'));
      // Play stores the DECODED `referrer` value and returns it as is.
      final stored = listing.queryParameters['referrer'];
      expect(ReferralRules.codeFromInstallReferrer(stored), 'ABCDEFGH23');
      // The campaign keys stay what the Play Console reads, with no code.
      final parts = Uri.splitQueryString(stored!);
      expect(parts['utm_source'], 'entrelares.app');
      expect(parts['utm_medium'], 'referral');
      expect(parts['utm_campaign'], 'family-referral');
      expect(
        parts.entries
            .where((e) => e.key.startsWith('utm_'))
            .map((e) => e.value),
        isNot(contains('ABCDEFGH23')),
      );
    });
  });

  test('F-80 PR 2 — the shared link is the landing page /i/<code>', () {
    expect(ReferralRules.shareLink('ABCDEFGH23'),
        'https://entrelares.app/i/ABCDEFGH23');
  });

  test('F-80 PR 2 — the share event carries the channel and never the code',
      () {
    expect(AnalyticsCatalog.props[AnalyticsEvents.referralShare], {'channel'});
    expect(
      AnalyticsCatalog.filterProps(AnalyticsEvents.referralShare, {
        'channel': 'android',
        'code': 'ABCDEFGH23',
        'link': 'https://entrelares.app/i/ABCDEFGH23',
      }),
      {'channel': 'android'},
    );
  });
}
