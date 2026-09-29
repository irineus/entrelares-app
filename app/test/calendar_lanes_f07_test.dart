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
import 'package:entrelares_db_contracts/models/swap_request.dart';
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

  // ── F-07 (PR 4b): swaps and today, per child ──

  Future<void> selectLane(WidgetTester tester, int childId) async {
    final chip = find.byKey(ValueKey('lane-$childId'));
    await tester.ensureVisible(chip);
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('Hoje, in Todas: who has whom when the children split today',
      (tester) async {
    final ds = FakeCustodyDataSource(members: const [ana, bruno], days: [
      laneRow(1, dayOfMonth(today.day), ana.id, lia.id),
      laneRow(2, dayOfMonth(today.day), bruno.id, theo.id),
    ])
      ..family = const Family(
          id: 7, name: 'Souza', plan: 'premium', scheduleMode: 'per_child')
      ..children = [lia, theo];
    await pump(tester, ds);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('today-lane-summary')))
            .data,
        'Lia com Ana Souza; Theo com Bruno Lima');
    // In one child's lane, the card is that child's — one name again.
    await selectLane(tester, theo.id);
    expect(find.byKey(const ValueKey('today-lane-summary')), findsNothing);
  });

  testWidgets('a swap asked for one child can be asked for the other too',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    // Both children with Ana (me) that day: the same state, the same swap.
    final ds = FakeCustodyDataSource(members: const [ana, bruno], days: [
      laneRow(1, dayOfMonth(day), ana.id, lia.id),
      laneRow(2, dayOfMonth(day), ana.id, theo.id),
    ])
      ..family = const Family(
          id: 7, name: 'Souza', plan: 'premium', scheduleMode: 'per_child')
      ..children = [lia, theo];
    await pump(tester, ds);
    await selectLane(tester, lia.id);
    await openDayEditor(tester, day);
    await tapVisible(tester, memberChip('Bruno').last);
    await tapVisible(tester, find.byKey(const ValueKey('day-also-for-11')));
    await tapVisible(tester, find.widgetWithText(FilledButton, l[K.commonSave]));
    expect(ds.createdSwapRequests, hasLength(2),
        reason: "one request per child — Lia's and Theo's");
    expect({for (final r in ds.createdSwapRequests) r['proposed']}, {bruno.id});
  });

  testWidgets("the approver approves every child's request of the day at once",
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    SwapRequest pending(int id, int child) => SwapRequest.fromJson({
          'id': id,
          'schedule_date': CareSchedule.isoDate(dayOfMonth(day)),
          'schedule_id': id,
          'child_id': child,
          'requesting_profile_id': bruno.id,
          'target_profile_id': ana.id,
          'proposed_actual_parent_id': bruno.id,
          'status': 'pending',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
    final ds = FakeCustodyDataSource(members: const [ana, bruno], days: [
      laneRow(1, dayOfMonth(day), ana.id, lia.id),
      laneRow(2, dayOfMonth(day), ana.id, theo.id),
    ])
      ..family = const Family(
          id: 7, name: 'Souza', plan: 'premium', scheduleMode: 'per_child')
      ..children = [lia, theo]
      ..frozenRequests = [pending(1, lia.id), pending(2, theo.id)];
    await pump(tester, ds);
    await selectLane(tester, lia.id);
    await openDay(tester, day);
    final all = find.byKey(const ValueKey('frozen-approve-all'));
    expect(find.descendant(of: all, matching: find.text(
        l.format(KApp.frozenApproveAll, [2]))), findsOne);
    await tapVisible(tester, all);
    expect({for (final a in ds.approvedSwaps) a.id}, {1, 2});
  });

  // ── F-07 (PR 5c): the aviso, per lane ──

  testWidgets("holding ONE child's day today is enough to send an aviso",
      (tester) async {
    // Todas shows Lia's lane (Bruno), but Ana — me — has Theo today.
    final ds = FakeCustodyDataSource(members: const [ana, bruno], days: [
      laneRow(1, dayOfMonth(today.day), bruno.id, lia.id),
      laneRow(2, dayOfMonth(today.day), ana.id, theo.id),
    ])
      ..family = const Family(
          id: 7, name: 'Souza', plan: 'premium', scheduleMode: 'per_child')
      ..children = [lia, theo];
    await pump(tester, ds);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text(l[KApp.noticeAction]), findsOne);
  });
}
