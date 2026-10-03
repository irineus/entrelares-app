import 'dart:convert';

import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '_billing.dart';
import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// T-99: every key `admin_weekly_sales_bulletin` may return, at any depth. The
/// bulletin goes to an inbox, so it is counts, dates and closed enums only —
/// no name, no e-mail and, unlike F-69, not even a family id. A key outside
/// this list is how a later edit would start shipping one, so a new key is
/// added HERE, on purpose, in the same delivery.
const _bulletinKeys = {
  // top level
  'report_version', 'generated_at', 'week_start', 'week_end', 'this_week',
  'previous_week', 'trend', 'snapshot', 'referrals',
  // a week
  'families_created', 'first_channel', 'android', 'web', 'web_installed',
  'none', 'planned_within_7d', 'invitations_sent', 'invitations_accepted',
  'active_families', 'conversions', 'total', 'during_trial', 'by_rail',
  'asaas', 'play', 'by_cycle', 'monthly', 'annual', 'single', 'unknown',
  'cancellations', 'overdue_started', 'trial_reminders', 'd7', 'd1', 'ended',
  'unplanned_nudges',
  // a trend point
  'conversions_total',
  // the snapshot
  'families_total', 'paying_families', 'trials_ending_7d', 'dunning',
};

Set<String> _keysOf(Object? node) => switch (node) {
      Map() => {
          for (final e in node.entries) ...{e.key as String, ..._keysOf(e.value)}
        },
      List() => {for (final v in node) ..._keysOf(v)},
      _ => const <String>{},
    };

