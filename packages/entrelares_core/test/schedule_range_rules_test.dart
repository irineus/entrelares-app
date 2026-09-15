// F-51 — the pure half of "clear planned days in one action": the range each
// entry point asks for, and the sentence each one closes with.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

final _pt = Localization(AppLanguage.ptBr);
final _en = Localization(AppLanguage.en);

void main() {
  group('monthClearRange', () {
    test('the current month runs from TODAY to its last day', () {
      final r = monthClearRange(
          visibleMonth: DateTime(2026, 9, 1), today: DateTime(2026, 9, 15))!;
      expect(r.from, DateTime(2026, 9, 15));
      expect(r.to, DateTime(2026, 9, 30));
    });

    test('a future month is whole', () {
      final r = monthClearRange(
          visibleMonth: DateTime(2026, 11, 1), today: DateTime(2026, 9, 15))!;
      expect(r.from, DateTime(2026, 11, 1));
      expect(r.to, DateTime(2026, 11, 30));
    });

    test('a past month has nothing to clear — the past is never touched', () {
      expect(
          monthClearRange(
              visibleMonth: DateTime(2026, 8, 1), today: DateTime(2026, 9, 15)),
          isNull);
    });

    test('the last day of the month clears exactly that day', () {
      final r = monthClearRange(
          visibleMonth: DateTime(2026, 9, 3), today: DateTime(2026, 9, 30))!;
      expect(r.from, DateTime(2026, 9, 30));
      expect(r.to, DateTime(2026, 9, 30));
    });

    test('time of day on the inputs never leaks into the range', () {
      final r = monthClearRange(
          visibleMonth: DateTime(2026, 9, 20, 13),
          today: DateTime(2026, 9, 15, 23, 59))!;
      expect(r.from, DateTime(2026, 9, 15));
      expect(r.to, DateTime(2026, 9, 30));
    });
  });

  group('wizardReplaceRange', () {
    test('[start, end) becomes an inclusive range ending the day before end',
        () {
      final r = wizardReplaceRange(
          start: DateTime(2026, 9, 15), end: DateTime(2026, 12, 15))!;
      expect(r.from, DateTime(2026, 9, 15));
      expect(r.to, DateTime(2026, 12, 14));
    });

    test('an empty plan has no range', () {
      expect(
          wizardReplaceRange(
              start: DateTime(2026, 9, 15), end: DateTime(2026, 9, 15)),
          isNull);
    });
  });

  test('plannedDaysInRange counts only the days inside, date-only', () {
    final range = (from: DateTime(2026, 9, 15), to: DateTime(2026, 9, 30));
    final planned = [
      DateTime(2026, 9, 14),
      DateTime(2026, 9, 15, 8),
      DateTime(2026, 9, 22),
      DateTime(2026, 9, 30, 23),
      DateTime(2026, 10, 1),
    ];
    expect(plannedDaysInRange(planned, range), 3);
  });

  group('ScheduleRangeResult.fromJson', () {
    test('reads every count and the batch id', () {
      final r = ScheduleRangeResult.fromJson({
        'deleted': 88,
        'kept_frozen': 1,
        'kept_swap': 1,
        'inserted': 90,
        'kept_existing': 2,
        'batch_id': 'b0b0',
      });
      expect(r.deleted, 88);
      expect(r.keptFrozen, 1);
      expect(r.keptSwap, 1);
      expect(r.kept, 2);
      expect(r.inserted, 90);
      expect(r.keptExisting, 2);
      expect(r.batchId, 'b0b0');
    });

    test('a plain clear answers no insert counts — they read as zero', () {
      final r = ScheduleRangeResult.fromJson(
          {'deleted': 5, 'kept_frozen': 0, 'kept_swap': 0});
      expect(r.inserted, 0);
      expect(r.keptExisting, 0);
      expect(r.batchId, isNull);
    });
  });

  group('clearRangeSummary', () {
    test('deleted and kept, by reason, joined with the middle dot', () {
      const r = ScheduleRangeResult(deleted: 5, keptFrozen: 1, keptSwap: 2);
      expect(clearRangeSummary(_pt, r),
          '5 dias apagados · 1 dia mantido (solicitação pendente) · '
          '2 dias mantidos (troca aprovada)');
      expect(clearRangeSummary(_en, r),
          '5 days cleared · 1 day kept (pending request) · '
          '2 days kept (approved swap)');
    });

    test('a single deleted day agrees in number', () {
      const r = ScheduleRangeResult(deleted: 1, keptFrozen: 0, keptSwap: 0);
      expect(clearRangeSummary(_pt, r), '1 dia apagado');
    });

    test('nothing deleted and nothing kept is the bulk "nothing to do"', () {
      const r = ScheduleRangeResult(deleted: 0, keptFrozen: 0, keptSwap: 0);
      expect(clearRangeSummary(_pt, r), _pt[K.sumNothingToDo]);
    });
  });

  group('wizardReplaceSummary', () {
    test('created, replaced and the kept reasons', () {
      const r = ScheduleRangeResult(
          deleted: 88, keptFrozen: 1, keptSwap: 1, inserted: 90,
          keptExisting: 2);
      expect(
          wizardReplaceSummary(_pt, r),
          'Plano gerado com sucesso! 90 dias criados. 88 dias do plano '
          'anterior foram substituídos. 1 dia mantido (solicitação pendente) '
          '· 1 dia mantido (troca aprovada).');
      expect(
          wizardReplaceSummary(_en, r),
          'Plan generated! 90 days created. 88 days of the '
          'previous plan were replaced. 1 day kept (pending request) · '
          '1 day kept (approved swap).');
    });

    test('a first plan over an empty range says only what it created', () {
      const r = ScheduleRangeResult(
          deleted: 0, keptFrozen: 0, keptSwap: 0, inserted: 30);
      expect(wizardReplaceSummary(_pt, r),
          'Plano gerado com sucesso! 30 dias criados.');
    });

    test('one replaced day agrees in number', () {
      const r = ScheduleRangeResult(
          deleted: 1, keptFrozen: 0, keptSwap: 0, inserted: 30);
      expect(wizardReplaceSummary(_pt, r),
          'Plano gerado com sucesso! 30 dias criados. 1 dia do plano '
          'anterior foi substituído.');
    });
  });
}
