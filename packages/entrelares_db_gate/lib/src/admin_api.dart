import 'dart:convert';

import 'package:http/http.dart' as http;

import 'test_env.dart';

/// Thin GoTrue Admin API wrapper (service_role) — the Dart twin of the C#
/// suite's `AdminApi`.
///
/// It creates PRE-CONFIRMED users, which is the whole point: the insert into
/// `auth.users` fires the REAL `handle_new_user` trigger (founder onboarding
/// from the metadata, invitee onboarding from `invite_token`) without any test
/// depending on a confirmation e-mail arriving. And it removes them at
/// teardown — `profiles.user_id` has no cascade, so users are deleted AFTER
/// `purge_e2e_family` has removed the public-schema rows.
///
/// Hand-built rather than driven through the SDK's `auth.admin`, for one
/// reason: these requests must control their own HEADER SHAPE (S-16 — see
/// [TestEnv.keyHeaders]), and a key format that has to be sent one way is
/// exactly the kind of thing a convenience wrapper decides for you.
class AdminApi {
  final http.Client _http = http.Client();

  Uri _uri(String path) => Uri.parse('${TestEnv.supabaseUrl}$path');

  Map<String, String> get _headers => {
        ...TestEnv.keyHeaders(TestEnv.serviceRoleKey),
        'Content-Type': 'application/json',
      };

  /// Returns the new user's id.
  ///
  /// There is deliberately no `app_metadata` parameter: GoTrue does not let
  /// the Admin API forge `provider`/`providers` (its own defaults win), which
  /// is exactly why the F-57 deferred branch keys on the ABSENCE of our
  /// user_metadata instead of on the provider — a provider-based rule would be
  /// one this gate can never exercise.
  Future<String> createConfirmedUser(
    String email,
    String password,
    Map<String, dynamic> metadata,
  ) async {
    final response = await _http.post(
      _uri('/auth/v1/admin/users'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'password': password,
        'email_confirm': true,
        'user_metadata': metadata,
      }),
    );
    if (response.statusCode >= 300) {
      throw StateError("Admin create user '$email' failed "
          '(${response.statusCode}): ${response.body}');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  /// S-21: a user with NO password at all — the shape a Google sign-in leaves
  /// behind, reproduced by the only means this gate has.
  ///
  /// The Admin API cannot forge `provider = google` (see the note above), so
  /// the gate cannot make a session that Google issued. It does not need to:
  /// what breaks the sudo gate is the ABSENCE OF A PASSWORD, not the name of
  /// the provider — `elevate`'s password mode verifies a credential through
  /// GoTrue's password grant, and there is nothing to verify either way. This
  /// helper reproduces exactly that condition, honestly and in one line.
  Future<String> createPasswordlessUser(
    String email,
    Map<String, dynamic> metadata,
  ) async {
    final response = await _http.post(
      _uri('/auth/v1/admin/users'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'email_confirm': true,
        'user_metadata': metadata,
      }),
    );
    if (response.statusCode >= 300) {
      throw StateError("Admin create password-less user '$email' failed "
          '(${response.statusCode}): ${response.body}');
    }
    return (jsonDecode(response.body) as Map<String, dynamic>)['id'] as String;
  }

  /// An access token for a user who cannot sign in with a password.
  ///
  /// `generate_link` MINTS the token without sending anything — no mail is
  /// spent and the Send Email Hook is never called — and `/verify` redeems it
  /// for a session, which is the ordinary GoTrue path a magic link takes when
  /// the recipient clicks it. This is the gate's only way to hold a session
  /// that has no password behind it.
  Future<String> passwordlessAccessToken(String email) async {
    final link = await _http.post(
      _uri('/auth/v1/admin/generate_link'),
      headers: _headers,
      body: jsonEncode({'type': 'magiclink', 'email': email}),
    );
    if (link.statusCode >= 300) {
      throw StateError("generate_link for '$email' failed "
          '(${link.statusCode}): ${link.body}');
    }
    final body = jsonDecode(link.body) as Map<String, dynamic>;
    final hashedToken =
        (body['properties'] as Map<String, dynamic>?)?['hashed_token'] ??
            body['hashed_token'];
    if (hashedToken is! String) {
      throw StateError('generate_link returned no hashed_token: ${link.body}');
    }

    final verify = await _http.post(
      _uri('/auth/v1/verify'),
      headers: {
        ...TestEnv.keyHeaders(TestEnv.anonKey),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'type': 'magiclink', 'token_hash': hashedToken}),
    );
    if (verify.statusCode >= 300) {
      throw StateError('magiclink verify failed '
          '(${verify.statusCode}): ${verify.body}');
    }
    final token =
        (jsonDecode(verify.body) as Map<String, dynamic>)['access_token'];
    if (token is! String) {
      throw StateError('verify returned no access_token: ${verify.body}');
    }
    return token;
  }

  /// F-16 tests: changes a user's e-mail as GoTrue itself would after the
  /// confirmation link — exercising the `profiles.email` sync trigger without a
  /// mailbox round-trip.
  Future<void> updateUserEmail(String userId, String newEmail) async {
    final response = await _http.put(
      _uri('/auth/v1/admin/users/$userId'),
      headers: _headers,
      body: jsonEncode({'email': newEmail, 'email_confirm': true}),
    );
    if (response.statusCode >= 300) {
      throw StateError('Admin update e-mail for $userId failed '
          '(${response.statusCode}): ${response.body}');
    }
  }

  /// Idempotent: a user already removed (404) is not an error.
  Future<void> deleteUser(String userId) async {
    final response =
        await _http.delete(_uri('/auth/v1/admin/users/$userId'), headers: _headers);
    if (response.statusCode >= 300 && response.statusCode != 404) {
      throw StateError(
          'Admin delete user $userId failed (${response.statusCode}).');
    }
  }

  void close() => _http.close();
}
