import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

/// F-55 — the agenda's pure rules. The DB gate proves the server; this pins
/// what the sheet says before a round trip, and the shape of the timeline.
void main() {
  final today = DateTime(2026, 9, 24);

  group('AgendaKind', () {
    test('every wire key parses back, and nothing else does', () {
      for (final k in AgendaKind.values) {
        expect(AgendaKind.parse(k.wire), k);
      }
      expect(AgendaKind.parse('meeting'), isNull);
    });

    test('the note is the only kind without a child and outside Premium', () {
      expect(AgendaKind.values.where((k) => !k.isStructured),
          [AgendaKind.note]);
    });

    test('the picker offers every kind once, the note first', () {
      expect(AgendaRules.pickerOrder.toSet(), AgendaKind.values.toSet());
      expect(AgendaRules.pickerOrder, hasLength(AgendaKind.values.length));
      expect(AgendaRules.pickerOrder.first, AgendaKind.note);
    });
  });

  group('who may write', () {
    test('today and ahead, never the past', () {
      expect(AgendaRules.canWriteDay(today, today), isTrue);
      expect(AgendaRules.canWriteDay(DateTime(2026, 9, 25, 3), today), isTrue);
      expect(AgendaRules.canWriteDay(DateTime(2026, 9, 23), today), isFalse);
    });

    test('a lapsed family keeps its structured events read-only', () {
      bool can(AgendaKind k, bool limited) => AgendaRules.canChange(
          kind: k, day: today, today: today, freeLimited: limited);
      expect(can(AgendaKind.school, true), isFalse);
      expect(can(AgendaKind.note, true), isTrue);
      expect(can(AgendaKind.school, false), isTrue);
    });

    test('free-limited only while the gate is on and there is no Premium', () {
      expect(
          AgendaRules.freeLimited(isPremium: false, premiumOnly: true), isTrue);
      expect(
          AgendaRules.freeLimited(isPremium: true, premiumOnly: true), isFalse);
      expect(AgendaRules.freeLimited(isPremium: false, premiumOnly: false),
          isFalse);
    });

    test('notes left never goes below zero', () {
      expect(AgendaRules.notesLeft(notesOnDay: 0, freeNotesPerDay: 1), 1);
      expect(AgendaRules.notesLeft(notesOnDay: 3, freeNotesPerDay: 1), 0);
    });
  });

  group('validate — the RPC sentences', () {
    String? v({
      AgendaKind kind = AgendaKind.school,
      int? childId = 1,
      String? start,
      String? end,
      String? body,
      int max = 500,
    }) =>
        AgendaRules.validate(
            kind: kind,
            childId: childId,
            start: start,
            end: end,
            body: body,
            maxChars: max);

    test('a complete school shift passes', () {
      expect(v(start: '13:00', end: '18:00'), isNull);
    });

    test('a note needs its text', () {
      expect(v(kind: AgendaKind.note, childId: null, body: '  '),
          'Escreva o texto da nota.');
      expect(v(kind: AgendaKind.note, childId: null, body: 'casaco'), isNull);
    });

    test('an end needs a start before it', () {
      const msg = 'O horário de fim precisa vir depois do início.';
      expect(v(end: '14:00'), msg);
      expect(v(start: '15:00', end: '14:00'), msg);
      expect(v(start: '15:00', end: '15:00'), msg);
    });

    test('a structured kind needs the child', () {
      expect(v(childId: null), startsWith('Escolha a criança do evento.'));
    });

    test('the text limit is the key, not a constant', () {
      expect(v(body: 'a' * 100, max: 100), isNull);
      expect(v(body: 'a' * 101, max: 100),
          'O texto do evento é limitado a 100 caracteres.');
    });
  });

  test('the timeline: untimed first, then by start, then as written', () {
    final t0 = DateTime.utc(2026, 9, 1);
    final entries = [
      AgendaEntry(
          id: 1, kind: AgendaKind.medicine, start: '14:00', createdAt: t0),
      AgendaEntry(
          id: 2,
          kind: AgendaKind.note,
          createdAt: t0.add(const Duration(minutes: 5))),
      AgendaEntry(id: 3, kind: AgendaKind.school, start: '07:30', createdAt: t0),
      AgendaEntry(id: 4, kind: AgendaKind.free, createdAt: t0),
      AgendaEntry(
          id: 5,
          kind: AgendaKind.activity,
          start: '14:00',
          createdAt: t0.add(const Duration(hours: 1))),
    ];
    expect(AgendaRules.timeline(entries, (e) => e).map((e) => e.id),
        [4, 2, 3, 1, 5]);
  });

  test('the operator keys read their seeds until the server answers', () {
    const s = PublicSettings.unloaded;
    expect(s.agendaPremiumOnly, isTrue);
    expect(s.agendaFreeNotesPerDay, 1);
    expect(s.agendaMaxEventsPerDay, 20);
    expect(s.agendaTextMaxChars, 500);
  });

  group('the routine (PR 3)', () {
    test('routineDays: the marked weekdays, both ends inclusive', () {
      // 24/09/2026 is a Thursday (4); 05/10/2026 a Monday.
      final days = AgendaRules.routineDays(
          today, DateTime(2026, 10, 5), [1, 4]);
      expect(days, [
        DateTime(2026, 9, 24),
        DateTime(2026, 9, 28),
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 5),
      ]);
      expect(AgendaRules.routineDays(today, DateTime(2026, 9, 23), [4]),
          isEmpty);
    });

    test("weekdaysLabel: week order, deduplicated, in the reader's words",
        () {
      const ab = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
      expect(AgendaRules.weekdaysLabel([5, 1, 3, 1], (w) => ab[w - 1]),
          'seg, qua, sex');
    });

    ({
      int id,
      DateTime date,
      DateTime created,
      DateTime? deleted,
      String? batch,
      bool converted,
    }) ev(int id, int day,
            {int createdMin = 0,
            int? deletedMin,
            String? batch,
            bool converted = false}) =>
        (
          id: id,
          date: DateTime(2026, 10, day),
          created: DateTime.utc(2026, 9, 24, 12, createdMin),
          deleted: deletedMin == null
              ? null
              : DateTime.utc(2026, 9, 24, 12, deletedMin),
          batch: batch,
          converted: converted,
        );

    test('trail: a routine written in one go is ONE line; a re-apply another',
        () {
      final lines = AgendaRules.trail(
        [
          ev(1, 5, batch: 'r', deletedMin: 30),
          ev(2, 1, batch: 'r'),
          ev(3, 12, batch: 'r', createdMin: 30),
          ev(4, 2, createdMin: 10),
          ev(5, 3, converted: true),
        ],
        date: (e) => e.date,
        createdAt: (e) => e.created,
        deletedAt: (e) => e.deleted,
        batchId: (e) => e.batch,
        converted: (e) => e.converted,
      );
      String shape(AgendaTrailLine l) =>
          '${l.isRoutine ? 'R' : 'E'}${l.deleted ? '-' : '+'}'
          '${[for (final e in l.events) (e as dynamic).id].join(',')}';
      // Newest first: the re-apply (added 3, removed 1, same instant), then
      // the single event, then the first application (2 and 1, by date).
      expect(lines.map(shape).toList()..sort(),
          ['E+4', 'R+2,1', 'R+3', 'R-1']..sort());
      expect(lines.last.events.map((e) => e.id), [2, 1]);
      expect(lines.last.isRoutine, isTrue);
      expect(lines.any((l) => l.events.any((e) => e.id == 5)), isFalse);
    });
  });

  test('the push catalog names the kinds exactly as the sheet does (PR 4)',
      () {
    for (final lang in AppLanguage.values) {
      final l = Localization(lang);
      for (final (kind, key) in [
        (AgendaKind.school, K.notifRenderAgendaKindSchool),
        (AgendaKind.health, K.notifRenderAgendaKindHealth),
        (AgendaKind.medicine, K.notifRenderAgendaKindMedicine),
        (AgendaKind.activity, K.notifRenderAgendaKindActivity),
        (AgendaKind.free, K.notifRenderAgendaKindFree),
        (AgendaKind.note, K.notifRenderAgendaKindNote),
        (AgendaKind.other, K.notifRenderAgendaKindOther),
      ]) {
        expect(l[key], l[kind.labelKey], reason: '$lang ${kind.wire}');
      }
    }
  });
}
