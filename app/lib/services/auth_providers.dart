import 'dart:convert';

import 'package:http/http.dart' as http;

import '../env.dart';

/// F-57 — whether the Google button may exist, asked of the one source that
/// cannot be wrong: GoTrue's own public settings endpoint
/// (`/auth/v1/settings`), which lists the external providers the PROJECT has
/// enabled.
///
/// This IS the fail-closed switch the rollout decision asked for, and it is
/// better than a flag of our own: an `app_settings` row could say "on" while
/// the provider config is still missing — a button that opens a broken
/// consent screen — and the login screen is ANONYMOUS, which in this 100%-RLS
/// app reads no table anyway. Here the owner flips exactly one thing (the
/// provider, in each project's console) and the button follows; the two can
/// never disagree. Per environment for free: dev and prod each answer for
/// themselves.
///
/// Fail-closed: any error, timeout or unexpected shape answers `false` — the
/// password form is always there.
class AuthProviders {
  /// One answer per process: the config changes at console cadence, not
  /// session cadence, and the login screen must not re-ask on every rebuild.
  static Future<bool>? _google;

  static Future<bool> googleEnabled({http.Client? client}) =>
      _google ??= _fetchGoogleEnabled(client);

  /// Test seam — widget tests inject the answer instead of the network.
  static void debugOverride(Future<bool>? value) => _google = value;

  static Future<bool> _fetchGoogleEnabled(http.Client? client) async {
    final ownClient = client == null;
    final c = client ?? http.Client();
    try {
      // `apikey` alone is the right shape for BOTH key formats here (S-16):
      // the settings endpoint is GoTrue's own and public behind the gateway —
      // no PostgREST role derivation is involved, so `Authorization` adds
      // nothing and a new-format key must not ride it anyway.
      final response = await c
          .get(
            Uri.parse('${Env.current.supabaseUrl}/auth/v1/settings'),
            headers: {'apikey': Env.current.supabaseKey},
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return false;
      final body = jsonDecode(response.body);
      final external_ = body is Map<String, dynamic> ? body['external'] : null;
      return external_ is Map<String, dynamic> && external_['google'] == true;
    } catch (_) {
      return false; // fail-closed: no button, password form intact
    } finally {
      if (ownClient) c.close();
    }
  }
}
