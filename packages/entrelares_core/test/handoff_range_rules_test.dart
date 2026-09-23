import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

HandoffNudgeDay _day(int dayOfMonth, int carer, {bool time = false}) =>
    HandoffNudgeDay(
        date: DateTime(2026, 9, dayOfMonth),
        effectiveParentId: carer,
        hasTime: time);

void main() {
  final pt = Localization(AppLanguage.ptBr);

  group('U-55 · showHandoffNudge', () {
    // A A B B A — transitions on the 22nd (yesterday was B), 24th and 26th.
    List<HandoffNudgeDay> plan({int? timeOn}) => [
          for (final (d, c) in [(22, 1), (23, 1), (24, 2), (25, 2), (26, 1)])
            _day(d, c, time: d == timeOn),
        ];
    final yesterday = _day(21, 2);

    test('an admin whose window has transitions and no time is offered it',
        () {
      expect(
          showHandoffNudge(
              isAdmin: true,
              dismissed: false,
              upcoming: plan(),
              yesterday: yesterday),
          isTrue);
    });

    test('one time on any transition means the family already chose', () {
      expect(
          showHandoffNudge(
              isAdmin: true,
              dismissed: false,
              upcoming: plan(timeOn: 24),
              yesterday: yesterday),
          isFalse);
    });

    test('a non-admin and a dismissed reader never see it', () {
      expect(
          showHandoffNudge(
              isAdmin: false,
              dismissed: false,
              upcoming: plan(),
              yesterday: yesterday),
          isFalse);
      expect(
          showHandoffNudge(
              isAdmin: true,
              dismissed: true,
              upcoming: plan(),
              yesterday: yesterday),
          isFalse);
    });

    test('an empty window, or one carer throughout, has nothing to offer', () {
      expect(
          showHandoffNudge(isAdmin: true, dismissed: false, upcoming: const []),
          isFalse);
      expect(
          showHandoffNudge(
              isAdmin: true,
              dismissed: false,
              upcoming: [_day(22, 1), _day(23, 1)],
              yesterday: _day(21, 1)),
          isFalse);
    });

    test('no row yesterday makes today a transition, as the database says',
        () {
      expect(
          showHandoffNudge(
              isAdmin: true,
              dismissed: false,
              upcoming: [_day(22, 1), _day(23, 1)]),
          isTrue);
    });

    test('a gap in the plan makes the next day a transition (T-27)', () {
      // Same carer on both sides of a missing day: still a transition in the
      // database (no D-1 row), and a time there counts as the family's.
      expect(
          showHandoffNudge(
              isAdmin: true,
              dismissed: false,
              upcoming: [_day(22, 1), _day(24, 1, time: true)],
              yesterday: _day(21, 1)),
          isFalse);
    });

    test('the window order does not matter', () {
      expect(
          showHandoffNudge(
              isAdmin: true,
              dismissed: false,
              upcoming: plan(timeOn: 26).reversed.toList(),
              yesterday: yesterday),
          isFalse);
    });
  });

  group('U-55 · handoffRangeSummary', () {
    test('the counts, each with its reason', () {
      expect(
          handoffRangeSummary(
              pt,
              const HandoffRangeResult(
                  updated: 12, keptFrozen: 1, keptExisting: 2)),
          '12 trocas com horário definido · 2 trocas já tinham horário '
          '(mantido) · 1 dia mantido (solicitação pendente)');
      expect(
          handoffRangeSummary(pt,
              const HandoffRangeResult(updated: 1, keptFrozen: 0, keptExisting: 0)),
          '1 troca com horário definido');
    });

    test('nothing to fill says so', () {
      expect(
          handoffRangeSummary(pt,
              const HandoffRangeResult(updated: 0, keptFrozen: 0, keptExisting: 0)),
          pt[K.handoffRangeNothing]);
    });

    test('fromJson reads the RPC answer; a missing count is zero', () {
      final r = HandoffRangeResult.fromJson(
          {'updated': 3, 'kept_frozen': 1, 'batch_id': 'b1'});
      expect(r.updated, 3);
      expect(r.keptFrozen, 1);
      expect(r.keptExisting, 0);
      expect(r.batchId, 'b1');
    });
  });

  group('U-55 · the Histórico knows the batch', () {
    test('handoff_range is its own kind', () {
      const batch = AuditBatch(batchId: 'b', kind: 'handoff_range', logs: []);
      expect(batch.isHandoff, isTrue);
      expect(batch.isReplace, isFalse);
    });
  });
}
