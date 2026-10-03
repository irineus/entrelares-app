import 'dart:convert';

import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:http/http.dart' as http;
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_billing.dart';
import '_helpers.dart';

/// F-80 PR 3 — `referral_rewards_due()`: the referred family's first PAID
/// payment opens a `referral.hold_days` window; a reversal inside it cancels;
/// a clean window qualifies and pays the REFERRER one free month on its rail —
/// the trial or the paid period in SQL, Asaas and Play as `pending_rail` (Play
/// then through the `referral-rewards` Edge Function) — at most
/// `referral.yearly_cap` a calendar year, `capped` beyond it. The notice to the
/// referrer names no family. Nothing moves while `feature.referral` is off.
///
/// Every job call is scoped to the test's own family (`p_family_id`); the
/// referral rows are written straight through the service client (PR 1's suite
/// already proves the attribution path), with the ledger events backdated to
/// put a payment before, inside or after its window.
void referralRewardTests(GateFixture fx) {
  const flag = 'feature.referral';
  final billing = Billing(fx);
  var seq = 0;

  Future<T> withSetting<T>(
    String key,
    String value,
    Future<T> Function() body,
  ) async {
    final before = await readFlag(fx, key);
    await writeFlag(fx, key, value);
    try {
      return await body();
    } finally {
      await writeFlag(fx, key, before);
    }
  }

  Future<T> on<T>(Future<T> Function() body) => withSetting(flag, 'true', body);

  DateTime daysAgo(num days) => DateTime.now().toUtc().subtract(
    Duration(minutes: (days * 24 * 60).round()),
  );

  Future<void> refer(ThrowawayFamily referrer, ThrowawayFamily referred) =>
      fx.service.from('family_referrals').insert({
        'referred_family_id': referred.familyId,
        'referrer_family_id': referrer.familyId,
        'code': 'ABCDEFGH23',
        'channel': 'web',
      });

  Future<void> ledger(
    int familyId,
    String type,
    DateTime at, {
    Map<String, dynamic> payload = const {},
  }) => fx.service.from('billing_events').insert({
    'event_id': 'evt_e2e_f80r_${fx.runId}_${seq++}',
    'event_type': type,
    'family_id': familyId,
    'payload': payload,
    'received_at': at.toIso8601String(),
  });

  Future<Map<String, dynamic>> run(int familyId) async {
    final raw = await fx.service.rpc<dynamic>(
      'referral_rewards_due',
      params: {'p_family_id': familyId},
    );
    return (raw is String ? jsonDecode(raw) : raw) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> referral(ThrowawayFamily referred) async =>
      (await fx.service
              .from('family_referrals')
              .select()
              .eq('referred_family_id', referred.familyId))
          .single;

  Future<List<Map<String, dynamic>>> notices(int profileId) async =>
      (await fx.service
              .from('notifications')
              .select()
              .eq('recipient_profile_id', profileId)
              .eq('type', 'referral_reward')
              .order('id', ascending: true))
          .cast<Map<String, dynamic>>();

  Future<Map<String, dynamic>> familyRow(int id) async =>
      (await fx.service.from('families').select().eq('id', id)).single;

  DateTime at(Object? v) => DateTime.parse(v as String).toUtc();

  void near(DateTime actual, DateTime expected, {String? reason}) => expect(
    actual.difference(expected).inSeconds.abs(),
    lessThan(120),
    reason: reason ?? 'expected ~$expected, got $actual',
  );

  /// A referrer on the free plan with no trial and no subscription.
  Future<ThrowawayFamily> freeReferrer(String tag) async {
    final fam = await fx.createFamily(tag);
    await billing.setTrial(fam.familyId, null);
    await billing.setPlan(fam.familyId, 'free');
    return fam;
  }

  /// A referred family whose first payment (Asaas) was [paidDaysAgo] ago.
  Future<ThrowawayFamily> paidReferral(
    ThrowawayFamily referrer,
    String tag,
    num paidDaysAgo,
  ) async {
    final referred = await fx.createFamily(tag);
    await refer(referrer, referred);
    await ledger(referred.familyId, 'PAYMENT_CONFIRMED', daysAgo(paidDaysAgo));
    return referred;
  }

  Future<(int, Map<String, dynamic>)> callPlayRail(
    Map<String, dynamic> body, {
    String? key,
  }) async {
    Future<http.Response> send() => http.post(
      Uri.parse(Billing.functionUrl('referral-rewards')),
      headers: {
        ...TestEnv.keyHeaders(key ?? TestEnv.serviceRoleKey),
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );
    var response = await send();
    for (
      var attempt = 1;
      attempt <= 4 && response.statusCode == 503;
      attempt++
    ) {
      await Future<void>.delayed(Duration(seconds: 2 * attempt));
      response = await send();
    }
    return (
      response.statusCode,
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  const pt =
      'Uma família que vocês indicaram assinou o Premium: '
      'a sua família ganhou um mês de Premium.';

  group('F-80 · referral reward', () {
    test(
      'dark: the job, the settle RPC and the Play rail do nothing',
      () async {
        await withSetting(flag, 'false', () async {
          final referrer = await freeReferrer('f80r-dark');
          final referred = await paidReferral(referrer, 'f80r-darkd', 40);

          expect(await run(referred.familyId), {'skipped': 'dark'});
          expect((await referral(referred))['status'], 'attributed');
          await expectRejected(
            () => fx.service.rpc<dynamic>(
              'referral_reward_delivered',
              params: {'p_referred_family_id': referred.familyId},
            ),
            contains: 'ainda não está disponível',
          );
          final (status, body) = await callPlayRail({
            'family_id': referrer.familyId,
          });
          expect(status, 200);
          expect(body, {'skipped': 'dark'});
          expect((await familyRow(referrer.familyId))['trial_ends_at'], isNull);
          expect(await notices(referrer.adminProfile.id), isEmpty);
        });
      },
    );

    test(
      'the first paid payment opens the window; a re-run keeps it',
      () async {
        await on(() async {
          final referrer = await freeReferrer('f80r-paid');
          final referred = await fx.createFamily('f80r-paidd');
          await refer(referrer, referred);
          final paidAt = daysAgo(2);
          await ledger(referred.familyId, 'PAYMENT_RECEIVED', paidAt);
          await ledger(referred.familyId, 'PAYMENT_CONFIRMED', daysAgo(1));

          expect((await run(referred.familyId))['paid'], 1);
          final row = await referral(referred);
          expect(row['status'], 'paid');
          near(at(row['first_paid_at']), paidAt);
          near(at(row['qualifies_at']), paidAt.add(const Duration(days: 30)));

          await run(referred.familyId);
          expect((await referral(referred))['status'], 'paid');
          expect(await notices(referrer.adminProfile.id), isEmpty);
        });
      },
    );

    test('a Play free trial is not a payment; a received one is', () async {
      await on(() async {
        final referrer = await freeReferrer('f80r-play1');
        final referred = await fx.createFamily('f80r-play1d');
        await refer(referrer, referred);
        await ledger(
          referred.familyId,
          'PLAY_PURCHASE_VERIFIED',
          daysAgo(3),
          payload: {
            'purchase': {'paymentState': 2},
          },
        );
        await ledger(referred.familyId, 'PLAY_RTDN_4', daysAgo(3));
        await run(referred.familyId);
        expect((await referral(referred))['status'], 'attributed');

        final paidAt = daysAgo(1);
        await ledger(
          referred.familyId,
          'PLAY_PURCHASE_VERIFIED',
          paidAt,
          payload: {
            'purchase': {'paymentState': 1},
          },
        );
        await run(referred.familyId);
        final row = await referral(referred);
        expect(row['status'], 'paid');
        near(at(row['first_paid_at']), paidAt);
      });
    });

    test('a refund or a chargeback inside the window cancels', () async {
      await on(() async {
        final referrer = await freeReferrer('f80r-rev');
        final refunded = await paidReferral(referrer, 'f80r-revr', 40);
        await ledger(refunded.familyId, 'PAYMENT_REFUNDED', daysAgo(35));
        final charged = await paidReferral(referrer, 'f80r-revc', 10);
        await ledger(
          charged.familyId,
          'PAYMENT_CHARGEBACK_REQUESTED',
          daysAgo(5),
        );
        final revoked = await fx.createFamily('f80r-revp');
        await refer(referrer, revoked);
        await ledger(revoked.familyId, 'PLAY_RTDN_2', daysAgo(12));
        await ledger(revoked.familyId, 'PLAY_RTDN_12', daysAgo(11));

        final counts = await run(referrer.familyId);
        expect(counts['cancelled'], 3);
        expect(counts['rewarded'], 0);
        for (final (fam, reason) in [
          (refunded, 'refunded'),
          (charged, 'chargeback'),
          (revoked, 'revoked'),
        ]) {
          final row = await referral(fam);
          expect(row['status'], 'cancelled');
          expect(row['cancel_reason'], reason);
          expect(row['cancelled_at'], isNotNull);
        }
        // Cancelled is terminal, and nobody was told anything.
        await run(referrer.familyId);
        expect((await referral(refunded))['status'], 'cancelled');
        expect(await notices(referrer.adminProfile.id), isEmpty);
        expect((await familyRow(referrer.familyId))['trial_ends_at'], isNull);
      });
    });

    test('a clean window pays a free referrer one month, once, and tells its '
        'caregivers without naming the family', () async {
      await on(() async {
        final referrer = await freeReferrer('f80r-free');
        expect(await billing.isPremium(referrer.familyId), isFalse);
        final referred = await paidReferral(referrer, 'f80r-freed', 40);
        // A refund AFTER the window is accepted risk: it changes nothing.
        await ledger(referred.familyId, 'PAYMENT_REFUNDED', daysAgo(5));

        final counts = await run(referred.familyId);
        expect(counts['paid'], 1);
        expect(counts['qualified'], 1);
        expect(counts['rewarded'], 1);

        final row = await referral(referred);
        expect(row['status'], 'rewarded');
        expect(row['reward_rail'], 'trial');
        expect(row['rewarded_at'], isNotNull);
        expect(row['reward_delivered_at'], isNotNull);
        final trialEnd = at(
          (await familyRow(referrer.familyId))['trial_ends_at'],
        );
        near(trialEnd, DateTime.now().toUtc().add(const Duration(days: 30)));
        // The entitlement check every gate reads sees the month.
        expect(await billing.isPremium(referrer.familyId), isTrue);

        final referredName =
            (await familyRow(referred.familyId))['name'] as String;
        for (final profile in [referrer.adminProfile, referrer.memberProfile]) {
          final n = await notices(profile.id);
          expect(n, hasLength(1), reason: 'every caregiver may hold the code');
          expect(n.single['title'], 'Um mês de Premium pela indicação');
          expect(n.single['message'], pt);
          expect(
            n.single['params'],
            {'kind': 'granted'},
            reason: 'nothing about the referred family travels',
          );
          expect(n.single['message'], isNot(contains(referredName)));
          expect(
            RegExp(r'\d').hasMatch(n.single['message'] as String),
            isFalse,
          );
        }
        // The referred family gets nothing extra, and hears nothing.
        expect(await notices(referred.adminProfile.id), isEmpty);
        expect(await notices(referred.memberProfile.id), isEmpty);

        // Idempotent: a re-run neither pays nor tells again.
        await run(referred.familyId);
        await run(referrer.familyId);
        expect(await notices(referrer.adminProfile.id), hasLength(1));
        near(
          at((await familyRow(referrer.familyId))['trial_ends_at']),
          trialEnd,
        );
      });
    });

    test('a running trial is extended from its own end', () async {
      await on(() async {
        final referrer = await fx.createFamily('f80r-trial');
        final end = DateTime.now().toUtc().add(const Duration(days: 10));
        await billing.setTrial(referrer.familyId, end);
        await paidReferral(referrer, 'f80r-triald', 31);

        await run(referrer.familyId);
        near(
          at((await familyRow(referrer.familyId))['trial_ends_at']),
          end.add(const Duration(days: 30)),
        );
      });
    });

    test(
      'paid time with no further charge gets the month on its period',
      () async {
        await on(() async {
          final referrer = await freeReferrer('f80r-period');
          await billing.setPlan(referrer.familyId, 'premium');
          final end = DateTime.now().toUtc().add(const Duration(days: 10));
          final sub = await billing.seed(
            referrer.familyId,
            'f80r-period-${fx.runId}',
            status: 'canceled',
            periodEnd: end,
          );
          final referred = await paidReferral(referrer, 'f80r-periodd', 33);

          await run(referred.familyId);
          final row = await referral(referred);
          expect(row['status'], 'rewarded');
          expect(row['reward_rail'], 'paid_period');
          near(
            (await billing.reload(sub.id)).currentPeriodEnd!.toUtc(),
            end.add(const Duration(days: 30)),
          );
          expect(
            (await familyRow(referrer.familyId))['trial_ends_at'],
            isNull,
            reason: 'the grace cron would clear a trial at the lapse',
          );
          expect(await notices(referrer.adminProfile.id), hasLength(1));
        });
      },
    );

    test('an Asaas subscriber waits as pending_rail until the operator '
        'settles it', () async {
      await on(() async {
        final referrer = await freeReferrer('f80r-asaas');
        await billing.setPlan(referrer.familyId, 'premium');
        final end = DateTime.now().toUtc().add(const Duration(days: 12));
        final sub = await billing.seed(
          referrer.familyId,
          'f80r-asaas-${fx.runId}',
          status: 'active',
          periodEnd: end,
        );
        final referred = await paidReferral(referrer, 'f80r-asaasd', 35);

        expect((await run(referred.familyId))['pending_rail'], 1);
        var row = await referral(referred);
        expect(row['status'], 'pending_rail');
        expect(row['reward_rail'], 'asaas');
        expect(row['reward_pending_reason'], 'asaas_manual');
        expect(row['rewarded_at'], isNotNull, reason: 'earned and counted');
        expect(row['reward_delivered_at'], isNull);
        expect(
          await notices(referrer.adminProfile.id),
          isEmpty,
          reason: 'nothing is promised before it is delivered',
        );
        near((await billing.reload(sub.id)).currentPeriodEnd!.toUtc(), end);

        // The operator moved the due date in Asaas; this records it.
        expect(
          await fx.service.rpc<dynamic>(
            'referral_reward_delivered',
            params: {'p_referred_family_id': referred.familyId},
          ),
          isTrue,
        );
        row = await referral(referred);
        expect(row['status'], 'rewarded');
        expect(row['reward_pending_reason'], isNull);
        expect(row['reward_delivered_at'], isNotNull);
        final moved = (await billing.reload(sub.id)).currentPeriodEnd!.toUtc();
        expect(moved.difference(end).inDays, inInclusiveRange(28, 31));
        expect(await notices(referrer.adminProfile.id), hasLength(1));

        // Settling twice is a no-op.
        expect(
          await fx.service.rpc<dynamic>(
            'referral_reward_delivered',
            params: {'p_referred_family_id': referred.familyId},
          ),
          isFalse,
        );
        expect(await notices(referrer.adminProfile.id), hasLength(1));
      });
    });

    test('a Play subscriber waits for the Play rail, which says why it could '
        'not deliver', () async {
      await on(() async {
        final referrer = await freeReferrer('f80r-play');
        await billing.setPlan(referrer.familyId, 'premium');
        final sub = await billing.seed(
          referrer.familyId,
          'f80r-play-${fx.runId}',
          status: 'active',
          periodEnd: DateTime.now().toUtc().add(const Duration(days: 9)),
        );
        await fx.service
            .from('subscriptions')
            .update({
              'gateway': 'play',
              'billing_type': 'PLAY',
              'store_purchase_token': 'tok_e2e_f80r_${fx.runId}',
              'store_product_id': 'premium_monthly',
            })
            .eq('id', sub.id);
        final referred = await paidReferral(referrer, 'f80r-playd', 36);

        await run(referred.familyId);
        var row = await referral(referred);
        expect(row['status'], 'pending_rail');
        expect(row['reward_rail'], 'play');
        expect(row['reward_pending_reason'], 'play_queued');

        // The local stack holds no Play service account: nothing is called,
        // and the row says so for the operator.
        final (status, body) = await callPlayRail({
          'family_id': referrer.familyId,
        });
        expect(status, 200, reason: '$body');
        expect(body['counts'], {'play_not_configured': 1});
        row = await referral(referred);
        expect(row['status'], 'pending_rail');
        expect(row['reward_pending_reason'], 'play_not_configured');
        expect(row['reward_delivered_at'], isNull);
        expect(await notices(referrer.adminProfile.id), isEmpty);

        // The publishable key is not the secret key.
        final (refused, _) = await callPlayRail({
          'family_id': referrer.familyId,
        }, key: TestEnv.anonKey);
        expect(refused, 401);
      });
    });

    test('the yearly cap: over it a referral is capped for good; last year '
        'does not count', () async {
      await on(
        () => withSetting('referral.yearly_cap', '1', () async {
          final referrer = await freeReferrer('f80r-cap');
          final first = await paidReferral(referrer, 'f80r-capa', 42);
          final second = await paidReferral(referrer, 'f80r-capb', 41);

          final counts = await run(referrer.familyId);
          expect(counts['rewarded'], 1);
          expect(counts['capped'], 1);
          expect((await referral(first))['status'], 'rewarded');
          final capped = await referral(second);
          expect(capped['status'], 'capped');
          expect(capped['rewarded_at'], isNull);
          expect(await notices(referrer.adminProfile.id), hasLength(1));

          await run(referrer.familyId);
          expect(
            (await referral(second))['status'],
            'capped',
            reason: 'terminal — never paid in a later year either',
          );

          // A reward earned LAST calendar year leaves this year's cap free.
          final other = await freeReferrer('f80r-cap2');
          final old = await paidReferral(other, 'f80r-cap2a', 400);
          final lastYear = DateTime.utc(DateTime.now().toUtc().year - 1, 6, 1);
          await fx.service
              .from('family_referrals')
              .update({
                'status': 'rewarded',
                'reward_rail': 'trial',
                'first_paid_at': lastYear.toIso8601String(),
                'qualifies_at': lastYear.toIso8601String(),
                'rewarded_at': lastYear.toIso8601String(),
                'reward_delivered_at': lastYear.toIso8601String(),
              })
              .eq('referred_family_id', old.familyId);
          final fresh = await paidReferral(other, 'f80r-cap2b', 40);
          await run(other.familyId);
          expect((await referral(fresh))['status'], 'rewarded');
        }),
      );
    });

    test('the window follows referral.hold_days while it waits', () async {
      await on(() async {
        final referrer = await freeReferrer('f80r-hold');
        final referred = await paidReferral(referrer, 'f80r-holdd', 20);
        await run(referred.familyId);
        expect((await referral(referred))['status'], 'paid');

        await withSetting('referral.hold_days', '14', () async {
          await run(referred.familyId);
          final row = await referral(referred);
          expect(row['status'], 'rewarded');
          near(
            at(row['qualifies_at']),
            at(row['first_paid_at']).add(const Duration(days: 14)),
          );
        });
      });
    });

    test('a referrer that no longer exists earns nothing', () async {
      await on(() async {
        final referrer = await freeReferrer('f80r-gone');
        final referred = await paidReferral(referrer, 'f80r-goned', 40);
        await fx.service
            .from('family_referrals')
            .update({'referrer_family_id': null})
            .eq('referred_family_id', referred.familyId);

        await run(referred.familyId);
        final row = await referral(referred);
        expect(row['status'], 'cancelled');
        expect(row['cancel_reason'], 'referrer_gone');
        expect(await notices(referrer.adminProfile.id), isEmpty);
      });
    });

    test(
      'a scoped run touches no other family; no client reaches the job',
      () async {
        await on(() async {
          final a = await freeReferrer('f80r-isoa');
          final b = await freeReferrer('f80r-isob');
          final aReferred = await paidReferral(a, 'f80r-isoad', 40);
          final bReferred = await paidReferral(b, 'f80r-isobd', 40);

          await run(a.familyId);
          expect((await referral(aReferred))['status'], 'rewarded');
          expect(
            (await referral(bReferred))['status'],
            'attributed',
            reason: 'outside the scope',
          );
          expect(await notices(b.adminProfile.id), isEmpty);
          expect((await familyRow(b.familyId))['trial_ends_at'], isNull);

          for (final SupabaseClient who in [a.admin, b.member, fx.founder]) {
            await expectRejected(
              () => who.rpc<dynamic>(
                'referral_rewards_due',
                params: {'p_family_id': b.familyId},
              ),
            );
            await expectRejected(
              () => who.rpc<dynamic>(
                'referral_reward_delivered',
                params: {'p_referred_family_id': bReferred.familyId},
              ),
            );
            await expectRejected(
              () => who.rpc<dynamic>(
                'referral_reward_notify',
                params: {
                  'p_referrer_family_id': who == a.admin
                      ? a.familyId
                      : b.familyId,
                },
              ),
            );
          }
          await expectRejected(
            () => fx.newAnonClient().rpc<dynamic>('referral_rewards_due'),
          );
          expect((await referral(bReferred))['status'], 'attributed');
          // The reward row stays out of every client's reach (PR 1's grant).
          List<dynamic> seen;
          try {
            seen = await a.admin.from('family_referrals').select();
          } catch (_) {
            seen = const [];
          }
          expect(seen, isEmpty);
        });
      },
    );
  });
}
