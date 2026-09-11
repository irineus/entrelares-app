import 'package:flutter/foundation.dart';

/// U-28 — who is signed in, for the app bar's account button.
///
/// The shell cannot load this itself: it owns no data source, and the screens
/// that do already fetch the member list for their own reasons. So the screens
/// PUBLISH what they loaded here, and the button on every tab reads it. The
/// same shape as [NotificationBadge] and [AdminMode], which is why it is a
/// service and not a provider package.
///
/// Everything is nullable on purpose: the button must render on the very first
/// frame, before any screen has loaded anything, and a generic person icon is a
/// correct answer to "who is this" while the answer is still arriving.
class AccountIdentity extends ChangeNotifier {
  String? _fullName;
  int? _colorSlot;

  String? get fullName => _fullName;
  int? get colorSlot => _colorSlot;

  /// The letter the avatar wears. `?` while nothing is known — never an empty
  /// circle, which reads as a rendering fault rather than as a pending load.
  String get initial {
    final name = _fullName?.trim() ?? '';
    return name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
  }

  /// Called by whichever screen loaded the signed-in member. It is a no-op when
  /// nothing changed — the calendar and the family screen both publish, and a
  /// notify on every refresh would rebuild four app bars for nothing.
  void adopt({required String? fullName, required int? colorSlot}) {
    if (fullName == _fullName && colorSlot == _colorSlot) return;
    _fullName = fullName;
    _colorSlot = colorSlot;
    notifyListeners();
  }

  /// Sign-out clears it, so the next session never flashes the last user's
  /// initial while its own profile loads.
  void clear() => adopt(fullName: null, colorSlot: null);
}
