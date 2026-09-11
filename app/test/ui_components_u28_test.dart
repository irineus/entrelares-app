// U-28 — the three components the adoption pass added, plus the two layout
// regressions the review found. The overflow ones are pinned as tests and not
// as a code comment on purpose: both were invisible to `flutter analyze` and
// visible only as a yellow-and-black stripe on a real device.
import 'package:entrelares_app/theme/tokens.dart';
import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {ThemeData? theme, double width = 360}) =>
    MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
              width: width, child: SingleChildScrollView(child: child)),
        ),
      ),
    );

void main() {
  group('AppBulletList', () {
    testWidgets('renders one bullet per item', (tester) async {
      await tester.pumpWidget(_host(const AppBulletList(
        items: ['Primeiro aviso', 'Segundo aviso', 'Terceiro aviso'],
      )));
      expect(find.text('•'), findsNWidgets(3));
      expect(find.text('Segundo aviso'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long item wraps without overflowing', (tester) async {
      await tester.pumpWidget(_host(
        const AppBulletList(items: [
          'TODOS os dados (calendário, histórico, auditoria e as contas de '
              'todos) serão apagados definitivamente após 30 dias, e não há '
              'como recuperá-los depois disso.',
        ]),
        width: 300,
      ));
      expect(tester.takeException(), isNull);
    });

    testWidgets('leading icons replace the bullets one for one',
        (tester) async {
      await tester.pumpWidget(_host(const AppBulletList(
        items: ['Relatório em PDF', 'Modo administrador'],
        leadingIcons: [
          Icon(Icons.picture_as_pdf, size: TypeScale.subtitle),
          Icon(Icons.shield, size: TypeScale.subtitle),
        ],
      )));
      expect(find.text('•'), findsNothing);
      expect(find.byIcon(Icons.shield), findsOneWidget);
    });
  });

  group('AppDangerZone', () {
    testWidgets('carries the title, the notices and a filled action',
        (tester) async {
      var pressed = false;
      await tester.pumpWidget(_host(AppDangerZone(
        title: 'Excluir família',
        intro: 'Ao confirmar você declara estar ciente de que:',
        notices: const ['Os dados serão apagados', 'Todos serão avisados'],
        actionLabel: 'Excluir família...',
        onAction: () => pressed = true,
      )));
      expect(find.text('Excluir família'), findsOneWidget);
      expect(find.text('Os dados serão apagados'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Excluir família...'));
      expect(pressed, isTrue,
          reason: 'the destructive action must be a real button, not a link');
    });

    testWidgets('a null action disables the button', (tester) async {
      await tester.pumpWidget(_host(const AppDangerZone(
        title: 'Sair da família',
        notices: ['Indique quem assume a administração antes de sair'],
        actionLabel: 'Sair da família...',
        onAction: null,
      )));
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('busy swaps the label for a spinner and blocks the tap',
        (tester) async {
      await tester.pumpWidget(_host(AppDangerZone(
        title: 'Excluir família',
        notices: const [],
        actionLabel: 'Excluir família...',
        busy: true,
        onAction: () {},
      )));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  group('AppTimelineEntry', () {
    testWidgets('shows marker, overline, title, detail and timestamp',
        (tester) async {
      await tester.pumpWidget(_host(AppTimelineEntry(
        tone: AppTokens.light.neutral,
        marker: '✏️',
        overline: 'Dia: 21/08/2026',
        title: const Text('Fernanda atualizou o agendamento'),
        detail: const Text('Horário da troca: 18:00'),
        timestamp: '19/08/2026 18:06',
      )));
      expect(find.text('✏️'), findsOneWidget);
      expect(find.text('Dia: 21/08/2026'), findsOneWidget);
      expect(find.text('Horário da troca: 18:00'), findsOneWidget);
      expect(find.text('19/08/2026 18:06'), findsOneWidget);
    });

    testWidgets('the rail runs between entries and stops at the last one',
        (tester) async {
      await tester.pumpWidget(_host(Column(
        children: [
          for (var i = 0; i < 3; i++)
            AppTimelineEntry(
              tone: AppTokens.light.neutral,
              marker: '✏️',
              title: Text('Entrada $i'),
              timestamp: '00:0$i',
              isLast: i == 2,
            ),
        ],
      )));
      // Two rails for three entries — the sequence is drawn BETWEEN them.
      final rails = find.byWidgetPredicate((w) =>
          w is Container &&
          w.constraints?.maxWidth == 2 &&
          w.color == AppTokens.light.outline);
      expect(rails, findsNWidgets(2));
    });
  });

  group('layout regressions', () {
    testWidgets(
        'a header with a date and three badges wraps instead of overflowing',
        (tester) async {
      // The shape the notification card hit: an inflexible badge group beside
      // text. In a Row the badges won and the date rendered one character per
      // line; a Wrap moves them to a second run instead.
      await tester.pumpWidget(_host(
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('📅 10/07/2026'),
            Wrap(children: [
              AppBadge(text: 'ATRASADO', tone: AppTokens.light.danger),
              AppBadge(text: 'Reversão confirmada', tone: AppTokens.light.success),
              AppBadge(text: 'Automático', tone: AppTokens.light.info),
            ]),
          ],
        ),
        width: 320,
      ));
      expect(tester.takeException(), isNull);
      // The date survives as ONE string, not as a column of characters.
      expect(find.text('📅 10/07/2026'), findsOneWidget);
    });

    testWidgets('the calendar skeleton honours the caller aspect ratio',
        (tester) async {
      await tester.pumpWidget(_host(
        const AppSkeletonCalendar(weeks: 6, childAspectRatio: 0.75),
      ));
      expect(find.byType(AppSkeleton), findsNWidgets(42));
      final cell = tester.getSize(find.byType(AppSkeleton).first);
      expect(cell.height, greaterThan(cell.width),
          reason: 'a day cell is taller than it is wide — the square cell is '
              'what pushed the handoff mark past the bottom edge');
    });
  });
}
