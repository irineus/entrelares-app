// The owner's validation (25/09/2026), on "Lançar despesa":
//
// 1. "Quem pagou" overflowed by 38 px with a long name — a dropdown that is
//    not `isExpanded` sizes itself to its widest item and ignores the screen.
//    Every dropdown in lib/ is expanded now, and a source gate keeps it so.
// 2. "Descrição", the first field's floating label, was cut in half and no
//    scroll revealed it — the sheet's scrolling body started at 0 and clipped
//    the half of the label that sits above the field's border.
import 'dart:io';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/screens/expenses_screen.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const longName = Member(
    id: 1,
    fullName: 'Irineu Junior Pinheiro dos Santos (Dev)',
    colorSlot: 1,
    userId: 'u1',
    isAdmin: true);
const other = Member(
    id: 2, fullName: 'Fernanda Daroit (Dev)', colorSlot: 2, userId: 'u2');

void main() {
  test('every dropdown in lib/ is isExpanded', () {
    final offenders = <String>[];
    for (final f in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('DropdownButtonFormField<') ||
            !lines[i].trimRight().endsWith('(')) {
          continue;
        }
        // The named arguments of this call, up to its first item list.
        final call = lines.skip(i + 1).takeWhile((l) => !l.contains('items:'));
        if (!call.any((l) => l.contains('isExpanded: true'))) {
          offenders.add('${f.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'a dropdown sized to its widest item overflows on a phone as '
            'soon as a name is long — pass isExpanded: true');
  });

  for (final scale in [1.0, 1.3]) {
    testWidgets('Lançar despesa holds a long name at 360 dp, $scale×, and '
        'shows the first field\'s label whole', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final ds = FakeCustodyDataSource(members: const [longName, other], days: [])
        ..publicSettings = const {'feature.expenses': 'true'};
      await tester.pumpWidget(AppL10n(
        l: Localization(AppLanguage.ptBr),
        setLanguage: (_) async {},
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => showAppSheet<bool>(
                    context: context,
                    builder: (_) => ExpenseEditorSheet(
                      dataSource: ds,
                      settings: const PublicSettings(
                          {'feature.expenses': 'true'}),
                      eligible: const [longName, other],
                      me: longName,
                      childId: null,
                      today: DateTime(2026, 9, 25),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // The label is inside the scrolling body's viewport, not above it.
      final body = tester.getRect(find.byKey(AppSheetFrame.bodyKey));
      final label = tester.getRect(find.text(
          Localization(AppLanguage.ptBr)[KApp.expenseDesc]).first);
      expect(label.top, greaterThanOrEqualTo(body.top),
          reason: 'the first field\'s floating label is clipped: $label vs '
              'the body at $body');
    });
  }
}
