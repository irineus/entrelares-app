import 'dart:convert';

import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-80 PR 1 — family referral, built DARK:
///   · `feature.referral` off → `my_referral_code` and `attribute_referral`
///     refuse, a sign-up's code is dropped, and no row is written anywhere;
///   · on → the code is opaque and stable per family, attribution happens
///     once (first touch wins), never to oneself, never for an old family,
///     never by a viewer or a non-founder; an unknown code answers exactly
///     what an already attributed family answers;
///   · the e-mail sign-up attributes in its own transaction and leaves no
///     code in the auth row;
///   · no client reads either table, and the anon key reaches only
///     `referral_enabled()`.
///
/// The flag is restored to what it was at the end of every test that flips it
/// — the gate runs on a local stack, but the suites share it.
void referralTests(GateFixture fx) {
  const flag = 'feature.referral';
  final shape = RegExp(r'^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{10}$');

  Future<T> withFlag<T>(String value, Future<T> Function() body) async {
    final before = await readFlag(fx, flag);
    await writeFlag(fx, flag, value);
    try {
      return await body();
    } finally {
      await writeFlag(fx, flag, before);
    }
  }

  Future<List<Map<String, dynamic>>> referralOf(int familyId) async =>
      (await fx.service
              .from('family_referrals')
              .select()
              .eq('referred_family_id', familyId))
          .cast<Map<String, dynamic>>();

  Future<List<Map<String, dynamic>>> codeRowOf(int familyId) async =>
      (await fx.service
              .from('family_referral_codes')
              .select()
              .eq('family_id', familyId))
          .cast<Map<String, dynamic>>();

  Future<String> codeOf(SupabaseClient who) async =>
      await who.rpc<dynamic>('my_referral_code') as String;

  Future<dynamic> attribute(
    SupabaseClient who,
    String code, {
    String channel = 'web',
  }) => who.rpc<dynamic>(
    'attribute_referral',
    params: {'p_code': code, 'p_channel': channel},
  );

  group('F-80 · referral', () {
    test('the settings are born dark, each with its T-80 metadata', () async {
      final rows = {
        for (final r
            in (await fx.service.from('app_settings').select().inFilter('key', [
              flag,
              'referral.hold_days',
              'referral.yearly_cap',
            ])).cast<Map<String, dynamic>>())
          r['key'] as String: r,
      };
      expect(
        rows.keys,
        unorderedEquals([flag, 'referral.hold_days', 'referral.yearly_cap']),
      );

      expect(rows[flag]!['value_type'], 'bool');
      expect(rows[flag]!['category'], 'features');
      expect(rows[flag]!['is_public'], isTrue);
      expect(rows[flag]!['impact'], 'critical');

      final hold = rows['referral.hold_days']!;
      expect(
        [hold['value'], hold['unit'], hold['min_value'], hold['max_value']],
        ['30', 'days', 7, 90],
      );
      expect(hold['is_public'], isFalse);
      final cap = rows['referral.yearly_cap']!;
      expect(
        [cap['value'], cap['unit'], cap['min_value'], cap['max_value']],
        ['12', 'count', 1, 24],
      );
      expect(cap['is_public'], isFalse);

      for (final r in rows.values) {
        expect((r['description'] as String).length, lessThanOrEqualTo(120));
      }
    });

    test('dark: both RPCs refuse and nothing is written', () async {
      await withFlag('false', () async {
        final fam = await fx.createFamily('f80off');
        await expectRejected(
          () => codeOf(fam.admin),
          contains: 'ainda não está disponível',
        );
        await expectRejected(
          () => attribute(fam.admin, 'ABCDEFGH23'),
          contains: 'ainda não está disponível',
        );
        expect(await codeRowOf(fam.familyId), isEmpty);
        expect(await referralOf(fam.familyId), isEmpty);
        expect(
          await fx.newAnonClient().rpc<dynamic>('referral_enabled'),
          isFalse,
        );
      });
    });

    test('dark: a sign-up carrying a code attributes nothing and keeps no '
        'trace of it in the auth row', () async {
      // A code that EXISTS, so only the flag can be what stops it.
      final code = await withFlag('true', () => codeOf(fx.founder));
      await withFlag('false', () async {
        final fam = await fx.createFamily(
          'f80offsu',
          founderMetadata: {'referral_code': code, 'referral_channel': 'web'},
        );
        expect(await referralOf(fam.familyId), isEmpty);
        final meta = fam.admin.auth.currentUser!.userMetadata!;
        expect(meta.containsKey('referral_code'), isFalse);
        expect(meta.containsKey('referral_channel'), isFalse);
        expect(jsonEncode(meta), isNot(contains(code)));
      });
    });

    test(
      'the code is opaque, stable, and the same for the whole family',
      () async {
        await withFlag('true', () async {
          expect(
            await fx.newAnonClient().rpc<dynamic>('referral_enabled'),
            isTrue,
          );
          final fam = await fx.createFamily('f80code');
          final first = await codeOf(fam.admin);
          expect(first, matches(shape));
          expect(await codeOf(fam.admin), first, reason: 'stable');
          expect(await codeOf(fam.member), first, reason: 'one per family');
          expect(first, isNot(contains(fam.familyId.toString())));
          expect(await codeRowOf(fam.familyId), hasLength(1));

          final other = await createFamilyCode(fx, 'f80ref2', codeOf);
          expect(other, isNot(first));
        });
      },
    );

    test('a viewer gets no code', () async {
      const viewersFlag = 'feature.viewers';
      final viewersBefore = await readFlag(fx, viewersFlag);
      await writeFlag(fx, viewersFlag, 'true');
      try {
        await withFlag('true', () async {
          final fam = await fx.createFamily('f80vw');
          final email = fx.testEmail('f80viewer');
          final rows = await fam.admin.rpc<dynamic>(
            'create_viewer_invitation',
            params: {'p_email': email, 'p_role_id': fx.roleId('grandmother')},
          );
          final token = (rows as List).single['token'] as String;
          await fx.createInvitedUser(email, token, fullName: 'E2E Vó F80');
          final viewer = await fx.signIn(email);
          await expectRejected(
            () => codeOf(viewer),
            contains: 'Somente responsáveis',
          );
          await expectRejected(
            () => attribute(viewer, 'ABCDEFGH23'),
            contains: 'Somente quem criou',
          );
          expect(await codeRowOf(fam.familyId), isEmpty);
        });
      } finally {
        await writeFlag(fx, viewersFlag, viewersBefore);
      }
    });

    test(
      'the founder attributes once; a second call is a quiet no-op',
      () async {
        await withFlag('true', () async {
          final referrerCode = await codeOf(fx.founder);
          final fam = await fx.createFamily('f80attr');

          expect(
            await attribute(fam.admin, referrerCode.toLowerCase()),
            'attributed',
          );
          final rows = await referralOf(fam.familyId);
          expect(rows, hasLength(1));
          expect(rows.single['referrer_family_id'], fx.familyId);
          expect(rows.single['code'], referrerCode);
          expect(rows.single['channel'], 'web');
          expect(rows.single['status'], 'attributed');
          expect(rows.single['first_paid_at'], isNull);

          // First touch wins: another code later changes nothing.
          final otherCode = await createFamilyCode(fx, 'f80ref3', codeOf);
          expect(
            await attribute(fam.admin, otherCode, channel: 'android'),
            'ignored',
          );
          expect(await attribute(fam.admin, referrerCode), 'ignored');
          final after = await referralOf(fam.familyId);
          expect(after.single['referrer_family_id'], fx.familyId);
          expect(after.single['channel'], 'web');
        });
      },
    );

    test('an unknown code answers what an attributed family answers — '
        'nothing about any code leaks', () async {
      await withFlag('true', () async {
        final fam = await fx.createFamily('f80unk');
        expect(await attribute(fam.admin, 'ZZZZZZZZZZ'), 'ignored');
        expect(await attribute(fam.admin, 'not a code'), 'ignored');
        expect(await attribute(fam.admin, ''), 'ignored');
        expect(await referralOf(fam.familyId), isEmpty);
      });
    });

    test(
      'no self-referral, no non-founder, no bad channel, no old family',
      () async {
        await withFlag('true', () async {
          final fam = await fx.createFamily('f80self');
          final own = await codeOf(fam.admin);
          await expectRejected(
            () => attribute(fam.admin, own),
            contains: 'si mesma',
          );

          final referrerCode = await codeOf(fx.founder);
          await expectRejected(
            () => attribute(fam.member, referrerCode),
            contains: 'Somente quem criou',
          );
          await expectRejected(
            () => attribute(fam.admin, referrerCode, channel: 'ios'),
            contains: 'Canal',
          );
          expect(await referralOf(fam.familyId), isEmpty);

          final old = await fx.createFamily('f80old');
          await fx.service
              .from('families')
              .update({
                'created_at': DateTime.now()
                    .toUtc()
                    .subtract(const Duration(days: 2))
                    .toIso8601String(),
              })
              .eq('id', old.familyId);
          await expectRejected(
            () => attribute(old.admin, referrerCode),
            contains: 'cadastro',
          );
          expect(await referralOf(old.familyId), isEmpty);
        });
      },
    );

    test('the e-mail sign-up attributes in its own transaction and strips '
        'the code from the auth row', () async {
      await withFlag('true', () async {
        final referrerCode = await codeOf(fx.founder);
        final fam = await fx.createFamily(
          'f80signup',
          founderMetadata: {
            'referral_code': referrerCode.toLowerCase(),
            'referral_channel': 'web',
          },
        );
        final rows = await referralOf(fam.familyId);
        expect(rows, hasLength(1));
        expect(rows.single['referrer_family_id'], fx.familyId);
        expect(rows.single['channel'], 'web');

        final meta = fam.admin.auth.currentUser!.userMetadata!;
        expect(meta.containsKey('referral_code'), isFalse);
        expect(meta.containsKey('referral_channel'), isFalse);
        // The rest of the sign-up metadata is untouched.
        expect(meta['role'], 'father');

        // A sign-up with an unknown code is still a sign-up.
        final unknown = await fx.createFamily(
          'f80signupx',
          founderMetadata: {'referral_code': 'ZZZZZZZZZZ'},
        );
        expect(await referralOf(unknown.familyId), isEmpty);
        expect(unknown.adminProfile.isAdmin, isTrue);
      });
    });

    test(
      'no client reads either table; the anon key reaches only the flag',
      () async {
        await withFlag('true', () async {
          await codeOf(fx.founder);
          for (final who in [fx.founder, fx.member, fx.founderB]) {
            for (final table in ['family_referral_codes', 'family_referrals']) {
              List<dynamic> seen;
              try {
                seen = await who.from(table).select();
              } catch (_) {
                seen = const [];
              }
              expect(seen, isEmpty, reason: '$table leaked to a client');
            }
            await expectRejected(
              () => who.rpc<dynamic>(
                'referral_attribute_family',
                params: {
                  'p_family_id': fx.familyId,
                  'p_code': 'ABCDEFGH23',
                  'p_channel': 'web',
                },
              ),
            );
            await expectRejected(() => who.rpc<dynamic>('referral_new_code'));
          }
          final anon = fx.newAnonClient();
          await expectRejected(() => anon.rpc<dynamic>('my_referral_code'));
          await expectRejected(() => attribute(anon, 'ABCDEFGH23'));
          expect(await anon.rpc<dynamic>('referral_enabled'), isTrue);
        });
      },
    );

    test('the bulletin counts the week\'s referrals only while the module is '
        'on', () async {
      Future<Map<String, dynamic>> bulletin() async {
        final raw = await fx.service.rpc<dynamic>(
          'admin_weekly_sales_bulletin',
          params: {'p_week_start': isoDate(saoPauloToday())},
        );
        return (raw is String ? jsonDecode(raw) : raw) as Map<String, dynamic>;
      }

      await withFlag('false', () async {
        expect((await bulletin())['referrals'], isNull);
      });
      await withFlag('true', () async {
        final before = (await bulletin())['referrals'] as int;
        final referrerCode = await codeOf(fx.founder);
        final fam = await fx.createFamily('f80blt');
        expect(await attribute(fam.admin, referrerCode), 'attributed');
        expect((await bulletin())['referrals'], before + 1);
      });
    });
  });
}

/// A fresh family's own code — a second referrer for the first-touch test.
Future<String> createFamilyCode(
  GateFixture fx,
  String tag,
  Future<String> Function(SupabaseClient who) codeOf,
) async {
  final fam = await fx.createFamily(tag);
  return codeOf(fam.admin);
}
