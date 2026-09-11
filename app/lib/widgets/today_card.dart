import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_l10n.dart';

/// Today at a Glance — port of `TodayCard.razor`. A dumb presentational
/// widget: every rule arrives computed ([TodayGlance] and the pure helpers in
/// core); the card only renders. The bottom half is a 3-way branch in the
/// web's precedence order: invite nudge (F-31) > today's responsible >
/// no-responsible hint.
///
/// U-28 rebuilt the look, not the rules. Three things were wrong:
///
/// * **Colour had been demoted to a 4 px stripe.** The web tints the whole
///   responsible band, which is what makes "who has the child today" readable
///   from across the room; the port left the band neutral with a hairline of
///   colour on its left edge. The band is filled again — `tone.container` with
///   `tone.onContainer` text, so it stays a token decision and stays legible in
///   both themes.
/// * **The role and the handoff time were gone.** "Fernanda Daroit" says less
///   than "Fernanda Daroit · Mãe · 19:00", and the web showed all three.
/// * **The greeting used the full legal name** and wrapped onto three lines on
///   a phone. It greets by FIRST name now; the full name is one tap away in the
///   account menu, and a greeting that wraps is not a greeting.
class TodayCard extends StatelessWidget {
  final TodayGlance glance;
  final String userFullName;

  /// The responsible's role as this reader's language spells it ("Mãe"), or
  /// null when the family has not set one. Resolved by the screen, which is
  /// where the roles are loaded.
  final String? responsibleRole;
  final DateTime today;
  final DateTime? nextHandoffDate;
  final bool viewingCurrentMonth;
  final bool showInviteNudge;
  final VoidCallback onGoToToday;
  final VoidCallback onInvite;

  const TodayCard({
    super.key,
    required this.glance,
    required this.userFullName,
    this.responsibleRole,
    required this.today,
    required this.nextHandoffDate,
    required this.viewingCurrentMonth,
    required this.showInviteNudge,
    required this.onGoToToday,
    required this.onInvite,
  });

