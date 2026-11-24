import 'package:shared_preferences/shared_preferences.dart';

/// T-109 — whether THIS install already retired the FCM registration token an
/// older build of the app stored on the server.
///
/// Up to firebase_messaging 16 the app registered a registration TOKEN; since
/// T-109 it registers a Firebase Installation ID. Nothing on the server ties
/// the two rows of one phone together, so without this step an updated device
/// would keep its old token row and receive every push twice. [PushService]
/// reads the old token ONCE, deletes its row and invalidates it at the
/// transport — once, because Firebase warns against running the token API and
/// the installation API side by side.
///
/// A device-local flag, like every display preference (the U-12 stance): it is
/// about this install's transport, never family data. Restored by Android Auto
/// Backup onto a new phone it only skips a step that phone has nothing for.
abstract interface class PushMigrationPrefs {
  bool get legacyTokenRetired;
  Future<void> markLegacyTokenRetired();
}

class SharedPushMigrationPrefs implements PushMigrationPrefs {
  final SharedPreferences _prefs;
  SharedPushMigrationPrefs(this._prefs);

  static const _key = 'app.push.legacyTokenRetired';

  @override
  bool get legacyTokenRetired => _prefs.getBool(_key) ?? false;

  /// Best-effort: a failed write repeats the step on the next session, which
  /// deletes a row that is already gone — harmless.
  @override
  Future<void> markLegacyTokenRetired() async {
    try {
      await _prefs.setBool(_key, true);
    } catch (_) {}
  }
}
