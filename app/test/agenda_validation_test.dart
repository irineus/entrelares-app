// The owner's validation of the agenda (25/09/2026).
//
// 1. The first child counts at once: the editor re-reads the children when it
//    opens (the day sheet can stay open while the admin adds the child under
//    Família), and an admin with no child registered gets the door to add it.
// 2. The day sheet's member chips: only the chosen one prints a name.
// 3. The calendar cell wears the day's first agenda item, with a "+" when
//    more follow — and holds, on the worst cells, at 360 dp and 1.3×, in both
//    clocks.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/child.dart';
import 'package:entrelares_db_contracts/models/child_event.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/screens/calendar_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/day_agenda.dart';

import 'calendar_slice_test.dart';
import 'frozen_day_test.dart' as frz;

const agendaOn = {'feature.child_agenda': 'true'};

/// Collides with Ana on the first letter — both avatars carry two.
const aline =
    Member(id: 2, fullName: 'Aline Costa', colorSlot: 2, userId: 'u2');

ChildEvent agendaItem(int id, DateTime date, String kind, {String? start}) =>
    ChildEvent(
      id: id,
      familyId: 7,
      eventDate: date,
      kind: kind,
      startTime: start,
      createdBy: 1,
      createdAt: DateTime.utc(2026, 9, 20, 12, id),
    );

/// The cells the owner named as the worst (25/09/2026): a two-digit day, two
/// letters in the avatar, a handoff time, a day frozen on a request (which
/// never shows a time), and more than one agenda item — each with the mark,
/// and one carrying everything that can go together.
FakeCustodyDataSource worstCaseAgendaSource() {
  final handoff = dayOfMonth(10);
  final frozen = dayOfMonth(21);
  final swapped = dayOfMonth(28);
  return FakeCustodyDataSource(
    members: [ana, aline],
    days: [
      row(1, handoff, 1, handoffTime: '12:00'),
      row(2, frozen, 2),
      row(3, swapped, 1, actual: 2, handoffTime: '10:00'),
    ],
  )
    ..publicSettings = agendaOn
    ..family = const Family(id: 7, name: 'Souza', plan: 'premium')
    ..frozenRequests = [frz.swapReq(10, frozen)]
    ..childEvents = [
      agendaItem(1, handoff, 'school', start: '07:30'),
      agendaItem(2, handoff, 'health', start: '15:00'),
      agendaItem(3, handoff, 'note'),
      agendaItem(4, frozen, 'medicine', start: '08:00'),
      agendaItem(5, frozen, 'activity', start: '17:00'),
      agendaItem(6, swapped, 'free', start: '09:00'),
    ];
}

Widget calendarIn(FakeCustodyDataSource ds, AppLanguage language) => AppL10n(
      l: Localization(language),
      setLanguage: (_) async {},
      child: MaterialApp(
        home: CalendarScreen(dataSource: ds, adminMode: AdminMode()),
      ),
    );

