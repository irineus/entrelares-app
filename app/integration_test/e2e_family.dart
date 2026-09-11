// The throwaway-family fixture for the E2E lane — the Flutter twin of the web
// suite's `E2EFamilyFixture` (T-30), and it pays for the same lessons:
//
//   * one family per run, named `E2E-<runId>` so the DB-side purge guard can
//     recognise it (`purge_e2e_family` re-validates the double signature —
//     a fixture bug cannot delete a real family);
//   * members born through the REAL onboarding path (admin create-user →
//     `handle_new_user` trigger; the second member via `create_invitation`),
//     never seeded rows;
//   * `@resend.dev` addresses (no real mailbox, no bounces);
//   * teardown always purges, green or red, and a startup sweep removes
//     ORPHANS older than 2h left by crashed runs — self-healing;
//   * `onboarding_*` stamped so the U-23 first-run tour never swallows a tap
//     (three web SmokeTests died that way before the stamp existed).
//
// Needs the DEV project's service_role key in `E2E_SUPABASE_SERVICE_ROLE_KEY`
// (CI: the `SUPABASE_SERVICE_ROLE_DEV` secret). It is never in the repo: this
// file only reads it from the environment via --dart-define.
library;

import 'dart:convert';
import 'dart:math';

import 'package:entrelares_app/env.dart';
import 'package:http/http.dart' as http;

const _serviceRoleKey =
    String.fromEnvironment('E2E_SUPABASE_SERVICE_ROLE_KEY');

/// Same signature the web suite uses — the purge RPC keys off it.
const familyPrefix = 'E2E-';

/// The seeded people, and their word ORDER is load-bearing.
///
/// Every carer chip in the app is labelled `fullName.split(' ').first` — a chip
/// shows a given name, not a full one (`screens/day_sheet.dart`). So the
/// DISTINCTIVE word has to come first, or two profiles both named `E2E …`
/// render two chips reading "E2E" and no finder can tell them apart.
///
/// They used to be `E2E Founder` / `E2E Member`, and the swap test looked for
/// `.split(' ').last` to get the distinctive half back. Neither half of that
/// pairing matched the app, and nobody noticed for six days because the suite
/// never reached the assertion (T-58).
const founderName = 'Founder E2E';
const memberName = 'Member E2E';

/// Resend's test domain: accepted, delivered nowhere, never bounces.
const emailDomain = '@resend.dev';

class E2eMember {
  final String email;
  final String fullName;
  final int profileId;
  final String userId;

  const E2eMember({
    required this.email,
    required this.fullName,
    required this.profileId,
    required this.userId,
  });
}

/// One disposable family per run: an admin (founder, `father`) and a member
/// (`mother`), both real users of the dev project.
class E2eFamily {
  final String runId;
  final String password;
  final E2eMember founder;
  final E2eMember member;
  final int familyId;
  final List<String> _userIds;

  E2eFamily._({
    required this.runId,
    required this.password,
    required this.founder,
    required this.member,
    required this.familyId,
    required this._userIds,
  });

  static String get _url => Env.dev.supabaseUrl;

  static Map<String, String> get _headers => {
        'apikey': _serviceRoleKey,
        'Authorization': 'Bearer $_serviceRoleKey',
        'Content-Type': 'application/json',
      };

  static void requireKey() {
    if (_serviceRoleKey.isEmpty) {
      throw StateError(
          'E2E_SUPABASE_SERVICE_ROLE_KEY is not set. The lane needs the DEV '
          "project's service_role key, passed as --dart-define "
          '(CI: the SUPABASE_SERVICE_ROLE_DEV secret). It never enters the repo.');
    }
  }

  static Future<Map<String, dynamic>> _post(String path, Object body) async {
    final res = await http.post(Uri.parse('$_url$path'),
        headers: _headers, body: jsonEncode(body));
    if (res.statusCode >= 300) {
      throw StateError('POST $path → ${res.statusCode}: ${res.body}');
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
  }

  static Future<List<dynamic>> _get(String path) async {
    final res = await http.get(Uri.parse('$_url$path'), headers: _headers);
    if (res.statusCode >= 300) {
      throw StateError('GET $path → ${res.statusCode}: ${res.body}');
    }
    final decoded = jsonDecode(res.body);
    return decoded is List ? decoded : [decoded];
  }

  /// The admin API's create-user with `email_confirm` — the same door the web
  /// fixture uses, so `handle_new_user` runs for real (family creation for a
  /// founder, family join for an invitee).
  static Future<String> _createConfirmedUser(
      String email, String password, Map<String, dynamic> metadata) async {
    final body = await _post('/auth/v1/admin/users', {
      'email': email,
      'password': password,
      'email_confirm': true,
      'user_metadata': metadata,
    });
    return body['id'] as String;
  }

  static Future<void> _deleteUser(String userId) async {
    try {
      await http.delete(Uri.parse('$_url/auth/v1/admin/users/$userId'),
          headers: _headers);
    } catch (_) {/* best effort */}
  }

  /// A user's access token via the password grant (anon key, like the app).
  /// T-32: GoTrue rate-limits a suite that creates many users — back off on
  /// 429 instead of flaking the run.
  static Future<String> _accessToken(String email, String password) async {
    for (var attempt = 0;; attempt++) {
      final res = await http.post(
        Uri.parse('$_url/auth/v1/token?grant_type=password'),
        headers: {
          'apikey': Env.dev.supabaseKey,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'email': email, 'password': password}),
      );
      if (res.statusCode < 300) {
        return jsonDecode(res.body)['access_token'] as String;
      }
      if (attempt >= 5 || !res.body.contains('rate_limit')) {
        throw StateError('sign-in failed (${res.statusCode}): ${res.body}');
      }
      await Future<void>.delayed(Duration(seconds: 1 << attempt));
    }
  }

