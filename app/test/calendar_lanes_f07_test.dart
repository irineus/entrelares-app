// F-07 (PR 4) — the calendar of a family that plans per child.
//
// The server is the rule (PR 2's lanes, PR 3's switch); these pin what the
// calendar adds: the lane chips, *Todas* painting a divergent day as a split
// that says who has whom, the "which child?" question before any write, and a
// single-plan family seeing none of it.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/child.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_app/screens/calendar_screen.dart';

import 'calendar_slice_test.dart';

const lia = Child(id: 10, familyId: 7, firstName: 'Lia', sortOrder: 0);
const theo = Child(id: 11, familyId: 7, firstName: 'Theo', sortOrder: 1);

CareSchedule laneRow(int id, DateTime date, int carer, int child) =>
    CareSchedule.fromJson({
      'id': id,
      'schedule_date': CareSchedule.isoDate(date),
      'scheduled_parent_id': carer,
      'actual_parent_id': null,
      'revision': 1,
      'revision_token': 'tok-$id',
      'child_id': child,
    });

FakeCustodyDataSource perChildSource(int day) =>
    FakeCustodyDataSource(members: const [ana, bruno], days: [
      // The divergent day: Lia with Ana, Theo with Bruno.
      laneRow(1, dayOfMonth(day), ana.id, lia.id),
      laneRow(2, dayOfMonth(day), bruno.id, theo.id),
    ])
      ..family = const Family(
          id: 7, name: 'Souza', plan: 'premium', scheduleMode: 'per_child')
      ..children = [lia, theo];

Future<void> pump(WidgetTester tester, FakeCustodyDataSource ds) async {
  await tester.binding.setSurfaceSize(const Size(420, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(app(ds));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  testWidgets('a single-plan family sees no lane chips', (tester) async {
    await pump(
        tester,
        FakeCustodyDataSource(members: const [ana, bruno], days: [])
          ..family = const Family(id: 7, name: 'Souza', plan: 'free'));
    expect(find.byKey(CalendarScreen.laneChipsKey), findsNothing);
  });

  testWidgets('per child: the chips name every child, Todas first',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pump(tester, perChildSource(day));
    expect(find.byKey(CalendarScreen.laneChipsKey), findsOne);
    expect(find.text(l[KApp.calLaneAll]), findsOne);
    expect(find.text('Lia'), findsOne);
    expect(find.text('Theo'), findsOne);
  });

  testWidgets('Todas: a divergent day says who has whom', (tester) async {
    final day = futureDay;
    if (day == null) return;
    final semantics = tester.ensureSemantics();
    await pump(tester, perChildSource(day));
    expect(
        find.bySemanticsLabel(
            RegExp('Lia com Ana Souza; Theo com Bruno Lima')),
        findsOne);
    semantics.dispose();
  });

  testWidgets("Todas: a tap asks which child, then opens that child's day",
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pump(tester, perChildSource(day));
    await openDay(tester, day);
    expect(find.byKey(CalendarScreen.laneChooserKey), findsOne);
    await tester.tap(find.byKey(const ValueKey('lane-choose-11')));
    await tester.pumpAndSettle();
    // The day sheet is Theo's, and the calendar moved to Theo's lane.
    expect(find.byKey(CalendarScreen.laneChooserKey), findsNothing);
    final theoChip =
        tester.widget<ChoiceChip>(find.byKey(const ValueKey('lane-11')));
    expect(theoChip.selected, isTrue);
  });

  testWidgets("a child's lane paints that child's carer, not the split",
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final semantics = tester.ensureSemantics();
    await pump(tester, perChildSource(day));
    // The chips scroll sideways when the names do not fit.
    await tester.ensureVisible(find.byKey(const ValueKey('lane-11')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lane-11')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('Theo com')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^$day, .*Bruno Lima')), findsOne);
    semantics.dispose();
  });
}
