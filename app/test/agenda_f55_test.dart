// F-55 (PR 2) — the day agenda on screen.
//
// The server is the rule; these pin what the client decides to OFFER: the
// section replaces the Observação only with `feature.child_agenda` on, a free
// family is offered the note alone (and none once its notes are used), the
// past is read-only, a refusal keeps the editor open with the server's words,
// and a delete asks first.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/child.dart';
import 'package:entrelares_db_contracts/models/child_event.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_app/screens/day_sheet.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';
import 'package:entrelares_app/widgets/day_agenda.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const ana = Member(
    id: 1, fullName: 'Ana Souza', userId: 'u1', isAdmin: true, roleId: 1);
const bruno = Member(id: 2, fullName: 'Bruno Lima', userId: 'u2', roleId: 2);
const lia = Child(id: 5, familyId: 7, firstName: 'Lia', sortOrder: 0);

final today = DateTime(2026, 9, 24);
final tomorrow = DateTime(2026, 9, 25);

const on = {'feature.child_agenda': 'true'};

FakeCustodyDataSource source({
  List<ChildEvent> events = const [],
  List<Child> children = const [lia],
}) =>
    FakeCustodyDataSource(members: const [ana, bruno], days: [])
      ..family = const Family(id: 7, name: 'Souza', plan: 'free')
      ..publicSettings = on
      ..children = List.of(children)
      ..childEvents = List.of(events);

ChildEvent event(int id, String kind,
        {DateTime? date,
        String? start,
        String? body,
        int? childId,
        int? createdBy = 2,
        int? source}) =>
    ChildEvent(
      id: id,
      familyId: 7,
      eventDate: date ?? tomorrow,
      kind: kind,
      startTime: start,
      body: body,
      childId: childId,
      createdBy: createdBy,
      sourceScheduleId: source,
      createdAt: DateTime.utc(2026, 9, 20, 12),
    );

