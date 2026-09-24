/// U-13 — the single entry point every screen uses to read text:
/// `l[K.loginSubmit]`, or `l.format(K.loginLockout, [seconds])` when the
/// string carries a placeholder. Ported from `entrelares-app`
/// `Entrelares/Localization/LocalizationService.cs`.
///
/// **Why the language never changes mid-render.** The instance is created at
/// boot with the resolved language and a switch rebuilds the app from the
/// root with a NEW instance (the Flutter analog of the web's `forceLoad`) —
/// no widget subscribes to a change event, so no screen can be caught
/// half-translated.
///
/// **Formatting stays invariant.** `format` substitutes positional `{n}`
/// slots textually — the UI language and the number/date format are separate
/// concerns, and the transport format (`CareSchedule.isoDate`) never routes
/// through here. Translating the UI must never change what goes on the wire.
library;

import 'app_language.dart';
import 'k_app.dart';
import 'strings_en.dart';
import 'strings_pt_br.dart';

class Localization {
  /// The language this session renders in.
  final AppLanguage current;

  final Map<String, String> _strings;
  final Map<String, String> _appStrings;

  Localization(this.current)
      : _strings = current == AppLanguage.en
            ? StringsEn.values
            : StringsPtBr.values,
        _appStrings = current == AppLanguage.en
            ? StringsAppEn.values
            : StringsAppPtBr.values;

  /// True when the user (or their device) put this session in English.
  bool get isEnglish => current == AppLanguage.en;

  /// The text for a key in the current language.
  String operator [](String key) => _lookup(key);

  /// The text for a key, with positional `{n}` arguments substituted.
  /// `string.Format` semantics minus the parts the catalogs never use: the
  /// placeholder SET is a contract between languages, the ORDER is not —
  /// which is exactly why they are numbered rather than concatenated at the
  /// call site.
  String format(String key, List<Object?> args) =>
      _substitute(_lookup(key), args);

  /// U-57 — an ordinal in the session's language ("3º" / "3rd"), for a
  /// sentence whose count comes from `app_settings` and so cannot be typed
  /// into the catalog.
  String ordinal(int n) {
    if (!isEnglish) return '$nº';
    final mod100 = n % 100;
    final suffix = mod100 >= 11 && mod100 <= 13
        ? 'th'
        : switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
    return '$n$suffix';
  }

  /// Picks between two already-localized values — for the handful of texts
  /// that are NOT catalog entries (the legal declarations).
  String pick(String ptBr, String en) => isEnglish ? en : ptBr;

  /// Decides whether a signed-in user's profile language should take over
  /// this device. Pure, so the loop-safety argument is testable without a
  /// device: adoption is only correct as a ONE-TIME event, and it is one-time
  /// only because the caller persists the result — the next boot resolves the
  /// adopted code from storage and this returns false.
  static bool shouldAdopt(
    String? profileLanguage,
    AppLanguage current,
    String? storedOverride,
  ) {
    final fromProfile = AppLanguage.tryParse(profileLanguage);
    if (fromProfile == null || fromProfile == current) return false;

    // An explicit local pick outranks the profile (the item's precedence
    // rule); only an untouched device follows the server.
    return storedOverride == null || storedOverride.trim().isEmpty;
  }

  /// U-13 — whether the profile's RECORDED language needs updating to match
  /// what this session actually renders in. `profiles.language_detected` is
  /// what makes an e-mail arrive in the same language as the screen when the
  /// user never touched the picker. Pure and trivially false when they agree,
  /// because this runs on every session boot.
  static bool shouldRecordDetected(String? profileDetected, AppLanguage current) =>
      AppLanguage.tryParse(profileDetected) != current;

  String _lookup(String key) {
    final own = _strings[key] ?? _appStrings[key];
    if (own != null) return own;
    // Belt and braces: the parity test makes this unreachable, but if a key
    // ever slips through, PT-BR text beats showing the raw key to a user.
    return StringsPtBr.values[key] ?? StringsAppPtBr.values[key] ?? key;
  }

  static final _placeholder = RegExp(r'\{(\d+)\}');

  static String _substitute(String template, List<Object?> args) =>
      template.replaceAllMapped(_placeholder, (m) {
        final index = int.parse(m.group(1)!);
        if (index >= args.length) return m.group(0)!;
        return args[index]?.toString() ?? '';
      });
}
