import 'dart:math';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:entrelares_db_contracts/entrelares_db_contracts.dart';
import 'package:supabase/supabase.dart';

import 'admin_api.dart';
import 'iso_date.dart';
import 'test_env.dart';

/// One throwaway family per RUN, created against the REAL dev project through
/// the REAL onboarding path — the Dart twin of the C# suite's
/// `E2EFamilyFixture` (T-30).
///
/// **The identity clients are the whole point.** RLS cannot be tested by one
/// privileged connection asserting about rows: it is tested by asking, as
/// person A, for something only person B may see, and getting nothing back. So
/// the fixture hands out FOUR live clients — [service] (bypasses RLS, for
/// seeding and inspection), [founder] and [member] of family A, and [founderB],
/// the founder of a second family that exists only so "another family" is a
/// real caller and not a hypothesis. Every one of them is a separate
/// [SupabaseClient] holding its own session, which is why this package depends
/// on the pure-Dart `supabase` and never on `supabase_flutter` — the latter is
/// a per-process singleton and could hold exactly one of them.
///
/// **Cleanup has two layers**, both inherited:
///   1. [dispose] always purges this run's data, green or red;
///   2. [initialize] sweeps ORPHANED E2E families (the double signature, older
///      than 2 h) left behind by runs a CI cancellation killed before teardown
///      — self-healing, and the 2 h floor is what stops it robbing a run that
///      is still going.
///
/// The purge itself is the `purge_e2e_family` RPC (service_role only), whose
/// double-signature guard lives in the DATABASE: a fixture bug cannot delete a
/// real family.
class GateFixture {
  String runId = '';
  String password = '';

  /// Bypasses RLS — seeding and inspection only. Never the subject of an
  /// assertion about what a USER may do.
  late final SupabaseClient service;

  /// Family A's admin, role `father`.
  late final SupabaseClient founder;

  /// Family A's non-admin, role `mother`.
  late final SupabaseClient member;

  /// A SECOND family's founder — the cross-family RLS assertions need a real
  /// other tenant, not a fabricated id.
  late final SupabaseClient founderB;

  late final Member founderProfile;
  late final Member memberProfile;
  late final Member founderBProfile;

  List<Role> roles = const [];
  int familyId = 0;
  int familyBId = 0;

  /// The token family A's [member] joined with — `RegisterInviteeTests` and the
  /// invitation suites replay it.
  String inviteToken = '';

  late final AdminApi _admin;
  final List<String> _userIds = [];
  final List<int> _extraFamilyIds = [];
  final List<SupabaseClient> _clients = [];
  int _dateCounter = 0;

  // ── Date allocation ──────────────────────────────────────────────────────
  // Every allocator here exists because a hand-picked offset in a SHARED family
  // is a landmine with a delivery-count fuse: the UNIQUE (family_id,
  // schedule_date) constraint has taken the gate down four times, twice at a
  // promotion. Tests take their days from here, never from local arithmetic.

  /// Unique future date per call — tests never collide on the UNIQUE
  /// `(family_id, schedule_date)` constraint.
  DateTime nextFutureDate() => nextFutureDates(1).first;

  /// Allocates [count] CONSECUTIVE unique future dates. Needed by tests that
  /// reason about NEIGHBOURING days (T-45: a day's transition status is defined
  /// against D-1) — taking the block in one step is what stops the next caller
  /// from being handed a date inside it.
  List<DateTime> nextFutureDates(int count) {
    _dateCounter += count;
    final first = addDays(today(), 10 + _dateCounter - count + 1);
    return [for (var i = 0; i < count; i++) addDays(first, i)];
  }

  DateTime _nextVisibleDay = addDays(today(), 3);

  /// Unique future date for tests that assert on rendered day CELLS. Shorthand
  /// for [nextVisibleDays] with a block of 1.
  DateTime nextVisibleDay() => nextVisibleDays(1).first;

