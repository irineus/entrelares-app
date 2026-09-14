import 'package:entrelares_core/entrelares_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What the boot learned about a session restored from the device.
enum RestoredSession {
  /// The refresh went through: route to the app.
  alive,

  /// T-18: the refresh could not reach the server. The session is KEPT and the
  /// app opens offline — nobody learned anything about the token.
  offline,

  /// No session, or the server refused its refresh token: route to login
  /// (a refused session has been locally cleared).
  signedOut,
}

/// Pilot lessons 1.1–1.3 (F-58 QA), the most expensive ones:
/// a RESTORED session is not a LIVE session — the refresh token may be dead on
/// the server, and every call then fails 42501 as `anon`. Blazor gets a fresh
/// DI scope via `forceLoad`; Flutter has no equivalent, so the gate is
/// explicit and runs BEFORE routing.
class SessionGate {
  final GoTrueClient _auth;

  SessionGate(this._auth);

  /// Validates the restored session with a real refresh.
  ///
  /// **A refresh that could not reach the server is not a verdict (T-18).**
  /// Until 14/09/2026 every failure here signed the reader out, so opening the
  /// app with no signal — at the school door, in the lift — landed on the login
  /// form, and the plan the reader came to look at sat behind a password that
  /// needs the network too. Gotrue itself draws the line this now follows: it
  /// clears the session only on a REFUSAL, and reports a transport failure as
  /// `AuthRetryableFetchException` while keeping the session. So only a refusal
  /// signs out here; a transport failure opens the app offline, and the
  /// refresh gotrue keeps retrying settles it later — a dead token still
  /// arrives as `signedOut` on the auth stream the app already obeys.
  ///
  /// [networkLost] completes at the first transport failure the app sees. The
  /// refresh is raced against it because gotrue retries for about ten seconds
  /// before throwing, and the splash would otherwise hold the reader for all
  /// of them.
  Future<RestoredSession> validateRestoredSession(
      {Future<void>? networkLost}) async {
    if (_auth.currentSession == null) return RestoredSession.signedOut;
    final refresh = _auth.refreshSession().then<RestoredSession>(
      (_) => RestoredSession.alive,
      onError: (Object e) async {
        if (isNetworkFailure(e.toString())) return RestoredSession.offline;
        await signOutSafely();
        return RestoredSession.signedOut;
      },
    );
    if (networkLost == null) return refresh;
    return Future.any([
      refresh,
      networkLost.then((_) => RestoredSession.offline),
    ]);
  }

  /// Lesson 1.3: `signOut()` with a dead token THROWS and the logout "does
  /// nothing". Fall back to a local sign-out; the caller navigates ALWAYS.
  Future<void> signOutSafely() async {
    try {
      await _auth.signOut();
    } catch (_) {
      try {
        await _auth.signOut(scope: SignOutScope.local);
      } catch (_) {
        // Even the local sign-out failing must not block navigation.
      }
    }
  }
}
