// The SnackBar face of the web's ToastService (T-53 lote 1): one at a time,
// tappable to dismiss, duration scaling with length (the formula itself is
// mirrored and tested in core — feedback_rules_test).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/widgets/app_snack.dart';

Widget host(void Function(BuildContext) onPressed) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => onPressed(context),
            child: const Text('go'),
          ),
        ),
      ),
    );

Future<void> flushSnackTimers(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 8100));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the message with the type icon', (tester) async {
    await tester.pumpWidget(host(
        (context) => showAppSnack(context, 'mensagem de teste')));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('mensagem de teste'), findsOneWidget);
    expect(find.text('✅'), findsOneWidget);
    await flushSnackTimers(tester);
  });

  testWidgets('error type carries the ❌ icon', (tester) async {
    await tester.pumpWidget(host((context) =>
        showAppSnack(context, 'algo falhou', type: AppSnackType.error)));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('❌'), findsOneWidget);
    await flushSnackTimers(tester);
  });

  // Web: ToastService.Show overwrites — exactly one toast at a time.
  testWidgets('a new snack replaces the current one', (tester) async {
    var second = false;
    await tester.pumpWidget(host((context) => showAppSnack(
        context, second ? 'segunda mensagem' : 'primeira mensagem')));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    second = true;
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    expect(find.text('primeira mensagem'), findsNothing);
    expect(find.text('segunda mensagem'), findsOneWidget);
    await flushSnackTimers(tester);
  });

  // Web: the toast is tappable — a user who already read a long summary
  // doesn't have to wait it out.
  testWidgets('tapping the snack dismisses it', (tester) async {
    await tester.pumpWidget(
        host((context) => showAppSnack(context, 'mensagem de teste')));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('mensagem de teste'));
    await tester.pumpAndSettle();
    expect(find.text('mensagem de teste'), findsNothing);
  });
}
