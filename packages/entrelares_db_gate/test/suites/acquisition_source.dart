import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// T-101 — every new family records where it came from, once, and the
/// bulletin reads the real cohort apart from the testers:
///   · the e-mail sign-up carries the word in its metadata, the server stamps
///     the family in the same transaction and strips the keys from the auth
///     row (on the INSERT and on GoTrue's write-back);
///   · the Google door passes it to `complete_oauth_onboarding`, whose
///     four-argument call (an older build) still works and reads `organic`;
///   · precedence: a referral (F-80's stash) → `referral`; no word →
///     `organic`; a word that is not ours → `unknown`; a misshaped campaign is
///     dropped;
///   · the columns are WRITE-ONCE, for the service role too;
///   · `acquisition.real_cohort_start` is born with its T-80 metadata and
///     refuses anything but a date;
///   · the bulletin's `real_cohort` counts each family under its source, and a
///     family created before the start under the test cohort.
///
/// The bulletin is global, so its counts are asserted as DELTAS around the
/// seeding, inside one test. The cohort start is moved to TODAY for the
/// bulletin tests (the default, 2026-10-05, may be ahead of the stack's
/// clock) and restored at the end.
void acquisitionSourceTests(GateFixture fx) {
  const cohortKey = 'acquisition.real_cohort_start';

  Future<Map<String, dynamic>> familyRow(int familyId) async => (await fx
          .service
          .from('families')
          .select('acquisition_source, acquisition_campaign, created_at')
          .eq('id', familyId))
      .single;

  Future<Map<String, dynamic>> cohort() async {
    final response = await fx.service.rpc<dynamic>(
        'admin_weekly_sales_bulletin',
        params: {'p_week_start': isoDate(saoPauloToday())});
    final b = (response is String ? jsonDecode(response) : response)
        as Map<String, dynamic>;
    return b['real_cohort'] as Map<String, dynamic>;
  }

  Future<T> withCohortStart<T>(String value, Future<T> Function() body) async {
    final before = await readFlag(fx, cohortKey);
    await writeFlag(fx, cohortKey, value);
    try {
      return await body();
    } finally {
      await writeFlag(fx, cohortKey, before);
    }
  }

  group('T-101 · acquisition source', () {
    test('the cohort key is born with its T-80 metadata and takes only a date',
        () async {
      final row = (await fx.service
              .from('app_settings')
              .select()
              .eq('key', cohortKey))
          .single;
      expect(row['value'], '2026-10-05');
      expect(row['value_type'], 'string');
      expect(row['unit'], 'date');
      expect(row['is_public'], isFalse);
      expect((row['description'] as String).length, lessThanOrEqualTo(120));
      final help = row['help'] as Map<String, dynamic>;
      expect(help['shown_at'], ['email']);

      for (final bad in ['05/10/2026', '2026-13-01', 'amanhã', '']) {
        await expectRejected(() => writeFlag(fx, cohortKey, bad),
            contains: cohortKey);
      }
      expect(await readFlag(fx, cohortKey), '2026-10-05');
    });

    test('the e-mail sign-up stamps the family and strips the auth row',
        () async {
      final fam = await fx.createFamily('t101meta', founderMetadata: {
        AcquisitionRules.sourceMetadataKey: 'meta',
        AcquisitionRules.campaignMetadataKey: 'Primeira-Turma',
      });
      final row = await familyRow(fam.familyId);
      expect(row['acquisition_source'], 'meta');
      expect(row['acquisition_campaign'], 'primeira-turma');

      final meta = fam.admin.auth.currentUser!.userMetadata!;
      expect(meta.containsKey(AcquisitionRules.sourceMetadataKey), isFalse);
      expect(meta.containsKey(AcquisitionRules.campaignMetadataKey), isFalse);
      expect(meta['role'], 'father', reason: 'the rest is untouched');

      // The invitee of that family carried nothing and created nothing.
      expect(fam.memberProfile.familyId, fam.familyId);
    });

    test('no word is organic, a stranger word is unknown, a bad campaign '
        'is dropped', () async {
      final plain = await fx.createFamily('t101none');
      expect((await familyRow(plain.familyId))['acquisition_source'],
          'organic');

      final odd = await fx.createFamily('t101odd', founderMetadata: {
        AcquisitionRules.sourceMetadataKey: 'tiktok',
        AcquisitionRules.campaignMetadataKey: 'has space',
      });
      final row = await familyRow(odd.familyId);
      expect(row['acquisition_source'], 'unknown');
      expect(row['acquisition_campaign'], isNull);
    });

    test('a referral wins over the word the link carried', () async {
      const flag = 'feature.referral';
      final before = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
      try {
        final code =
            await fx.founder.rpc<dynamic>('my_referral_code') as String;
        final fam = await fx.createFamily('t101ref', founderMetadata: {
          'referral_code': code,
          'referral_channel': 'web',
          AcquisitionRules.sourceMetadataKey: 'meta',
        });
        final row = await familyRow(fam.familyId);
        expect(row['acquisition_source'], 'referral');
        expect(row['acquisition_campaign'], isNull);
      } finally {
        await writeFlag(fx, flag, before);
      }
    });

    test('the Google door records the word; the four-argument call is organic',
        () async {
      Future<int> onboard(String tag, Map<String, dynamic> extra) async {
        final email = await fx.createOauthUser(tag);
        final client = await fx.signIn(email);
        await client.rpc<dynamic>('complete_oauth_onboarding', params: {
          'p_full_name': 'E2E $tag',
          'p_role': 'father',
          'p_family_name': '${TestEnv.e2eFamilyPrefix}${fx.runId}-$tag',
          'p_policy_version': PolicyVersions.current,
          ...extra,
        });
        final familyId = (await client
                .from('profiles')
                .select('family_id')
                .eq('email', email))
            .single['family_id'] as int;
        fx.trackFamily(familyId);
        return familyId;
      }

      final ad = await onboard('t101oauth', {
        'p_acquisition_source': 'google_app',
        'p_acquisition_campaign': 'app-1',
      });
      final adRow = await familyRow(ad);
      expect(adRow['acquisition_source'], 'google_app');
      expect(adRow['acquisition_campaign'], 'app-1');

      final old = await onboard('t101oauthold', const {});
      expect((await familyRow(old))['acquisition_source'], 'organic');
    });

    test('the source is written once — not even the service role moves it',
        () async {
      final fam = await fx.createFamily('t101once', founderMetadata: {
        AcquisitionRules.sourceMetadataKey: 'google_search',
      });
      await expectRejected(
        () => fx.service
            .from('families')
            .update({'acquisition_source': 'meta'}).eq('id', fam.familyId),
        contains: 'origem',
      );
      await expectRejected(
        () => fx.service
            .from('families')
            .update({'acquisition_campaign': 'x'}).eq('id', fam.familyId),
        contains: 'origem',
      );
      // A family member reads the row, but writes nothing.
      await fam.admin
          .from('families')
          .update({'acquisition_source': 'meta'}).eq('id', fam.familyId);
      expect((await familyRow(fam.familyId))['acquisition_source'],
          'google_search');
    });

    test('the bulletin counts the real cohort per source, the testers apart',
        () async {
      await withCohortStart(isoDate(saoPauloToday()), () async {
        final before = await cohort();
        expect(before['start'], isoDate(saoPauloToday()));
        expect((before['by_source'] as Map).keys.toSet(),
            AcquisitionRules.sources.toSet());

        final fam = await fx.createFamily('t101cnt', founderMetadata: {
          AcquisitionRules.sourceMetadataKey: 'meta',
        });
        await fx.service.from('care_schedules').insert({
          'family_id': fam.familyId,
          'schedule_date': isoDate(fx.nextFutureDate()),
          'scheduled_parent_id': fam.adminProfile.id,
        });

        final after = await cohort();
        int delta(Map<String, dynamic> a, Map<String, dynamic> b,
                List<String> path) =>
            (path.fold<dynamic>(a, (n, k) => (n as Map)[k]) as int) -
            (path.fold<dynamic>(b, (n, k) => (n as Map)[k]) as int);

        expect(delta(after, before, ['by_source', 'meta', 'families']), 1);
        expect(delta(after, before, ['by_source', 'meta', 'created_week']), 1);
        expect(delta(after, before, ['by_source', 'meta', 'planned_7d']), 1);
        expect(delta(after, before, ['by_source', 'meta', 'invited']), 1,
            reason: 'createFamily invites the member');
        expect(
            delta(after, before, ['by_source', 'meta', 'invitee_joined']), 1);
        expect(delta(after, before, ['by_source', 'meta', 'paid']), 0);
        expect(delta(after, before, ['by_source', 'organic', 'families']), 0);
        expect(delta(after, before, ['test_cohort', 'families']), 0);

        // Created before the start → the test cohort.
        await fx.service.from('families').update({
          'created_at': DateTime.now()
              .toUtc()
              .subtract(const Duration(days: 3))
              .toIso8601String(),
        }).eq('id', fam.familyId);
        final moved = await cohort();
        expect(delta(moved, before, ['by_source', 'meta', 'families']), 0);
        expect(delta(moved, before, ['test_cohort', 'families']), 1);
      });
    });
  });
}
