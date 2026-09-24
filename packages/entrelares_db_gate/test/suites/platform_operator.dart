import 'dart:convert';

import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '_helpers.dart';
import 'day_notice.dart' show saoPauloToday;

/// F-69: every key `admin_family_usage_report` may return, at any depth. The
/// payload is counts, dates, ids and closed enums only, and a key outside this
/// list is how a later edit would start shipping a text column — so a new key
/// has to be added HERE, on purpose, in the same delivery.
const _usageReportKeys = {
  // top level
  'report_version', 'generated_at', 'today', 'family', 'members', 'plan',
  'weeks', 'swaps', 'notices', 'day_accounts',
  // T-82: the windows the report used (`usage_report.*`)
  'windows', 'active_days',
  // family
  'id', 'created_at', 'is_premium', 'trial_ends_at', 'comp_premium_at',
  'seats_used', 'seats_cap', 'subscription', 'invitations',
  'gateway', 'status', 'cycle', 'current_period_end', 'overdue_since',
  'canceled_at',
  'open', 'accepted', 'expired', 'revoked', 'oldest_open_created_at',
  // members
  'profile_id', 'role', 'is_admin', 'state', 'joined_via_invite', 'left_at',
  'has_password', 'has_google', 'language', 'tour_seen_at',
  'consent_policy_version', 'consent_accepted_at', 'last_active_day',
  'last_active_source', 'active_days_30', 'channels_30', 'devices', 'unread',
  'platform', 'count', 'last_seen_at', 'type',
  // plan
  'first_day', 'last_day', 'days_total', 'days_ahead',
  'days_with_handoff_time', 'days_with_note', 'days_diverged',
  'transitions_ahead', 'transitions_ahead_with_time', 'carers_ahead', 'days',
  // weeks
  'week_start', 'edits', 'edits_by_member', 'admin_overrides',
  'swaps_opened', 'swaps_resolved', 'active_members',
  // swaps
  'by_status', 'resolved_by', 'median_answer_hours', 'pending',
  'oldest_pending_created_at',
  // notices, day_accounts
  'total', 'by_outcome', 'outcome', 'corrections',
  // F-55: the agenda — counts only (weeks gain `agenda_events`)
  'agenda', 'agenda_events', 'children', 'events_active', 'events_ahead',
  'events_deleted', 'notes_active', 'converted', 'by_kind', 'kind',
  // F-55 PR 3: the routine — counts only
  'routines', 'events_from_routine',
  // F-55 PR 4: the reminders — counts only
  'with_reminder', 'reminders_sent',
  // F-50: the viewers — the category per member and counts per family
  'membership', 'viewers_used', 'viewers_cap', 'viewer_invitations_open',
  // F-64: the verifiable reports — counts only
  'attestations', 'issued', 'active',
  // F-34: the expenses — counts only
  'expenses', 'deleted', 'settlements_pending', 'settlements_confirmed',
};

Set<String> _keysOf(Object? node) => switch (node) {
      Map() => {
          for (final e in node.entries) ...{e.key as String, ..._keysOf(e.value)}
        },
      List() => {for (final v in node) ..._keysOf(v)},
      _ => const <String>{},
    };

