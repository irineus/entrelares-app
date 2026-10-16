import 'package:web/web.dart' as web;

const _key = 'entrelares.pendingInvite';

/// Web half: `sessionStorage` — this tab, surviving a reload and a sign-out,
/// gone with the tab. Best effort: blocked storage means memory only.
Future<String?> readInviteNote() async {
  try {
    final token = web.window.sessionStorage.getItem(_key)?.trim();
    return token == null || token.isEmpty ? null : token;
  } catch (_) {
    return null;
  }
}

Future<void> writeInviteNote(String token) async {
  try {
    web.window.sessionStorage.setItem(_key, token);
  } catch (_) {/* best effort */}
}

Future<void> clearInviteNote() async {
  try {
    web.window.sessionStorage.removeItem(_key);
  } catch (_) {/* best effort */}
}
