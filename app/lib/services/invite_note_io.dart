import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Native half: one small file under the app's cache directory — out of the
/// Auto Backup that copies `shared_preferences` (T-18). Best effort: a failure
/// only means the invitation lives in memory, as before.
Future<File> _file() async =>
    File('${(await getTemporaryDirectory()).path}/pending_invite/token');

Future<String?> readInviteNote() async {
  try {
    final file = await _file();
    if (!await file.exists()) return null;
    final token = (await file.readAsString()).trim();
    return token.isEmpty ? null : token;
  } catch (_) {
    return null;
  }
}

Future<void> writeInviteNote(String token) async {
  try {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(token, flush: true);
  } catch (_) {/* best effort */}
}

Future<void> clearInviteNote() async {
  try {
    final file = await _file();
    if (await file.exists()) await file.delete();
  } catch (_) {/* best effort */}
}