/// F-58 — the platform-operator console, DB foundation:
///   · every `admin_*` RPC refuses a caller who is not in `platform_operators`,
///     no matter how elevated or family-admin they are;
///   · writes additionally require an ACTIVE S-10 elevation
///     (`ELEVATION_REQUIRED`);
///   · `admin_update_setting` validates against `value_type` and refuses
///     `policy.*`; since T-80 it also refuses a value out of the row's range
///     and a pair of keys that contradict each other, with a sentence;
///   · the comp flows through `is_premium()` ITSELF — never a parallel check —
///     and survives a billing-style plan downgrade;
///   · every operator action leaves its `operator_audit_logs` trail, and a comp
///     grant/revoke also lands in the FAMILY's own `account_logs`, which is the
///     transparency half;
///   · neither operator table is readable by any authenticated client;
///   · F-69: the usage report is audited on every call (a miss too), returns
///     only the keys `_usageReportKeys` names, and no free text from any
///     column the family typed into.
///
/// The three operator tables have no app contract and never will — the client
/// reaches them only through the RPCs — so this suite reads them as raw
/// projections through the service client.
///
/// Port of `db-gate/Entrelares.IntegrationTests/PlatformOperatorTests.cs`.
void platformOperatorTests(GateFixture fx) {
  Future<void> removeOperator(Member who) async {
    await fx.service
        .from('platform_operators')
        .delete()
        .eq('user_id', who.userId!);
  }

  Future<void> makeOperator(Member who) async {
    // Idempotent (delete-first): a fixed-key seed must clean its own leftover,
    // because a cancelled run never reaches the teardown.
    await removeOperator(who);
    await fx.service.from('platform_operators').insert({
      'user_id': who.userId,
      'note': 'e2e throwaway operator',
    });
  }

  Future<bool> isPremium(int familyId) async {
    final result = await fx.service
        .rpc<dynamic>('is_premium', params: {'p_family_id': familyId});
    return result == true || result.toString().contains('true');
  }

  Future<List<Map<String, dynamic>>> auditRows(String operatorUserId) async =>
      (await fx.service
              .from('operator_audit_logs')
              .select()
              .eq('operator_user_id', operatorUserId))
          .cast<Map<String, dynamic>>();

  Future<Map<String, String>> settingValues(List<String> keys) async => {
        for (final row in await fx.service
            .from('app_settings')
            .select('key, value')
            .inFilter('key', keys))
          row['key'] as String: row['value'] as String
      };

  // Only writes back what a failed refusal moved, so a red run does not also
  // poison the shared dev config the other suites read.
  Future<void> restoreSettings(Map<String, String> before) async {
    final now = await settingValues(before.keys.toList());
    for (final entry in before.entries) {
      if (now[entry.key] != entry.value) {
        await fx.service
            .from('app_settings')
            .update({'value': entry.value}).eq('key', entry.key);
      }
    }
  }

  Future<List<AccountLog>> familyLogs(int familyId) async => [
        for (final row
            in await fx.service.from('account_logs').select().eq('family_id', familyId))
          AccountLog.fromJson(row)
      ];

  group('PlatformOperatorTests', () {
    // ── The operator gate itself ─────────────────────────────────────────

    test('a family admin, however elevated, is refused by every admin RPC',
        () async {
      // The refusal comes BEFORE anything else is checked — which is the point:
      // the operator gate is not one permission among several, it is the door.
      await removeOperator(fx.founderProfile);
      await fx.elevate(fx.founderProfile);
      try {
        final calls = <(String, Map<String, dynamic>)>[
          ('admin_list_settings', {}),
          ('admin_list_families', {}),
          ('admin_list_audit', {}),
          (
            'admin_update_setting',
            {'p_key': 'free_caregivers', 'p_value': '2'}
          ),
          ('admin_lookup_family', {'p_email': fx.founderProfile.email}),
          ('admin_set_comp', {'p_family_id': fx.familyId, 'p_granted': true}),
          ('admin_family_usage_report', {'p_family_id': fx.familyId}),
        ];
        for (final (rpc, args) in calls) {
          await expectRejected(
            () => fx.founder.rpc<dynamic>(rpc, params: args),
            contains: 'restrito',
          );
        }
      } finally {
        await fx.clearElevation(fx.founderProfile);
      }
    });

    test('neither operator table leaks to an authenticated client', () async {
      // Not even to the operator themselves — the console goes through the RPCs.
      await expectRejected(() => fx.founder.from('platform_operators').select());
      await expectRejected(
          () => fx.founder.from('operator_audit_logs').select());
      // F-69: the last-active helper is SECURITY DEFINER with no client
      // grant — callable, it would hand any member the other's last use.
      await expectRejected(() => fx.founder.rpc<dynamic>('member_last_active',
          params: {'p_profile_id': fx.memberProfile.id}));
    });

    // ── Sudo on writes ───────────────────────────────────────────────────

    test('an operator without elevation can read but not write', () async {
      await makeOperator(fx.founderProfile);
      await fx.clearElevation(fx.founderProfile);
      try {
        final settings =
            await fx.founder.rpc<dynamic>('admin_list_settings');
        expect(settings.toString(), contains('email_cap_free'));

        await expectRejected(
          () => fx.founder.rpc<dynamic>('admin_update_setting',
              params: {'p_key': 'free_caregivers', 'p_value': '2'}),
          contains: 'ELEVATION_REQUIRED',
        );

        await expectRejected(
          () => fx.founder.rpc<dynamic>('admin_set_comp',
              params: {'p_family_id': fx.familyId, 'p_granted': true}),
          contains: 'ELEVATION_REQUIRED',
        );
      } finally {
        await removeOperator(fx.founderProfile);
      }
    });

    // ── Settings editor rules ────────────────────────────────────────────

    test('admin_update_setting validates the type and refuses policy.*',
        () async {
      await makeOperator(fx.founderProfile);
      await fx.elevate(fx.founderProfile);
      try {
        await expectRejected(
          () => fx.founder.rpc<dynamic>('admin_update_setting',
              params: {'p_key': 'free_caregivers', 'p_value': 'abc'}),
          contains: 'int',
        );

        // `policy.*` is refused even for a VALID value: those two rows travel
        // with a code constant and a migration, and an out-of-band edit is what
        // locks the whole user base out of the app.
        await expectRejected(
          () => fx.founder.rpc<dynamic>('admin_update_setting',
              params: {'p_key': 'policy.current_version', 'p_value': '9.9'}),
          contains: 'policy',
        );

        // The console EDITS; it never creates.
        await expectRejected(
          () => fx.founder.rpc<dynamic>('admin_update_setting',
              params: {'p_key': 'no_such_setting', 'p_value': '1'}),
          contains: 'inexistente',
        );
      } finally {
        await fx.clearElevation(fx.founderProfile);
        await removeOperator(fx.founderProfile);
      }
    });

    test('admin_update_setting refuses a value the product cannot hold',
        () async {
      // T-80: each refusal names the range in the key's own unit — the sentence
      // the console shows. Every one of these was ACCEPTED before the item, each
      // with a real consequence (Asaas refusing every Pix under R$ 5,00, a 5th
      // member with no colour, a grace period of zero days).
      await makeOperator(fx.founderProfile);
      await fx.elevate(fx.founderProfile);
      final keys = [
        'billing.price_monthly_cents',
        'max_caregivers',
        'billing.grace_days',
        'billing.grace_warning_days',
        'billing.price_annual_cents',
      ];
      final before = await settingValues(keys);
      try {
        await expectRejected(
          () => fx.founder.rpc<dynamic>('admin_update_setting', params: {
            'p_key': 'billing.price_monthly_cents',
            'p_value': '300'
          }),
          contains: r'de R$ 5,00 a R$ 999,00',
        );
        await expectRejected(
          () => fx.founder.rpc<dynamic>('admin_update_setting',
              params: {'p_key': 'max_caregivers', 'p_value': '5'}),
          contains: 'de 2 a 4',
        );
        await expectRejected(
          () => fx.founder.rpc<dynamic>('admin_update_setting',
              params: {'p_key': 'billing.grace_days', 'p_value': '0'}),
          contains: 'de 1 a 30 dias',
        );

        // In range on its own, refused as a PAIR — and the sentence names the
        // other key, so the operator knows which one to move first.
        await expectRejected(
          () => fx.founder.rpc<dynamic>('admin_update_setting', params: {
            'p_key': 'billing.grace_warning_days',
            'p_value': '7'
          }),
          contains: 'billing.grace_days',
        );
        await expectRejected(
          () => fx.founder.rpc<dynamic>('admin_update_setting', params: {
            'p_key': 'billing.price_annual_cents',
            'p_value': '9999'
          }),
          contains: 'billing.price_monthly_cents',
        );

        expect(await settingValues(keys), before);
        // A refused write leaves no audit row behind: the trail records what
        // CHANGED, and nothing did.
        final audit = (await auditRows(fx.founderProfile.userId!)).where((l) =>
            l['action'] == 'setting_updated' &&
            keys.contains(l['setting_key']));
        expect(audit, isEmpty);
      } finally {
        await restoreSettings(before);
        await fx.clearElevation(fx.founderProfile);
        await removeOperator(fx.founderProfile);
      }
    });

    test('a valid setting update persists and leaves its audit row', () async {
      // Against a THROWAWAY settings row, so the shared dev config is never
      // mutated by the suite — and delete-first, so a cancelled run cannot leave
      // a fixed key behind for the next one.
      const probeKey = 'e2e.console_probe';

      await makeOperator(fx.founderProfile);
      await fx.elevate(fx.founderProfile);
      await fx.service.from('app_settings').delete().eq('key', probeKey);
      await fx.service.from('app_settings').insert({
        'key': probeKey,
        'value': '1',
        'value_type': 'int',
        'category': 'e2e',
      });
      try {
        await fx.founder.rpc<dynamic>('admin_update_setting',
            params: {'p_key': probeKey, 'p_value': '2'});

        final row = (await fx.service
                .from('app_settings')
                .select('value')
                .eq('key', probeKey))
            .single;
        expect(row['value'], '2');

        final audit = (await auditRows(fx.founderProfile.userId!)).where((l) =>
            l['action'] == 'setting_updated' && l['setting_key'] == probeKey);
        expect(audit, hasLength(1));
        expect(audit.single['old_value'], '1');
        expect(audit.single['new_value'], '2');
      } finally {
        await fx.service.from('app_settings').delete().eq('key', probeKey);
        await fx.clearElevation(fx.founderProfile);
        await removeOperator(fx.founderProfile);
      }
    });

    // ── Comp Premium ─────────────────────────────────────────────────────

    test('the comp flows through the entitlement itself, and is audited',
        () async {
      final fam = await fx.createFamily('f58-comp');
      await fx.service.rpc<dynamic>('set_family_plan',
          params: {'p_family_id': fam.familyId, 'p_plan': 'free'});
      expect(await isPremium(fam.familyId), isFalse);

      await makeOperator(fx.founderProfile);
      await fx.elevate(fx.founderProfile);
      try {
        await fx.founder.rpc<dynamic>('admin_set_comp', params: {
          'p_family_id': fam.familyId,
          'p_granted': true,
          'p_note': 'e2e comp',
        });
        expect(await isPremium(fam.familyId), isTrue);

        // A billing-style downgrade must NOT clobber the courtesy — otherwise
        // the next dunning cycle would silently take back what support gave.
        await fx.service.rpc<dynamic>('set_family_plan',
            params: {'p_family_id': fam.familyId, 'p_plan': 'free'});
        expect(await isPremium(fam.familyId), isTrue);

        // Idempotent: a repeated grant keeps the ORIGINAL timestamp.
        Future<DateTime?> compAt() async => Family.fromJson((await fx.service
                .from('families')
                .select()
                .eq('id', fam.familyId))
            .single).compPremiumAt;
        final first = await compAt();
        await fx.founder.rpc<dynamic>('admin_set_comp',
            params: {'p_family_id': fam.familyId, 'p_granted': true});
        expect(await compAt(), first);

        // Transparency: the FAMILY's own history shows the act, WITH the reason.
        expect(
            (await familyLogs(fam.familyId)).where((l) =>
                l.action == 'comp_premium_granted' && l.newValue == 'e2e comp'),
            hasLength(1));

        // …and the operator trail keeps the grant.
        expect(
            (await auditRows(fx.founderProfile.userId!)).where((l) =>
                l['action'] == 'comp_granted' && l['family_id'] == fam.familyId),
            hasLength(1));

        // Revoke — with ITS OWN reason: entitlement drops and the entry reads
        // "courtesy's note → revoke's reason".
        await fx.founder.rpc<dynamic>('admin_set_comp', params: {
          'p_family_id': fam.familyId,
          'p_granted': false,
          'p_note': 'e2e revoke',
        });
        expect(await isPremium(fam.familyId), isFalse);

        expect(
            (await familyLogs(fam.familyId)).where((l) =>
                l.action == 'comp_premium_revoked' &&
                l.oldValue == 'e2e comp' &&
                l.newValue == 'e2e revoke'),
            hasLength(1));
        expect(
            (await auditRows(fx.founderProfile.userId!)).where((l) =>
                l['action'] == 'comp_revoked' && l['family_id'] == fam.familyId),
            hasLength(1));
      } finally {
        await fx.clearElevation(fx.founderProfile);
        await removeOperator(fx.founderProfile);
      }
    });

    // ── Support lookup ───────────────────────────────────────────────────

    test('the lookup crosses families, and every call is logged', () async {
      // Crossing the family RLS is the POINT — it is what the operator gate
      // exists for — which is exactly why a miss is audited too: an access
      // attempt that found nothing is still an access attempt.
      await makeOperator(fx.founderProfile);
      try {
        final hit = await fx.founder.rpc<dynamic>('admin_lookup_family',
            params: {'p_email': fx.founderBProfile.email});
        final decoded = hit is String
            ? jsonDecode(hit) as Map<String, dynamic>
            : hit as Map<String, dynamic>;
        expect((decoded['family'] as Map)['id'], fx.familyBId);
        expect(
            (decoded['members'] as List).map((m) => (m as Map)['email']),
            contains(fx.founderBProfile.email));

        final missEmail = fx.testEmail('f58-nobody');
        final miss = await fx.founder
            .rpc<dynamic>('admin_lookup_family', params: {'p_email': missEmail});
        expect(miss.toString(), isNot(contains('family')));

        final audit = await auditRows(fx.founderProfile.userId!);
        expect(
            audit.where((l) =>
                l['action'] == 'family_lookup' &&
                l['family_id'] == fx.familyBId &&
                l['new_value'] == fx.founderBProfile.email!.toLowerCase()),
            isNotEmpty);
        expect(
            audit.where((l) =>
                l['action'] == 'family_lookup' &&
                l['family_id'] == null &&
                l['new_value'] == missEmail.toLowerCase()),
            isNotEmpty);
      } finally {
        await removeOperator(fx.founderProfile);
      }
    });

    // ── QA round: the full listing and the login e-mail change ───────────

    test('admin_list_families returns everything with members, and audits',
        () async {
      // The console lists EVERYTHING upfront and filters locally, so the bulk
      // read itself is an audited act.
      await makeOperator(fx.founderProfile);
      try {
        final response = await fx.founder.rpc<dynamic>('admin_list_families');
        final families = (response is String
                ? jsonDecode(response) as List
                : response as List)
            .cast<Map<String, dynamic>>();

        final ids = families.map((f) => f['id']).toSet();
        expect(ids, contains(fx.familyId));
        expect(ids, contains(fx.familyBId));

        final familyA = families.firstWhere((f) => f['id'] == fx.familyId);
        final emails =
            (familyA['members'] as List).map((m) => (m as Map)['email']);
        expect(emails, contains(fx.founderProfile.email));
        expect(emails, contains(fx.memberProfile.email));

        // F-69: the dates the console sorts by. The founder has signed in
        // (this fixture's clients did), so GoTrue has a last sign-in, and the
        // last-active rule falls back to the session until T-78 has a row.
        final founder = (familyA['members'] as List)
            .cast<Map<String, dynamic>>()
            .firstWhere((m) => m['id'] == fx.founderProfile.id);
        expect(founder['created_at'], isNotNull);
        expect(founder['last_sign_in_at'], isNotNull);
        expect(founder['last_active_day'], isNotNull);
        expect(founder['last_active_source'], isIn(['activity', 'auth_sessions']));

        expect(
            (await auditRows(fx.founderProfile.userId!))
                .where((l) => l['action'] == 'families_listed'),
            isNotEmpty);
      } finally {
        await removeOperator(fx.founderProfile);
      }
    });

    test('admin_list_audit returns the trail, newest first', () async {
      await makeOperator(fx.founderProfile);
      try {
        // Leave a fresh, recognizable footprint to find in the trail.
        await fx.founder.rpc<dynamic>('admin_lookup_family',
            params: {'p_email': fx.founderBProfile.email});

        final response = await fx.founder
            .rpc<dynamic>('admin_list_audit', params: {'p_limit': 50});
        final entries = (response is String
                ? jsonDecode(response) as List
                : response as List)
            .cast<Map<String, dynamic>>();

        expect(
            entries.where((e) =>
                e['action'] == 'family_lookup' && e['family_name'] != null),
            isNotEmpty);

        final ids = [for (final e in entries) e['id'] as int];
        expect(ids, orderedEquals([...ids]..sort((a, b) => b.compareTo(a))));
      } finally {
        await removeOperator(fx.founderProfile);
      }
    });

    test("a plan change writes the family's history with an inferred reason",
        () async {
      // QA 2: the flips narrate themselves in the FAMILY's own history, and the
      // reason is inferred from the subscription state — a paid activation and a
      // dunning downgrade, through the REAL writers.
      final fam = await fx.createFamily('f58-hist');
      await fx.deleteSubscriptionSeed('sub_e2e_f58-hist');
      final sub = Subscription.fromJson((await fx.service
              .from('subscriptions')
              .insert({
                'family_id': fam.familyId,
                'external_subscription_id': 'sub_e2e_f58-hist',
                'cycle': 'monthly',
                'price_cents': 549,
              })
              .select())
          .single);

      await fx.service
          .from('subscriptions')
          .update({'status': 'active'}).eq('id', sub.id);
      await fx.service.rpc<dynamic>('set_family_plan',
          params: {'p_family_id': fam.familyId, 'p_plan': 'premium'});

      await fx.service.from('subscriptions').update({
        'status': 'overdue',
        'overdue_since': DateTime.now()
            .toUtc()
            .subtract(const Duration(days: 10))
            .toIso8601String(),
      }).eq('id', sub.id);
      // The grace cron downgrades by DIRECT UPDATE — reproduce that path, not a
      // convenient RPC, because the trigger has to fire for the cron's writes.
      await fx.service
          .from('families')
          .update({'plan': 'free', 'trial_ends_at': null}).eq(
              'id', fam.familyId);

      final logs = await familyLogs(fam.familyId);
      expect(
          logs.where((l) =>
              l.action == 'plan_premium_payment' &&
              l.oldValue == 'free' &&
              l.newValue == 'premium'),
          hasLength(1));
      expect(
          logs.where((l) =>
              l.action == 'plan_free_overdue' &&
              l.oldValue == 'premium' &&
              l.newValue == 'free'),
          hasLength(1));
    });

    test('an operator changes a member login e-mail, end to end', () async {
      final fam = await fx.createFamily('f58-mail');
      final bearer = fx.founder.auth.currentSession!.accessToken;
      final newEmail = fx.testEmail('f58-mail-new');

      Future<(int, String)> changeEmail(int profileId, String email) async {
        final response = await http.post(
          Uri.parse('${TestEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}'
              '/functions/v1/admin-update-member-email'),
          headers: {
            'apikey': TestEnv.anonKey,
            'Authorization': 'Bearer $bearer',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'profile_id': profileId, 'new_email': email}),
        );
        return (response.statusCode, response.body);
      }

      // Not an operator yet → refused before anything else.
      await removeOperator(fx.founderProfile);
      final refused = await changeEmail(fam.memberProfile.id, newEmail);
      expect(refused.$1, 403);
      expect(refused.$2, contains('restrito'));

      await makeOperator(fx.founderProfile);
      try {
        // Operator without sudo → the ELEVATION_REQUIRED contract.
        await fx.clearElevation(fx.founderProfile);
        final unelevated = await changeEmail(fam.memberProfile.id, newEmail);
        expect(unelevated.$1, 403);
        expect(unelevated.$2, contains('ELEVATION_REQUIRED'));

        await fx.elevate(fx.founderProfile);

        // Another account's address → refused by GoTrue.
        final duplicate =
            await changeEmail(fam.memberProfile.id, fam.adminProfile.email!);
        expect(duplicate.$1, 409);

        final ok = await changeEmail(fam.memberProfile.id, newEmail);
        expect(ok.$1, 200);

        // profiles.email followed via sync_profile_email…
        final profile = Member.fromJson((await fx.service
                .from('profiles')
                .select()
                .eq('id', fam.memberProfile.id))
            .single);
        expect(profile.email, newEmail.toLowerCase());

        // …the LOGIN really moved (same password, new address)…
        final signedIn = await fx.signIn(newEmail);
        expect(signedIn.auth.currentSession, isNotNull);

        // …and both trails carry the act.
        expect(
            (await auditRows(fx.founderProfile.userId!)).where((l) =>
                l['action'] == 'member_email_changed' &&
                l['family_id'] == fam.familyId &&
                l['new_value'] == newEmail.toLowerCase()),
            isNotEmpty);
        expect(
            (await familyLogs(fam.familyId))
                .where((l) => l.action == 'email_changed'),
            isNotEmpty);
      } finally {
        await fx.clearElevation(fx.founderProfile);
        await removeOperator(fx.founderProfile);
      }
    });

    // ── F-69: the family usage report ────────────────────────────────────

    Map<String, dynamic>? decodeReport(dynamic response) => response == null
        ? null
        : (response is String ? jsonDecode(response) : response)
            as Map<String, dynamic>;

    test('T-82: the report windows are the operator keys, and it says which',
        () async {
      const keys = ['usage_report.weeks', 'usage_report.active_days'];
      final before = await settingValues(keys);
      await makeOperator(fx.founderProfile);
      try {
        await fx.service
            .from('app_settings')
            .update({'value': '4'}).eq('key', 'usage_report.weeks');
        await fx.service
            .from('app_settings')
            .update({'value': '7'}).eq('key', 'usage_report.active_days');
        final report = decodeReport(await fx.founder.rpc<dynamic>(
            'admin_family_usage_report',
            params: {'p_family_id': fx.familyBId}))!;
        expect(report['windows'], {'weeks': 4, 'active_days': 7});
        expect(report['weeks'] as List, hasLength(4));
      } finally {
        await restoreSettings(before);
        await removeOperator(fx.founderProfile);
      }
    });

    test('the usage report is audited on every call, an unknown family too',
        () async {
      // Read-only, so no sudo — the lookup's rule. And the lookup's other
      // rule: a miss is still an access attempt.
      await makeOperator(fx.founderProfile);
      await fx.clearElevation(fx.founderProfile);
      try {
        final hit = decodeReport(await fx.founder.rpc<dynamic>(
            'admin_family_usage_report',
            params: {'p_family_id': fx.familyBId}));
        expect((hit!['family'] as Map)['id'], fx.familyBId);

        const unknown = -69;
        final miss = await fx.founder.rpc<dynamic>('admin_family_usage_report',
            params: {'p_family_id': unknown});
        expect(miss, isNull);

        final audit = (await auditRows(fx.founderProfile.userId!))
            .where((l) => l['action'] == 'family_usage_report');
        expect(
            audit.where((l) =>
                l['family_id'] == fx.familyBId &&
                l['new_value'] == '${fx.familyBId}'),
            isNotEmpty);
        expect(
            audit.where(
                (l) => l['family_id'] == null && l['new_value'] == '$unknown'),
            isNotEmpty);
      } finally {
        await removeOperator(fx.founderProfile);
      }
    });

    test(
        'the usage report returns only whitelisted keys, and no free text '
        'from any column that holds it', () async {
      // A marker in EVERY text column the report's tables carry — the family
      // name, both names, a custom role, the day note, the swap message, the
      // approval note, the rejection reason, the aviso note and its outcome's,
      // the relato, a notification's title/message/params, the push token and
      // its device label, the invitation e-mail. The report may count them;
      // none may come back.
      const marker = 'zzf69leak';
      final fam = await fx.createFamily('f69rep');
      final today = saoPauloToday();
      final days = fx.nextFutureDates(2);
      final swapDays = fx.nextFutureDates(2);

      // The E2E prefix stays: `purge_e2e_family` refuses a family whose name
      // lost its signature, and the teardown would leave this one behind.
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

      // Two consecutive days: the first carries a note and is a transition
      // (no D-1 row); the second changes carer and carries a time.
      await fx.service.from('care_schedules').insert([
        {
          'family_id': fam.familyId,
          'schedule_date': isoDate(days[0]),
          'scheduled_parent_id': fam.adminProfile.id,
          'notes': '$marker-note',
        },
        {
          'family_id': fam.familyId,
          'schedule_date': isoDate(days[1]),
          'scheduled_parent_id': fam.memberProfile.id,
          'handoff_time': '18:00',
        },
      ]);

      // Two swaps through the real clients: one approved with a note, one
      // rejected with a reason — the F-44 columns.
      Future<int> openSwap(DateTime date) async => (await fam.member
              .from('swap_requests')
              .insert({
                'schedule_date': isoDate(date),
                'requesting_profile_id': fam.memberProfile.id,
                'target_profile_id': fam.adminProfile.id,
                'previous_actual_parent_id': null,
                'proposed_actual_parent_id': fam.memberProfile.id,
                'status': 'pending',
                'request_message': '$marker-request',
              })
              .select('id'))
          .single['id'] as int;
      final approved = await openSwap(swapDays[0]);
      await fam.admin.from('swap_requests').update({
        'status': 'approved',
        'approval_note': '$marker-approval',
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', approved);
      final rejected = await openSwap(swapDays[1]);
      await fam.admin.from('swap_requests').update({
        'status': 'rejected',
        'rejection_reason': '$marker-rejection',
        'resolved_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', rejected);

      final notice = (await fx.service
              .from('day_notices')
              .insert({
                'family_id': fam.familyId,
                'schedule_date': isoDate(today),
                'sender_profile_id': fam.adminProfile.id,
                'reason': 'outro',
                'request': 'info',
                'note': '$marker-aviso',
              })
              .select('id'))
          .single['id'] as int;
      await fx.service.from('day_notice_outcomes').insert({
        'notice_id': notice,
        'outcome': 'cancelled',
        'actor_profile_id': fam.adminProfile.id,
        'note': '$marker-outcome',
      });

      // F-55: a child and an agenda event, both carrying the marker — the
      // report counts them and says neither the name nor the text.
      final child = (await fx.service
              .from('children')
              .insert({'family_id': fam.familyId, 'first_name': '$marker-kid'})
              .select('id'))
          .single['id'] as int;
      await fx.service.from('child_events').insert({
        'family_id': fam.familyId,
        'child_id': child,
        'event_date': isoDate(days[1]),
        'kind': 'school',
        'body': '$marker-agenda',
      });

      await fx.service.from('day_accounts').insert({
        'family_id': fam.familyId,
        'account_date': isoDate(addDays(today, -1)),
        'author_profile_id': fam.adminProfile.id,
        'body': '$marker-relato',
      });

      // A type outside PUSH_TYPES (the F-28 fan-out), so the dispatcher never
      // touches the fake token below.
      await fx.service.from('notifications').insert({
        'recipient_profile_id': fam.memberProfile.id,
        'type': 'swap_family_info',
        'title': '$marker-title',
        'message': '$marker-message',
        'params': {'note': '$marker-params'},
      });

      await fx.service.from('push_subscriptions').insert({
        'profile_id': fam.memberProfile.id,
        'token': '$marker-token-${fam.familyId}',
        'platform': 'android',
        'device_label': '$marker-device',
      });

      await fx.service.from('family_invitations').insert({
        'family_id': fam.familyId,
        'email': fx.testEmail('$marker-inv'),
        'role_id': fx.roleId('grandmother'),
        'invited_by': fam.adminProfile.id,
      });

      // T-78: the member used the app today; the admin has no activity row,
      // so the report falls back to the GoTrue session and says so.
      await fam.member
          .rpc<dynamic>('touch_activity', params: {'p_channel': 'android'});

      await makeOperator(fx.founderProfile);
      try {
        final report = decodeReport(await fx.founder.rpc<dynamic>(
            'admin_family_usage_report',
            params: {'p_family_id': fam.familyId}))!;

        // ── Nothing typed by a person comes back ──
        final encoded = jsonEncode(report).toLowerCase();
        expect(encoded, isNot(contains(marker)));
        expect(encoded, isNot(contains(fam.adminProfile.email!.toLowerCase())));
        expect(
            encoded, isNot(contains(fam.memberProfile.email!.toLowerCase())));

        // ── …and no key the list does not name ──
        expect(_keysOf(report).difference(_usageReportKeys), isEmpty,
            reason: 'a new report key must be added to _usageReportKeys '
                'on purpose, after checking it is not free text');

        // ── The facts are the seeded ones ──
        final family = report['family'] as Map<String, dynamic>;
        expect(family['id'], fam.familyId);
        expect(family['seats_cap'], isA<int>());
        expect((family['invitations'] as Map)['open'], 1);
        expect((family['invitations'] as Map)['accepted'], 1);

        final members = (report['members'] as List)
            .cast<Map<String, dynamic>>()
            .toList();
        final admin =
            members.firstWhere((m) => m['profile_id'] == fam.adminProfile.id);
        final member =
            members.firstWhere((m) => m['profile_id'] == fam.memberProfile.id);
        expect(admin['role'], 'father');
        expect(member['role'], 'custom');
        expect(admin['state'], 'active');
        expect(member['has_password'], isTrue);

        expect(member['last_active_source'], 'activity');
        expect(member['last_active_day'], isoDate(today));
        expect(member['channels_30'], ['android']);
        expect(admin['last_active_source'], 'auth_sessions');

        expect(member['devices'], [
          allOf(containsPair('platform', 'android'), containsPair('count', 1)),
        ]);
        expect(admin['devices'], isEmpty);
        expect(
            member['unread'],
            contains(allOf(containsPair('type', 'swap_family_info'),
                containsPair('count', 1))));

        final plan = report['plan'] as Map<String, dynamic>;
        expect(plan['days_with_note'], 1);
        expect(plan['days_with_handoff_time'], 1);
        expect(plan['first_day'], isoDate(days[0]));

        final byStatus = ((report['swaps'] as Map)['by_status'] as List)
            .cast<Map<String, dynamic>>();
        expect(byStatus.map((s) => s['status']),
            containsAll(['approved', 'rejected']));

        final notices = report['notices'] as Map<String, dynamic>;
        expect(notices['total'], 1);
        expect(notices['by_outcome'], [
          {'outcome': 'cancelled', 'count': 1}
        ]);
        expect((report['day_accounts'] as Map)['total'], 1);
        final agenda = report['agenda'] as Map<String, dynamic>;
        expect(agenda['children'], 1);
        expect(agenda['events_active'], 1);
        expect(agenda['routines'], 0);
        expect(agenda['events_from_routine'], 0);
        expect(agenda['with_reminder'], 0);
        expect(agenda['reminders_sent'], 0);
        expect(agenda['by_kind'], [
          {'kind': 'school', 'count': 1}
        ]);

        expect(report['weeks'] as List, hasLength(12));
      } finally {
        await removeOperator(fx.founderProfile);
      }
    });
  });
}