  /// Allocates [count] consecutive unique future dates that satisfy both rules
  /// a day-cell test depends on: the block falls in ONE calendar month, so a
  /// single month view shows it whole, and it stays OFF that month's LAST grid
  /// row.
  ///
  /// The last row is excluded because it is the row that sits at the bottom of
  /// the viewport, where anything fixed to the bottom — the selection action
  /// bar — overlaps it. A press there tests the overlap instead of the feature.
  ///
  /// Both rules are satisfied the same way: move the block WHOLE to day 1 of
  /// the next month. The first allocator clamped the overflow to day 1 of the
  /// CURRENT month, which is a PAST day (immutable per V008) and the same date
  /// on every overflow (UNIQUE violations); it broke every promotion run near
  /// the end of a month.
  List<DateTime> nextVisibleDays(int count) {
    // The tightest month (28 days starting on a Sunday) is 4 rows, so 21 days
    // always fit above the last one. Beyond that no start date can satisfy the
    // rule and the loop below would never end — say so here rather than hang.
    if (count < 1 || count > 21) {
      throw RangeError.value(
        count,
        'count',
        'A block must fit above the last grid row; the tightest month leaves '
            'room for 21 days',
      );
    }
    while (!_fitsAboveLastRow(_nextVisibleDay, count)) {
      _nextVisibleDay = DateTime(_nextVisibleDay.year, _nextVisibleDay.month + 1, 1);
    }
    final block = [
      for (var i = 0; i < count; i++) addDays(_nextVisibleDay, i),
    ];
    _nextVisibleDay = addDays(_nextVisibleDay, count);
    return block;
  }

  static bool _fitsAboveLastRow(DateTime start, int count) {
    final last = addDays(start, count - 1);
    return last.month == start.month && _gridRow(last) < _lastGridRow(start);
  }

  // Sunday-first, mirroring the calendar itself. Dart's DateTime.weekday is
  // 1=Monday…7=Sunday, so Sunday must fold back to 0.
  static int _leadingBlanks(DateTime day) =>
      DateTime(day.year, day.month, 1).weekday % 7;

  static int _gridRow(DateTime day) => (_leadingBlanks(day) + day.day - 1) ~/ 7;

  static int _lastGridRow(DateTime day) =>
      (_leadingBlanks(day) + _daysInMonth(day) - 1) ~/ 7;

  static int _daysInMonth(DateTime day) =>
      DateTime(day.year, day.month + 1, 0).day;