/// T-99 — the weekly sales bulletin e-mailed to the operator:
///   · `admin_weekly_sales_bulletin` answers to the service role only — no
///     family session and no OPERATOR session either;
///   · its JSON keeps a closed key list, and nothing a person typed (family
///     name, member name, invitation e-mail, a day note, a custom role) comes
///     back — F-69's marker technique;
///   · its counts react to the rows a week really has;
///   · the `weekly-bulletin` function renders it without sending (`dry_run`),
///     honours the kill switch and sends a week only once.
///
/// The aggregate is GLOBAL — every family on the stack counts — so each count
/// is asserted as a DELTA between two reads around the seeding, inside one
/// test (the suites run one at a time). The week asked is the CURRENT one
/// (`p_week_start` = today, normalised to its Monday), so the rows a test
/// seeds now are inside it. The function is never called without `dry_run`
/// unless the run is guaranteed to stop before Resend: the stack holds a dummy
/// key and the operator's inbox is real.
void weeklyBulletinTests(GateFixture fx) {
  final billing = Billing(fx);

  Map<String, dynamic> decode(dynamic response) =>
      (response is String ? jsonDecode(response) : response)
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> bulletin({DateTime? week}) async => decode(
      await fx.service.rpc<dynamic>('admin_weekly_sales_bulletin', params: {
        'p_week_start': week == null ? null : isoDate(week),
      }));

  /// The edge runtime answers 503 while a function is still booting; that is
  /// never our answer (see edge_function_auth.dart).
  Future<(int, Map<String, dynamic>)> callFunction(
      Map<String, dynamic> body) async {
    Future<http.Response> send() => http.post(
          Uri.parse(Billing.functionUrl('weekly-bulletin')),
          headers: {
            ...TestEnv.keyHeaders(TestEnv.serviceRoleKey),
            'Content-Type': 'application/json',
          },
          body: jsonEncode(body),
        );
    var response = await send();
    for (var attempt = 1; attempt <= 4 && response.statusCode == 503; attempt++) {
      await Future<void>.delayed(Duration(seconds: 2 * attempt));
      response = await send();
    }
    return (
      response.statusCode,
      jsonDecode(response.body) as Map<String, dynamic>
    );
  }

  Future<List<dynamic>> ledgerRow(String weekStart) => fx.service
      .from('weekly_bulletin_sends')
      .select()
      .eq('week_start', weekStart);

  group('WeeklyBulletinTests', () {
    test('the kill switch is born with its T-80 metadata', () async {
      final row = (await fx.service
              .from('app_settings')
              .select()
              .eq('key', 'ops.weekly_bulletin.enabled'))
          .single;
      expect(row['value'], 'true');
      expect(row['value_type'], 'bool');
      expect(row['category'], 'operator');
      expect(row['is_public'], isFalse);
      expect(row['unit'], 'flag');
      expect(row['impact'], 'normal');
      final help = row['help'] as Map<String, dynamic>;
      expect(help['shown_at'], ['email']);
      for (final field in [
        'controls',
        'if_increased',
        'if_decreased',
        'takes_effect',
        'caveats'
      ]) {
        expect((help[field] as String?)?.trim(), isNotEmpty, reason: field);
      }
      expect((row['description'] as String).length, lessThanOrEqualTo(120));
    });

    test('no client can read the bulletin — an operator session included',
        () async {
      final fam = await fx.createFamily('t99-rls');
      await expectRejected(() => fam.admin.rpc<dynamic>(
          'admin_weekly_sales_bulletin',
          params: {'p_week_start': null}));
      await expectRejected(() => fam.admin.rpc<dynamic>(
          'admin_weekly_sales_bulletin_week',
          params: {'p_week_start': isoDate(saoPauloToday())}));

      // The console's operator reads ONE family through F-69, audited; the
      // product-wide bulletin is the e-mail's, not the console's.
      await fx.service
          .from('platform_operators')
          .delete()
          .eq('user_id', fx.founderProfile.userId!);
      await fx.service.from('platform_operators').insert({
        'user_id': fx.founderProfile.userId,
        'note': 'e2e throwaway operator (T-99)',
      });
      try {
        await expectRejected(() => fx.founder.rpc<dynamic>(
            'admin_weekly_sales_bulletin',
            params: {'p_week_start': null}));
      } finally {
        await fx.service
            .from('platform_operators')
            .delete()
            .eq('user_id', fx.founderProfile.userId!);
      }

      List<dynamic> seen;
      try {
        seen = await fam.admin.from('weekly_bulletin_sends').select();
      } catch (_) {
        seen = const [];
      }
      expect(seen, isEmpty);
    });

    test('the default week is the one that just ended, Monday to Sunday',
        () async {
      final b = await bulletin();
      final today = saoPauloToday();
      final thisMonday = addDays(today, -(today.weekday - DateTime.monday));
      expect(b['week_start'], isoDate(addDays(thisMonday, -7)));
      expect(b['week_end'], isoDate(addDays(thisMonday, -1)));
      expect((b['previous_week'] as Map)['week_start'],
          isoDate(addDays(thisMonday, -14)));

      final trend = (b['trend'] as List).cast<Map<String, dynamic>>();
      expect(trend.map((t) => t['week_start']), [
        isoDate(addDays(thisMonday, -28)),
        isoDate(addDays(thisMonday, -21)),
        isoDate(addDays(thisMonday, -14)),
        isoDate(addDays(thisMonday, -7)),
      ]);
      // F-80: the key is always there; its value is a count only while
      // `feature.referral` is on (F-82 turned it on in production) and NULL
      // while it is off. The referral suite pins both states with the flag
      // held; here it is whatever the stack's migrations left.
      expect(b.containsKey('referrals'), isTrue);
      if (await readFlag(fx, 'feature.referral') == 'true') {
        expect(b['referrals'], isA<num>());
      } else {
        expect(b['referrals'], isNull);
      }
    });

    test('closed keys, and nothing a person typed comes back', () async {
      const marker = 'zzt99leak';
      final fam = await fx.createFamily('t99leak');

      // The E2E prefix stays: `purge_e2e_family` refuses a family whose name
      // lost its signature.
      await fx.service.from('families').update({
        'name': '${TestEnv.e2eFamilyPrefix}${fx.runId}-$marker-family'
      }).eq('id', fam.familyId);
      await fx.service.from('profiles').update(
          {'full_name': '$marker-admin'}).eq('id', fam.adminProfile.id);
      final customRole = (await fx.service
              .from('roles')
              .insert({
                'role': '$marker-role',
                'label_pt': '$marker-label',
                'family_id': fam.familyId,
                'emoji': 'X',
              })
              .select('id'))
          .single['id'] as int;
      await fx.service.from('profiles').update({
        'full_name': '$marker-member',
        'role_id': customRole,
      }).eq('id', fam.memberProfile.id);
      await fx.service.from('family_invitations').insert({
        'family_id': fam.familyId,
        'email': fx.testEmail('$marker-inv'),
        'role_id': fx.roleId('grandmother'),
        'invited_by': fam.adminProfile.id,
      });
      await fx.service.from('care_schedules').insert({
        'family_id': fam.familyId,
        'schedule_date': isoDate(fx.nextFutureDate()),
        'scheduled_parent_id': fam.adminProfile.id,
        'notes': '$marker-note',
      });
      await fam.member
          .rpc<dynamic>('touch_activity', params: {'p_channel': 'web'});

      final b = await bulletin(week: saoPauloToday());

      expect(_keysOf(b).difference(_bulletinKeys), isEmpty,
          reason: 'a new bulletin key must be added to _bulletinKeys on '
              'purpose, after checking it is not free text or an id');
      final encoded = jsonEncode(b).toLowerCase();
      expect(encoded, isNot(contains(marker)));
      expect(encoded, isNot(contains('@')),
          reason: 'no e-mail address, of anyone');
      expect(encoded, isNot(contains(fx.runId.toLowerCase())));

      // ── The e-mail built from it says no more than the JSON ──
      final (status, body) =
          await callFunction({'dry_run': true, 'week_start': b['week_start']});
      expect(status, 200, reason: '$body');
      final html = (body['html'] as String).toLowerCase();
      final subject = body['subject'] as String;
      expect(html, isNot(contains(marker)));
      expect(html, isNot(contains(fam.adminProfile.email!.toLowerCase())));
      expect(html, isNot(contains(fam.memberProfile.email!.toLowerCase())));
      expect(html, isNot(contains('@resend.dev')));

      // `APP_ENVIRONMENT=Development` on the local stack → the dev tag.
      final start = DateTime.parse(b['week_start'] as String);
      final end = DateTime.parse(b['week_end'] as String);
      String ddmm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}';
      expect(subject,
          '[Dev] Boletim semanal — semana de ${ddmm(start)} a ${ddmm(end)}');

      // The three manual readings, with their direct URLs.
      expect(
          html,
          allOf(
            contains('store-listings?metric=metric_acquisition'),
            contains('resource_id=sc-domain%3aentrelares.app'),
            contains('websites/6fdd6c5a-4bce-449f-8188-3b7399a859d8'),
          ));
      // A dry run sends and stamps nothing.
      expect(await ledgerRow(b['week_start'] as String), isEmpty);
    });

    test('the counts react to what a week really had', () async {
      final week = saoPauloToday();
      final before = await bulletin(week: week);

      // A family created this week (with its invitation sent and accepted), a
      // member on Android, a day planned, a trial-end reminder, the F-78 nudge
      // and a first payment on the web rail.
      final fam = await fx.createFamily('t99cnt');
      await fam.member
          .rpc<dynamic>('touch_activity', params: {'p_channel': 'android'});
      await fx.service.from('care_schedules').insert({
        'family_id': fam.familyId,
        'schedule_date': isoDate(fx.nextFutureDate()),
        'scheduled_parent_id': fam.adminProfile.id,
      });
      final trialEnd = (await fx.service
              .from('families')
              .select('trial_ends_at')
              .eq('id', fam.familyId))
          .single['trial_ends_at'] as String;
      await fx.service.from('trial_end_reminders').insert({
        'family_id': fam.familyId,
        'trial_ends_at': trialEnd,
        'stage': 'd7',
      });
      await fx.service
          .from('unplanned_family_nudges')
          .insert({'family_id': fam.familyId});

      final eventId = 'e2e-t99-${fx.runId}';
      await fx.service.from('billing_events').delete().eq('event_id', eventId);
      await billing.seed(fam.familyId, 't99', status: 'active');
      try {
        await fx.service.from('billing_events').insert({
          'event_id': eventId,
          'event_type': 'PAYMENT_CONFIRMED',
          'family_id': fam.familyId,
          'payload': {'source': 'db-gate T-99'},
        });

        final after = await bulletin(week: week);
        expect(after['week_start'], before['week_start']);

        final b = before['this_week'] as Map<String, dynamic>;
        final a = after['this_week'] as Map<String, dynamic>;
        int delta(List<String> path) {
          dynamic at(Map<String, dynamic> m) =>
              path.fold<dynamic>(m, (node, k) => (node as Map)[k]);
          return (at(a) as int) - (at(b) as int);
        }

        expect(delta(['families_created']), 1);
        expect(delta(['first_channel', 'android']), 1);
        expect(delta(['first_channel', 'none']), 0);
        expect(delta(['planned_within_7d']), 1);
        expect(delta(['invitations_sent']), 1);
        expect(delta(['invitations_accepted']), 1);
        expect(delta(['active_families']), 1);
        expect(delta(['conversions', 'total']), 1);
        expect(delta(['conversions', 'during_trial']), 1,
            reason: 'the trial (default 30 days) is still running');
        expect(delta(['conversions', 'by_rail', 'asaas']), 1);
        expect(delta(['conversions', 'by_rail', 'play']), 0);
        expect(delta(['conversions', 'by_cycle', 'monthly']), 1);
        expect(delta(['trial_reminders', 'd7']), 1);
        expect(delta(['unplanned_nudges']), 1);

        // The newest trend point IS this week.
        final trend = (after['trend'] as List).cast<Map<String, dynamic>>();
        expect(trend.last['week_start'], after['week_start']);
        expect(trend.last['families_created'], a['families_created']);
        expect(trend.last['conversions_total'],
            (a['conversions'] as Map)['total']);

        // A SECOND paying event is a renewal, not a second conversion.
        await fx.service.from('billing_events').insert({
          'event_id': '$eventId-renewal',
          'event_type': 'PAYMENT_RECEIVED',
          'family_id': fam.familyId,
          'payload': {'source': 'db-gate T-99'},
        });
        final again = await bulletin(week: week);
        expect(((again['this_week'] as Map)['conversions'] as Map)['total'],
            (a['conversions'] as Map)['total']);
      } finally {
        await fx.service
            .from('billing_events')
            .delete()
            .inFilter('event_id', [eventId, '$eventId-renewal']);
        await fx.deleteSubscriptionSeed('sub_e2e_t99');
      }
    });

    test('the kill switch stops a real run before anything is built',
        () async {
      const key = 'ops.weekly_bulletin.enabled';
      final before = await readFlag(fx, key);
      await writeFlag(fx, key, 'false');
      try {
        final (status, body) = await callFunction(const {});
        expect(status, 200, reason: '$body');
        expect(body, {'skipped': 'disabled'});
      } finally {
        await writeFlag(fx, key, before);
      }
      final week = (await bulletin())['week_start'] as String;
      expect(await ledgerRow(week), isEmpty);
    });

    test('a week already sent is never sent again', () async {
      // The claim exists, so the function stops before Resend — the stack's
      // dummy key never meets the operator's real inbox.
      final week = (await bulletin())['week_start'] as String;
      await fx.service.from('weekly_bulletin_sends').delete().eq('week_start', week);
      await fx.service.from('weekly_bulletin_sends').insert({'week_start': week});
      try {
        final (status, body) = await callFunction(const {});
        expect(status, 200, reason: '$body');
        expect(body, {'skipped': 'already_sent', 'week_start': week});
      } finally {
        await fx.service
            .from('weekly_bulletin_sends')
            .delete()
            .eq('week_start', week);
      }
    });
  });
}
