import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Native delivery: the file goes to the app's own cache directory (never
/// external storage — no extra permission, and the OS reclaims it) and then to
/// the system share sheet, so it can land in Drive, an e-mail or a chat
/// instead of a downloads folder. This is the lote-4 native improvement, and
/// it stays exactly as it was.
Future<void> deliverTextFile(
  String fileName,
  String contents, {
  required String mimeType,
}) async {
  final directory = await getTemporaryDirectory();
  final file = File('${directory.path}/$fileName');
  await file.writeAsString(contents, encoding: utf8);
  await Share.shareXFiles([XFile(file.path, mimeType: mimeType)]);
}
