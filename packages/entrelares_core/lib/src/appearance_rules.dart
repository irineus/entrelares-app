/// U-12 — which of the two themes the app wears, as the reader asked.
///
/// U-27 (20/08/2026) wrote both themes from the token file and the app has
/// followed the device ever since (`ThemeMode.system`). What was missing is the
/// per-app override: someone reading in bed on a device set to light, or the
/// reverse. That is a DISPLAY preference and nothing else — it is persisted
/// locally, per device, and never reaches the database: `profiles.language`
/// exists because the SERVER writes e-mails in the reader's language (U-13),
/// and no server-side sender has a theme to pick.
///
/// The rule lives here, in pure Dart, for the same reason the language's does:
/// it is read BEFORE the first frame, before any session exists, and a stored
/// value that cannot be parsed must resolve to something sane without a widget
/// tree to ask.
library;

/// The three states the reader chooses between.
///
/// A closed enum and not Flutter's `ThemeMode` on purpose — nothing under
/// `packages/` may import Flutter (the gate runs under plain `dart test`), and
/// the mapping to `ThemeMode` is one line in the app package.
enum ThemePreference {
  /// Always the light theme, whatever the device says.
  light,

  /// Always the dark theme, whatever the device says.
  dark,

  /// Follow the device — the behaviour every build has had since U-27, and
  /// what an app that was never asked still does.
  system;

  /// The persisted code. A storage CONTRACT, like `AppLanguage.code`: these
  /// three strings are what sits in `shared_preferences` on devices already in
  /// the field, so renaming one silently resets everybody's choice.
  String get code => switch (this) {
        ThemePreference.light => 'light',
        ThemePreference.dark => 'dark',
        ThemePreference.system => 'system',
      };

  /// Local-storage key holding the choice. Sits beside
  /// `LanguageResolver.storageKey` (`app-language`) and reads the same way.
  static const String storageKey = 'app-theme';

  /// What an app nobody asked wears: the device's own setting.
  static const ThemePreference defaultPreference = ThemePreference.system;

  /// Parses a stored code. Null/blank/unknown yields `null`, so a caller can
  /// tell "never chosen" from "chose to follow the system" — the two are the
  /// same PICTURE and different facts, and only the second survives the device
  /// changing its mind about what the app should look like.
  static ThemePreference? tryParse(String? code) {
    final trimmed = code?.trim().toLowerCase();
    if (trimmed == null || trimmed.isEmpty) return null;
    for (final preference in ThemePreference.values) {
      if (preference.code == trimmed) return preference;
    }
    return null;
  }

  /// The preference this boot starts on: the stored choice, or the default.
  ///
  /// Unlike the language, there is exactly ONE source — no profile column and
  /// no device tag to fall back through, because "follow the device" is itself
  /// one of the three answers rather than a separate layer.
  static ThemePreference resolve(String? storedChoice) =>
      tryParse(storedChoice) ?? defaultPreference;
}
