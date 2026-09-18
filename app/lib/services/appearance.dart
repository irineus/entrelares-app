import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// U-12 — the reader's theme choice, held for the life of the process.
///
/// A [ValueNotifier] for the same reason [ConnectivityStatus] is one: the
/// control that changes it lives deep inside a route go_router caches, and the
/// widget that has to react is `MaterialApp` at the very root. Only a
/// listenable crosses that distance.
///
/// The value is resolved BEFORE `runApp` (the app must not paint one theme and
/// then blink into the other), and every change is written back best-effort:
/// a storage that refuses the write still gives this session the theme it was
/// asked for, and the next boot falls back to the device — the same posture
/// the language switch takes (U-13). It is a display preference and never
/// travels to the database: `profiles.language` exists because the server
/// writes e-mails, and no server-side sender has a theme to choose.
class Appearance extends ValueNotifier<ThemePreference> {
  /// Where the choice is written. Null in a scene that has no storage — the
  /// value still moves, it just does not outlive the process.
  final SharedPreferences? prefs;

  Appearance({this.prefs, ThemePreference? initial})
      : super(initial ?? ThemePreference.defaultPreference);

  /// Reads the stored choice, or the default when there is none — what `main`
  /// calls with the `SharedPreferences` it already opened for the language.
  factory Appearance.fromPrefs(SharedPreferences prefs) => Appearance(
        prefs: prefs,
        initial:
            ThemePreference.resolve(prefs.getString(ThemePreference.storageKey)),
      );

  /// The picker's path: the value first (the app repaints from it), the
  /// storage after and best-effort.
  Future<void> choose(ThemePreference preference) async {
    if (preference == value) return;
    value = preference;
    try {
      await prefs?.setString(ThemePreference.storageKey, preference.code);
    } catch (_) {
      // Storage refused: this session still wears the chosen theme; the next
      // boot resolves to the device again.
    }
  }

  /// What `MaterialApp.themeMode` takes. The only place the pure rule meets
  /// Flutter's own enum — U-27 wrote both themes, this only says which.
  ThemeMode get themeMode => switch (value) {
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
        ThemePreference.system => ThemeMode.system,
      };
}
