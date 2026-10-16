import 'package:entrelares_core/entrelares_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// F-59 — the dismissals of the *Ativar notificações* strip under the Hoje
/// card, on THIS device. A display preference (the U-12 stance): the question
/// is about this device's push, so another phone of the same reader still asks
/// on its own. The rhythm is U-54's, read by [PushTodayRules].
abstract interface class PushTodayPrefs {
  InstallHintDismissals read();
  Future<void> dismiss(DateTime now);
}

class SharedPushTodayPrefs implements PushTodayPrefs {
  final SharedPreferences _prefs;
  SharedPushTodayPrefs(this._prefs);

  static const _countKey = 'app.pushToday.dismissCount';
  static const _lastKey = 'app.pushToday.lastDismissedMs';

  @override
  InstallHintDismissals read() {
    final lastMs = _prefs.getInt(_lastKey);
    return InstallHintDismissals(
      count: _prefs.getInt(_countKey) ?? 0,
      last: lastMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastMs),
    );
  }

  /// Best-effort, like every display preference: a failed write costs the
  /// reader one more sight of the strip, never the calendar.
  @override
  Future<void> dismiss(DateTime now) async {
    final next = read().next(now);
    try {
      await _prefs.setInt(_countKey, next.count);
      await _prefs.setInt(_lastKey, next.last!.millisecondsSinceEpoch);
    } catch (_) {}
  }
}
