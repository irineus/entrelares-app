import 'offline_cache.dart';

/// Web half: no copy is kept on this channel (see `OfflineCache`).
class _NoOfflineCacheStore implements OfflineCacheStore {
  @override
  Future<String?> read(String account) async => null;

  @override
  Future<void> write(String account, String contents) async {}

  @override
  Future<void> delete(String account) async {}

  @override
  Future<void> deleteAll() async {}
}

/// The store this platform uses.
OfflineCacheStore createOfflineCacheStore() => _NoOfflineCacheStore();
