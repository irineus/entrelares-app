import 'package:flutter/foundation.dart';

/// Session-scoped state for the explicit "admin mode" (F-14) — mirror of the
/// web's `AdminModeService`. Admin actions are deliberately separated from the
/// normal parental flow: an admin must switch the mode on (persistent banner
/// shown by the shell) before the UI relaxes the day-protection guards. This
/// is a UI convenience only — the real enforcement (and the admin bypass)
/// lives in the database triggers (V008/F-40).
class AdminMode extends ChangeNotifier {
  bool _active = false;

  bool get isActive => _active;

  void toggle() {
    _active = !_active;
    notifyListeners();
  }

  void deactivate() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }
}
