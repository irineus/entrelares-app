// U-28 — what the Família and Perfil pass changed, pinned where it matters:
// the two danger zones, the placeholder defect, and the sections that had come
// loose from their cards.
import 'package:entrelares_app/screens/profile_screen.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;
import 'family_page_test.dart' as family;

final _l = Localization(AppLanguage.ptBr);

Future<void> _pumpProfile(WidgetTester tester, FakeCustodyDataSource ds,
    {int? profileId}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(
      theme: AppTheme.light,
      home: ProfileScreen(
        dataSource: ds,
        sudo: SudoService(ds),
        profileId: profileId,
        onReopenOnboarding: ({required bool replayTour}) async {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the current e-mail no longer prints its own placeholder',
      (tester) async {
    await _pumpProfile(tester, family.source());

    // The key is a format string ("E-mail atual: {0}") and was being
    // interpolated, so the screen read "E-mail atual: {0} ana@exemplo.com".
    expect(find.textContaining('{0}'), findsNothing);
    expect(
        find.text(_l.format(K.profCurrentEmail, ['ana@example.com'])),
        findsOneWidget);
  });

  testWidgets('leaving the family is a danger zone, not a link',
      (tester) async {
    await _pumpProfile(tester, family.source());

    expect(find.byType(AppDangerZone), findsOneWidget);
    final zone = tester.widget<AppDangerZone>(find.byType(AppDangerZone));
    expect(zone.notices, isNotEmpty,
        reason: 'the reader declares they understand these — they belong '
            'inside the frame, not loose above it');
  });

  testWidgets('every settings section sits in its own card', (tester) async {
    await _pumpProfile(tester, family.source());

    // Dados, E-mail, Senha, Idioma, Meus dados (LGPD), Primeiros passos.
    expect(find.byType(AppCard), findsNWidgets(6));
    for (final title in [
      K.profSectionData,
      K.profSectionEmail,
      K.profSectionPassword,
      K.languageLabel,
      K.profSectionLgpd,
    ]) {
      expect(find.text(_l[title]), findsOneWidget);
    }
  });

  testWidgets('the language setting is back, with the sentence that explains it',
      (tester) async {
    await _pumpProfile(tester, family.source());

    expect(find.text(_l[K.languageHint]), findsOneWidget,
        reason: 'the only place the app says the choice follows the reader '
            'into their e-mail');
    expect(find.byType(AppSegmented<AppLanguage>), findsOneWidget);
  });

  testWidgets('the version is on the page a tester is asked to read',
      (tester) async {
    await _pumpProfile(tester, family.source());
    expect(find.textContaining('Entrelares v'), findsOneWidget);
  });
}
