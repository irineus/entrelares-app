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
  Future<void> write(String account, String contents) async {
    final file = await _file(account);
    await file.parent.create(recursive: true);
    // Written aside and renamed over: a copy cut in half by a killed process
    // must never be the one the next offline boot reads.
    final partial = File('${file.path}.partial');
    await partial.writeAsString(contents, encoding: utf8, flush: true);
    await partial.rename(file.path);
  }

  @override
  Future<void> delete(String account) async {
    final file = await _file(account);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<void> deleteAll() async {
    final dir = await _dir();
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}

/// The store this platform uses.
OfflineCacheStore createOfflineCacheStore() => FileOfflineCacheStore();
