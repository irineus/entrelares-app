// U-29 — the design-review deliveries that need their own assertions: the
// calendar cell's composed semantics (the grid used to be mute to a screen
// reader), the login eye toggle U-19 had shipped and the port dropped, and
// the bulk sheet's U-28 alignment (bordered form fields, not underlines).
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:entrelares_app/screens/login_screen.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'calendar_slice_test.dart';

final pt = Localization(AppLanguage.ptBr);

Widget wrap(Widget child) => AppL10n(
      l: pt,
      setLanguage: (_) async {},
      child: MaterialApp(home: child),
    );

void main() {
  group('U-29 · calendar cell semantics', () {
    testWidgets('an assigned day announces its responsible by name',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final ds = FakeCustodyDataSource(
          members: [ana, bruno], days: [row(1, dayOfMonth(10), 1)]);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      // "Hoje" joins the label only when the 10th IS today — either way the
      // name must be there, which is what the port's grid never said.
      expect(
          find.bySemanticsLabel(
              RegExp('^10(, ${pt[K.calToday]})?, Ana Souza\$')),
          findsOneWidget);
      semantics.dispose();
    });

    testWidgets('a swapped day announces the swap, not just the colour',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final ds = FakeCustodyDataSource(
          members: [ana, bruno],
          days: [row(2, dayOfMonth(11), 1, actual: 2)]);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      expect(
          find.bySemanticsLabel(RegExp(
              '^11(, ${pt[K.calToday]})?, Bruno Lima, ${pt[K.calSwapped]}\$')),
          findsOneWidget);
      semantics.dispose();
    });
  });

  group('U-29 · login password eye toggle (U-19 parity)', () {
    testWidgets('the toggle reveals and re-hides what was typed',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(wrap(LoginScreen(
        onSignIn: (_, _) async {},
        onForgotPassword: () {},
        onSignUp: () {},
        prefs: prefs,
      )));
      await tester.pumpAndSettle();

      bool obscured() => tester
          .widget<EditableText>(find.byType(EditableText).last)
          .obscureText;

      expect(obscured(), isTrue);
      await tester.tap(find.byTooltip(pt[K.commonShowPassword]));
      await tester.pump();
      expect(obscured(), isFalse);
      await tester.tap(find.byTooltip(pt[K.commonHidePassword]));
      await tester.pump();
      expect(obscured(), isTrue);
    });
  });

  group('U-29 · bulk sheet joins the U-28 conventions', () {
    testWidgets('every bulk control is a bordered form field, not an '
        'underline', (tester) async {
      final lastDay = DateTime(today.year, today.month + 1, 0).day;
      if (today.day + 1 > lastDay) return;
      final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();

      final dayFinder = find.text('${today.day + 1}').last;
      await tester.ensureVisible(dayFinder);
      await tester.pumpAndSettle();
      await tester.longPress(dayFinder);
      await tester.pumpAndSettle();
      await tester.tap(find.text(pt.format(K.selectionEdit, [1])));
      await tester.pumpAndSettle();

      for (final key in const [
        'bulkScheduled',
        'bulkActual',
        'bulkHandoffHour',
        'bulkHandoffMinute',
      ]) {
        expect(
            find.descendant(
                of: find.byKey(Key(key)),
                matching: find.byType(InputDecorator)),
            findsOneWidget,
            reason: '$key must wear the bordered field decoration');
      }
    });
  });
}
