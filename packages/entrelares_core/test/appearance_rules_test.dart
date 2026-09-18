// U-12 — the theme preference, read the way a boot reads it.
//
// Everything this rule has to get right happens before a widget exists: a
// stored code parsed into one of three states, and anything unreadable
// answering "follow the device" instead of throwing at the reader.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  group('codes', () {
    test('every state round-trips through its stored code', () {
      for (final preference in ThemePreference.values) {
        expect(ThemePreference.tryParse(preference.code), preference,
            reason: preference.name);
      }
    });

    test('the codes are the ones already on devices', () {
      // A storage contract: renaming one of these resets the choice of every
      // reader who already made it, silently.
      expect(ThemePreference.light.code, 'light');
      expect(ThemePreference.dark.code, 'dark');
      expect(ThemePreference.system.code, 'system');
      expect(ThemePreference.storageKey, 'app-theme');
    });
  });

  group('tryParse', () {
    test('absent or blank is null, not a state', () {
      // "never chose" and "chose to follow the device" paint the same screen
      // and are different facts — only the caller can tell them apart, and
      // only if this answers null.
      expect(ThemePreference.tryParse(null), isNull);
      expect(ThemePreference.tryParse(''), isNull);
      expect(ThemePreference.tryParse('   '), isNull);
    });

    test('surrounding whitespace and case are tolerated', () {
      expect(ThemePreference.tryParse(' Dark '), ThemePreference.dark);
      expect(ThemePreference.tryParse('SYSTEM'), ThemePreference.system);
    });

    test('a code this version does not know is null', () {
      // A device that once ran a build with a fourth state, or a hand-edited
      // localStorage: the app falls back rather than carrying a state it
      // cannot render.
      expect(ThemePreference.tryParse('sepia'), isNull);
      expect(ThemePreference.tryParse('ThemeMode.dark'), isNull);
    });
  });

  group('resolve', () {
    test('a stored choice wins', () {
      expect(ThemePreference.resolve('dark'), ThemePreference.dark);
      expect(ThemePreference.resolve('light'), ThemePreference.light);
    });

    test('nothing stored follows the device', () {
      expect(ThemePreference.resolve(null), ThemePreference.system);
      expect(ThemePreference.resolve('sepia'), ThemePreference.system);
      expect(ThemePreference.defaultPreference, ThemePreference.system);
    });
  });
}
