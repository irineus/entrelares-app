import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:supabase/supabase.dart';
import 'package:test/test.dart';

import '_helpers.dart';

/// T-41 — the central app-configuration table.
///
/// Security model: the client only READS the public rows, as a UX mirror; every
/// real limit is enforced server-side. These tests prove a malicious
/// authenticated user can neither read the private settings nor change any
/// setting for their own benefit.
///
/// T-80 adds the other half: every row explains itself to the operator (the
/// completeness pin), the type, the range and the rules between keys hold for
/// EVERY writer — the service role included — and the operator's columns stay
/// out of a client's SELECT.
///
/// Port of `db-gate/Entrelares.IntegrationTests/AppSettingsTests.cs`.
void appSettingsTests(GateFixture fx) {
  Future<Set<String>> keysSeenBy(SupabaseClient who) async =>
      {for (final row in await who.from('app_settings').select('key')) row['key'] as String};

  group('AppSettingsTests', () {
    test('an authenticated client reads only the PUBLIC settings', () async {
      final keys = await keysSeenBy(fx.member);

      expect(keys, contains('calendar_months_free'));
      expect(keys, contains('calendar_months_premium'));
      expect(keys, contains('free_caregivers'));
      expect(keys, contains('max_caregivers'));
      expect(keys, isNot(contains('email_cap_free')));
      expect(keys, isNot(contains('email_cap_premium')));
    });

    test("the operator's columns stay out of a client's reach", () async {
      // T-80: RLS filters the ROWS to is_public; a column grant filters what a
      // client may read of them. The app reads `key, value`, and the range and
      // unit stay readable for a future UX mirror (U-57) — but the operator's
      // explanation, the impact level and who wrote are not a family's business.
      final row = (await fx.member
              .from('app_settings')
              .select('key, value, min_value, max_value, unit')
              .eq('key', 'calendar_months_free'))
          .single;
      expect(row['unit'], 'months');

      for (final column in ['help', 'impact', 'updated_by']) {
        await expectRejected(
            () => fx.member.from('app_settings').select('key, $column'));
      }
    });

    test('the Blazor cutover date is gone', () async {
      // Its only reader was the Blazor client, archived on 25/08/2026. A key
      // with no reader is a knob that turns nothing — and the operator console
      // would keep offering it.
      final rows = await fx.service
          .from('app_settings')
          .select('key')
          .eq('key', 'cutover.web_date');
      expect(rows, isEmpty);
    });

    test('the service role sees every setting', () async {
      final keys = await keysSeenBy(fx.service);

      expect(keys, contains('email_cap_free'));
      expect(keys, contains('calendar_months_free'));
    });

    test('an authenticated client cannot write settings', () async {
      await expectRejected(() => fx.member
          .from('app_settings')
          .update({'value': '999'}).eq('key', 'calendar_months_free'));

      await expectRejected(() => fx.member.from('app_settings').insert({
            'key': 'hacker_key',
            'value': '1',
            'value_type': 'int',
            'category': 'general',
          }));

      // The real value is untouched — the server reads the truth.
      final row = (await fx.service
              .from('app_settings')
              .select('value')
              .eq('key', 'calendar_months_free'))
          .single;
      expect(row['value'], '6');
    });

    // ── T-80: every parameter explains itself and holds only what fits ────

    test('every setting explains itself to the operator', () async {
      // The completeness pin: a key born without its explanation, its range or
      // its unit turns this red — which is what keeps T-82/T-83 (and every key
      // after them) honest. `e2e.*` rows are the suites' own throwaway probes.
      const shownAt = {'app', 'email', 'push', 'landing', 'server_only'};
      final rows = (await fx.service.from('app_settings').select(
              'key, value_type, description, min_value, max_value, unit, help, impact'))
          .cast<Map<String, dynamic>>()
          .where((r) => !(r['key'] as String).startsWith('e2e.'));

      expect(rows, isNotEmpty);
      for (final row in rows) {
        final key = row['key'] as String;
        final help = row['help'] as Map<String, dynamic>;
        final description = row['description'] as String?;

        expect(description, isNotNull, reason: '$key: no description');
        expect(description!.trim(), isNotEmpty, reason: '$key: no description');
        for (final field in [
          'controls',
          'if_increased',
          'if_decreased',
          'takes_effect'
        ]) {
          expect((help[field] as String?)?.trim() ?? '', isNotEmpty,
              reason: '$key: help.$field is empty');
        }
        final where = (help['shown_at'] as List?)?.cast<String>() ?? const [];
        expect(where, isNotEmpty, reason: '$key: help.shown_at is empty');
        expect(shownAt.containsAll(where), isTrue,
            reason: '$key: help.shown_at outside $shownAt: $where');

        expect(row['unit'], isNotNull, reason: '$key: no unit');
        expect(row['impact'], isNotNull, reason: '$key: no impact');
        if (row['value_type'] == 'int' || row['value_type'] == 'decimal') {
          expect(row['min_value'], isNotNull, reason: '$key: no min_value');
          expect(row['max_value'], isNotNull, reason: '$key: no max_value');
        }
      }
    });

    test('the service role is held to the range and the type too', () async {
      // The row trigger judges EVERY writer: a migration seeding a value the
      // product cannot hold fails at `db push`, not in production. Against a
      // throwaway row, delete-first, so the shared dev config never moves.
      const probeKey = 'e2e.bounds_probe';
      Future<String> stored() async => (await fx.service
              .from('app_settings')
              .select('value')
              .eq('key', probeKey))
          .single['value'] as String;

      await fx.service.from('app_settings').delete().eq('key', probeKey);
      try {
        await expectRejected(
          () => fx.service.from('app_settings').insert({
            'key': probeKey,
            'value': '11',
            'value_type': 'int',
            'category': 'e2e',
            'min_value': 1,
            'max_value': 10,
            'unit': 'days',
          }),
          contains: 'de 1 a 10 dias',
        );

        await fx.service.from('app_settings').insert({
          'key': probeKey,
          'value': '5',
          'value_type': 'int',
          'category': 'e2e',
          'min_value': 1,
          'max_value': 10,
          'unit': 'days',
        });
        await expectRejected(
          () => fx.service
              .from('app_settings')
              .update({'value': '0'}).eq('key', probeKey),
          contains: 'faixa',
        );
        await expectRejected(
          () => fx.service
              .from('app_settings')
              .update({'value': 'cinco'}).eq('key', probeKey),
          contains: 'int',
        );
        // A bound that no longer covers the stored value is refused as well:
        // the range moves only together with a value inside it.
        await expectRejected(
          () => fx.service
              .from('app_settings')
              .update({'max_value': 3}).eq('key', probeKey),
          contains: 'faixa',
        );
        expect(await stored(), '5');
      } finally {
        await fx.service.from('app_settings').delete().eq('key', probeKey);
      }
    });

    test('a flag is stored in one spelling', () async {
      // Readers compare the string ('true'), so 'TRUE' would read as off.
      const probeKey = 'e2e.flag_probe';
      await fx.service.from('app_settings').delete().eq('key', probeKey);
      try {
        await fx.service.from('app_settings').insert({
          'key': probeKey,
          'value': 'TRUE',
          'value_type': 'bool',
          'category': 'e2e',
          'unit': 'flag',
        });
        final row = (await fx.service
                .from('app_settings')
                .select('value')
                .eq('key', probeKey))
            .single;
        expect(row['value'], 'true');
      } finally {
        await fx.service.from('app_settings').delete().eq('key', probeKey);
      }
    });

    test('the service role cannot leave two keys contradicting each other',
        () async {
      // The rules BETWEEN keys are a deferred constraint trigger, judged on the
      // state a transaction leaves. A warning on the downgrade day is a warning
      // after the fact (billing_grace_warnings_due); in range on its own, the
      // pair is what is refused.
      Future<String> warningDays() async => (await fx.service
              .from('app_settings')
              .select('value')
              .eq('key', 'billing.grace_warning_days'))
          .single['value'] as String;
      final before = await warningDays();
      try {
        await expectRejected(
          () => fx.service
              .from('app_settings')
              .update({'value': '7'}).eq('key', 'billing.grace_warning_days'),
          contains: 'billing.grace_days',
        );
        expect(await warningDays(), before);
      } finally {
        // Only reached with a value if the rule failed to fire: put it back,
        // so a red run does not also poison the shared dev config.
        if (await warningDays() != before) {
          await fx.service
              .from('app_settings')
              .update({'value': before}).eq('key', 'billing.grace_warning_days');
        }
      }
    });
  });
}
