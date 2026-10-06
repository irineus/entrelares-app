// F-99 — only the two ends of a handoff (or an admin) change its time. The
// database refuses the rest (gate suite `handoff_party.dart`); the day sheet
// reads the time to everyone else and points them at the aviso.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/widgets/ui/ui.dart';

import 'calendar_slice_test.dart';

final _pt = Localization(AppLanguage.ptBr);
const _carla =
    Member(id: 3, fullName: 'Carla Dias', colorSlot: 3, userId: 'u3');

void main() {
  testWidgets('a caregiver at neither end reads the time and is pointed at '
      'the aviso', (tester) async {
    final day = futureDay;
    if (day == null || day < 2) return;
    // Carla reads (first member); Bruno has D-1, Ana has the day.
    final ds = FakeCustodyDataSource(members: [
      _carla,
      ana,
      bruno
    ], days: [
      row(1, dayOfMonth(day - 1), bruno.id),
      row(2, dayOfMonth(day), ana.id, handoffTime: '18:00:00'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDayEditor(tester, day);

    expect(find.byKey(const ValueKey('handoff-party-only')), findsOneWidget);
    expect(find.text(_pt[KApp.noticeHandoffPartyOnly]), findsOneWidget);
    expect(tester.widget<AppTimeField>(find.byType(AppTimeField)).enabled,
        isFalse);
  });

  testWidgets('the end that hands over may change it', (tester) async {
    final day = futureDay;
    if (day == null || day < 2) return;
    // Bruno reads (first member) and has D-1.
    final ds = FakeCustodyDataSource(members: [
      bruno,
      ana
    ], days: [
      row(1, dayOfMonth(day - 1), bruno.id),
      row(2, dayOfMonth(day), ana.id, handoffTime: '18:00:00'),
    ]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
    await openDayEditor(tester, day);
    expect(find.byKey(const ValueKey('handoff-party-only')), findsNothing);
    expect(tester.widget<AppTimeField>(find.byType(AppTimeField)).enabled,
        isTrue);
  });
}
