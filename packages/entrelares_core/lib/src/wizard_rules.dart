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
const wizardPresetIds = [
  '7-7',
  '14-14',
  '1-1',
  '5-2-2-5',
  '2-2-3',
  // F-97 (owner, 05/10/2026): the most common Brazilian arrangement — the
  // child lives with one parent, the other has every other weekend (Fri–Sun),
  // optionally plus a Wednesday overnight. Both are 14-day cycles anchored on
  // a FRIDAY ([wizardPresetAnchor]).
  '3-11',
  '3-2-1-6-1-1',
];

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
    // F-97: "Fins de semana alternados (sex–dom)" — p2 has Fri, Sat, Sun;
    // p1 the eleven days until the next weekend of p2.
    '3-11' => [CycleBlock(p2, 3), CycleBlock(p1, 11)],
    // F-97: "… + pernoite de quarta" — p2's weekend, p1 Mon–Tue, p2 Wednesday,
    // p1 Thu through the next Tuesday (p1's own weekend), p2 Wednesday again,
    // p1 Thursday.
    '3-2-1-6-1-1' => [
        CycleBlock(p2, 3),
        CycleBlock(p1, 2),
        CycleBlock(p2, 1),
        CycleBlock(p1, 6),
        CycleBlock(p2, 1),
        CycleBlock(p1, 1),
      ],
    _ => [CycleBlock(p1, 7), CycleBlock(p2, 7)],
  };
}

/// F-97: the weekday a preset's cycle must start on ([DateTime.friday] for
/// the alternating weekends), or null when any day will do.
int? wizardPresetAnchor(String preset) =>
    const {'3-11': DateTime.friday, '3-2-1-6-1-1': DateTime.friday}[preset];

/// F-97: [start] moved to the next [weekday] — or kept, when it already is
/// one. Never earlier: a start in the past is refused anyway.
DateTime snapToWeekday(DateTime start, int weekday) {
  final d = dateOnly(start);
  final ahead = (weekday - d.weekday + 7) % 7;
  return DateTime(d.year, d.month, d.day + ahead);
}

/// F-97: a plan that CONTINUES one already written. [previousParentId] is
/// D-1's effective carer. For a free-weekday cycle the blocks turn so the
/// first one is the block right after the first block of that carer — a
/// 7/7 ending on Mom's week continues with Dad's, not with Mom again. An
/// anchored cycle ([anchored]) is never turned: its weekday alignment IS the
/// pattern, and turning it would move the weekends; D-1 then only feeds the
/// first day's handoff ([generateRotation]'s `previousParentId`).
List<CycleBlock> continueCycle(List<CycleBlock> blocks,
    {required int? previousParentId, required bool anchored}) {
  if (anchored || previousParentId == null || blocks.length < 2) return blocks;
  final i = blocks.indexWhere((b) => b.profileId == previousParentId);
  if (i < 0) return blocks;
  final from = (i + 1) % blocks.length;
  return [...blocks.sublist(from), ...blocks.sublist(0, from)];
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
/// parent and gets NO handoff (custody isn't changing hands mid-plan there) —
/// unless [previousParentId] says who had D-1 (F-97).
/// [end] arrives already clamped by [clampScheduleEnd] (F-39).
List<GeneratedDay> generateRotation({
  required DateTime start,
  required DateTime end,
  required List<CycleBlock> blocks,
  ({int hour, int minute})? handoffTime,
  int? previousParentId,
}) {
  final result = <GeneratedDay>[];
  if (blocks.isEmpty) return result;
  var current = dateOnly(start);
  final last = dateOnly(end);
  var blockIndex = 0;
  var dayInBlock = 0;
  // F-97: D-1's carer when the plan continues one already written — the first
  // generated day is then a real transition and gets the handoff time.
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
