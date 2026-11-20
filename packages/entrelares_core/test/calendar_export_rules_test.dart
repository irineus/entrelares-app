import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-08 — what the export to another calendar carries (owner, 20/11/2026).
void main() {
  final l = Localization(AppLanguage.ptBr);
  const ana = 1, bruno = 2, carla = 3;
  const lucas = 10, bia = 11;

  const family = CalendarExportFamily(
    familyId: 7,
    familyName: 'Silva',
    names: {ana: 'Ana', bruno: 'Bruno', carla: 'Carla'},
    childNames: {lucas: 'Lucas', bia: 'Bia'},
  );
  final perChild = CalendarExportFamily(
    familyId: 7,
    familyName: 'Silva',
    names: family.names,
    childNames: family.childNames,
    perChild: true,
    dayUrl: (d) => 'https://web.entrelares.app/?day='
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
  );

  ExportPlanDay day(int d, int who,
          {int? planned, String? handoff, int? lane, int month = 12}) =>
      ExportPlanDay(
        date: DateTime(2026, month, d),
        plannedId: planned ?? who,
        effectiveId: who,
        handoff: handoff,
        lane: lane,
      );

  final december = CalendarExportOptions(
      from: DateTime(2026, 12, 1), to: DateTime(2026, 12, 31));

  List<IcsEvent> build(List<ExportPlanDay> plan,
          {List<ExportAgendaEvent> agenda = const [],
          CalendarExportOptions? options,
          CalendarExportFamily? fam}) =>
      CalendarExportRules.build(
          plan: plan,
          agenda: agenda,
          options: options ?? december,
          family: fam ?? family,
          l: l);

  group('handoffs', () {
    test('one event per change of carer, at the handoff hour, 30 minutes',
        () {
      final events = build([
        day(30, ana, month: 11),
        day(1, ana),
        day(2, ana),
        day(3, bruno, handoff: '18:00:00'),
        day(4, bruno),
      ]);
      expect(events, hasLength(1));
      final e = events.single;
      expect(e.summary, 'Entrega: Ana → Bruno');
      expect(e.startUtc, DateTime.utc(2026, 12, 3, 21));
      expect(e.endUtc, DateTime.utc(2026, 12, 3, 21, 30));
      expect(e.uid, 'handoff-7-all-20261203@entrelares.app');
      expect(e.alarm, isNull, reason: 'reminders are off by default');
    });

    test('the first day of the period is a handoff when D-1 (read, never '
        'exported) had another carer', () {
      final events = build([day(30, bruno, month: 11), day(1, ana)]);
      expect(events.single.summary,
          'Entrega: Bruno → Ana (sem horário definido)');
      expect(events.single.allDayStart, DateTime(2026, 12, 1));
    });

    test('no set time is an all-day event that says so; a gap is no handoff',
        () {
      final events = build([
        day(1, ana),
        day(2, bruno),
        // 3 has no row: the plan has a hole, nobody hands over on the 4th.
        day(4, ana),
      ]);
      expect(events, hasLength(1));
      expect(events.single.summary,
          'Entrega: Ana → Bruno (sem horário definido)');
      expect(events.single.isAllDay, isTrue);
      expect(events.single.allDayEndExclusive, DateTime(2026, 12, 3));
    });

    test('a swapped day says who was planned', () {
      final events = build([
        day(1, bruno),
        day(2, ana, planned: bruno, handoff: '09:00'),
        day(3, bruno, handoff: '09:00'),
      ]);
      expect(events.map((e) => e.summary),
          ['Entrega: Bruno → Ana', 'Entrega: Ana → Bruno']);
      expect(events.first.description, 'Planejado: Bruno');
      expect(events.last.description, isNull);
    });

    test('"só o que envolve você" keeps the handoffs the reader gives or takes',
        () {
      final plan = [day(1, ana), day(2, bruno), day(3, carla), day(4, ana)];
      final mine = build(plan, options: december.copyWith(onlyProfileId: () => ana));
      expect(mine.map((e) => e.summary),
          ['Entrega: Ana → Bruno (sem horário definido)',
           'Entrega: Carla → Ana (sem horário definido)']);
    });

    test('reminders: 60 minutes before a timed handoff', () {
      final events = build([day(1, ana), day(2, bruno, handoff: '18:00')],
          options: december.copyWith(reminders: true));
      expect(events.single.alarm!.minutesBefore, 60);
    });
  });

  group('lanes (F-07)', () {
    test('each lane hands over on its own, and the title names the child', () {
      final events = build([
        day(1, ana, lane: lucas),
        day(2, bruno, lane: lucas, handoff: '18:00'),
        day(1, ana, lane: bia),
        day(2, ana, lane: bia),
      ], fam: perChild);
      expect(events.single.summary, 'Entrega: Ana → Bruno · Lucas');
      expect(events.single.uid, 'handoff-7-10-20261202@entrelares.app');
      expect(events.single.url, 'https://web.entrelares.app/?day=2026-12-02');
    });

    test('the children picker drops the other lanes', () {
      final plan = [
        day(1, ana, lane: lucas),
        day(2, bruno, lane: lucas),
        day(1, ana, lane: bia),
        day(2, bruno, lane: bia),
      ];
      final events = build(plan,
          fam: perChild, options: december.copyWith(children: () => {bia}));
      expect(events.single.summary,
          'Entrega: Ana → Bruno (sem horário definido) · Bia');
    });
  });

  group("each carer's days", () {
    final plan = [
      day(1, ana),
      day(2, ana),
      day(3, bruno),
      day(4, bruno),
      day(5, bruno),
      day(6, ana),
    ];
    final daysOnly = december.copyWith(handoffs: false, events: false, days: true);

    test('one all-day, free-time event per run of the same carer', () {
      final events = build(plan, options: daysOnly);
      expect(events.map((e) => e.summary), ['Com Ana', 'Com Bruno', 'Com Ana']);
      expect(events[1].allDayStart, DateTime(2026, 12, 3));
      expect(events[1].allDayEndExclusive, DateTime(2026, 12, 6));
      expect(events.every((e) => e.transparent), isTrue);
      expect(events[1].uid, 'days-7-all-20261203@entrelares.app');
    });

    test('a gap breaks the run; "só o que envolve você" keeps the reader\'s',
        () {
      final events = build([day(1, ana), day(3, ana)],
          options: daysOnly.copyWith(onlyProfileId: () => ana));
      expect(events, hasLength(2));
      expect(build(plan, options: daysOnly.copyWith(onlyProfileId: () => bruno))
          .single.summary, 'Com Bruno');
    });

    test('off by default', () {
      expect(build(plan).where((e) => e.uid.startsWith('days-')), isEmpty);
    });
  });

  group("children's events (F-55)", () {
    final plan = [day(1, ana), day(2, ana), day(3, bruno)];
    final noHandoffs = december.copyWith(handoffs: false);

    test('the kind, the child and the first line; timed in UTC', () {
      final events = build(plan, options: noHandoffs, agenda: [
        ExportAgendaEvent(
          id: 501,
          date: DateTime(2026, 12, 2),
          kind: AgendaKind.school,
          childId: lucas,
          start: '08:00',
          end: '09:30',
          body: 'Reunião de pais\nLevar o caderno',
        ),
      ]);
      final e = events.single;
      expect(e.summary, 'Escola · Lucas: Reunião de pais');
      expect(e.description, 'Reunião de pais\nLevar o caderno');
      expect(e.startUtc, DateTime.utc(2026, 12, 2, 11));
      expect(e.endUtc, DateTime.utc(2026, 12, 2, 12, 30));
      expect(e.uid, 'event-501@entrelares.app');
    });

    test('no end is one hour; no start is all-day; the note is off by default',
        () {
      final events = build(plan, options: noHandoffs, agenda: [
        ExportAgendaEvent(
            id: 1, date: DateTime(2026, 12, 1), kind: AgendaKind.health,
            childId: lucas, start: '14:00'),
        ExportAgendaEvent(
            id: 2, date: DateTime(2026, 12, 1), kind: AgendaKind.activity,
            childId: bia),
        ExportAgendaEvent(
            id: 3, date: DateTime(2026, 12, 1), kind: AgendaKind.note,
            body: 'Dia de chuva'),
      ]);
      expect(events.map((e) => e.uid),
          ['event-2@entrelares.app', 'event-1@entrelares.app']);
      final health = events.last;
      expect(health.endUtc!.difference(health.startUtc!), const Duration(hours: 1));
      expect(events.first.summary, 'Atividade · Bia');
      expect(events.first.isAllDay, isTrue);

      final withNotes = build(plan,
          options: noHandoffs.copyWith(
              kinds: {...CalendarExportRules.defaultKinds, AgendaKind.note}),
          agenda: [
            ExportAgendaEvent(
                id: 3, date: DateTime(2026, 12, 1), kind: AgendaKind.note,
                body: 'Dia de chuva'),
          ]);
      expect(withNotes.single.summary, 'Nota: Dia de chuva');
    });

    test('a deleted event goes out CANCELLED and is not counted', () {
      final events = build(plan, options: noHandoffs, agenda: [
        ExportAgendaEvent(
            id: 9, date: DateTime(2026, 12, 2), kind: AgendaKind.school,
            childId: lucas, deleted: true),
      ]);
      expect(events.single.cancelled, isTrue);
      expect(CalendarExportRules.count(events), 0);
    });

    test('"só o que envolve você": events on the reader\'s days', () {
      final agenda = [
        ExportAgendaEvent(
            id: 1, date: DateTime(2026, 12, 2), kind: AgendaKind.school,
            childId: lucas),
        ExportAgendaEvent(
            id: 2, date: DateTime(2026, 12, 3), kind: AgendaKind.school,
            childId: lucas),
      ];
      final mine = build(plan,
          options: noHandoffs.copyWith(onlyProfileId: () => bruno),
          agenda: agenda);
      expect(mine.single.uid, 'event-2@entrelares.app');
    });

    test('a long title is cut with an ellipsis', () {
      final events = build(plan, options: noHandoffs, agenda: [
        ExportAgendaEvent(
            id: 1, date: DateTime(2026, 12, 2), kind: AgendaKind.other,
            body: 'x' * 100),
      ]);
      expect(events.single.summary, 'Outro: ${'x' * 60}…');
    });

    test('reminders: the event\'s own offset, and F-105\'s eve at 19h', () {
      final events = build(plan,
          options: noHandoffs.copyWith(reminders: true),
          agenda: [
            ExportAgendaEvent(
                id: 1, date: DateTime(2026, 12, 2), kind: AgendaKind.health,
                childId: lucas, start: '10:00', remindMinutes: 30),
            ExportAgendaEvent(
                id: 2, date: DateTime(2026, 12, 3), kind: AgendaKind.health,
                childId: lucas, start: '10:00',
                remindMinutes: AgendaNotify.eveAt19),
          ]);
      expect(events.first.alarm!.minutesBefore, 30);
      expect(events.last.alarm!.atUtc, DateTime.utc(2026, 12, 2, 22));

      final off = build(plan, options: noHandoffs, agenda: [
        ExportAgendaEvent(
            id: 1, date: DateTime(2026, 12, 2), kind: AgendaKind.health,
            childId: lucas, start: '10:00', remindMinutes: 30),
      ]);
      expect(off.single.alarm, isNull);
    });
  });

  group('the file', () {
    test('every event becomes one VEVENT of a calendar named after the family',
        () {
      final events = build([day(1, ana), day(2, bruno, handoff: '18:00')],
          options: december.copyWith(days: true));
      final text = IcsWriter.write(events,
          calendarName: CalendarExportRules.calendarName(l, family),
          stampUtc: DateTime.utc(2026, 11, 20));
      expect('BEGIN:VEVENT'.allMatches(text), hasLength(events.length));
      expect(text, contains('X-WR-CALNAME:Entrelares — Silva'));
    });

    test('the name carries the period only; the props are tokens', () {
      expect(CalendarExportRules.fileName(december),
          'entrelares-20261201-20261231.ics');
      expect(CalendarExportRules.layersToken(december), 'he');
      expect(CalendarExportRules.sizeBucket(0), 'lt10');
      expect(CalendarExportRules.sizeBucket(120), 'lt200');
      expect(CalendarExportRules.sizeBucket(500), 'gte200');
      expect(CalendarExportRules.fetchFrom(DateTime(2026, 12, 1)),
          DateTime(2026, 11, 30));
    });
  });
}
