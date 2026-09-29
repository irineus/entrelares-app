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
import 'package:entrelares_db_contracts/models/child_event.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/screens/day_sheet.dart' show daySheetEditKey;
import 'package:entrelares_app/widgets/person_chip.dart';

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
    expect(find.text(l[KApp.calLaneAllShort]), findsOne);
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

  testWidgets("Todas: a tap opens the whole day, read-only, one block per child",
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pump(tester, perChildSource(day));
    await openDay(tester, day);
    expect(find.byKey(const ValueKey('day-lanes')), findsOne);
    expect(find.byKey(const ValueKey('day-lane-10')), findsOne);
    expect(find.byKey(const ValueKey('day-lane-11')), findsOne);
    // Read-only: no pencil, no save.
    expect(find.byKey(daySheetEditKey), findsNothing);
    expect(find.text(l[K.commonSave]), findsNothing);
    // "Editar o dia de Theo" moves the calendar to Theo and opens his day.
    final edit = find.byKey(const ValueKey('day-lane-edit-11'));
    await tester.ensureVisible(edit);
    await tester.pumpAndSettle();
    await tester.tap(edit);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('day-lanes')), findsNothing);
    final theoChip =
        tester.widget<PersonChip>(find.byKey(const ValueKey('lane-11')));
    expect(theoChip.selected, isTrue);
  });

  testWidgets('Todas: a long press asks to pick the child above', (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pump(tester, perChildSource(day));
    final cell = find.text('$day').last;
    await tester.ensureVisible(cell);
    await tester.pumpAndSettle();
    await tester.longPress(cell);
    await tester.pumpAndSettle();
    expect(find.text(l[KApp.calLanePickFirst]), findsOne);
  });

  testWidgets('Todas: the split day draws avatars, not letters', (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pump(tester, perChildSource(day));
    expect(find.byKey(ValueKey('cell-split-$day')), findsOne);
    expect(find.text('A/B'), findsNothing);
  });

  // ── F-07 (owner's QA, 29/09/2026, round 2): the people, with avatars ──

  List<String> avatarsIn(WidgetTester tester, Finder of) => [
        for (final a in tester.widgetList<MiniAvatar>(
            find.descendant(of: of, matching: find.byType(MiniAvatar))))
          a.letters,
      ];

  testWidgets('Todas: the split day is one column per carer, children below',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pump(tester, perChildSource(day));
    final split = find.byKey(ValueKey('cell-split-$day'));
    final letters = avatarsIn(tester, split);
    // Two carers, one child each: four avatars, Lia's and Theo's among them.
    expect(letters, hasLength(4));
    expect(letters, containsAll(['L', 'T']));
  });

  testWidgets('the same carer for every child: no split, no child avatar',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pump(
        tester,
        FakeCustodyDataSource(members: const [ana, bruno], days: [
          laneRow(1, dayOfMonth(day), ana.id, lia.id),
          laneRow(2, dayOfMonth(day), ana.id, theo.id),
        ])
          ..family = const Family(
              id: 7, name: 'Souza', plan: 'premium', scheduleMode: 'per_child')
          ..children = [lia, theo]);
    expect(find.byKey(ValueKey('cell-split-$day')), findsNothing);
  });

  testWidgets("the lane chips carry the child's avatar", (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pump(tester, perChildSource(day));
    expect(avatarsIn(tester, find.byKey(const ValueKey('lane-10'))), ['L']);
    expect(avatarsIn(tester, find.byKey(const ValueKey('lane-11'))), ['T']);
  });

  testWidgets("the whole day's blocks open with the child's avatar",
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pump(tester, perChildSource(day));
    await openDay(tester, day);
    expect(avatarsIn(tester, find.byKey(const ValueKey('day-lane-10'))),
        contains('L'));
    expect(avatarsIn(tester, find.byKey(const ValueKey('day-lane-11'))),
        contains('T'));
  });

  testWidgets("a carer's chip opens my profile, or the Família",
      (tester) async {
    final opened = <(MemberLinkTarget, int)>[];
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(
        FakeCustodyDataSource(members: const [ana, bruno], days: []),
        onOpenMember: (t, id) => opened.add((t, id))));
    await tester.pumpAndSettle();
    // No role in the chip any more: the first name only.
    expect(find.descendant(
        of: find.byKey(ValueKey('legend-member-${ana.id}')),
        matching: find.text('Ana')), findsOne);
    await tester.tap(find.byKey(ValueKey('legend-member-${ana.id}')));
    await tester.tap(find.byKey(ValueKey('legend-member-${bruno.id}')));
    // Ana (me) is not an admin here: Bruno's chip lands on the Família.
    expect(opened, [
      (MemberLinkTarget.ownProfile, ana.id),
      (MemberLinkTarget.family, bruno.id),
    ]);
  });

  testWidgets("an admin's tap on another carer opens that profile",
      (tester) async {
    final opened = <(MemberLinkTarget, int)>[];
    const admin = Member(
        id: 1, fullName: 'Ana Souza', colorSlot: 1, userId: 'u1', isAdmin: true);
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(
        FakeCustodyDataSource(members: const [admin, bruno], days: []),
        onOpenMember: (t, id) => opened.add((t, id))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('legend-member-${bruno.id}')));
    expect(opened, [(MemberLinkTarget.memberProfile, bruno.id)]);
  });

  // ── F-07 (owner's QA, 29/09/2026, round 3): the small phone ──

  const carla = Member(id: 3, fullName: 'Carla Dias', colorSlot: 3);
  const davi =
      Member(id: 4, fullName: 'Davi Rocha', colorSlot: 4, userId: 'u4');
  const bia = Child(id: 12, familyId: 7, firstName: 'Bia', sortOrder: 2);
  const filho =
      Child(id: 13, familyId: 7, firstName: 'Filho Pródigo', sortOrder: 3);

  /// Four carers (Carla pending) and four children; on [day] each child is
  /// with a different carer.
  FakeCustodyDataSource crowded(int day) =>
      FakeCustodyDataSource(members: const [ana, bruno, carla, davi], days: [
        laneRow(1, dayOfMonth(day), ana.id, lia.id),
        laneRow(2, dayOfMonth(day), bruno.id, theo.id),
        laneRow(3, dayOfMonth(day), davi.id, bia.id),
        laneRow(4, dayOfMonth(day), carla.id, filho.id),
      ])
        ..family = const Family(
            id: 7, name: 'Souza', plan: 'premium', scheduleMode: 'per_child')
        ..children = [lia, theo, bia, filho];

  Future<void> pumpSe(WidgetTester tester, FakeCustodyDataSource ds) async {
    await tester.binding.setSurfaceSize(const Size(375, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(app(ds));
    await tester.pumpAndSettle();
  }

  Finder inChip(String key, String text) => find.descendant(
      of: find.byKey(ValueKey(key)), matching: find.text(text));

  testWidgets('a small phone: the key is the avatars, the names are spoken',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final semantics = tester.ensureSemantics();
    await pumpSe(tester, crowded(day));
    expect(inChip('legend-member-${ana.id}', 'Ana'), findsNothing);
    expect(find.bySemanticsLabel('Ana'), findsOne);
    // "Trocado" and every carer on ONE row: the same top for all.
    final tops = {
      for (final m in const [ana, bruno, carla, davi])
        tester.getTopLeft(find.byKey(ValueKey('legend-member-${m.id}'))).dy,
    };
    expect(tops, hasLength(1));
    semantics.dispose();
  });

  testWidgets('a wide phone keeps the names', (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pump(tester, perChildSource(day));
    expect(inChip('legend-member-${ana.id}', 'Ana'), findsOne);
    expect(inChip('lane-10', 'Lia'), findsOne);
    expect(inChip('lane-all', l[KApp.calLaneAllShort]), findsOne);
  });

  testWidgets('the pending carer is a hollow avatar, never "(pendente)"',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final semantics = tester.ensureSemantics();
    await pump(tester, crowded(day));
    final avatar = tester.widget<MiniAvatar>(
        find.byKey(ValueKey('legend-avatar-${carla.id}')));
    expect(avatar.dashedRing, isNotNull);
    expect(
        tester
            .widget<MiniAvatar>(find.byKey(ValueKey('legend-avatar-${ana.id}')))
            .dashedRing,
        isNull);
    expect(find.textContaining(l[KApp.calMemberPending]), findsNothing);
    expect(
        find.bySemanticsLabel('Carla ${l[KApp.calMemberPending]}'), findsOne);
    semantics.dispose();
  });

  testWidgets('a small phone: only the selected child keeps a name',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pumpSe(tester, crowded(day));
    // Todas selected: "Todas" is its icon, every child an avatar.
    expect(inChip('lane-all', l[KApp.calLaneAllShort]), findsNothing);
    expect(inChip('lane-13', 'Filho Pródigo'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('lane-13')));
    await tester.pumpAndSettle();
    expect(inChip('lane-13', 'Filho Pródigo'), findsOne, reason: 'never cut');
    expect(inChip('lane-10', 'Lia'), findsNothing);
    // All five chips on screen, no scroll. (With the test font's wide glyphs
    // "Filho Pródigo" alone passes the edge; the row then scrolls — never
    // cuts. Measured with a short name.)
    await tester.tap(find.byKey(const ValueKey('lane-12')));
    await tester.pumpAndSettle();
    expect(inChip('lane-12', 'Bia'), findsOne);
    final width = tester.getSize(find.byType(MaterialApp)).width;
    for (final k in ['lane-all', 'lane-10', 'lane-11', 'lane-12', 'lane-13']) {
      final r = tester.getRect(find.byKey(ValueKey(k)));
      expect(r.left, greaterThanOrEqualTo(0), reason: k);
      expect(r.right, lessThanOrEqualTo(width), reason: k);
    }
  });

  testWidgets('four carers in a small cell overlap inside it, on their bands',
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    await pumpSe(tester, crowded(day));
    final split = find.byKey(ValueKey('cell-split-$day'));
    final cell = tester.getRect(split);
    final avatars = find.descendant(of: split, matching: find.byType(MiniAvatar));
    expect(avatars, findsNWidgets(8));
    for (final e in avatars.evaluate()) {
      final box = e.renderObject! as RenderBox;
      final r = box.localToGlobal(Offset.zero) & box.size;
      expect(r.left, greaterThanOrEqualTo(cell.left - 0.01));
      expect(r.right, lessThanOrEqualTo(cell.right + 0.01));
    }
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

  // ── F-07 (owner's QA, 29/09/2026): the agenda follows the lane ──

  ChildEvent event(int id, int day, int? child, String kind) =>
      ChildEvent.fromJson({
        'id': id,
        'family_id': 7,
        'child_id': child,
        'event_date': CareSchedule.isoDate(dayOfMonth(day)),
        'start_time': '08:00:00',
        'kind': kind,
        'body': 'item $id',
        'created_by': ana.id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

  testWidgets("a child's day lists that child's items and the family's notes",
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = perChildSource(day)
      ..publicSettings = const {'feature.child_agenda': 'true'}
      ..childEvents = [
        event(1, day, lia.id, 'school'),
        event(2, day, theo.id, 'school'),
        event(3, day, null, 'note'),
      ];
    await pump(tester, ds);
    await tester.ensureVisible(find.byKey(const ValueKey('lane-11')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lane-11')));
    await tester.pumpAndSettle();
    await openDay(tester, day);
    expect(find.textContaining('item 2'), findsOne, reason: "Theo's item");
    expect(find.textContaining('item 3'), findsOne, reason: 'the family note');
    expect(find.textContaining('item 1'), findsNothing, reason: "Lia's item");
  });

  testWidgets("a new item in a child's day is that child's — no picker",
      (tester) async {
    final day = futureDay;
    if (day == null) return;
    final ds = perChildSource(day)
      ..family = const Family(
          id: 7, name: 'Souza', plan: 'premium', scheduleMode: 'per_child')
      ..publicSettings = const {'feature.child_agenda': 'true'};
    await pump(tester, ds);
    await tester.ensureVisible(find.byKey(const ValueKey('lane-11')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('lane-11')));
    await tester.pumpAndSettle();
    await openDay(tester, day);
    final add = find.text(l[KApp.agendaAdd]);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    // The kind that needs a child: the child is Theo, fixed.
    await tester.tap(find.text(l[KApp.agendaKindSchool]).last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agenda-child')), findsNothing);
    expect(find.text('Theo'), findsWidgets);
  });
}
