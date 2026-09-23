/// Client mirrors of the Rotation Wizard rules — ported from `entrelares-app`
/// `Entrelares/Pages/Components/ScheduleWizard.razor` (presets, block
/// validation, cycle preview and the plan expansion). The generation is pure:
/// the DB's `enforce_day_protection` still guards every row the bulk upsert
/// writes, and existing days are preserved server-side (the upsert skips
/// them — `WizDoneKept`).
library;

import 'date_math.dart';
import 'freemium_rules.dart';

/// One block of the rotation cycle: [profileId] keeps the child for [days]
/// consecutive days. `profileId == 0` mirrors the web's "not picked yet".
class CycleBlock {
  final int profileId;
  final int days;

  const CycleBlock(this.profileId, this.days);
}

/// The preset ids, in menu order. The VALUES are pattern ids and never change
/// with the language — only the labels do (U-13).
const wizardPresetIds = ['7-7', '14-14', '1-1', '5-2-2-5', '2-2-3'];

/// Mirror of `ApplyPresetBlocks`: expands a preset id over the first two
/// profiles ([profileIds] in roster order; missing slots become 0 and fail
/// validation later). Unknown ids fall back to 7/7 like the web.
List<CycleBlock> wizardPresetBlocks(String preset, List<int> profileIds) {
  final p1 = profileIds.isNotEmpty ? profileIds[0] : 0;
  final p2 = profileIds.length > 1 ? profileIds[1] : 0;
  return switch (preset) {
    '7-7' => [CycleBlock(p1, 7), CycleBlock(p2, 7)],
    '14-14' => [CycleBlock(p1, 14), CycleBlock(p2, 14)],
    '1-1' => [CycleBlock(p1, 1), CycleBlock(p2, 1)],
    '5-2-2-5' => [
        CycleBlock(p1, 5),
        CycleBlock(p2, 2),
        CycleBlock(p1, 2),
        CycleBlock(p2, 5),
      ],
    '2-2-3' => [
        CycleBlock(p1, 2),
        CycleBlock(p2, 2),
        CycleBlock(p1, 3),
        CycleBlock(p2, 2),
        CycleBlock(p1, 2),
        CycleBlock(p2, 3),
      ],
    _ => [CycleBlock(p1, 7), CycleBlock(p2, 7)],
  };
}

/// Mirror of `SetBlockDays`' `Math.Clamp(days, 1, 60)`.
int clampBlockDays(int days) => days < 1 ? 1 : (days > 60 ? 60 : days);

/// The validation failures of `GenerateSchedule`, in check order. The UI maps
/// each to its catalogue key (the web still carries two pre-U-13 hardcoded
/// PT-BR strings for the first and third — the RULE is what ports, the copy
/// lives in the catalogue here).
enum WizardValidationError {
  /// F-28: with N caregivers the rotation is any non-empty block list.
  tooFewBlocks,
  blockWithoutParent,
  blockWithoutDays,
  startInPast,

  /// F-39: the start itself must be within the family's planning horizon.
  startBeyondHorizon,

  /// U-55: the handoff time was neither picked nor declared absent. Checked
  /// LAST, and rendered on the field itself rather than in the sheet's
  /// banner — it is the one failure that belongs to a single control.
  handoffUnanswered,
}

/// U-55: the wizard's handoff time is a QUESTION, not an optional field.
/// Family 19 planned 365 days with none (21/09/2026) because the field could
/// be scrolled past, and a day without a time anchors urgency (F-22), the
/// F-24/F-60 deadline and the F-52 estimate at MIDNIGHT. So the answer is a
/// time or an explicit "não temos horário fixo" — never a default: a guessed
/// 18:00 would be a wrong deadline written into every transition day.
enum WizardHandoffAnswer {
  unanswered,
  time,

  /// Behaves exactly like the null the field used to allow.
  noFixedTime,
}

/// Picking a time wins over a stale "none": the UI clears one when the other
/// is chosen, and this keeps the rule right even if it did not.
WizardHandoffAnswer wizardHandoffAnswer({
  required bool hasTime,
  required bool declaredNone,
}) =>
    hasTime
        ? WizardHandoffAnswer.time
        : (declaredNone
            ? WizardHandoffAnswer.noFixedTime
            : WizardHandoffAnswer.unanswered);

/// Mirror of the validation prologue of `GenerateSchedule` — first failure
/// wins, null = valid.
WizardValidationError? validateWizard({
  required List<CycleBlock> blocks,
  required DateTime start,
  required DateTime today,
  DateTime? maxScheduleDate,
  required WizardHandoffAnswer handoff,
}) {
  if (blocks.isEmpty) return WizardValidationError.tooFewBlocks;
  if (blocks.any((b) => b.profileId == 0)) {
    return WizardValidationError.blockWithoutParent;
  }
  if (blocks.any((b) => b.days < 1)) return WizardValidationError.blockWithoutDays;
  if (dateOnly(start).isBefore(dateOnly(today))) {
    return WizardValidationError.startInPast;
  }
  if (isStartBeyondHorizon(start, maxScheduleDate)) {
    return WizardValidationError.startBeyondHorizon;
  }
  if (handoff == WizardHandoffAnswer.unanswered) {
    return WizardValidationError.handoffUnanswered;
  }
  return null;
}

