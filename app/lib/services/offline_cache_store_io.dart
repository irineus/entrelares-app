import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'offline_cache.dart';

/// Native half: one JSON file per account under the app's cache directory
/// (`getTemporaryDirectory()` is `Context.getCacheDir()` on Android).
class FileOfflineCacheStore implements OfflineCacheStore {
  final Future<Directory> Function() _root;

  FileOfflineCacheStore({Future<Directory> Function()? root})
      : _root = root ?? getTemporaryDirectory;

  Future<Directory> _dir() async =>
      Directory('${(await _root()).path}/offline_calendar');

  /// The account id becomes a file name, so anything but the characters a
  /// UUID uses is refused rather than escaped.
  Future<File> _file(String account) async {
    if (!RegExp(r'^[A-Za-z0-9-]+$').hasMatch(account)) {
      throw ArgumentError.value(account, 'account');
    }
    return File('${(await _dir()).path}/$account.json');
  }

  @override
  Future<String?> read(String account) async {
    final file = await _file(account);
    return await file.exists() ? file.readAsString(encoding: utf8) : null;
  }

  @override
  Future<void> write(String account, String contents) => _inTurn(() async {
        final file = await _file(account);
        await file.parent.create(recursive: true);
        // Written aside and renamed over: a copy cut in half by a killed
        // process must never be the one the next offline boot reads.
        final partial = File('${file.path}.partial');
        await partial.writeAsString(contents, encoding: utf8, flush: true);
        await partial.rename(file.path);
      });

  @override
  Future<void> delete(String account) => _inTurn(() async {
        final file = await _file(account);
        if (await file.exists()) await file.delete();
      });

  @override
  Future<void> deleteAll() => _inTurn(() async {
        final dir = await _dir();
        if (await dir.exists()) await dir.delete(recursive: true);
      });

  /// Every change to the directory waits for the previous one to finish.
  ///
  /// T-77 (16/09/2026): the calendar saves unawaited on each load of the
  /// current month, and two loads close together put two writes on the same
  /// `.partial` — the first rename took the file and the second threw
  /// `PathNotFoundException`. Worse, a sign-out `deleteAll` that landed between
  /// a write and its rename let the rename put the family's plan back on the
  /// device after the wipe. In turn, the last save wins and a wipe really is
  /// the last word. Process-wide on purpose: the directory is, too.
  static Future<void> _tail = Future.value();

  static Future<void> _inTurn(Future<void> Function() change) {
    final done = _tail.then((_) => change());
    _tail = done.catchError((Object _) {});
    return done;
  }
}

/// The store this platform uses.
OfflineCacheStore createOfflineCacheStore() => FileOfflineCacheStore();
