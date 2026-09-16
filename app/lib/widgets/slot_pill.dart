import 'package:flutter/material.dart';

import '../theme/slot_pattern.dart';
import '../theme/tokens.dart';

/// A pill in a calendar identity's own colours — the month legend's key and,
/// since U-25, the day sheet's summary chips.
///
/// It was `_Legend._key` until U-25 needed the same shape in the sheet. Two
/// copies of "what a carer looks like outside the grid" is exactly the drift
/// U-27 argued a shared widget prevents, so the key moved here unchanged and
/// the sheet uses the same one.
///
/// Colour is never the only vector (U-27): [dashed] draws the swapped day's
/// outline instead of the solid border — that border IS the signal — and
/// [patterned] lays the slot's texture under the label, as the grid cell does.
class SlotPill extends StatelessWidget {
  final SlotColors slot;
  final String label;
  final double height;
  final bool dashed;
  final bool patterned;

  /// A small leading mark (the sheet's clock on the handoff chip).
  final IconData? icon;

  /// A long name ellipsizes instead of pushing the row past a 344 dp phone.
  final double? maxWidth;

  const SlotPill({
    super.key,
    required this.slot,
    required this.label,
    this.height = 22,
    this.dashed = false,
    this.patterned = false,
    this.icon,
    this.maxWidth,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: slot.tone.onContainer);
    final text = Text(label,
        style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    // No `alignment:` on the Container, and that is the whole fix the legend
    // paid for: a Container WITH an alignment expands to fill whatever space
    // it is offered, so each key took a full row of the Wrap. Without it the
    // pill shrink-wraps its text.
    final pill = Container(
      height: height,
      constraints:
          maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth!),
      clipBehavior: patterned ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: slot.tone.container,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: dashed ? null : Border.all(color: slot.tone.border),
      ),
      // The texture sits between the fill and the label, as in the grid cell.
      child: CustomPaint(
        painter: patterned
            ? SlotPatternPainter(slot.pattern, slot.tone.border)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
          child: Center(
            widthFactor: 1,
            child: icon == null
                ? text
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: (style?.fontSize ?? 12) + 2,
                          color: slot.tone.onContainer),
                      const SizedBox(width: Spacing.xs),
                      Flexible(child: text),
                    ],
                  ),
          ),
        ),
      ),
    );
    if (!dashed) return pill;
    return CustomPaint(
      foregroundPainter:
          DashedBorderPainter(color: slot.tone.border, radius: Radii.lg),
      child: pill,
    );
  }
}
