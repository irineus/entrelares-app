// U-34 — the bell's tab says "Notificações", and it still fits.
//
// The word is the one the screen's own title uses; the price is its width:
// 79.7 dp at 1.0× and 101.7 dp at 1.3× in a 90 dp slot (360 dp phone, four
// destinations, real Inter). `NavigationDestination` paints a bare `Text`, so
// a label wider than its slot breaks MID-WORD into a second line the bar has
// no height for. The shell clamps the bar's text scaling to the largest
// factor at which the widest label fits (the U-39 shape), and this suite
// measures the painted paragraph — under the host's fallback font every glyph
// is a square and no label fits at all, so Inter is loaded first.
import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:entrelares_app/screens/home_shell.dart';
import 'package:entrelares_app/services/account_identity.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/notification_badge.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const _phone = Size(360, 740);
const _navKeys = [
  K.navCalendar,
  K.navFamily,
  K.navNotificationsShort,
  K.navReports,
];

Future<void> _loadInter() async {
  Future<ByteData> bytes(String file) async => ByteData.sublistView(
      Uint8List.fromList(await File('assets/fonts/$file').readAsBytes()));
  final inter = FontLoader('Inter');
  for (final f in [
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
    'Inter-Bold.ttf',
  ]) {
    inter.addFont(bytes(f));
  }
  await inter.load();
}

Widget _shellApp(Localization l, {required int selected}) {
  const paths = ['/', '/family', '/notifications', '/reports'];
  final router = GoRouter(
    initialLocation: paths[selected],
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (_, _, shell) => HomeShell(
            shell: shell,
            adminMode: AdminMode(),
            identity: AccountIdentity(),
            onSignOut: () async {},
            onOpenProfile: () {},
            badge: NotificationBadge(
                FakeCustodyDataSource(members: const [], days: []))),
        branches: [
          for (final path in paths)
            StatefulShellBranch(routes: [
              GoRoute(
                  path: path,
                  builder: (_, _) => const Scaffold(body: SizedBox())),
            ]),
        ],
      ),
    ],
  );
  return AppL10n(
    l: l,
    setLanguage: (_) async {},
    child: MaterialApp.router(
        theme: AppTheme.light, routerConfig: router),
  );
}

void main() {
  setUpAll(_loadInter);

  Future<void> usePhone(WidgetTester tester, double textScale) async {
    await tester.binding.setSurfaceSize(_phone);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    tester.view.physicalSize = _phone;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
  }

  RenderParagraph paragraphOf(WidgetTester tester, String label) =>
      tester.renderObject<RenderParagraph>(find.descendant(
          of: find.byType(NavigationBar), matching: find.text(label)));

  for (final language in AppLanguage.values) {
    final l = Localization(language);

    // The selected label is the widest (w600), so every tab takes its turn.
    for (var selected = 0; selected < _navKeys.length; selected++) {
      testWidgets(
          '$language, tab $selected selected: every label is ONE line inside '
          'its slot at 1.3×', (tester) async {
        await usePhone(tester, 1.3);
        await tester.pumpWidget(_shellApp(l, selected: selected));
        await tester.pumpAndSettle();

        final slot = _phone.width / _navKeys.length;
        for (final key in _navKeys) {
          final paragraph = paragraphOf(tester, l[key]);
          final lines = paragraph
              .getBoxesForSelection(TextSelection(
                  baseOffset: 0, extentOffset: l[key].length))
              .map((box) => box.top)
              .toSet();
          expect(lines, hasLength(1), reason: '"${l[key]}" wrapped');
          expect(paragraph.size.width, lessThanOrEqualTo(slot),
              reason: '"${l[key]}" is wider than its slot');
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$language: at the default scale the bar is left alone',
        (tester) async {
      await usePhone(tester, 1.0);
      await tester.pumpWidget(_shellApp(l, selected: 2));
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(NavigationBar));
      expect(MediaQuery.textScalerOf(context).scale(12), 12);
      // labelSmall, as designed: nobody at 1.0× pays for the longer word.
      final paragraph = paragraphOf(tester, l[K.navNotificationsShort]);
      expect(paragraph.text.style?.fontSize, 12);
      expect(paragraph.textScaler.scale(12), 12);
    });

    testWidgets('$language: a reader at 1.3× never gets LESS than 1.0×',
        (tester) async {
      await usePhone(tester, 1.3);
      await tester.pumpWidget(_shellApp(l, selected: 2));
      await tester.pumpAndSettle();

      final paragraph = paragraphOf(tester, l[K.navNotificationsShort]);
      expect(paragraph.textScaler.scale(12), greaterThanOrEqualTo(12));
    });
  }
}