  // ── Lifecycle ────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    _admin = AdminApi(); // throws with instructions if the service key is missing
    service = _track(SupabaseClient(TestEnv.supabaseUrl, TestEnv.serviceRoleKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false)));

    await _sweepOrphanedFamilies();

    runId = '${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[-:.TZ]'), '')}'
        '-${_randomHex(4)}';
    password = _throwawayCredential();

    // Family A: founder through the real trigger path.
    final founderEmail = testEmail('founder');
    _userIds.add(await _admin.createConfirmedUser(founderEmail, password, {
      'full_name': 'E2E Founder',
      'role': 'father',
      'family_name': '${TestEnv.e2eFamilyPrefix}$runId',
      'policy_version': PolicyVersions.current,
    }));
    founder = await signIn(founderEmail);

    roles = await _rolesOf(founder);
    founderProfile = (await _profilesOf(founder)).single;
    familyId = founderProfile.familyId!;

    // Member joins through the real invitation flow (create_invitation RPC).
    final memberEmail = testEmail('member');
    inviteToken =
        await createInvitation(founder, memberEmail, roleId('mother'));
    _userIds.add(await _admin.createConfirmedUser(memberEmail, password, {
      'full_name': 'E2E Member',
      'invite_token': inviteToken,
      'policy_version': PolicyVersions.current,
    }));
    member = await signIn(memberEmail);
    memberProfile = (await _profilesOf(founder))
        .firstWhere((p) => p.id != founderProfile.id);

    // Family B: single founder, for cross-family RLS assertions.
    final founderBEmail = testEmail('founder-b');
    _userIds.add(await _admin.createConfirmedUser(founderBEmail, password, {
      'full_name': 'E2E Founder B',
      'role': 'father',
      'family_name': '${TestEnv.e2eFamilyPrefix}$runId-B',
      'policy_version': PolicyVersions.current,
    }));
    founderB = await signIn(founderBEmail);
    founderBProfile = (await _profilesOf(founderB)).single;
    familyBId = founderBProfile.familyId!;

    await _markOnboarded(
        [founderProfile.id, memberProfile.id, founderBProfile.id]);
  }

  Future<void> dispose() async {
    try {
      if (familyId != 0) await purgeFamily(familyId);
      if (familyBId != 0) await purgeFamily(familyBId);
      for (final id in _extraFamilyIds) {
        await purgeFamily(id);
      }
    } finally {
      for (final id in _userIds) {
        try {
          await _admin.deleteUser(id);
        } catch (_) {/* best effort */}
      }
      _admin.close();
      for (final client in _clients) {
        try {
          await client.dispose();
        } catch (_) {/* best effort */}
      }
    }
  }

  // ── Identities ───────────────────────────────────────────────────────────

  /// A brand-new ANONYMOUS client — no session, so PostgREST runs it as `anon`,
  /// which in this 100%-RLS app reads nothing. Callers dispose it themselves
  /// when they made one for a single assertion.
  SupabaseClient newAnonClient() => _track(SupabaseClient(
        TestEnv.supabaseUrl,
        TestEnv.anonKey,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ));

  /// A signed-in client for [email], using this run's [password].
  Future<SupabaseClient> signIn(String email) async {
    final client = newAnonClient();
    await _signInWithBackoff(client, email);
    return client;
  }

  /// T-32: the growing suite creates many throwaway families, each with several
  /// sign-ins; GoTrue's request rate limit (HTTP 429) then flakes the whole run.
  /// Back off and retry so scale does not break CI.
  Future<void> _signInWithBackoff(SupabaseClient client, String email) async {
    for (var attempt = 0;; attempt++) {
      try {
        await client.auth.signInWithPassword(email: email, password: password);
        return;
      } on AuthException catch (e) {
        final rateLimited = e.statusCode == '429' ||
            e.message.toLowerCase().contains('rate limit') ||
            (e.code ?? '').contains('rate_limit');
        if (attempt >= 5 || !rateLimited) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << attempt)); // 1,2,4,8,16s
      }
    }
  }

  String testEmail(String who) =>
      'delivered+e2e-$runId-$who${TestEnv.e2eEmailDomain}';

  /// The id of a BUILT-IN role by its canonical name (`father`, `mother`,
  /// `grandmother`, …). Seed data differs across environments, so the suite
  /// matches through the catalog rather than hardcoding an id.
  int roleId(String roleName) => roles
      .firstWhere((r) => r.roleName.toLowerCase() == roleName.toLowerCase())
      .id;

  /// F-57: a user created the way an OAUTH (Google) sign-up creates one, in
  /// the respect that matters — NO founder/invite metadata in
  /// `raw_user_meta_data`, which is the condition `handle_new_user` defers
  /// the profile on. (The provider itself cannot be simulated: the Admin API
  /// refuses to forge `provider: google`, which is why the deferred branch is
  /// keyed on the metadata's absence and not on the provider.) The password is
  /// kept on purpose: it lets the suite sign this user in and exercise the
  /// authenticated RPCs with the same JWT shape the real OAuth session would
  /// carry.
  Future<String> createOauthUser(String tag) async {
    final email = testEmail(tag);
    _userIds.add(await _admin.createConfirmedUser(
      email,
      password,
      {'full_name': 'E2E OAuth $tag'},
    ));
    return email;
  }

  /// F-56: a user created the way `register-invitee` creates one — pre-confirmed
  /// and carrying the invite token, the typed name and the policy version — so
  /// `handle_new_user`'s invitee branch runs for real against [token]. Returns
  /// the auth uid; tracked so teardown removes it.
  Future<String> createInvitedUser(
    String email,
    String token, {
    required String fullName,
  }) async {
    final uid = await _admin.createConfirmedUser(email, password, {
      'full_name': fullName,
      'invite_token': token,
      'policy_version': PolicyVersions.current,
    });
    _userIds.add(uid);
    return uid;
  }

  /// F-57: a user with NO metadata at all — the shape a password sign-up
  /// straight at the GoTrue API (never our forms) produces. Since the
  /// deferred branch keys on the metadata's absence, this defers exactly like
  /// an OAuth sign-up; the suite pins that down as documented behaviour. The
  /// id is tracked so teardown removes it.
  Future<void> createBareUser(String email) async {
    _userIds.add(await _admin.createConfirmedUser(email, password, const {}));
  }

  /// S-21: a member of [family] whose account has **no password at all** — the
  /// condition a Google sign-in leaves behind, and the one that shut the whole
  /// sudo surface before the elevation code existed.
  ///
  /// It takes a THROWAWAY family rather than using family A, and that is not
  /// tidiness: the shared family's member count is load-bearing for other
  /// suites. A third caregiver added here made `auto-approval writes render
  /// params on every notification it makes` fan out to two rows and die on
  /// `.single` — a suite that had nothing to do with this one, failing for a
  /// reason nothing in its own file explains. (`ensureThirdMember` exists for
  /// the tests that WANT that, and shares one.)
  ///
  /// The account is built through the REAL invitation branch of
  /// `handle_new_user`, so the profile is an ordinary member in every respect
  /// except the missing credential. The access token comes from a generated
  /// magic link: a password-less account has no other way in, which is
  /// precisely the point being tested.
  Future<
      ({
        String email,
        String userId,
        String accessToken,
        Member profile,
        SupabaseClient client
      })> createPasswordlessMember(
    ThrowawayFamily family,
    String tag, {
    required String fullName,
  }) async {
    final email = testEmail(tag);
    final token =
        await createInvitation(family.admin, email, roleId('grandmother'));
    final uid = await _admin.createPasswordlessUser(email, {
      'full_name': fullName,
      'invite_token': token,
      'policy_version': PolicyVersions.current,
    });
    _userIds.add(uid);

    final profile = (await _profilesOf(family.admin))
        .firstWhere((p) => p.email?.toLowerCase() == email.toLowerCase());
    await _markOnboarded([profile.id]);

    // The token goes on the client as a HEADER rather than through
    // `auth.setSession`: this account has no password, so there is no sign-in to
    // restore a session from, and PostgREST only ever reads the bearer anyway.
    final accessToken = await _admin.passwordlessAccessToken(email);
    final client = _track(SupabaseClient(
      TestEnv.supabaseUrl,
      TestEnv.anonKey,
      headers: {'Authorization': 'Bearer $accessToken'},
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    ));

    return (
      email: email,
      userId: uid,
      accessToken: accessToken,
      profile: profile,
      client: client,
    );
  }

  /// F-57: registers a family created OUTSIDE [createFamily] (e.g. by
  /// `complete_oauth_onboarding`) for the run's teardown purge.
  void trackFamily(int familyId) => _extraFamilyIds.add(familyId);

  /// F-28: lazily add a THIRD caregiver to family A through the real invitation
  /// flow, shared by every test that needs a multi-caregiver family (one GoTrue
  /// user for the whole run; the purge removes it with the family).
  Member? _thirdProfile;
  SupabaseClient? _thirdClient;

  Future<Member> ensureThirdMember() async {
    final existing = _thirdProfile;
    if (existing != null) return existing;

    final email = testEmail('third');
    final token = await createInvitation(founder, email, roleId('grandmother'));
    _userIds.add(await _admin.createConfirmedUser(email, password, {
      'full_name': 'E2E Grandmother',
      'invite_token': token,
      // S-15: without this the profile is created with consent_policy_version
      // NULL — a legacy profile — and the gate BOUNCES every flow to the
      // acceptance screen once policy.enforce_from has passed. The other
      // creation sites stamp it; this one was missed once, and the miss was
      // invisible while enforce_from was still in the future.
      'policy_version': PolicyVersions.current,
    }));
    final profile = (await _profilesOf(founder))
        .firstWhere((p) => p.email == email);
    await _markOnboarded([profile.id]);
    return _thirdProfile = profile;
  }

  /// The third caregiver's own client — created on first use, so a suite that
  /// only needs the PROFILE never pays for a sign-in.
  Future<SupabaseClient> ensureThirdClient() async {
    await ensureThirdMember();
    return _thirdClient ??= await signIn(testEmail('third'));
  }

  /// S-11: a fresh, isolated 2-member family (admin + member) for the
  /// DESTRUCTIVE tests — leaving a member mutates the family, so it must not
  /// touch the shared [familyId] the rest of the gate uses. Purged (and its
  /// auth users removed) in [dispose].
  Future<ThrowawayFamily> createFamily(String tag) async {
    final adminEmail = testEmail('$tag-adm');
    _userIds.add(await _admin.createConfirmedUser(adminEmail, password, {
      'full_name': 'E2E $tag Adm',
      'role': 'father',
      'family_name': '${TestEnv.e2eFamilyPrefix}$runId-$tag',
      'policy_version': PolicyVersions.current,
    }));
    final adminClient = await signIn(adminEmail);
    final adminProfile = (await _profilesOf(adminClient)).single;
    _extraFamilyIds.add(adminProfile.familyId!);

    final memberEmail = testEmail('$tag-mbr');
    final token =
        await createInvitation(adminClient, memberEmail, roleId('mother'));
    _userIds.add(await _admin.createConfirmedUser(memberEmail, password, {
      'full_name': 'E2E $tag Mbr',
      'invite_token': token,
      'policy_version': PolicyVersions.current,
    }));
    final memberClient = await signIn(memberEmail);
    final memberProfile = (await _profilesOf(adminClient))
        .firstWhere((p) => p.id != adminProfile.id);

    await _markOnboarded([adminProfile.id, memberProfile.id]);

    return ThrowawayFamily(
      admin: adminClient,
      member: memberClient,
      adminProfile: adminProfile,
      memberProfile: memberProfile,
      familyId: adminProfile.familyId!,
    );
  }

  // ── Seeding helpers ──────────────────────────────────────────────────────

  /// S-10: sudo elevations seeded straight into `auth_elevations` with the
  /// service client — simpler than driving the `elevate` Edge Function in every
  /// RPC test (the function itself has its own coverage).
  Future<void> elevate(Member who, {int minutes = 10}) async {
    await service.from('auth_elevations').upsert({
      'user_id': who.userId,
      'elevated_until':
          DateTime.now().toUtc().add(Duration(minutes: minutes)).toIso8601String(),
    });
  }

  Future<void> clearElevation(Member who) async {
    await service.from('auth_elevations').delete().eq('user_id', who.userId!);
  }

  /// T-39 billing seeds use FIXED external ids (`sub_e2e_*`). A CI run CANCELLED
  /// by the concurrency group dies before teardown, and the startup sweep
  /// deliberately spares anything younger than 2 h — so the next run finds the
  /// id already taken (23505). Seeds call this first.
  Future<void> deleteSubscriptionSeed(String externalSubscriptionId) async {
    await service
        .from('subscriptions')
        .delete()
        .eq('external_subscription_id', externalSubscriptionId);
  }

  /// Stamps profiles as "the first-run onboarding already ran".
  ///
  /// Every fixture profile is born from the REAL sign-up flow, so the three
  /// `onboarding_*` columns are NULL — which is exactly the condition that opens
  /// the U-23 tour and the "Primeiros passos" card. For a real user that is the
  /// feature; for a test it is an overlay that swallows every interaction and a
  /// card that pushes the day cells down. The gate does not render anything, but
  /// it SHARES this fixture's shape with the flow gate, and stamping all three
  /// here is what keeps the two saying the same thing about a steady-state app.
  Future<void> _markOnboarded(List<int> profileIds) async {
    final seenAt = DateTime.now().toUtc().toIso8601String();
    for (final id in profileIds) {
      await service.from('profiles').update({
        'onboarding_tour_seen_at': seenAt,
        'onboarding_swap_explained_at': seenAt,
        'onboarding_dismissed_at': seenAt,
      }).eq('id', id);
    }
  }

  // ── Invitations and purge ────────────────────────────────────────────────

  /// `create_invitation` reads `auth.uid()`, so the service role cannot stand in
  /// for the inviter — this always runs as [inviter].
  static Future<String> createInvitation(
    SupabaseClient inviter,
    String email,
    int roleId,
  ) async {
    final result = await inviter.rpc<dynamic>('create_invitation',
        params: {'p_email': email, 'p_role_id': roleId});
    if (result is List && result.isNotEmpty) {
      return (result.first as Map)['token'] as String;
    }
    if (result is Map && result['token'] != null) {
      return result['token'] as String;
    }
    throw StateError('create_invitation returned no token: $result');
  }

  /// Purge via the guarded RPC, then remove the auth users it returns.
  Future<void> purgeFamily(int familyId) async {
    final result = await service
        .rpc<dynamic>('purge_e2e_family', params: {'p_family_id': familyId});
    if (result is List) {
      for (final id in result) {
        if (id is String) {
          try {
            await _admin.deleteUser(id);
          } catch (_) {/* best effort */}
        }
      }
    }
  }

  /// Families older than 2 h carrying the E2E signature — the debris of runs a
  /// CI cancellation killed before teardown. The 2 h floor is deliberate: it is
  /// what stops this sweep from eating a run that is still going.
  Future<void> _sweepOrphanedFamilies() async {
    try {
      final cutoff = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 2))
          .toIso8601String();
      final rows = await service
          .from('families')
          .select('id')
          .like('name', '${TestEnv.e2eFamilyPrefix}%')
          .lt('created_at', cutoff);
      for (final row in rows) {
        // The RPC re-validates the double signature server-side.
        try {
          await purgeFamily(row['id'] as int);
        } catch (_) {/* leave for manual inspection */}
      }
    } catch (_) {/* the sweep must never fail a run */}
  }

  // ── Reads the fixture itself needs ───────────────────────────────────────

  Future<List<Member>> _profilesOf(SupabaseClient client) async {
    final rows = await client.from('profiles').select();
    return [for (final row in rows) Member.fromJson(row)];
  }

  Future<List<Role>> _rolesOf(SupabaseClient client) async {
    final rows = await client.from('roles').select();
    return [for (final row in rows) Role.fromJson(row)];
  }

  SupabaseClient _track(SupabaseClient client) {
    _clients.add(client);
    return client;
  }

  /// The run's credential for every throwaway user — generated fresh per run
  /// from secure randomness, never a literal. It lives only in memory: the users
  /// it belongs to are deleted in [dispose].
  static String _throwawayCredential() {
    const pool = 'abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    final body =
        List.generate(28, (_) => pool[rng.nextInt(pool.length)]).join();
    return 'E2e!$body';
  }

  /// LOWERCASE hex, and that is not cosmetic. The run id goes into every
  /// throwaway address, GoTrue LOWERCASES the e-mail it stores, and several
  /// suites find a profile by comparing that stored address to the one they
  /// asked for. A mixed-case suffix therefore made those lookups miss — as
  /// `Bad state: No element` on a `.single`, which reads like a rule that did
  /// not fire and is really a string that does not match (T-56 PR 7).
  static String _randomHex(int length) {
    final rng = Random.secure();
    return List.generate(length, (_) => rng.nextInt(16).toRadixString(16)).join();
  }
}

/// A family that exists for ONE destructive scenario and dies with the run.
class ThrowawayFamily {
  final SupabaseClient admin;
  final SupabaseClient member;
  final Member adminProfile;
  final Member memberProfile;
  final int familyId;

  const ThrowawayFamily({
    required this.admin,
    required this.member,
    required this.adminProfile,
    required this.memberProfile,
    required this.familyId,
  });
}
