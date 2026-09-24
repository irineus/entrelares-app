import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

/// F-38 — the freemium gate on transactional e-mail.
///
/// Free families get a generous 100/month cap (per calendar month,
/// `America/Sao_Paulo`); premium has a HIGH anti-abuse cap and is still counted
/// — nothing is truly unlimited. `consume_email_quota` (called by
/// `send-swap-email`) returns a status and posts the in-app heads-ups: 80 %
/// (`email_cap_80`), the last e-mail (`email_cap_last` — the warning takes the
/// final slot) and over-cap (`email_cap_reached`). Each fires ONCE per month,
/// and in-app notification is never capped.
///
/// The counter is seeded near each threshold rather than driven there: 100 real
/// calls would be 100 real rows and minutes of runtime for a rule that is about
/// the boundary.
///
/// Port of `db-gate/Entrelares.IntegrationTests/EmailQuotaGateTests.cs`.
void emailQuotaGateTests(GateFixture fx) {
  Future<void> setPlan(int familyId, String plan) => fx.service.rpc<dynamic>(
      'set_family_plan', params: {'p_family_id': familyId, 'p_plan': plan});

  Future<String> consume(int familyId) async =>
      (await fx.service.rpc<dynamic>('consume_email_quota',
              params: {'p_family_id': familyId}))
          .toString();

  Future<void> seedCount(int familyId, int count) => fx.service
      .from('email_usage')
      .update({'sent_count': count}).eq('family_id', familyId);

  Future<int> sentCount(int familyId) async => (await fx.service
          .from('email_usage')
          .select('sent_count')
          .eq('family_id', familyId))
      .single['sent_count'] as int;

  Future<int> inAppCount(int recipientProfileId, String type) async =>
      (await fx.service
              .from('notifications')
              .select('id')
              .eq('recipient_profile_id', recipientProfileId)
              .eq('type', type))
          .length;

  group('EmailQuotaGateTests', () {
    // T-82: the heads-up threshold is `email_quota.warn_percent` (default 80,
    // range 50–95). At 60 the heads-up fires at 60 %, and the stored title,
    // sentence and `params.percent` all say 60 — the app renders from params.
    test('the heads-up threshold is the operator key', () async {
      final fam = await fx.createFamily('t82warn');
      await setPlan(fam.familyId, 'free');
      final before = (await fx.service
              .from('app_settings')
              .select('value')
              .eq('key', 'email_quota.warn_percent'))
          .single['value'] as String;
      await fx.service
          .from('app_settings')
          .update({'value': '60'}).eq('key', 'email_quota.warn_percent');
      try {
        expect(await consume(fam.familyId), contains('allowed'));
        await seedCount(fam.familyId, 59);
        expect(await consume(fam.familyId), contains('warn_80'));
        final row = (await fx.service
                .from('notifications')
                .select('title, message, params')
                .eq('recipient_profile_id', fam.adminProfile.id)
                .eq('type', 'email_cap_80'))
            .single;
        expect(row['title'], 'E-mails do mês em 60%');
        expect(row['message'] as String, contains('já usou 60%'));
        expect((row['params'] as Map)['percent'], '60');
      } finally {
        await fx.service
            .from('app_settings')
            .update({'value': before}).eq('key', 'email_quota.warn_percent');
      }
    });

    test('a free family gets each milestone once, then is denied', () async {
      final fam = await fx.createFamily('f38');
      await setPlan(fam.familyId, 'free');
      final admin = fam.adminProfile.id;

      // Under every threshold: allowed, and the counter is created.
      expect(await consume(fam.familyId), contains('allowed'));

      // Crossing 80 %: warn_80 plus ONE in-app heads-up.
      await seedCount(fam.familyId, 79);
      expect(await consume(fam.familyId), contains('warn_80'));
      expect(await inAppCount(admin, 'email_cap_80'), 1);

      // Crossing the last slot: warn_last plus one in-app — and the warning
      // itself takes the final slot, so the counter lands exactly on the cap.
      await seedCount(fam.familyId, 98);
      expect(await consume(fam.familyId), contains('warn_last'));
      expect(await inAppCount(admin, 'email_cap_last'), 1);
      expect(await sentCount(fam.familyId), 100);

      // Over the cap: denied, plus one in-app.
      expect(await consume(fam.familyId), contains('denied'));
      expect(await inAppCount(admin, 'email_cap_reached'), 1);

      // Still denied — and NO second over-cap notification. A cap that nags on
      // every attempt teaches people to ignore it.
      expect(await consume(fam.familyId), contains('denied'));
      expect(await inAppCount(admin, 'email_cap_reached'), 1);

      // Premium bypasses the capped counter entirely.
      await setPlan(fam.familyId, 'premium');
      expect(await consume(fam.familyId), contains('allowed'));
    });

    test('a premium family has a high cap and is still counted', () async {
      final fam = await fx.createFamily('f38-prem'); // premium via the trial

      expect(await consume(fam.familyId), contains('allowed'));

      // Counted against `email_cap_premium` — a usage row exists.
      expect(await sentCount(fam.familyId), 1);

      // And no free-tier conversion nudge for a family that already pays.
      expect(await inAppCount(fam.adminProfile.id, 'email_cap_80'), 0);
    });
  });
}