Future<void> pumpSection(
  WidgetTester tester,
  FakeCustodyDataSource ds, {
  DateTime? date,
  bool isPremium = true,
  Map<String, String> settings = on,
  VoidCallback? onOpenPlan,
}) async {
  await tester.binding.setSurfaceSize(const Size(420, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DayAgendaSection(
            date: date ?? tomorrow,
            today: today,
            dataSource: ds,
            settings: PublicSettings(settings),
            isPremium: isPremium,
            me: bruno,
            allProfiles: const [ana, bruno],
            onOpenPlan: onOpenPlan,
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  group('the section', () {
    testWidgets('an empty day says so, and offers the add door',
        (tester) async {
      await pumpSection(tester, source());
      expect(find.byKey(const ValueKey('day-agenda-empty')), findsOne);
      expect(find.byKey(const ValueKey('day-agenda-add')), findsOne);
    });

    testWidgets('entries read as the timeline: untimed first, then by hour',
        (tester) async {
      await pumpSection(
          tester,
          source(events: [
            event(1, 'medicine', start: '14:00', childId: 5, body: '5 ml'),
            event(2, 'note', body: 'levar o casaco'),
            event(3, 'school', start: '07:30', childId: 5),
          ]));
      final order = [
        for (final id in [2, 3, 1])
          tester
              .getTopLeft(find.byKey(ValueKey('day-agenda-entry-$id')))
              .dy,
      ];
      expect(order, orderedEquals([...order]..sort()));
      expect(find.text('14:00 · Remédio · Lia'), findsOne);
      expect(find.text('5 ml'), findsOne);
      expect(find.text(l.format(KApp.agendaBy, ['Bruno Lima'])), findsWidgets);
    });

    testWidgets('a converted note says where it came from', (tester) async {
      await pumpSection(
          tester,
          source(events: [
            event(9, 'note', body: 'pediatra', createdBy: null, source: 44),
          ]));
      expect(find.text(l[KApp.agendaFromObservation]), findsOne);
    });

    testWidgets('a past day is read-only — no add, no pencil', (tester) async {
      final yesterday = DateTime(2026, 9, 23);
      await pumpSection(
          tester, source(events: [event(1, 'note', date: yesterday, body: 'x')]),
          date: yesterday);
      expect(find.byKey(const ValueKey('day-agenda-add')), findsNothing);
      expect(find.byKey(const ValueKey('day-agenda-edit-1')), findsNothing);
      expect(find.text(l[KApp.agendaReadOnlyPast]), findsOne);
    });
  });

  group('the free family', () {
    testWidgets('is offered the note alone, and told the number the key says',
        (tester) async {
      var opened = 0;
      await pumpSection(tester, source(),
          isPremium: false, onOpenPlan: () => opened++);
      final banner = find.byKey(const ValueKey('day-agenda-free'));
      expect(banner, findsOne);
      expect(find.text(l.format(KApp.agendaFreeNotesOne, [1])), findsOne);
      await tester.tap(find.text(l[K.famSeePremium]));
      expect(opened, 1);

      await tester.tap(find.byKey(const ValueKey('day-agenda-add')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agenda-kind-note')), findsOne);
      expect(find.byKey(const ValueKey('agenda-kind-school')), findsNothing);
    });

    testWidgets('with its note used, no add door is offered', (tester) async {
      await pumpSection(tester, source(events: [event(1, 'note', body: 'x')]),
          isPremium: false);
      expect(find.byKey(const ValueKey('day-agenda-add')), findsNothing);
    });

    testWidgets('a Premium event of a lapsed family has no pencil',
        (tester) async {
      await pumpSection(
          tester,
          source(events: [
            event(1, 'school', start: '07:30', childId: 5),
            event(2, 'note', body: 'x'),
          ]),
          isPremium: false);
      expect(find.byKey(const ValueKey('day-agenda-edit-1')), findsNothing);
      expect(find.byKey(const ValueKey('day-agenda-edit-2')), findsOne);
      expect(find.text(l[KApp.agendaReadOnlyPremium]), findsOne);
    });
  });

  group('the editor', () {
    testWidgets('Premium adds a school shift for the only child',
        (tester) async {
      final ds = source();
      await pumpSection(tester, ds);
      await tester.tap(find.byKey(const ValueKey('day-agenda-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('agenda-kind-school')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const ValueKey('agenda-body')), 'turma B');
      await tester.tap(find.text(l[K.commonSave]));
      await tester.pumpAndSettle();
      expect(ds.eventWrites, ['add:school:5:-:-:turma B']);
      expect(find.text(l[KApp.agendaSaved]), findsOne);
      expect(find.text('Escola · Lia'), findsOne);
    });

    testWidgets('a note without text never reaches the server',
        (tester) async {
      final ds = source();
      await pumpSection(tester, ds);
      await tester.tap(find.byKey(const ValueKey('day-agenda-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l[K.commonSave]));
      await tester.pumpAndSettle();
      expect(ds.eventWrites, isEmpty);
      expect(find.text('Escreva o texto da nota.'), findsOne);
    });

    testWidgets('a structured kind with no child registered says who adds it',
        (tester) async {
      final ds = source(children: const []);
      await pumpSection(tester, ds);
      await tester.tap(find.byKey(const ValueKey('day-agenda-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('agenda-kind-health')));
      await tester.pumpAndSettle();
      expect(find.text(l[KApp.agendaNoChildMember]), findsOne);
    });

    testWidgets('a server refusal keeps the editor open with its sentence',
        (tester) async {
      final ds = source()
        ..throwOnEventWrite = Exception('{"code":"23514","message":'
            '"No plano gratuito, a agenda aceita 1 nota(s) por dia. '
            'Com o Premium, as notas não têm limite."}');
      await pumpSection(tester, ds);
      await tester.tap(find.byKey(const ValueKey('day-agenda-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('agenda-body')), 'x');
      await tester.tap(find.text(l[K.commonSave]));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('agenda-body')), findsOne);
      expect(find.textContaining('No plano gratuito'), findsOne);
    });

    testWidgets('deleting asks first, in the editor, then removes',
        (tester) async {
      final ds = source(events: [event(1, 'note', body: 'casaco')]);
      await pumpSection(tester, ds);
      await tester.tap(find.byKey(const ValueKey('day-agenda-edit-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('agenda-delete')));
      await tester.pumpAndSettle();
      expect(ds.eventWrites, isEmpty);
      final confirm = find.byKey(const ValueKey('agenda-delete-confirm'));
      expect(confirm, findsOne);
      await tester.tap(find.descendant(
          of: confirm, matching: find.text(l[KApp.agendaDelete])));
      await tester.pumpAndSettle();
      expect(ds.eventWrites, ['delete:1']);
      expect(find.text(l[KApp.agendaDeleted]), findsOne);
      expect(find.byKey(const ValueKey('day-agenda-empty')), findsOne);
    });
  });

  group('the day sheet', () {
    Future<void> openSheet(WidgetTester tester, FakeCustodyDataSource ds,
        {required Map<String, String> settings}) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(AppL10n(
        l: Localization(AppLanguage.ptBr),
        setLanguage: (_) async {},
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDaySheet(
                  context: context,
                  date: tomorrow,
                  day: CareSchedule(
                    id: 70,
                    scheduleDate: tomorrow,
                    scheduledParentId: 2,
                    notes: 'observação antiga',
                  ),
                  previousDay: null,
                  members: const [ana, bruno],
                  memberViews: [ana.toView(), bruno.toView()],
                  today: today,
                  dataSource: ds,
                  ownProfileId: 2,
                  myProfile: bruno,
                  allProfiles: const [ana, bruno],
                  isPremium: true,
                  settings: PublicSettings(settings),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('agenda ON: the section replaces the observation field',
        (tester) async {
      await openSheet(tester, source(), settings: on);
      expect(find.byKey(const ValueKey('day-agenda')), findsOne);
      expect(find.text(l[K.editorDayNote]), findsNothing);
    });

    testWidgets('agenda OFF: the observation stays, no agenda', (tester) async {
      await openSheet(tester, source(), settings: const {});
      expect(find.byKey(const ValueKey('day-agenda')), findsNothing);
      expect(find.text(l[K.editorDayNote]), findsWidgets);
    });
  });
}
