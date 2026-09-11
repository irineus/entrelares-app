// Lote 2 PR 4 — the Rotation Wizard against the fake data source: the 7/7
// preset expansion, existing days preserved (insert-only write), the T-27
// transition-only handoff, the F-39 free-tier clamp and the block validation.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/family.dart';

import 'calendar_slice_test.dart';

final pt = Localization(AppLanguage.ptBr);

Future<void> openWizard(WidgetTester tester) async {
  await tester.tap(find.byTooltip(pt[K.calWizard]));
  await tester.pumpAndSettle();
}

Future<void> generate(WidgetTester tester) async {
  await tapSheet(tester, find.text(pt[K.wizGenerate]));
}

int daysInThreeMonths() =>
    addMonthsClamped(dateOnly(today), 3).difference(dateOnly(today)).inDays;

void main() {
  testWidgets('the default 7/7 preset expands from today, alternating the '
      'first two members', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await generate(tester);

    expect(ds.inserted, hasLength(daysInThreeMonths()));
    expect(ds.inserted.first.scheduleDate, dateOnly(today));
    expect(
        ds.inserted.take(7).every((r) => r.scheduledParentId == 1), isTrue);
    expect(ds.inserted.skip(7).take(7).every((r) => r.scheduledParentId == 2),
        isTrue);
    expect(find.textContaining('dias criados'), findsOneWidget);

    // Closing reloads the calendar behind the sheet.
    await tapSheet(tester, find.text(pt[K.wizClose]));
    expect(find.text(pt[K.wizTitle]), findsNothing);
  });

  testWidgets('already-assigned days are preserved and reported as kept',
      (tester) async {
    final future = futureDay;
    if (future == null) return;
    final ds = FakeCustodyDataSource(
        members: [ana, bruno], days: [row(7, dayOfMonth(future), 2)]);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await generate(tester);

    expect(ds.inserted, hasLength(daysInThreeMonths() - 1));
    expect(
        ds.inserted
            .where((r) =>
                CareSchedule.isoDate(r.scheduleDate) ==
                CareSchedule.isoDate(dayOfMonth(future)))
            .isEmpty,
        isTrue);
    expect(find.textContaining('foram mantidos'), findsOneWidget);
  });

  testWidgets('T-27: the handoff time lands only on transition days — never '
      'the first', (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await tapSheet(tester, find.byKey(const Key('wizHandoffHour')));
    await tester.tap(find.text('01').last);
    await tester.pumpAndSettle();
    await generate(tester);

    expect(ds.inserted.first.handoffTime, isNull);
    // Day 8 (index 7) is the first 7/7 transition.
    expect(ds.inserted[7].handoffTime, '01:00:00');
    expect(ds.inserted[8].handoffTime, isNull);
  });

  testWidgets('F-39: the free horizon clamps the plan with the upsell note',
      (tester) async {
    final ds = FakeCustodyDataSource(members: [ana, bruno], days: [])
      ..family = const Family(id: 1, plan: 'free')
      ..publicSettings = const {'calendar_months_free': '1'};
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await generate(tester); // duration stays at the default 3 months

    final horizonDays =
        addMonthsClamped(dateOnly(today), 1).difference(dateOnly(today)).inDays;
    expect(ds.inserted, hasLength(horizonDays));
    expect(find.textContaining('limitado ao horizonte'), findsOneWidget);
  });

  testWidgets('a block without a parent refuses to generate', (tester) async {
    // A single-member family: the 7/7 preset's second block has no parent.
    final ds = FakeCustodyDataSource(members: [ana], days: []);
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();

    await openWizard(tester);
    await generate(tester);

    expect(find.textContaining(pt[K.wizErrPickParentPerBlock]),
        findsOneWidget);
    expect(ds.inserted, isEmpty);
  });
}