/// Mirror of `GetCycleSummary`'s arithmetic — the preview's numbers
/// (`WizCycleSummary` formats them). Month addition clamps like .NET.
({int cycleDays, int repetitions, int totalDays}) wizardCycleSummary({
  required List<CycleBlock> blocks,
  required DateTime start,
  required int durationMonths,
}) {
  final cycleDays = blocks.fold(0, (sum, b) => sum + b.days);
  final totalDays = addMonthsClamped(dateOnly(start), durationMonths)
      .difference(dateOnly(start))
      .inDays;
  return (
    cycleDays: cycleDays,
    repetitions: cycleDays > 0 ? totalDays ~/ cycleDays : 0,
    totalDays: totalDays,
  );
}

/// One generated day of the plan.
class GeneratedDay {
  final DateTime date;
  final int scheduledParentId;

  /// Set only on TRANSITION days when the wizard carries a handoff time.
  final ({int hour, int minute})? handoffTime;

  const GeneratedDay(this.date, this.scheduledParentId, this.handoffTime);
}

/// Mirror of the expansion loop in `GenerateSchedule`: walks [start, end)
/// cycling through [blocks]. T-27: a handoff time lands only on TRANSITION
/// days — and the wizard's local rule deliberately differs from the
/// calendar's [isTransitionDay]: the FIRST generated day has no previous
/// parent and gets NO handoff (custody isn't changing hands mid-plan there).
/// [end] arrives already clamped by [clampScheduleEnd] (F-39).
List<GeneratedDay> generateRotation({
  required DateTime start,
  required DateTime end,
  required List<CycleBlock> blocks,
  ({int hour, int minute})? handoffTime,
}) {
  final result = <GeneratedDay>[];
  if (blocks.isEmpty) return result;
  var current = dateOnly(start);
  final last = dateOnly(end);
  var blockIndex = 0;
  var dayInBlock = 0;
  int? previousParentId;
  while (current.isBefore(last)) {
    final block = blocks[blockIndex];
    final isTransition =
        previousParentId != null && previousParentId != block.profileId;
    result.add(GeneratedDay(
      current,
      block.profileId,
      isTransition && handoffTime != null ? handoffTime : null,
    ));
    previousParentId = block.profileId;
    dayInBlock++;
    if (dayInBlock >= block.days) {
      dayInBlock = 0;
      blockIndex = (blockIndex + 1) % blocks.length;
    }
    current = DateTime(current.year, current.month, current.day + 1);
  }
  return result;
}

// ── U-41 · the preview strip ──────────────────────────────────────────────
//
// The wizard's preview used to be ONE sentence of arithmetic ("14 days per
// cycle · repeats ~6× · 84 days"), which never answers the question a parent
// actually has — who has the child on which weekday. The strip is the
// calendar about to be born: [generateRotation]'s first N days, painted in
// the carers' slot colours. Nothing here is a new rule; these two helpers
// only decide how MANY days the strip shows and how a screen reader hears
// them.

/// The strip shows TWO cycles so the reader sees the pattern come round…
const cycleStripMinDays = 14;

/// …with a floor of two weeks (a 1/1 cycle is 2 days, and four cells say
/// nothing about weekdays) and a ceiling of four weeks (the sheet is a
/// phone-height surface; a 30/30 cycle shows its first month and the reader
/// scrolls the real calendar for the rest).
const cycleStripMaxDays = 28;

/// How many days the preview strip renders for a cycle of [cycleDays].
int cycleStripLength(int cycleDays) {
  final twoCycles = cycleDays * 2;
  if (twoCycles < cycleStripMinDays) return cycleStripMinDays;
  if (twoCycles > cycleStripMaxDays) return cycleStripMaxDays;
  return twoCycles;
}

/// One run of consecutive strip days with the same planned responsible —
/// what a screen reader hears instead of N coloured squares ("Ana for 5 days,
/// Bruno for 2 days, …").
class CycleRun {
  final int profileId;
  final int days;

  const CycleRun(this.profileId, this.days);

  @override
  bool operator ==(Object other) =>
      other is CycleRun && other.profileId == profileId && other.days == days;

  @override
  int get hashCode => Object.hash(profileId, days);

  @override
  String toString() => 'CycleRun($profileId × $days)';
}

/// Collapses [days] into runs, in order. An empty strip has no runs.
List<CycleRun> cycleStripRuns(List<GeneratedDay> days) {
  final runs = <CycleRun>[];
  for (final day in days) {
    if (runs.isNotEmpty && runs.last.profileId == day.scheduledParentId) {
      runs[runs.length - 1] =
          CycleRun(day.scheduledParentId, runs.last.days + 1);
    } else {
      runs.add(CycleRun(day.scheduledParentId, 1));
    }
  }
  return runs;
}
