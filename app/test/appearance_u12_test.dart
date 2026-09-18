// U-12 — the theme the reader chose, from the tap to the next boot.
//
// U-27 wrote both themes and the app has followed the device ever since; what
// this item adds is the override, and the two things that can go wrong with an
// override are that the app does not repaint and that the choice does not
// survive the process. Both are asserted here against the real widgets: the
// picker on the profile page, and a root wired exactly as `main` wires it.
import 'package:entrelares_app/screens/profile_screen.dart';
import 'package:entrelares_app/services/appearance.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_test.dart' as prof;

final pt = Localization(AppLanguage.ptBr);
final en = Localization(AppLanguage.en);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> prefsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    return SharedPreferences.getInstance();
  }

  /// The profile page, pumped the way its own suite pumps it, plus the
  /// controller the production routes hand it.
  Future<void> pumpProfile(
    WidgetTester tester, {
    required Appearance? appearance,
    AppLanguage language = AppLanguage.ptBr,
  }) async {
    final ds = prof.source();
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(AppL10n(
      l: Localization(language),
      setLanguage: (_) async {},
      child: MaterialApp(
        home: ProfileScreen(
          dataSource: ds,
          sudo: SudoService(ds),
          deliverExport: (_, _) async {},
          appearance: appearance,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  group('the preference reaches storage', () {
    testWidgets('choosing dark persists it under the storage key',
        (tester) async {
      final prefs = await prefsWith({});
      final appearance = Appearance(prefs: prefs);
      await pumpProfile(tester, appearance: appearance);

      expect(find.text(pt[KApp.appearanceLabel]), findsOneWidget,
          reason: 'the Aparência card is where a reader looks for a setting');
      await tester.tap(find.text(pt[KApp.appearanceDark]));
      await tester.pumpAndSettle();

      expect(appearance.value, ThemePreference.dark);
      expect(prefs.getString(ThemePreference.storageKey), 'dark',
          reason: 'the next boot reads this, and nothing else');
    });

    testWidgets('going back to Sistema is a CHOICE, and is stored as one',
        (tester) async {
      // "Never chose" and "chose to follow the device" paint the same screen.
      // Only the stored code tells them apart, and the difference shows the
      // day someone goes back: the value has to be written, not cleared.
      final prefs = await prefsWith({ThemePreference.storageKey: 'dark'});
      final appearance = Appearance.fromPrefs(prefs);
      await pumpProfile(tester, appearance: appearance);

      await tester.tap(find.text(pt[KApp.appearanceSystem]));
      await tester.pumpAndSettle();

      expect(appearance.value, ThemePreference.system);
      expect(prefs.getString(ThemePreference.storageKey), 'system');
    });

    testWidgets('a storage that never answered still shows the device default',
        (tester) async {
      // No prefs at all: the control renders on "Sistema" and taps still work,
      // in memory. A refused write must never cost the reader the theme.
      final appearance = Appearance();
      await pumpProfile(tester, appearance: appearance);

      await tester.tap(find.text(pt[KApp.appearanceLight]));
      await tester.pumpAndSettle();
      expect(appearance.value, ThemePreference.light);
    });
  });

  group('the preference survives the process', () {
    test('a stored code is what the next boot starts on', () async {
      final prefs = await prefsWith({ThemePreference.storageKey: 'light'});
      expect(Appearance.fromPrefs(prefs).value, ThemePreference.light);
      expect(Appearance.fromPrefs(prefs).themeMode, ThemeMode.light);
    });

    test('nothing stored — or something unreadable — follows the device',
        () async {
      expect(Appearance.fromPrefs(await prefsWith({})).value,
          ThemePreference.system);
      final broken =
          await prefsWith({ThemePreference.storageKey: 'ThemeMode.dark'});
      expect(Appearance.fromPrefs(broken).value, ThemePreference.system);
    });

    test('every preference maps to the ThemeMode MaterialApp takes', () {
      expect(Appearance(initial: ThemePreference.light).themeMode,
          ThemeMode.light);
      expect(
          Appearance(initial: ThemePreference.dark).themeMode, ThemeMode.dark);
      expect(Appearance(initial: ThemePreference.system).themeMode,
          ThemeMode.system);
    });
  });

  testWidgets('the app repaints in the chosen theme, device set to light',
      (tester) async {
    // The property the item is FOR: a device on light, a reader who wants
    // dark. The root is wired as `main` wires it — themeMode off the
    // controller, a listener that rebuilds — so this measures the app, not a
    // mock of it.
    final appearance = Appearance(prefs: await prefsWith({}));
    late BuildContext inside;
    await tester.pumpWidget(
      MediaQuery(
        // The device's own setting, which "Sistema" would follow.
        data: const MediaQueryData(platformBrightness: Brightness.light),
        child: _Root(
          appearance: appearance,
          child: Builder(builder: (context) {
            inside = context;
            return const SizedBox.shrink();
          }),
        ),
      ),
    );
    expect(Theme.of(inside).brightness, Brightness.light,
        reason: 'following a light device is where every build starts');

    await appearance.choose(ThemePreference.dark);
    await tester.pumpAndSettle();
    expect(Theme.of(inside).brightness, Brightness.dark,
        reason: 'the choice overrides the device, which is the whole item');

    await appearance.choose(ThemePreference.system);
    await tester.pumpAndSettle();
    expect(Theme.of(inside).brightness, Brightness.light,
        reason: 'and going back hands the device its say again');
  });

  testWidgets('both languages name the three states', (tester) async {
    await pumpProfile(tester,
        appearance: Appearance(), language: AppLanguage.en);
    for (final key in [
      KApp.appearanceLabel,
      KApp.appearanceLight,
      KApp.appearanceDark,
      KApp.appearanceSystem,
    ]) {
      expect(find.text(en[key]), findsOneWidget, reason: key);
      expect(en[key], isNot(pt[key]),
          reason: '$key must actually be translated, not copied');
    }
  });

  group('the three labels fit a phone, in both languages, at 1.3×', () {
    // U-34's defect and U-48's rule in one place: a segmented control whose
    // label does not fit does not throw — Material paints it ELLIPSIZED or
    // wrapped, and every gate stays green while "Sistema" reads "Sis…". So the
    // measurement is painted width against the text's OWN intrinsic width,
    // with the font the product ships (the host's fallback draws squares).
    setUpAll(() async {
      final inter = FontLoader('Inter')
        ..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-Medium.ttf'))
        ..addFont(rootBundle.load('assets/fonts/Inter-SemiBold.ttf'));
      await inter.load();
    });

    for (final scale in [1.0, 1.3]) {
      for (final language in [AppLanguage.ptBr, AppLanguage.en]) {
        testWidgets('${language.code} at $scale×', (tester) async {
          final l = Localization(language);
          // The phone U-32 measures every screen on, and the page's own
          // 16 dp gutters.
          await tester.binding.setSurfaceSize(const Size(360, 740));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await tester.pumpWidget(MaterialApp(
            theme: AppTheme.light,
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: AppSegmented<ThemePreference>(
                    selected: ThemePreference.system,
                    onChanged: (_) {},
                    options: [
                      (
                        value: ThemePreference.light,
                        label: l[KApp.appearanceLight]
                      ),
                      (
                        value: ThemePreference.dark,
                        label: l[KApp.appearanceDark]
                      ),
                      (
                        value: ThemePreference.system,
                        label: l[KApp.appearanceSystem]
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ));
          await tester.pumpAndSettle();

          for (final key in [
            KApp.appearanceLight,
            KApp.appearanceDark,
            KApp.appearanceSystem,
          ]) {
            final paragraph =
                tester.renderObject<RenderParagraph>(find.text(l[key]));
            expect(paragraph.size.width,
                closeTo(paragraph.getMaxIntrinsicWidth(double.infinity), 0.5),
                reason: '"${l[key]}" is painted narrower than it wants to be '
                    '— that is an ellipsis nobody asked for');
            expect(paragraph.size.height,
                lessThan(paragraph.getMaxIntrinsicHeight(double.infinity) * 2),
                reason: '"${l[key]}" wrapped to a second line');
          }
          expect(
              tester
                  .getSize(find.byType(SegmentedButton<ThemePreference>))
                  .width,
              lessThanOrEqualTo(360 - 32),
              reason: 'the control is wider than the page it sits on');
        });
      }
    }
  });

  testWidgets('a screen pumped without a controller shows no Aparência card',
      (tester) async {
    // The seam is optional so 37 existing suites keep pumping this screen
    // unchanged. That is also how a setting silently disappears (U-40's
    // `_notWiredYet`), so the two production routes pass one and the U-32
    // accessibility scene measures the card — this only pins the seam's
    // meaning.
    await pumpProfile(tester, appearance: null);
    expect(find.text(pt[KApp.appearanceLabel]), findsNothing);
    expect(find.text(pt[K.languageLabel]), findsOneWidget,
        reason: 'the page itself still renders — only the card is absent');
  });
}

/// `main`'s wiring, reduced to what the theme needs: the two themes from the
/// tokens, the mode off the controller, and a rebuild when it changes.
class _Root extends StatefulWidget {
  final Appearance appearance;
  final Widget child;

  const _Root({required this.appearance, required this.child});

  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  @override
  void initState() {
    super.initState();
    widget.appearance.addListener(_changed);
  }

  @override
  void dispose() {
    widget.appearance.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: widget.appearance.themeMode,
        home: widget.child,
      );
}
