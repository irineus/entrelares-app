import 'package:entrelares_core/entrelares_core.dart';

/// F-87 — an auth call that failed, already classified. `main.dart` (the only
/// place allowed to touch the Supabase client, T-88/T-89) reads GoTrue's
/// `code` and HTTP status and rethrows this, so the screens decide the
/// sentence from a closed [AuthFailure] instead of matching English text.
class AuthFailed implements Exception {
  final AuthFailure kind;
  final String? detail;

  const AuthFailed(this.kind, [this.detail]);

  /// What a screen should read from any error: the classified kind when the
  /// adapter classified it, else a best guess from the text.
  static AuthFailure of(Object error) => error is AuthFailed
      ? error.kind
      : classifyAuthFailure(message: error.toString());

  @override
  String toString() => 'AuthFailed($kind${detail == null ? '' : ': $detail'})';
}
