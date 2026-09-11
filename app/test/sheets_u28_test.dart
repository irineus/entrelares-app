// U-28 QA — the sheet contract, pinned once instead of per screen.
//
// The owner reviewed five sheets and found the same three faults in each. That
// is what a missing component looks like, so the fixes live in one place and so
// do these tests: a source-level check that no screen opens a sheet around the
// helper, plus behaviour tests on the frame itself.
import 'dart:io';

import 'package:entrelares_app/theme/app_theme.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child, {Size size = const Size(400, 700)}) => MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: SizedBox(
              width: size.width, height: size.height, child: child),
        ),
      ),
    );

void main() {
  test('every sheet in the app opens through showAppSheet', () {
    // The gate that keeps the fix from decaying: `showModalBottomSheet` with
    // `isScrollControlled: true` and no constraints is exactly the combination
    // that let five sheets grow to the status bar, and it is one line to write
    // by accident.
    final offenders = <String>[];
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.endsWith('sheets.dart'))) {
      if (file.readAsStringSync().contains('showModalBottomSheet')) {
        offenders.add(file.path);
      }
    }
    expect(offenders, isEmpty,
        reason: 'A sheet opened outside showAppSheet can fill the screen and '
            'leave nothing to tap to dismiss: $offenders');
  });

  group('AppSheetFrame', () {
    testWidgets('the actions stay put while the body scrolls', (tester) async {
      await tester.pumpWidget(_host(AppSheetFrame(
        title: 'Um dia qualquer',
        primaryLabel: 'Salvar',
        onPrimary: () {},
        secondaryLabel: 'Cancelar',
        onSecondary: () {},
        children: [
          for (var i = 0; i < 40; i++)
            SizedBox(height: 40, child: Text('linha $i')),
        ],
      )));

      final before = tester.getRect(find.text('Salvar'));
      await tester.drag(find.text('linha 2'), const Offset(0, -400));
      await tester.pumpAndSettle();

      expect(find.text('Salvar'), findsOneWidget);
      expect(tester.getRect(find.text('Salvar')), before,
          reason: 'the answer to the sheet must not scroll away from the '
              'question');
      expect(find.text('Cancelar'), findsOneWidget);
    });

    testWidgets('a read-only sheet gets no action row at all', (tester) async {
      await tester.pumpWidget(_host(const AppSheetFrame(
        title: 'Ontem',
        children: [Text('apenas visualização')],
      )));
      expect(find.byType(FilledButton), findsNothing);
      expect(find.byType(OutlinedButton), findsNothing);
    });

    testWidgets('the pinned notice never scrolls', (tester) async {
      await tester.pumpWidget(_host(AppSheetFrame(
        title: 'Dia bloqueado',
        pinnedNotice: const Text('🔒 Dia passado'),
        primaryLabel: 'Salvar',
        onPrimary: () {},
        children: [
          for (var i = 0; i < 40; i++)
            SizedBox(height: 40, child: Text('linha $i')),
        ],
      )));
      final before = tester.getRect(find.text('🔒 Dia passado'));
      await tester.drag(find.text('linha 2'), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('🔒 Dia passado')), before);
    });

    testWidgets('busy blocks both buttons, not just the primary',
        (tester) async {
      var cancelled = false;
      await tester.pumpWidget(_host(AppSheetFrame(
        title: 'Salvando',
        primaryLabel: 'Salvar',
        onPrimary: () {},
        secondaryLabel: 'Cancelar',
        onSecondary: () => cancelled = true,
        busy: true,
        children: const [Text('corpo')],
      )));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      expect(cancelled, isFalse,
          reason: 'a form mid-save must not offer a cancel that races the '
              'write it cannot recall');
    });
  });

  group('AppFieldLabel', () {
    testWidgets('the explanation is a tooltip that opens on TAP',
        (tester) async {
      await tester.pumpWidget(_host(const Padding(
        padding: EdgeInsets.all(20),
        child: AppFieldLabel('Observação do dia',
            info: 'Fica no dia, mesmo depois de trocas.'),
      )));

      expect(find.text('Fica no dia, mesmo depois de trocas.'), findsNothing);
      await tester.tap(find.byIcon(Icons.info_outline));
      await tester.pumpAndSettle();
      // On Android a Tooltip only opens on a LONG press by default, which
      // nobody discovers — the tip has to answer a normal tap.
      expect(find.text('Fica no dia, mesmo depois de trocas.'), findsOneWidget);
    });

    testWidgets('optional is marked; required is not', (tester) async {
      await tester.pumpWidget(_host(const Column(
        children: [
          AppFieldLabel('Horário de troca', optionalLabel: 'opcional'),
          AppFieldLabel('Responsável agendado'),
        ],
      )));
      expect(find.text('opcional'), findsOneWidget,
          reason: 'required is the default and goes unmarked — most fields '
              'here are required, so marking them would be noise');
    });
  });
}
