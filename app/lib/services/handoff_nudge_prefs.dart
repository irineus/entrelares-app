import 'package:shared_preferences/shared_preferences.dart';

/// U-55 — whether the "Definir horário" strip was dismissed, per family, on
/// THIS device. A display preference (the U-12 stance): it never becomes
/// family data, and another admin, or the same admin on another phone, still
/// sees the offer until they answer it themselves.
abstract interface class HandoffNudgePrefs {
  bool isDismissed(int familyId);
  Future<void> dismiss(int familyId);
}

class SharedHandoffNudgePrefs implements HandoffNudgePrefs {
  final SharedPreferences _prefs;
  SharedHandoffNudgePrefs(this._prefs);

  static String _key(int familyId) => 'app.handoffNudge.dismissed.$familyId';

  @override
  bool isDismissed(int familyId) => _prefs.getBool(_key(familyId)) ?? false;

  /// Best-effort, like every display preference: a failed write costs the
  /// reader one more sight of the strip, never the calendar.
  @override
  Future<void> dismiss(int familyId) async {
    try {
      await _prefs.setBool(_key(familyId), true);
    } catch (_) {}
  }
}
