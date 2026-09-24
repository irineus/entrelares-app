import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// T-82 — values that were hardcoded become operator parameters, each read by
/// the server at the moment it decides. Both defaults stay the single writer
/// (a column default reads the key), so what these tests pin is that the NEXT
/// row follows the key and nothing already written moves.
///
/// Every test puts the shared dev key back in `finally`: the other suites run
/// against the same project and assume the seeds.
void serverParametersTests(GateFixture fx) {
  Future<String> getSetting(String key) async => (await fx.service
          .from('app_settings')
          .select('value')
          .eq('key', key))
      .single['value'] as String;

  Future<void> setSetting(String key, String value) => fx.service
      .from('app_settings')
      .update({'value': value}).eq('key', key);

  Future<void> withSetting(
      String key, String value, Future<void> Function() body) async {
    final before = await getSetting(key);
    await setSetting(key, value);
    try {
      await body();
    } finally {
      await setSetting(key, before);
    }
  }

  group('T-82 · server parameters', () {
    test("a new family's trial reads trial.days", () async {
      await withSetting('trial.days', '10', () async {
        final row = (await fx.service
                .from('families')
                .insert({'name': 'e2e-t82-trial'}).select('id, trial_ends_at'))
            .single;
        try {
          final ends = DateTime.parse(row['trial_ends_at'] as String);
          final days =
              ends.difference(DateTime.now().toUtc()).inMinutes / (24 * 60);
          expect(days, closeTo(10, 0.1));
        } finally {
          await fx.service.from('families').delete().eq('id', row['id'] as int);
        }
      });
    });

    test("a new invitation's expiry reads invitation.valid_days", () async {
      final fam = await fx.createFamily('t82inv');
      // Two members already fill the free seats; the invitation is about the
      // expiry, not the F-37 gate.
      await fx.service.rpc<dynamic>('set_family_plan',
          params: {'p_family_id': fam.familyId, 'p_plan': 'premium'});
      await withSetting('invitation.valid_days', '3', () async {
        await GateFixture.createInvitation(
          fam.admin,
          'e2e-t82-inv-${DateTime.now().microsecondsSinceEpoch}@resend.dev',
          fx.roleId('grandmother'),
        );
        final row = (await fx.service
                .from('family_invitations')
                .select('created_at, expires_at')
                .eq('family_id', fam.familyId)
                .order('id', ascending: false)
                .limit(1))
            .single;
        final valid = DateTime.parse(row['expires_at'] as String)
            .difference(DateTime.parse(row['created_at'] as String));
        expect(valid.inMinutes / (24 * 60), closeTo(3, 0.01));
      });
    });

    test('each key refuses what the product cannot hold', () async {
      await expectRejected(() => setSetting('trial.days', '91'),
          contains: 'de 0 a 90 dias');
      await expectRejected(() => setSetting('invitation.valid_days', '31'),
          contains: 'de 1 a 30 dias');
      await expectRejected(() => setSetting('email_quota.warn_percent', '96'),
          contains: 'de 50% a 95%');
      await expectRejected(() => setSetting('billing.asaas_due_days', '0'),
          contains: 'de 1 a 30 dias');
      await expectRejected(() => setSetting('usage_report.weeks', '53'),
          contains: 'de 4 a 52');
      await expectRejected(() => setSetting('usage_report.active_days', '6'),
          contains: 'de 7 a 90 dias');
      // T-83 (1/4)
      await expectRejected(
          () => setSetting('session.idle_timeout_minutes', '4'),
          contains: 'de 5 a 240 minutos');
      // T-83 (2/4)
      await expectRejected(
          () => setSetting('sync.poll_seconds_degraded', '9'),
          contains: 'de 10 a 120 segundos');
      await expectRejected(
          () => setSetting('sync.poll_seconds_healthy', '601'),
          contains: 'de 0 a 600 segundos');
      // T-83 (4/4)
      await expectRejected(() => setSetting('support.anon_hourly', '21'),
          contains: 'de 1 a 20');
      await expectRejected(() => setSetting('support.member_daily', '101'),
          contains: 'de 1 a 100');
      await expectRejected(
          () => setSetting('support.message_max_chars', '2001'),
          contains: 'de 200 a 2000 caracteres');
    });

    test('a support limit per hour never exceeds its daily one', () async {
      await expectRejected(() => setSetting('support.anon_hourly', '11'),
          contains: 'support.anon_daily');
      // Both in range (1–20 / 1–100): the daily one lowered to 10, eleven per
      // hour is the pair that must be refused.
      await withSetting('support.member_daily', '10', () async {
        await expectRejected(() => setSetting('support.member_hourly', '11'),
            contains: 'support.member_daily');
      });
    });

    test('the push kill switch names only types the dispatcher pushes',
        () async {
      // T-83 (3/4): the list is read back from dispatch_push_notification's
      // own filter — no second copy of the twelve types.
      await withSetting('push.disabled_types', '["swap_requested"]', () async {
        expect(await getSetting('push.disabled_types'), '["swap_requested"]');
      });
      await expectRejected(
          () => setSetting('push.disabled_types', '["billing"]'),
          contains: 'não é um tipo que gera push');
      await expectRejected(
          () => setSetting('push.disabled_types', '{"swap_requested": true}'),
          contains: 'lista JSON');
    });

    test('the healthy poll is off or never more frequent than the degraded one',
        () async {
      // In range on its own (0–600), refused as a pair: with the socket up the
      // poll is a safety net, never busier than the poll that replaces it.
      await expectRejected(
          () => setSetting('sync.poll_seconds_healthy', '20'),
          contains: 'sync.poll_seconds_degraded');
      // 0 is the documented "off", and is accepted.
      await withSetting('sync.poll_seconds_healthy', '0', () async {
        expect(await getSetting('sync.poll_seconds_healthy'), '0');
      });
    });
  });
}
