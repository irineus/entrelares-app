/// T-18 — where the device's copy of the calendar is written, one per
/// platform.
///
/// **Not `shared_preferences`, and the reason is Android Auto Backup.** The
/// manifest does not opt out of backup, so everything in the preferences file
/// travels to the user's Google account and comes back on the next phone — a
/// family's calendar leaving the device, and a copy that outlives the sign-out
/// that was supposed to wipe it. The app's CACHE directory is the one place
/// Auto Backup never copies, and the operating system may empty it when space
/// runs out — which is exactly what a cache is allowed to suffer.
///
/// The web has no such directory and no copy at all (see `OfflineCache`); its
/// half stores nothing.
///
/// The choice is made at COMPILE time by the conditional export below, so
/// neither implementation's imports ever reach the other platform — the same
/// split `network_client.dart` uses.
library;

export 'offline_cache_store_io.dart'
    if (dart.library.js_interop) 'offline_cache_store_web.dart';
