import 'package:supabase_flutter/supabase_flutter.dart';

/// Pilot lessons 1.1–1.3 (F-58 QA), the most expensive ones:
/// a RESTORED session is not a LIVE session — the refresh token may be dead on
/// the server, and every call then fails 42501 as `anon`. Blazor gets a fresh
/// DI scope via `forceLoad`; Flutter has no equivalent, so the gate is
/// explicit and runs BEFORE routing.
class SessionGate {
  final GoTrueClient _auth;

  SessionGate(this._auth);

  /// True → route to the app; false → route to login (any restored-but-dead
  /// session has been locally cleared).
  Future<bool> validateRestoredSession() async {
    if (_auth.currentSession == null) return false;
    try {
      await _auth.refreshSession();
      return true;
    } catch (_) {
      await signOutSafely();
      return false;
    }
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
