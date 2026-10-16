import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

import 'mirrors/repo_files.dart';

/// T-101 — where a new family came from: one test per branch of the
/// precedence, on both doors, and the two promises around it — the client's
/// vocabulary and token shape are the server's, and the source never reaches
/// Umami.
void main() {
  const migration =
      'supabase/migrations/20261004120000_t101_acquisition_source.sql';
  const code = 'ABCDEFGH23';

  group('fromInstallReferrer (Android, Play Install Referrer)', () {
    test('a referral code wins over everything else', () {
      expect(
        AcquisitionRules.fromInstallReferrer(
            'utm_source=meta&utm_campaign=x&gclid=abc&ref=$code'),
        Acquisition.referral,
      );
      // The F-80 string itself.
      expect(
        AcquisitionRules.fromInstallReferrer(
            ReferralRules.installReferrer(code)),
        Acquisition.referral,
      );
    });

    test('Google Ads auto-tagging (gclid / gbraid) is the app campaign', () {
      expect(
        AcquisitionRules.fromInstallReferrer('gclid=Cj0KCQjw-abc_123'),
        const Acquisition(AcquisitionRules.googleApp),
      );
      expect(
        AcquisitionRules.fromInstallReferrer(
            'gbraid=0AAAAA&utm_campaign=Primeira-Turma'),
        const Acquisition(AcquisitionRules.googleApp, 'primeira-turma'),
      );
      expect(
        AcquisitionRules.fromInstallReferrer(
            'utm_source=google&utm_medium=cpc&utm_campaign=app'),
        const Acquisition(AcquisitionRules.googleApp, 'app'),
      );
    });

    test('our own source words, with the campaign', () {
      expect(
        AcquisitionRules.fromInstallReferrer(
            'utm_source=meta&utm_medium=paid&utm_campaign=primeira-turma'),
        const Acquisition(AcquisitionRules.meta, 'primeira-turma'),
      );
      expect(
        AcquisitionRules.fromInstallReferrer('utm_source=google_search'),
        const Acquisition(AcquisitionRules.googleSearch),
      );
    });

    test('a referrer encoded once more is unwrapped once', () {
      expect(
        AcquisitionRules.fromInstallReferrer(
            'utm_source%3Dmeta%26utm_campaign%3Dt1'),
        const Acquisition(AcquisitionRules.meta, 't1'),
      );
    });

    test('no signal, or only an organic marker, is organic', () {
      for (final raw in [
        null,
        '',
        '   ',
        'utm_source=google-play&utm_medium=organic',
        'utm_source=(not%20set)&utm_medium=(not%20set)',
        PlayInstallRules.referrer,
        'utm_medium=organic',
      ]) {
        expect(AcquisitionRules.fromInstallReferrer(raw), Acquisition.organic,
            reason: '$raw');
      }
    });

    test('a signal that is none of ours is unknown', () {
      for (final raw in [
        'utm_source=tiktok&utm_campaign=x',
        'garbage-without-pairs',
        'ref=NOTACODE',
        'utm_source=referral',
        'utm_source=organic-but-not-really',
      ]) {
        expect(AcquisitionRules.fromInstallReferrer(raw), Acquisition.unknown,
            reason: raw);
      }
    });

    test('a malformed encoding is unknown, never a throw', () {
      expect(AcquisitionRules.fromInstallReferrer('%E0%A4%A'),
          Acquisition.unknown);
    });
  });

  group('fromUri (web, /register)', () {
    Acquisition? of(String url) =>
        AcquisitionRules.fromUri(Uri.parse('https://web.entrelares.app$url'));

    test('a referral code wins over the source word', () {
      expect(of('/register?ref=$code&src=meta'), Acquisition.referral);
    });

    test('our source words, with the campaign', () {
      expect(of('/register?src=meta&cmp=primeira-turma'),
          const Acquisition(AcquisitionRules.meta, 'primeira-turma'));
      expect(of('/register?src=GOOGLE_SEARCH'),
          const Acquisition(AcquisitionRules.googleSearch));
    });

    test('no signal is organic', () {
      expect(of('/register'), Acquisition.organic);
      expect(of('/register?lang=en'), Acquisition.organic);
    });

    test('a signal that is none of ours is unknown', () {
      expect(of('/register?src=tiktok'), Acquisition.unknown);
      expect(of('/register?src=organic'), Acquisition.unknown);
      expect(of('/register?ref=bad'), Acquisition.unknown);
    });

    test('an invitation, or another route, carries no source', () {
      expect(of('/register?invite=tok&src=meta'), isNull);
      expect(of('/login?src=meta'), isNull);
    });
  });

  group('campaignToken', () {
    test('our naming passes, lower-cased', () {
      expect(AcquisitionRules.campaignToken('Primeira-Turma_1'),
          'primeira-turma_1');
    });

    test('free text never passes', () {
      for (final bad in [
        '',
        ' ',
        '-starts-with-dash',
        'has space',
        'acentuação',
        'a@b.com',
        'https://x',
        'x' * 41,
        null,
      ]) {
        expect(AcquisitionRules.campaignToken(bad), isNull, reason: '$bad');
      }
      expect(AcquisitionRules.campaignToken('x' * 40), 'x' * 40);
    });
  });

  group('the server agrees', () {
    test('the closed vocabulary is the migration CHECK, word for word', () {
      final sql = repoFile(migration);
      final check = RegExp(r"acquisition_source IN \(([^)]*)\)").firstMatch(sql);
      expect(check, isNotNull, reason: 'CHECK not found in $migration');
      final words = RegExp(r"'([a-z_]+)'")
          .allMatches(check!.group(1)!)
          .map((m) => m.group(1))
          .toList();
      expect(words, AcquisitionRules.sources);
    });

    test('the campaign shape is the migration\'s', () {
      final sql = repoFile(migration);
      expect(sql, contains(r"'^[a-z0-9][a-z0-9_-]{0,39}$'"));
    });

    test('the metadata keys are the ones the server strips', () {
      final sql = repoFile(migration);
      expect(sql, contains("'${AcquisitionRules.sourceMetadataKey}'"));
      expect(sql, contains("'${AcquisitionRules.campaignMetadataKey}'"));
    });
  });

  test('the source never reaches Umami', () {
    expect(
      sanitizeAnalyticsPath('/register?src=meta&cmp=primeira-turma'),
      isNot(contains('meta')),
    );
    for (final entry in AnalyticsCatalog.props.entries) {
      expect(entry.value, isNot(contains('acquisition_source')),
          reason: entry.key);
      expect(entry.value, isNot(contains('campaign')), reason: entry.key);
    }
  });
}
