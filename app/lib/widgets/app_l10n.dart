import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'ui/ui.dart';

/// U-13 — hands every screen the session's [Localization] and the switcher.
///
/// The language is FIXED for the lifetime of the subtree: a switch rebuilds
/// the app from the root with a new [Localization] (the Flutter analog of the
/// web's `forceLoad`), so no widget subscribes to a change event and no
/// screen can be caught half-translated. `updateShouldNotify` returning true
/// on instance change is what makes the root rebuild reach everyone.
class AppL10n extends InheritedWidget {
  final Localization l;

  /// Persists the choice locally, best-effort to the profile when signed in,
  /// and rebuilds the app in the new language.
  final Future<void> Function(AppLanguage language) setLanguage;

  const AppL10n({
    super.key,
    required this.l,
    required this.setLanguage,
    required super.child,
  });

  static AppL10n of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppL10n>()!;

  @override
  bool updateShouldNotify(AppL10n oldWidget) => l != oldWidget.l;
}

/// The compact two-pill picker the auth screens show — an anonymous visitor's
/// pick persists locally only (there is no profile row to write yet).
class LanguagePickerRow extends StatelessWidget {
  const LanguagePickerRow({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppL10n.of(context);
    final l = app.l;
    // U-28: a segmented control, not two text buttons. The pair read as two
    // loose links with one of them mysteriously dead (the current language was
    // a `TextButton` with `onPressed: null`) — nothing said they were ONE
    // choice with a state. The segmented button says both at once.
    return Center(
      child: AppSegmented<AppLanguage>(
        semantics: l[K.languageAriaLabel],
        selected: l.current,
        onChanged: app.setLanguage,
        options: [
          (value: AppLanguage.ptBr, label: l[K.languagePtBr]),
          (value: AppLanguage.en, label: l[K.languageEn]),
        ],
      ),
    );
  }
}