  /// A heading starts with a capital; the date formatters lowercase because
  /// their output usually sits inside a sentence.
  String _capitalize(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  /// The greeting's name. The web prints the full legal name; on a phone that
  /// is three lines of card spent on something the reader already knows.
  String get _firstName {
    final parts = userFullName.trim().split(' ');
    return parts.isEmpty ? userFullName : parts.first;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final responsible = context.tokens.slot(glance.responsibleSlot);

    final user = context.tokens.slot(glance.userSlot);
    // U-28 QA: the card carries TWO identities, as the web's does. The top band
    // is the reader's own colour ("this is you asking") and the band under it is
    // whoever has the child today. The first version tinted only the second, so
    // the card said who is responsible but never said who is looking — and on a
    // day the reader IS responsible, the two bands agreeing is itself the
    // answer. Between them runs a short gradient: a hard seam between two
    // saturated tints reads as two stacked cards, not as one.
    final bandsDiffer = glance.hasSchedule &&
        !showInviteNudge &&
        glance.userSlot != glance.responsibleSlot;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Web: the card is clickable only when NOT viewing the current month.
        onTap: viewingCurrentMonth ? null : onGoToToday,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: user.tone.container,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // U-28 QA: one line, greeting left and date right. The web
                  // puts them on one line too but lets the name wrap; the first
                  // name plus an ellipsis keeps the promise the layout makes.
                  // `spaceBetween` is what actually pushes the date right, and
                  // the third attempt at it. A `Flexible` greeting takes LESS
                  // than the space the flex algorithm allots it, and a Row
                  // hands that leftover to the END of the line — so the date's
                  // box started right after the name no matter what alignment
                  // lived inside it. With the leftover placed BETWEEN the two,
                  // the greeting keeps the left edge and the date the right.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          l.format(K.cardGreeting, [_firstName]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(color: user.tone.onContainer),
                        ),
                      ),
                      // U-28 QA: the date must arrive WHOLE — "quinta-feira,
                      // 20 de ag…" is worse than no date at all. It is not
                      // rigid either, or a long month name would overflow the
                      // row on a narrow phone: `scaleDown` gives up a couple of
                      // percent of type size instead of the last five letters.
                      //
                      // The `Align` is not decoration. `Expanded` + `FittedBox`
                      // alone left the date floating next to the name: a
                      // FittedBox reports the size its CHILD needs, so the
                      // alignment inside it had nothing to align against.
                      // `Align` takes the whole half and puts the date at the
                      // end of it, which is what "right-aligned" means.
                      Flexible(
                        child: Padding(
                          padding: const EdgeInsets.only(left: Spacing.sm),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              _capitalize(l.formatTodayHeading(today)),
                              maxLines: 1,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: user.tone.onContainer),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // U-28 QA: "Voltar para hoje" used to sit here as a line of
                  // link text and read as an orphan sentence inside a coloured
                  // band. It is a chip in the month bar now, beside the month
                  // it takes you away from. The card itself stays tappable.
                ],
              ),
            ),
            // The transition zone. Only drawn when the two bands are actually
            // different colours — between two identical tints it would be a
            // gradient from a colour to itself, i.e. eight wasted pixels.
            if (bandsDiffer)
              Container(
                height: 8,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [user.tone.container, responsible.tone.container],
                  ),
                ),
              ),
            if (showInviteNudge || !glance.hasSchedule)
              Container(
                color: user.tone.container,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: showInviteNudge
                    ? _inviteNudge(context, l)
                    : _noResponsibleRow(context, l),
              )
            else
              // The one place in the app where a reader answers "who has the
              // child today" without reading a word.
              Container(
                color: responsible.tone.container,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                child: _responsibleRow(context, l, responsible),
              ),
          ],
        ),
      ),
    );
  }

  Widget _inviteNudge(BuildContext context, Localization l) => Row(
        children: [
          const Text('👋', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l[K.cardInviteTitle],
                    style: Theme.of(context).textTheme.titleSmall),
                Text(l[K.cardInviteHint],
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
              onPressed: onInvite, child: Text(l[K.cardInviteAction])),
        ],
      );

  Widget _responsibleRow(
      BuildContext context, Localization l, SlotColors responsible) {
    final textTheme = Theme.of(context).textTheme;
    final on = responsible.tone.onContainer;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: responsible.tone.solid,
          child: Text(glance.avatarLetter,
              style: TextStyle(color: responsible.tone.onSolid)),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l[K.cardResponsibleToday],
                  style: textTheme.labelSmall?.copyWith(color: on)),
              // U-28 QA: one line at `titleSmall`. At `titleMedium` over two
              // lines this single field was costing the grid a whole week.
              Text(glance.responsibleName ?? l[K.homeNotDefined],
                  style: textTheme.titleSmall?.copyWith(color: on),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              // Web: both badges can appear — swapped and the ⏰ time are
              // independent. U-28 adds the ROLE, which the port had dropped.
              if (responsibleRole != null ||
                  glance.isSwapped ||
                  glance.handoffTime != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs),
                  child: Wrap(
                    spacing: Spacing.sm,
                    runSpacing: Spacing.xs,
                    children: [
                      if (responsibleRole != null)
                        _pill(context, responsibleRole!, responsible),
                      if (glance.isSwapped)
                        _pill(context, l[K.cardSwappedBadge],
                            context.tokens.swapped),
                      if (glance.handoffTime != null)
                        _pill(
                            context,
                            '⏰ ${l.formatTimeString(glance.handoffTime!)}',
                            responsible),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (nextHandoffDate != null) _handoffBlock(context, l),
      ],
    );
  }

  /// A pill ON the tinted band. It cannot be [AppBadge]: that one paints the
  /// tone's own container, which here would be the same colour as the band it
  /// sits on. This one uses the solid at low opacity, so it reads as raised out
  /// of the band rather than as a hole in it.
  Widget _pill(BuildContext context, String text, SlotColors slot) => Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.xs / 2),
        decoration: BoxDecoration(
          color: slot.tone.solid.withValues(alpha: 0.14),
          border: Border.all(color: slot.tone.border),
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: slot.tone.onContainer)),
      );

  Widget _noResponsibleRow(BuildContext context, Localization l) => Row(
        children: [
          const Text('📭', style: TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l[K.cardNoResponsibleTitle],
                    style: Theme.of(context).textTheme.titleSmall),
                Text(l[K.cardNoResponsibleHint],
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          // Parity: the web repeats the handoff block in this branch too (in
          // practice Home nulls the date on no-schedule days — kept identical).
          if (nextHandoffDate != null) _handoffBlock(context, l),
        ],
      );

  Widget _handoffBlock(BuildContext context, Localization l) {
    final date = nextHandoffDate!;
    final urgencyColor = switch (handoffUrgency(date, today)) {
      HandoffUrgency.urgent => Theme.of(context).colorScheme.error,
      HandoffUrgency.soon => context.tokens.warning.onContainer,
      HandoffUrgency.near => context.tokens.warning.solid,
      HandoffUrgency.none => Theme.of(context).hintColor,
    };
    // U-28 QA: its own box, as the web has it. Loose on the tinted band the
    // three lines read as a continuation of the responsible's name; framed,
    // they read as what they are — a different fact, about a different day.
    // U-28 QA: the box belongs to the responsible's card, so it wears the
    // responsible's colour — one shade STRONGER than the band, the way the web
    // draws it. White made it read as a hole punched in the card.
    final slot = context.tokens.slot(glance.responsibleSlot);
    return Container(
      margin: const EdgeInsets.only(left: Spacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm, vertical: Spacing.xs),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            slot.tone.solid.withValues(alpha: 0.18), slot.tone.container),
        border: Border.all(color: slot.tone.border),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l[K.cardNextHandoff],
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: slot.tone.onContainer)),
          Text(formatHandoffDate(date, l),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(
                      color: slot.tone.onContainer,
                      fontWeight: FontWeight.w600)),
          Text(daysUntilLabel(date, today, l),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: urgencyColor, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
