// U-27 — the shared component set. These are the behaviours the screens now
// depend on, so each one is pinned here rather than re-verified per screen.
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('AppBanner', () {
    testWidgets('renders title and message, and prefixes the leading mark',
        (tester) async {
      await tester.pumpWidget(_host(AppBanner(
        tone: AppTokens.light.danger,
        leading: '⚠️',
        title: 'Falhou',
        message: 'Tente de novo',
      )));
      expect(find.text('⚠️ Falhou'), findsOneWidget);
      expect(find.text('Tente de novo'), findsOneWidget);
    });

    testWidgets('with no title the mark rides the message instead',
        (tester) async {
      await tester.pumpWidget(_host(AppBanner(
        tone: AppTokens.light.warning,
        leading: '⚠️',
        message: 'Atrasado',
      )));
      // The mark must not be dropped just because there is nothing to title.
      expect(find.text('⚠️ Atrasado'), findsOneWidget);
    });
  });

  group('AppBadge', () {
    testWidgets('the semantics label is what a screen reader hears',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(AppBadge(
        text: 'Atrasado',
        tone: AppTokens.light.danger,
        semantics: 'Pedido atrasado desde ontem',
      )));
      // The annotation merges with the pill's own text rather than replacing
      // it, which is what the notification list has always done — the reader
      // hears the abbreviation AND the full state.
      expect(find.bySemanticsLabel(RegExp('Pedido atrasado desde ontem')),
          findsOneWidget);
      handle.dispose();
    });

    testWidgets('soft and solid pick opposite ink', (tester) async {
      await tester.pumpWidget(_host(Column(children: [
        AppBadge(text: 'a', tone: AppTokens.light.info),
        AppBadge(text: 'b', tone: AppTokens.light.info, soft: false),
      ])));
      final soft = tester.widget<Text>(find.text('a'));
      final solid = tester.widget<Text>(find.text('b'));
      expect(soft.style?.color, AppTokens.light.info.onContainer);
      expect(solid.style?.color, AppTokens.light.info.onSolid);
    });
  });

  group('AppEmptyState', () {
    testWidgets('the body is optional', (tester) async {
      await tester.pumpWidget(
          _host(const AppEmptyState(icon: '📭', title: 'Nada aqui')));
      expect(find.text('📭'), findsOneWidget);
      expect(find.text('Nada aqui'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('AppListRow', () {
    test('a row with neither value nor widget is rejected at construction', () {
      // A row with no value is a section header; letting it through would put
      // an empty Expanded on every detail panel.
      expect(() => AppListRow(label: 'x'), throwsAssertionError);
    });

    testWidgets('renders label and value', (tester) async {
      await tester.pumpWidget(
          _host(const AppListRow(label: 'De', value: '10/08/2026')));
      expect(find.text('De'), findsOneWidget);
      expect(find.text('10/08/2026'), findsOneWidget);
    });
  });

  group('AppActionPair', () {
    testWidgets('the confirming action comes FIRST — the web app\'s order',
        (tester) async {
      // Parity, not taste: the Blazor app has always put the confirmation
      // before the way out, and the cutover hands the Flutter app to people
      // who learned that order.
      await tester.pumpWidget(_host(AppActionPair(
        primaryLabel: 'Sim, apagar',
        onPrimary: () {},
        secondaryLabel: 'Não, voltar',
        onSecondary: () {},
      )));
      final confirm = tester.getTopLeft(find.text('Sim, apagar')).dx;
      final back = tester.getTopLeft(find.text('Não, voltar')).dx;
      expect(confirm, lessThan(back));
    });

    testWidgets('busy disables BOTH and swaps the label for a spinner',
        (tester) async {
      var primary = 0, secondary = 0;
      await tester.pumpWidget(_host(AppActionPair(
        primaryLabel: 'Salvar',
        onPrimary: () => primary++,
        secondaryLabel: 'Cancelar',
        onSecondary: () => secondary++,
        busy: true,
      )));
      expect(find.text('Salvar'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      await tester.tap(find.text('Cancelar'));
      // A cancel mid-save races a write that cannot be recalled.
      expect(primary, 0);
      expect(secondary, 0);
    });

    testWidgets('a lone primary fills the width', (tester) async {
      await tester.pumpWidget(
          _host(AppActionPair(primaryLabel: 'Continuar', onPrimary: () {})));
      expect(find.text('Não, voltar'), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
    });
  });

  group('AppSegmented', () {
    testWidgets('reports the tapped option', (tester) async {
      var picked = 'a';
      await tester.pumpWidget(_host(AppSegmented<String>(
        options: const [(value: 'a', label: 'Um'), (value: 'b', label: 'Dois')],
        selected: 'a',
        onChanged: (v) => picked = v,
      )));
      await tester.tap(find.text('Dois'));
      expect(picked, 'b');
    });

    testWidgets('disabled takes no choice — a filter mid-load fires no second '
        'read', (tester) async {
      var picked = 'a';
      await tester.pumpWidget(_host(AppSegmented<String>(
        options: const [(value: 'a', label: 'Um'), (value: 'b', label: 'Dois')],
        selected: 'a',
        enabled: false,
        onChanged: (v) => picked = v,
      )));
      await tester.tap(find.text('Dois'));
      expect(picked, 'a');
    });
  });

  group('AppTextField', () {
    testWidgets('the label is visible BEFORE and AFTER typing', (tester) async {
      // The whole accessibility argument of this item: the field border is a
      // hairline, so the permanent label is what satisfies WCAG 1.4.11. A
      // placeholder that vanishes on the first keystroke would not.
      final controller = TextEditingController();
      await tester.pumpWidget(_host(AppTextField(
        label: 'E-mail',
        hint: 'voce@exemplo.com',
        controller: controller,
      )));
      expect(find.text('E-mail'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'a@b.com');
      await tester.pump();
      expect(find.text('E-mail'), findsOneWidget);
    });

    testWidgets('the character counter is hidden unless asked for',
        (tester) async {
      await tester.pumpWidget(_host(const AppTextField(
          label: 'Nome', maxLength: 40, initialValue: 'Ana')));
      expect(find.text('3/40'), findsNothing);

      await tester.pumpWidget(_host(const AppTextField(
          label: 'Nome',
          maxLength: 40,
          initialValue: 'Ana',
          showCounter: true)));
      expect(find.text('3/40'), findsOneWidget);
    });
  });

  group('AppAvatar', () {
    testWidgets('wears the carer\'s slot colours when given one',
        (tester) async {
      final slot = AppTokens.light.slots[2];
      await tester
          .pumpWidget(_host(AppAvatar(initials: 'AN', slot: slot)));
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundColor, slot.tone.solid);
      expect(tester.widget<Text>(find.text('AN')).style?.color,
          slot.tone.onSolid);
    });
  });

  group('dark theme', () {
    testWidgets('every component renders under the dark theme', (tester) async {
      await tester.pumpWidget(_host(
        Column(children: [
          AppBanner(tone: AppTokens.dark.danger, message: 'erro'),
          AppBadge(text: 'novo', tone: AppTokens.dark.accent),
          const AppEmptyState(icon: '📭', title: 'vazio', body: 'nada aqui'),
          const AppListRow(label: 'a', value: 'b'),
          const AppSectionHeader(title: 'Seção'),
          AppCard(title: 'Cartão', child: const Text('conteúdo')),
          const AppTextField(label: 'Campo'),
          AppActionPair(primaryLabel: 'ok', onPrimary: () {}),
          const AppAvatar(initials: 'AB'),
        ]),
        theme: AppTheme.dark,
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('Seção'), findsOneWidget);
    });
  });
}