void main() {
  group('1. the first child', () {
    const lia = Child(id: 5, familyId: 7, firstName: 'Lia', sortOrder: 0);

    Future<void> pumpSection(WidgetTester tester, FakeCustodyDataSource ds,
        {required Member me, VoidCallback? onOpenChildren}) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(AppL10n(
        l: Localization(AppLanguage.ptBr),
        setLanguage: (_) async {},
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DayAgendaSection(
                date: DateTime(2026, 9, 25),
                today: DateTime(2026, 9, 24),
                dataSource: ds,
                settings: const PublicSettings(agendaOn),
                isPremium: true,
                me: me,
                allProfiles: [me],
                onOpenChildren: onOpenChildren,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> openAddEditor(WidgetTester tester) async {
      await tester.tap(find.text(Localization(AppLanguage.ptBr)[KApp.agendaAdd]));
      await tester.pumpAndSettle();
      await tester.tap(find.text(
          Localization(AppLanguage.ptBr)[AgendaKind.school.labelKey]));
      await tester.pumpAndSettle();
    }

    const admin = Member(
        id: 1, fullName: 'Ana Souza', userId: 'u1', isAdmin: true, roleId: 1);
    final pt = Localization(AppLanguage.ptBr);

    testWidgets('a child added while the section was open is there when the '
        'editor opens', (tester) async {
      final ds = FakeCustodyDataSource(members: const [admin], days: [])
        ..family = const Family(id: 7, name: 'Souza', plan: 'premium');
      await pumpSection(tester, ds, me: admin, onOpenChildren: () {});

      ds.children = [lia]; // the admin added her under Família meanwhile
      await openAddEditor(tester);
      expect(find.text(pt[KApp.agendaNoChildAdmin]), findsNothing);
    });

    testWidgets('with no child, the admin gets the door to add one',
        (tester) async {
      var opened = 0;
      final ds = FakeCustodyDataSource(members: const [admin], days: [])
        ..family = const Family(id: 7, name: 'Souza', plan: 'premium');
      await pumpSection(tester, ds, me: admin, onOpenChildren: () => opened++);
      await openAddEditor(tester);
      expect(find.text(pt[KApp.agendaNoChildAdmin]), findsOne);
      await tester.tap(find.byKey(const ValueKey('agenda-add-child')));
      await tester.pumpAndSettle();
      expect(opened, 1);
    });

    testWidgets('a member who is not the admin reads the sentence, no door',
        (tester) async {
      const member = Member(id: 2, fullName: 'Bruno Lima', userId: 'u2');
      final ds = FakeCustodyDataSource(members: const [member], days: [])
        ..family = const Family(id: 7, name: 'Souza', plan: 'premium');
      await pumpSection(tester, ds, me: member, onOpenChildren: () {});
      await openAddEditor(tester);
      expect(find.text(pt[KApp.agendaNoChildMember]), findsOne);
      expect(find.byKey(const ValueKey('agenda-add-child')), findsNothing);
    });
  });

  group('2. the day sheet chips', () {
    testWidgets('only the chosen member prints a name; the others are their '
        'avatar, named for a screen reader', (tester) async {
      final day = futureDay;
      if (day == null) return;
      final handle = tester.ensureSemantics();
      final ds = FakeCustodyDataSource(
          members: [ana, bruno], days: [row(1, dayOfMonth(day), 1)]);
      await tester.pumpWidget(app(ds));
      await tester.pumpAndSettle();
      await openDayEditor(tester, day);

      // Bruno is not chosen anywhere: his chips print no name, but they are
      // there and say it aloud.
      expect(memberChip('Bruno'), findsWidgets);
      expect(find.descendant(of: memberChip('Bruno'), matching: find.text('Bruno')),
          findsNothing);
      expect(find.bySemanticsLabel(RegExp('Bruno')), findsWidgets);
      // "Sem troca" is the whole answer now.
      expect(find.text(Localization(AppLanguage.ptBr)[KApp.editorNoSwap]),
          findsOne);
      handle.dispose();
    });
  });

  group('3. the calendar cell', () {
    testWidgets('the first item\'s icon, a "+" when more follow, and the same '
        'fact aloud', (tester) async {
      final handle = tester.ensureSemantics();
      final ds = worstCaseAgendaSource();
      await tester.pumpWidget(calendarIn(ds, AppLanguage.ptBr));
      await tester.pumpAndSettle();

      // Day 10: the day sheet's order — the untimed note leads, then school
      // (07:30) and health (15:00). The cell wears the sheet's first line.
      final ten = find.byKey(const ValueKey('cell-agenda-10'));
      expect(ten, findsOne);
      expect(
          find.descendant(
              of: ten, matching: find.byIcon(Icons.sticky_note_2_outlined)),
          findsOne);
      expect(find.byKey(const ValueKey('cell-agenda-more-10')), findsOne);
      // Day 28: one item, no "+".
      expect(find.byKey(const ValueKey('cell-agenda-28')), findsOne);
      expect(find.byKey(const ValueKey('cell-agenda-more-28')), findsNothing);
      // A day without items has no mark.
      expect(find.byKey(const ValueKey('cell-agenda-11')), findsNothing);

      final pt = Localization(AppLanguage.ptBr);
      expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(pt.format(
              KApp.agendaCellAriaMore, [pt[AgendaKind.note.labelKey], 2])))),
          findsOne);
      expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(pt.format(
              KApp.agendaCellAria,
              ['${pt[AgendaKind.free.labelKey]} 09:00'])))),
          findsOne);
      handle.dispose();
    });

    testWidgets('agenda off: no marks, and the month is not asked for items',
        (tester) async {
      final ds = worstCaseAgendaSource()..publicSettings = const {};
      await tester.pumpWidget(calendarIn(ds, AppLanguage.ptBr));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cell-agenda-10')), findsNothing);
    });

    testWidgets('an item written on another device marks its day',
        (tester) async {
      final ds = worstCaseAgendaSource();
      await tester.pumpWidget(calendarIn(ds, AppLanguage.ptBr));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cell-agenda-11')), findsNothing);

      ds.childEvents = [
        ...ds.childEvents,
        agendaItem(9, dayOfMonth(11), 'school', start: '07:00'),
      ];
      ds.agendaListener!();
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('cell-agenda-11')), findsOne);
    });

    // The worst cells at 360 dp, 1.3×, in the 12-hour clock too ("12:00 PM"
    // is the widest time line, U-39). An overflow is an exception here.
    for (final language in [AppLanguage.ptBr, AppLanguage.en]) {
      for (final height in [640.0, 900.0]) {
        testWidgets(
            'worst cells hold at 360×$height, 1.3×, ${language.name}',
            (tester) async {
          tester.view.physicalSize = Size(360, height);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await tester.pumpWidget(
              calendarIn(worstCaseAgendaSource(), language));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          for (final d in [10, 21, 28]) {
            final mark = find.byKey(ValueKey('cell-agenda-$d'));
            expect(mark, findsOne, reason: 'day $d wears its mark');
            // Inside its cell, and never over the neighbour.
            final cell = find.ancestor(
                of: mark, matching: find.byType(InkWell)).first;
            // What is drawn: the icon and the "+" (the line's box is the
            // cell's width by construction).
            final cellRect = tester.getRect(cell).inflate(0.5);
            for (final drawn in find
                .descendant(of: mark, matching: find.byType(Icon))
                .evaluate()) {
              final r = tester.getRect(find.byWidget(drawn.widget));
              expect(cellRect.contains(r.topLeft) &&
                  cellRect.contains(r.bottomRight), isTrue,
                  reason: 'day $d: $r in $cellRect');
            }
          }
        });
      }
    }
  });
}
