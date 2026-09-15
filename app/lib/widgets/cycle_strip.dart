import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../theme/slot_pattern.dart';
import '../theme/tokens.dart';
import 'app_l10n.dart';

/// U-41 — the wizard's preview as the calendar it is about to create.
///
/// The card's sentence ("14 days per cycle · repeats ~6× · 84 days") describes
/// arithmetic; the question a parent has is *who has the child on which
/// weekday*, and for 5/2/2/5 or 2/2/3 the only way to find out used to be
/// generating and looking. This strip paints [generateRotation]'s first N
/// days — one square per day, in the carer's slot colour with the carer's
/// initial inside — laid out **Sunday-first with leading blanks, exactly like
/// the calendar grid** (owner's choice, 15/09/2026): the reader recognises the
/// position of every day rather than learning a rotated header.
///
/// The cell is the brand mark's cell (`AppBrandMark`: solid fill, `Radii.sm`),
/// not the grid's container-and-avatar one — at ~40 dp there is room for one
/// bold initial and nothing else, and the solid tone is what reads at that
/// size. A transition day carrying a handoff time wears a thin edge on its
/// left (T-27: the time lands on transitions only, so the edge says "the
/// handoff happens here"). A block whose carer is not picked yet paints slot
/// 0 — grey with the departed member's hatch — and "?", so the gap is visible
/// before the validation sentence says so.
///
/// No new rule lives here: which days, in which order, with which handoff is
/// [generateRotation]'s; the colour is [profileSlotIndex]'s; the initial is
/// [displayInitials]'s, with the grid's own collision tiers. The strip only
/// paints.
class CycleStrip extends StatelessWidget {
  /// The days to paint, in order — already cut to [cycleStripLength].
  final List<GeneratedDay> days;

  /// The family's assignable members, for colour and initial.
  final List<MemberView> views;

  const CycleStrip({super.key, required this.days, required this.views});

  /// The keyed cell for day [index] of the strip — what a test reads.
  static Key cellKey(int index) => ValueKey('wizStrip-$index');

  /// A leading blank before the start date's weekday column.
  static Key blankKey(int index) => ValueKey('wizStripBlank-$index');

  static const _columns = 7;
  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();
    final l = AppL10n.of(context).l;
    final tokens = context.tokens;
    // Sunday-first, the grid's convention: DateTime.weekday has Mon=1..Sun=7,
    // so %7 puts Sunday at 0 — the same blank count as the month view.
    final weekdayInitials = l[K.calWeekdayInitials].split(',');
    final blanks = days.first.date.weekday % _columns;
    final rows = ((blanks + days.length) / _columns).ceil();

    // U-29's lesson applied on day one: the strip says to a screen reader what
    // it paints for everyone else — one sentence of runs, never N squares.
    final runText = [
      for (final run in cycleStripRuns(days))
        l.format(
          run.days == 1 ? K.wizStripRunOne : K.wizStripRunMany,
          [_nameOf(run.profileId, l), run.days],
        ),
    ].join(', ');
    final semanticsLabel = l.format(
        K.wizStripSemantics, [l.formatDate(days.first.date), runText]);

    final headerStyle = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(fontWeight: FontWeight.bold);

    return Semantics(
      label: semanticsLabel,
      // One node: the inner initials would read as loose letters.
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final (i, w) in weekdayInitials.indexed)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(left: i == 0 ? 0 : _gap),
                    child: Center(child: Text(w, style: headerStyle)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: _gap),
          for (var row = 0; row < rows; row++)
            Padding(
              padding: EdgeInsets.only(top: row == 0 ? 0 : _gap),
              child: Row(
                children: [
                  for (var col = 0; col < _columns; col++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: col == 0 ? 0 : _gap),
                        child: _slot(context, tokens,
                            row * _columns + col - blanks),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _nameOf(int profileId, Localization l) {
    for (final v in views) {
      if (v.id == profileId) return v.fullName;
    }
    return l[K.wizStripNobody];
  }

  /// The cell at strip position [index]: a blank before the first day, a
  /// filler after the last, or the day itself.
  Widget _slot(BuildContext context, AppTokens tokens, int index) {
    if (index < 0) {
      return AspectRatio(
          aspectRatio: 1, child: SizedBox(key: blankKey(-index - 1)));
    }
    if (index >= days.length) {
      return const AspectRatio(aspectRatio: 1, child: SizedBox());
    }
    final day = days[index];
    final slot = tokens.slot(profileSlotIndex(day.scheduledParentId, views));
    final initial = displayInitials(day.scheduledParentId, views);
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        key: cellKey(index),
        decoration: BoxDecoration(
          color: slot.tone.solid,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        clipBehavior: Clip.antiAlias,
        child: CustomPaint(
          painter: SlotPatternPainter(slot.pattern, slot.tone.border),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Text(
                  initial,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1,
                        color: slot.tone.onSolid,
                      ),
                ),
              ),
              // T-27: the handoff edge, on transition days only — the rule
              // already decided which days carry a time; the strip just
              // marks them.
              if (day.handoffTime != null)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(width: 2.5, color: tokens.text),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