  /// An RPC call as the SIGNED-IN user — `create_invitation` reads
  /// `auth.uid()`, so the service role cannot stand in for the inviter.
  static Future<dynamic> _rpcAs(
      String accessToken, String name, Map<String, dynamic> args) async {
    final res = await http.post(
      Uri.parse('$_url/rest/v1/rpc/$name'),
      headers: {
        'apikey': Env.dev.supabaseKey,
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(args),
    );
    if (res.statusCode >= 300) {
      throw StateError('RPC $name → ${res.statusCode}: ${res.body}');
    }
    return res.body.isEmpty ? null : jsonDecode(res.body);
  }

  /// Creates the family. [policyVersion] must match the app's current S-15
  /// consent version; the trigger stores it on the profile.
  static Future<E2eFamily> create({required String policyVersion}) async {
    requireKey();
    await _sweepOrphans();

    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
        RegExp(r'[-:.TZ]'), '');
    final runId = '$stamp-${DateTime.now().microsecondsSinceEpoch % 10000}';
    final password = _throwawayCredential();
    final userIds = <String>[];

    String emailFor(String who) => 'delivered+e2e-$runId-$who$emailDomain';

    // Founder — `handle_new_user` creates the family from the metadata.
    final founderEmail = emailFor('founder');
    userIds.add(await _createConfirmedUser(founderEmail, password, {
      'full_name': founderName,
      'role': 'father',
      'family_name': '$familyPrefix$runId',
      'policy_version': policyVersion,
    }));

    final founderRows = await _get(
        '/rest/v1/profiles?email=eq.${Uri.encodeComponent(founderEmail)}&select=id,user_id,family_id');
    final founderRow = founderRows.first as Map<String, dynamic>;
    final familyId = founderRow['family_id'] as int;

    // Member — through the REAL invitation flow, as a family joiner.
    final roles = await _get('/rest/v1/roles?select=id,role');
    final motherRoleId = (roles.firstWhere((r) =>
            (r as Map)['role'].toString().toLowerCase() == 'mother')
        as Map)['id'] as int;
    final memberEmail = emailFor('member');
    final founderToken = await _accessToken(founderEmail, password);
    final invite = await _rpcAs(founderToken, 'create_invitation', {
      'p_email': memberEmail,
      'p_role_id': motherRoleId,
    });
    final token = _tokenOf(invite);

    userIds.add(await _createConfirmedUser(memberEmail, password, {
      'full_name': memberName,
      'invite_token': token,
      'policy_version': policyVersion,
    }));
    final memberRows = await _get(
        '/rest/v1/profiles?email=eq.${Uri.encodeComponent(memberEmail)}&select=id,user_id');
    final memberRow = memberRows.first as Map<String, dynamic>;

    final family = E2eFamily._(
      runId: runId,
      password: password,
      familyId: familyId,
      founder: E2eMember(
          email: founderEmail,
          fullName: founderName,
          profileId: founderRow['id'] as int,
          userId: founderRow['user_id'] as String),
      member: E2eMember(
          email: memberEmail,
          fullName: memberName,
          profileId: memberRow['id'] as int,
          userId: memberRow['user_id'] as String),
      userIds: userIds,
    );

    // U-23: present the app in its STEADY state — the first-run tour is an
    // overlay that swallows every tap (the web suite's hardest-won lesson).
    await family._markOnboarded();
    return family;
  }

  /// The run's credential for both throwaway users — generated fresh per run
  /// from secure randomness, never a literal. It lives only in memory: the
  /// users it belongs to are deleted in [purge].
  static String _throwawayCredential() {
    const pool =
        'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789-_.';
    final rng = Random.secure();
    return List.generate(28, (_) => pool[rng.nextInt(pool.length)]).join();
  }

  static String _tokenOf(dynamic rpcResult) {
    if (rpcResult is List && rpcResult.isNotEmpty) {
      return (rpcResult.first as Map)['token'] as String;
    }
    if (rpcResult is Map && rpcResult['token'] != null) {
      return rpcResult['token'] as String;
    }
    throw StateError('create_invitation returned no token: $rpcResult');
  }

