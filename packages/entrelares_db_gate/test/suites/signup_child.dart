import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// U-61 — the founder may name the child at sign-up, and the name becomes the
/// family's first `children` row (F-55's entity) through ONE writer, the
/// `families_add_signup_child` trigger:
///   · the e-mail sign-up carries it in the signUp metadata; the server
///     writes the child in the same transaction and STRIPS the key from the
///     auth row — a child's name never rests on `auth.users`;
///   · the Google door passes it to `complete_oauth_onboarding`, whose older
///     six-argument call still works and names nobody;
///   · the name is normalised by F-55's `child_normalize_name`; an invalid
///     one is DROPPED and the account is created all the same — the field is
///     optional and the client validates it;
///   · with `feature.child_agenda` off nothing is written (T-84).
void signupChildTests(GateFixture fx) {
  const flag = 'feature.child_agenda';

  Future<List<Map<String, dynamic>>> childrenOf(int familyId) async =>
      (await fx.service
              .from('children')
              .select()
              .eq('family_id', familyId)
              .order('sort_order', ascending: true))
          .cast<Map<String, dynamic>>();

  Future<int> familyOf(String email) async => (await fx.service
          .from('profiles')
          .select('family_id')
          .eq('email', email))
      .single['family_id'] as int;

  group('U-61 · child first name at sign-up', () {
    late String flagBefore;

    setUpAll(() async {
      flagBefore = await readFlag(fx, flag);
      await writeFlag(fx, flag, 'true');
    });

    tearDownAll(() => writeFlag(fx, flag, flagBefore));

    test('the e-mail sign-up writes the first child and strips the auth row',
        () async {
      final fam = await fx.createFamily('u61named', founderMetadata: {
        ChildRules.signupMetadataKey: '  Sofia   Maria ',
      });
      final rows = await childrenOf(fam.familyId);
      expect(rows, hasLength(1));
      expect(rows.single['first_name'], 'Sofia Maria',
          reason: 'trimmed and collapsed, like add_child');
      expect(rows.single['sort_order'], 0);
      expect(rows.single['created_by'], isNull,
          reason: 'the founder\'s profile is inserted after the family');

      final meta = fam.admin.auth.currentUser!.userMetadata!;
      expect(meta.containsKey(ChildRules.signupMetadataKey), isFalse,
          reason: 'a child\'s name never rests on the auth row');
      expect(meta['role'], 'father', reason: 'the rest is untouched');

      // The invitee of that family carried nothing and created nothing more.
      expect(await childrenOf(fam.familyId), hasLength(1));
    });

    test('no name: no child — the field is optional', () async {
      final fam = await fx.createFamily('u61none');
      expect(await childrenOf(fam.familyId), isEmpty);
    });

    test('an invalid name is dropped, never a refused account', () async {
      final fam = await fx.createFamily('u61long', founderMetadata: {
        ChildRules.signupMetadataKey: 'A' * (ChildRules.maxNameLength + 1),
      });
      expect(fam.familyId, isPositive);
      expect(await childrenOf(fam.familyId), isEmpty);
      final meta = fam.admin.auth.currentUser!.userMetadata!;
      expect(meta.containsKey(ChildRules.signupMetadataKey), isFalse);
    });

    test('the Google door writes the child; the six-argument call names nobody',
        () async {
      Future<int> onboard(String tag, Map<String, dynamic> extra) async {
        final email = await fx.createOauthUser(tag);
        final client = await fx.signIn(email);
        await client.rpc<dynamic>('complete_oauth_onboarding', params: {
          'p_full_name': 'E2E U61 $tag',
          'p_role': 'father',
          'p_family_name': '${TestEnv.e2eFamilyPrefix}${fx.runId}-$tag',
          'p_policy_version': PolicyVersions.current,
          ...extra,
        });
        return familyOf(email);
      }

      final named = await onboard('u61oauth', {'p_child_first_name': ' Theo '});
      final rows = await childrenOf(named);
      expect(rows, hasLength(1));
      expect(rows.single['first_name'], 'Theo');

      final old = await onboard('u61oauth6', {
        'p_acquisition_source': 'meta',
        'p_acquisition_campaign': 'turma',
      });
      expect(await childrenOf(old), isEmpty);
    });

    test('with the module dark nothing is written (T-84)', () async {
      await writeFlag(fx, flag, 'false');
      try {
        final fam = await fx.createFamily('u61dark', founderMetadata: {
          ChildRules.signupMetadataKey: 'Lia',
        });
        expect(await childrenOf(fam.familyId), isEmpty);
        final meta = fam.admin.auth.currentUser!.userMetadata!;
        expect(meta.containsKey(ChildRules.signupMetadataKey), isFalse,
            reason: 'stripped whatever the flag says');
      } finally {
        await writeFlag(fx, flag, 'true');
      }
    });
  });
}
