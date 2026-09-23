/// The Rotation Wizard rules had no C# unit suite — they were inline in
/// `ScheduleWizard.razor` (the E2E pack covered them end-to-end). These pin
/// the port: presets, validation order, the preview arithmetic and the
/// expansion loop, whose transition rule deliberately differs from the
/// calendar's (the FIRST generated day gets no handoff).
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

final _today = DateTime(2026, 8, 19);

void main() {
  group('wizardPresetBlocks', () {
    const profiles = [10, 20];
    test('7-7 alternates the first two profiles', () {
      final blocks = wizardPresetBlocks('7-7', profiles);
      expect(blocks.map((b) => (b.profileId, b.days)),
          [(10, 7), (20, 7)]);
    });
    test('5-2-2-5 mirrors the web pattern', () {
      final blocks = wizardPresetBlocks('5-2-2-5', profiles);
      expect(blocks.map((b) => (b.profileId, b.days)),
          [(10, 5), (20, 2), (10, 2), (20, 5)]);
    });
    test('2-2-3 expands to the six-block fortnight', () {
      final blocks = wizardPresetBlocks('2-2-3', profiles);
      expect(blocks.map((b) => (b.profileId, b.days)),
          [(10, 2), (20, 2), (10, 3), (20, 2), (10, 2), (20, 3)]);
    });
    test('unknown preset falls back to 7-7', () {
      final blocks = wizardPresetBlocks('nope', profiles);
      expect(blocks.map((b) => (b.profileId, b.days)),
          [(10, 7), (20, 7)]);
    });
    test('missing profiles become 0 (and fail validation later)', () {
      final blocks = wizardPresetBlocks('7-7', const [10]);
      expect(blocks.map((b) => b.profileId), [10, 0]);
    });
  });

  group('clampBlockDays', () {
    test('mirrors Math.Clamp(days, 1, 60)', () {
      expect(clampBlockDays(0), 1);
      expect(clampBlockDays(30), 30);
      expect(clampBlockDays(99), 60);
    });
  });

  group('validateWizard (first failure wins)', () {
    test('valid input passes', () {
      expect(
          validateWizard(
            blocks: const [CycleBlock(10, 7), CycleBlock(20, 7)],
            start: _today,
            today: _today,
            handoff: WizardHandoffAnswer.time,
          ),
          isNull);
    });
    test('empty cycle', () {
      expect(
          validateWizard(
              blocks: const [],
              start: _today,
              today: _today,
              handoff: WizardHandoffAnswer.time),
          WizardValidationError.tooFewBlocks);
    });
    test('a block without a parent', () {
      expect(
          validateWizard(
            blocks: const [CycleBlock(10, 7), CycleBlock(0, 7)],
            start: _today,
            today: _today,
            handoff: WizardHandoffAnswer.time,
          ),
          WizardValidationError.blockWithoutParent);
    });
    test('a block without days', () {
      expect(
          validateWizard(
            blocks: const [CycleBlock(10, 0)],
            start: _today,
            today: _today,
            handoff: WizardHandoffAnswer.time,
          ),
          WizardValidationError.blockWithoutDays);
    });
    test('start in the past', () {
      expect(
          validateWizard(
            blocks: const [CycleBlock(10, 7)],
            start: DateTime(2026, 8, 18),
            today: _today,
            handoff: WizardHandoffAnswer.time,
          ),
          WizardValidationError.startInPast);
    });
    test('start beyond the horizon (F-39)', () {
      expect(
          validateWizard(
            blocks: const [CycleBlock(10, 7)],
            start: DateTime(2027, 3, 1),
            today: _today,
            maxScheduleDate: DateTime(2027, 2, 19),
            handoff: WizardHandoffAnswer.time,
          ),
          WizardValidationError.startBeyondHorizon);
    });
    test('U-55: an unanswered handoff fails, and only after the others', () {
      expect(
          validateWizard(
            blocks: const [CycleBlock(10, 7)],
            start: _today,
            today: _today,
            handoff: WizardHandoffAnswer.unanswered,
          ),
          WizardValidationError.handoffUnanswered);
      expect(
          validateWizard(
            blocks: const [CycleBlock(0, 7)],
            start: _today,
            today: _today,
            handoff: WizardHandoffAnswer.unanswered,
          ),
          WizardValidationError.blockWithoutParent);
    });
    test('U-55: "não temos horário fixo" is an answer', () {
      expect(
          validateWizard(
            blocks: const [CycleBlock(10, 7)],
            start: _today,
            today: _today,
            handoff: WizardHandoffAnswer.noFixedTime,
          ),
          isNull);
    });
    test('U-55: the answer — a time wins over a stale "none"', () {
      expect(wizardHandoffAnswer(hasTime: false, declaredNone: false),
          WizardHandoffAnswer.unanswered);
      expect(wizardHandoffAnswer(hasTime: false, declaredNone: true),
          WizardHandoffAnswer.noFixedTime);
      expect(wizardHandoffAnswer(hasTime: true, declaredNone: false),
          WizardHandoffAnswer.time);
      expect(wizardHandoffAnswer(hasTime: true, declaredNone: true),
          WizardHandoffAnswer.time);
    });
    test('today itself is a valid start', () {
      expect(
          validateWizard(
            blocks: const [CycleBlock(10, 7)],
            start: DateTime(2026, 8, 19, 23, 0),
            today: _today,
            handoff: WizardHandoffAnswer.time,
          ),
          isNull);
    });
  });

  group('wizardCycleSummary', () {
    test('mirrors GetCycleSummary\'s arithmetic', () {
      final summary = wizardCycleSummary(
        blocks: const [CycleBlock(10, 7), CycleBlock(20, 7)],
        start: DateTime(2026, 9, 1),
        durationMonths: 3,
      );
      // Sep 1 + 3 months = Dec 1 → 91 days; 91 ~/ 14 = 6 repetitions.
      expect(summary.cycleDays, 14);
      expect(summary.totalDays, 91);
      expect(summary.repetitions, 6);
    });
    test('zero cycle days yields zero repetitions, never a division error', () {
      final summary = wizardCycleSummary(
          blocks: const [], start: DateTime(2026, 9, 1), durationMonths: 1);
      expect(summary.cycleDays, 0);
      expect(summary.repetitions, 0);
    });
  });

  group('generateRotation', () {
    test('walks [start, end) cycling through the blocks', () {
      final days = generateRotation(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 7),
        blocks: const [CycleBlock(10, 2), CycleBlock(20, 1)],
      );
      expect(days.map((d) => d.scheduledParentId), [10, 10, 20, 10, 10, 20]);
      expect(days.first.date, DateTime(2026, 9, 1));
      expect(days.last.date, DateTime(2026, 9, 6)); // end is exclusive
    });

    test('handoff lands only on transition days — never the first day', () {
      final days = generateRotation(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 5),
        blocks: const [CycleBlock(10, 2), CycleBlock(20, 2)],
        handoffTime: (hour: 18, minute: 0),
      );
      // Days: 10, 10, 20, 20 — only day 3 (10→20) is a transition.
      expect(days.map((d) => d.handoffTime), [
        null,
        null,
        (hour: 18, minute: 0),
        null,
      ]);
    });

    test('no handoff time set: every day null even on transitions', () {
      final days = generateRotation(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 3),
        blocks: const [CycleBlock(10, 1), CycleBlock(20, 1)],
      );
      expect(days.map((d) => d.handoffTime), [null, null]);
    });

    test('a single-profile cycle never transitions', () {
      final days = generateRotation(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 4),
        blocks: const [CycleBlock(10, 1)],
        handoffTime: (hour: 18, minute: 0),
      );
      expect(days.every((d) => d.handoffTime == null), isTrue);
    });

    test('clamped end (F-39) bounds the walk', () {
      final clamped = clampScheduleEnd(
          addMonthsClamped(DateTime(2026, 9, 1), 12), DateTime(2026, 9, 10));
      expect(clamped.clamped, isTrue);
      final days = generateRotation(
        start: DateTime(2026, 9, 1),
        end: clamped.end,
        blocks: const [CycleBlock(10, 7), CycleBlock(20, 7)],
      );
      expect(days.length, 9);
    });

    test('crosses month boundaries day by day', () {
      final days = generateRotation(
        start: DateTime(2026, 8, 30),
        end: DateTime(2026, 9, 2),
        blocks: const [CycleBlock(10, 1)],
      );
      expect(days.map((d) => d.date), [
        DateTime(2026, 8, 30),
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 1),
      ]);
    });
  });

  group('U-41 · cycleStripLength', () {
    test('two cycles, floored at two weeks and capped at four', () {
      expect(cycleStripLength(7), 14); // 7/7
      expect(cycleStripLength(28), 28); // 14/14
      expect(cycleStripLength(2), 14); // 1/1 — four cells say nothing
      expect(cycleStripLength(14), 28); // 5/2/2/5 and 2/2/3
      expect(cycleStripLength(10), 20); // a custom 5/5
      expect(cycleStripLength(60), 28); // 30/30 — a phone-height sheet
      expect(cycleStripLength(0), 14); // no blocks: the floor, harmless
    });

    test('every preset renders whole cycles', () {
      for (final preset in wizardPresetIds) {
        final cycle = wizardPresetBlocks(preset, const [10, 20])
            .fold(0, (sum, b) => sum + b.days);
        expect(cycleStripLength(cycle) % cycle, 0, reason: preset);
      }
    });
  });

  group('U-41 · cycleStripRuns', () {
    test('collapses consecutive days into runs, in order', () {
      final days = generateRotation(
        start: _today,
        end: DateTime(2026, 9, 2), // 14 days
        blocks: const [
          CycleBlock(10, 5),
          CycleBlock(20, 2),
          CycleBlock(10, 2),
          CycleBlock(20, 5),
        ],
      );
      expect(cycleStripRuns(days), const [
        CycleRun(10, 5),
        CycleRun(20, 2),
        CycleRun(10, 2),
        CycleRun(20, 5),
      ]);
    });

    test('adjacent blocks of the SAME carer merge — the reader hears one run',
        () {
      final days = generateRotation(
        start: _today,
        end: DateTime(2026, 8, 25),
        blocks: const [CycleBlock(10, 2), CycleBlock(10, 2), CycleBlock(20, 2)],
      );
      expect(cycleStripRuns(days), const [CycleRun(10, 4), CycleRun(20, 2)]);
    });

    test('an empty strip has no runs', () {
      expect(cycleStripRuns(const []), isEmpty);
    });
  });
}