  Future<void> _markOnboarded() async {
    final seenAt = DateTime.now().toUtc().toIso8601String();
    for (final id in [founder.profileId, member.profileId]) {
      await http.patch(
        Uri.parse('$_url/rest/v1/profiles?id=eq.$id'),
        headers: _headers,
        body: jsonEncode({
          'onboarding_tour_seen_at': seenAt,
          'onboarding_swap_explained_at': seenAt,
          'onboarding_dismissed_at': seenAt,
        }),
      );
    }
  }

  /// Seeds a day directly (service role) — the calendar state a scenario
  /// starts from, not the thing under test.
  Future<void> seedDay({
    required DateTime date,
    required int scheduledParentId,
    int? actualParentId,
    String? notes,
  }) async {
    await _post('/rest/v1/care_schedules', {
      'schedule_date': _iso(date),
      'scheduled_parent_id': scheduledParentId,
      'actual_parent_id': actualParentId,
      'notes': notes,
      'family_id': familyId,
    });
  }

  /// The family's open requests — what an assertion checks after the UI acted.
  Future<List<Map<String, dynamic>>> openRequests() async {
    final rows = await _get('/rest/v1/swap_requests'
        '?family_id=eq.$familyId&status=in.(pending,revert_pending)&select=*');
    return [for (final r in rows) r as Map<String, dynamic>];
  }

  Future<Map<String, dynamic>?> dayOf(DateTime date) async {
    final rows = await _get('/rest/v1/care_schedules'
        '?family_id=eq.$familyId&schedule_date=eq.${_iso(date)}&select=*');
    return rows.isEmpty ? null : rows.first as Map<String, dynamic>;
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Always runs, green or red. The RPC re-validates the double signature
  /// server-side and returns the auth users to remove.
  // ── Lote 4 helpers (account, family and legal) ───────────────────────────

  /// Another throwaway address in this run's namespace — an invitee that never
  /// signs up, so the family's own purge takes the invitation with it.
  String disposableEmail(String who) =>
      'delivered+e2e-$runId-$who$emailDomain';

  /// Invitations neither accepted nor revoked — what the Família page lists.
  Future<List<Map<String, dynamic>>> openInvitations() async {
    final rows = await _get('/rest/v1/family_invitations'
        '?family_id=eq.$familyId&accepted_at=is.null&revoked_at=is.null'
        '&select=id,email,role_id,token,expires_at,profile_id');
    return rows.cast<Map<String, dynamic>>();
  }

  /// Every invitation, including the revoked ones — the revoke assertion needs
  /// to see the row it just closed.
  Future<List<Map<String, dynamic>>> allInvitations() async {
    final rows = await _get('/rest/v1/family_invitations'
        '?family_id=eq.$familyId&select=id,email,revoked_at');
    return rows.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>?> profileOf(int profileId) async {
    final rows = await _get(
        '/rest/v1/profiles?id=eq.$profileId&select=id,is_admin,role_id,full_name');
    return rows.isEmpty ? null : rows.first as Map<String, dynamic>;
  }

  Future<int> roleIdOf(String roleName) async {
    final roles = await _get('/rest/v1/roles?select=id,role');
    return (roles.firstWhere((r) =>
            (r as Map)['role'].toString().toLowerCase() ==
            roleName.toLowerCase()) as Map)['id'] as int;
  }

  /// Lifts the family past the F-37 free cap so the invite FORM renders. The
  /// cap itself is the DB's business and has its own server-side tests; this
  /// lane is here to exercise the screen behind it.
  Future<void> setPlan(String plan) async {
    await http.patch(
      Uri.parse('$_url/rest/v1/families?id=eq.$familyId'),
      headers: {..._headers, 'Content-Type': 'application/json'},
      body: jsonEncode({'plan': plan}),
    );
  }

  Future<void> purge() async {
    try {
      final result =
          await _post('/rest/v1/rpc/purge_e2e_family', {'p_family_id': familyId});
      final data = result['data'];
      if (data is List) {
        for (final id in data) {
          if (id is String) await _deleteUser(id);
        }
      }
    } finally {
      for (final id in _userIds) {
        await _deleteUser(id);
      }
    }
  }

  /// Families older than 2h whose name carries the E2E signature — the debris
  /// of runs the CI concurrency group killed before teardown.
  static Future<void> _sweepOrphans() async {
    try {
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .toIso8601String();
      final rows = await _get('/rest/v1/families'
          '?name=like.$familyPrefix*&created_at=lt.$cutoff&select=id');
      for (final row in rows) {
        try {
          await _post('/rest/v1/rpc/purge_e2e_family',
              {'p_family_id': (row as Map)['id']});
        } catch (_) {/* leave for manual inspection */}
      }
    } catch (_) {/* the sweep must never fail a run */}
  }
}
