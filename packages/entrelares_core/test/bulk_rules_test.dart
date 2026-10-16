/// Summary half: mirror of `entrelares-app`
/// `Entrelares.Tests/BulkSummaryTests.cs` — same cases, same expected strings
/// in both languages. Rules half: the pure decision rules that were inline in
/// `Home.razor` (pre-fill, eligibility/skip, S-09 kept planned parent, no-op
/// detection) — no C# unit suite existed for those; these pin the port to the
/// web's documented behaviour.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

final _pt = Localization(AppLanguage.ptBr);
final _en = Localization(AppLanguage.en);
final _today = DateTime(2026, 8, 19);

void main() {
  // F-100: press the first day, tap the last.
  group('selectionRange', () {
    test('inclusive, in either order, across months', () {
      final r = selectionRange(DateTime(2026, 12, 30), DateTime(2027, 1, 2));
      expect(r, [
        DateTime(2026, 12, 30),
        DateTime(2026, 12, 31),
        DateTime(2027, 1, 1),
        DateTime(2027, 1, 2),
      ]);
      expect(selectionRange(DateTime(2027, 1, 2), DateTime(2026, 12, 30)), r);
    });
    test('never past the planning horizon', () {
      expect(
          selectionRange(DateTime(2026, 10, 1), DateTime(2026, 10, 9),
              horizon: DateTime(2026, 10, 3)),
          [DateTime(2026, 10, 1), DateTime(2026, 10, 2), DateTime(2026, 10, 3)]);
    });
  });

  group('bulkSummary (mirror of BulkSummaryTests)', () {
    test('all parts joined with the middle dot', () {
      expect(
        bulkSummary(_pt,
            directCount: 2,
            directSingularKey: K.sumUpdatedOne,
            directPluralKey: K.sumUpdatedMany,
            swapCount: 1,
            revertCount: 1,
            skippedCount: 3,
            unchangedCount: 1),
        '2 dias atualizados · 1 solicitação de troca · 1 reversão solicitada · '
        '1 dia sem alterações · 3 dias ignorados',
      );
    });

    test('zero-count parts are omitted', () {
      expect(
        bulkSummary(_pt,
            directCount: 1,
            directSingularKey: K.sumUpdatedOne,
            directPluralKey: K.sumUpdatedMany),
        '1 dia atualizado',
      );
    });

    test('only unchanged days: reported without claiming updates (S-09)', () {
      expect(
        bulkSummary(_pt,
            directCount: 0,
            directSingularKey: K.sumUpdatedOne,
            directPluralKey: K.sumUpdatedMany,
            skippedCount: 1,
            unchangedCount: 2),
        '2 dias sem alterações · 1 dia ignorado',
      );
    });

    test('nothing happened: fallback text', () {
      expect(
        bulkSummary(_pt,
            directCount: 0,
            directSingularKey: K.sumUpdatedOne,
            directPluralKey: K.sumUpdatedMany),
        'Nenhuma alteração necessária',
      );
    });

    test('delete path uses the caller-provided noun', () {
      expect(
        bulkSummary(_pt,
            directCount: 3,
            directSingularKey: K.sumDeletedOne,
            directPluralKey: K.sumDeletedMany,
            skippedCount: 1),
        '3 dias apagados · 1 dia ignorado',
      );
    });

    test('the assembly is language-agnostic (same structure in English)', () {
      expect(
        bulkSummary(_en,
            directCount: 2,
            directSingularKey: K.sumUpdatedOne,
            directPluralKey: K.sumUpdatedMany,
            swapCount: 1,
            revertCount: 1,
            skippedCount: 3,
            unchangedCount: 1),
        '2 days updated · 1 swap request · 1 revert requested · '
        '1 day unchanged · 3 days skipped',
      );
    });

    test('nothing happened, in English', () {
      expect(
        bulkSummary(_en,
            directCount: 0,
            directSingularKey: K.sumUpdatedOne,
            directPluralKey: K.sumUpdatedMany),
        'No change needed',
      );
    });
  });

  group('bulkPluralize', () {
    // ZERO takes the plural, not the singular — easy to break when strings move.
    const cases = {1: '1 dia ignorado', 2: '2 dias ignorados', 0: '0 dias ignorados'};
    cases.forEach((count, expected) {
      test('$count → "$expected"', () {
        expect(bulkPluralize(_pt, count, K.sumSkippedOne, K.sumSkippedMany),
            expected);
      });
    });

    // PT-BR agrees the participle in gender AND number — two whole phrases
    // per count, never a stem plus "s".
    test('gender and number agreement', () {
      expect(bulkPluralize(_pt, 1, K.sumRevertOne, K.sumRevertMany),
          '1 reversão solicitada');
      expect(bulkPluralize(_pt, 2, K.sumRevertOne, K.sumRevertMany),
          '2 reversões solicitadas');
    });
  });

  group('isSelectionMode (U-11)', () {
    test('active with days selected or armed, never otherwise', () {
      expect(isSelectionMode(selectedCount: 1, armed: false), isTrue);
      expect(isSelectionMode(selectedCount: 0, armed: true), isTrue);
      expect(isSelectionMode(selectedCount: 0, armed: false), isFalse);
    });
  });

  group('bulkPrefill (mirror of OpenBulkSheet)', () {
    test('common values pre-fill each field', () {
      final prefill = bulkPrefill(const [
        BulkDayFields(
            scheduledParentId: 1,
            actualParentId: 2,
            notes: 'escola',
            handoffTime: (hour: 18, minute: 30)),
        BulkDayFields(
            scheduledParentId: 1,
            actualParentId: 2,
            notes: 'escola',
            handoffTime: (hour: 18, minute: 30)),
      ]);
      expect(prefill.scheduledParentId, 1);
      expect(prefill.actualParentId, 2);
      expect(prefill.notes, 'escola');
      expect(prefill.handoffHour, 18);
      expect(prefill.handoffMinute, 30);
    });

    test('mixed values fall to each field\'s sentinel', () {
      final prefill = bulkPrefill(const [
        BulkDayFields(
            scheduledParentId: 1,
            actualParentId: 2,
            notes: 'a',
            handoffTime: (hour: 18, minute: 0)),
        BulkDayFields(scheduledParentId: 2, notes: 'b'),
      ]);
      expect(prefill.scheduledParentId, 0);
      expect(prefill.actualParentId, 0);
      expect(prefill.notes, isNull);
      expect(prefill.handoffHour, -1);
      expect(prefill.handoffMinute, 0);
    });

    test('no existing rows: every field at its sentinel', () {
      final prefill = bulkPrefill(const []);
      expect(prefill.scheduledParentId, 0);
      expect(prefill.actualParentId, 0);
      expect(prefill.notes, isNull);
      expect(prefill.handoffHour, -1);
    });

    test('a null actual counts as 0 when comparing (web parity)', () {
      // One row with no actual + one with actual 0-equivalent state: common.
      final prefill = bulkPrefill(const [
        BulkDayFields(scheduledParentId: 1),
        BulkDayFields(scheduledParentId: 1),
      ]);
      expect(prefill.actualParentId, 0);
    });
  });

  group('bulkEligibleDays (F-13/F-12 + clear-on-approved-swap)', () {
    final existing = {
      DateTime(2026, 8, 20):
          const BulkDayFields(scheduledParentId: 1, actualParentId: 2),
      DateTime(2026, 8, 21): const BulkDayFields(scheduledParentId: 1),
    };
    BulkDayFields? lookup(DateTime d) => existing[d];

    test('past days are skipped for regular members', () {
      final result = bulkEligibleDays(
        selectedDates: [DateTime(2026, 8, 17), DateTime(2026, 8, 21)],
        today: _today,
        adminBypass: false,
        frozenDates: const [],
        existingFor: lookup,
        clearScheduledParent: false,
      );
      expect(result.eligible, [DateTime(2026, 8, 21)]);
      expect(result.skipped, 1);
    });

    test('admin bypass keeps past days (F-14)', () {
      final result = bulkEligibleDays(
        selectedDates: [DateTime(2026, 8, 17)],
        today: _today,
        adminBypass: true,
        frozenDates: const [],
        existingFor: lookup,
        clearScheduledParent: false,
      );
      expect(result.eligible, [DateTime(2026, 8, 17)]);
      expect(result.skipped, 0);
    });

    test('frozen days are never eligible — even for admins', () {
      final result = bulkEligibleDays(
        selectedDates: [DateTime(2026, 8, 21)],
        today: _today,
        adminBypass: true,
        frozenDates: [DateTime(2026, 8, 21)],
        existingFor: lookup,
        clearScheduledParent: false,
      );
      expect(result.eligible, isEmpty);
      expect(result.skipped, 1);
    });

    test('clearing skips approved-swap days (deleting would erase the swap)',
        () {
      final result = bulkEligibleDays(
        selectedDates: [DateTime(2026, 8, 20), DateTime(2026, 8, 21)],
        today: _today,
        adminBypass: false,
        frozenDates: const [],
        existingFor: lookup,
        clearScheduledParent: true,
      );
      expect(result.eligible, [DateTime(2026, 8, 21)]);
      expect(result.skipped, 1);
    });

    test('without the clear flag the approved-swap day stays eligible', () {
      final result = bulkEligibleDays(
        selectedDates: [DateTime(2026, 8, 20)],
        today: _today,
        adminBypass: false,
        frozenDates: const [],
        existingFor: lookup,
        clearScheduledParent: false,
      );
      expect(result.eligible, [DateTime(2026, 8, 20)]);
      expect(result.skipped, 0);
    });
  });

  group('bulkDayScheduled (S-09 kept planned parent)', () {
    const assigned = BulkDayFields(scheduledParentId: 1);
    test('regular user keeps the existing planned parent on assigned days', () {
      expect(
          bulkDayScheduled(
              overwriteScheduled: false,
              existing: assigned,
              bulkScheduledParentId: 2),
          1);
    });
    test('unassigned days take the bulk choice', () {
      expect(
          bulkDayScheduled(
              overwriteScheduled: false,
              existing: null,
              bulkScheduledParentId: 2),
          2);
    });
    test('admin overwrite applies the bulk choice everywhere', () {
      expect(
          bulkDayScheduled(
              overwriteScheduled: true,
              existing: assigned,
              bulkScheduledParentId: 2),
          2);
    });
  });

  group('bulkOverwriteCount (S-09 confirmation gate)', () {
    final existing = {
      DateTime(2026, 8, 20): const BulkDayFields(scheduledParentId: 1),
      DateTime(2026, 8, 21): const BulkDayFields(scheduledParentId: 2),
    };
    test('counts only assigned days whose planned parent would change', () {
      expect(
          bulkOverwriteCount(
            days: [
              DateTime(2026, 8, 20),
              DateTime(2026, 8, 21),
              DateTime(2026, 8, 22), // no row — not an overwrite
            ],
            existingFor: (d) => existing[d],
            bulkScheduledParentId: 2,
          ),
          1);
    });
  });

  group('bulkProposedActual / bulkProposedHandoff', () {
    test('a picked parent wins, Limpar clears, else the existing stays', () {
      expect(
          bulkProposedActual(
              bulkActualParentId: 3, clearActual: false,
              existingActualParentId: 2),
          3);
      expect(
          bulkProposedActual(
              bulkActualParentId: 0, clearActual: true,
              existingActualParentId: 2),
          isNull);
      expect(
          bulkProposedActual(
              bulkActualParentId: 0, clearActual: false,
              existingActualParentId: 2),
          2);
    });
    test('same precedence for the handoff time (−1 = not set)', () {
      expect(
          bulkProposedHandoff(
              bulkHour: 18,
              bulkMinute: 30,
              clearHandoff: false,
              existing: (hour: 8, minute: 0)),
          (hour: 18, minute: 30));
      expect(
          bulkProposedHandoff(
              bulkHour: -1,
              bulkMinute: 0,
              clearHandoff: true,
              existing: (hour: 8, minute: 0)),
          isNull);
      expect(
          bulkProposedHandoff(
              bulkHour: -1,
              bulkMinute: 0,
              clearHandoff: false,
              existing: (hour: 8, minute: 0)),
          (hour: 8, minute: 0));
    });
  });

  group('bulkComposeDay + bulkDayIsNoOp (the S-09 no-op regression)', () {
    const existing = BulkDayFields(
        scheduledParentId: 1,
        actualParentId: null,
        notes: 'escola',
        handoffTime: (hour: 18, minute: 0));

    test('a kept planned parent as the only "change" is a no-op', () {
      final proposed = bulkComposeDay(
        existing: existing,
        dayScheduled: 1, // S-09 kept the existing value
        bulkActualParentId: 0,
        clearActual: false,
        bulkNotes: null,
        clearNotes: false,
        bulkHour: -1,
        clearHandoff: false,
        proposedHandoff: null,
      );
      expect(bulkDayIsNoOp(existing, proposed), isTrue);
    });

    test('clearing the notes is a real change', () {
      final proposed = bulkComposeDay(
        existing: existing,
        dayScheduled: 1,
        bulkActualParentId: 0,
        clearActual: false,
        bulkNotes: null,
        clearNotes: true,
        bulkHour: -1,
        clearHandoff: false,
        proposedHandoff: null,
      );
      expect(proposed.notes, isNull);
      expect(bulkDayIsNoOp(existing, proposed), isFalse);
    });

    test('a set hour applies the transition-filtered handoff — including null',
        () {
      // T-27: the sheet set 18:30 but the day is NOT a transition, so the
      // filtered proposal is null and must WIN over the existing time.
      final proposed = bulkComposeDay(
        existing: existing,
        dayScheduled: 1,
        bulkActualParentId: 0,
        clearActual: false,
        bulkNotes: null,
        clearNotes: false,
        bulkHour: 18,
        clearHandoff: false,
        proposedHandoff: null,
      );
      expect(proposed.handoffTime, isNull);
      expect(bulkDayIsNoOp(existing, proposed), isFalse);
    });

    test('empty bulk notes never overwrite (only Limpar clears)', () {
      final proposed = bulkComposeDay(
        existing: existing,
        dayScheduled: 1,
        bulkActualParentId: 0,
        clearActual: false,
        bulkNotes: '',
        clearNotes: false,
        bulkHour: -1,
        clearHandoff: false,
        proposedHandoff: null,
      );
      expect(proposed.notes, 'escola');
    });
  });
}
