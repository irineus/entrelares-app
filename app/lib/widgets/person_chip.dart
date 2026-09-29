import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// F-07 (owner's QA, 29/09/2026) — one chip for every person above the
/// calendar: the carers' legend and the children's lanes wear the same shape
/// (an avatar and a short name), so the row reads as one family.
///
/// 32 dp drawn, 40 dp to touch — the legend's named exception in the U-32
/// gate (`accessibility_guidelines_test`), the Google button's own floor
/// (U-45): two rows at Material's 48 would take the height the month grid
/// needs.
class PersonChip extends StatelessWidget {
  final String label;
  final Widget avatar;
  final Color background;
  final Color border;
  final Color ink;
  final bool selected;
  final VoidCallback? onTap;

  /// What a screen reader says; the label when null.
  final String? semanticsLabel;

  static const double visual = 32;
  static const double target = 40;

  const PersonChip({
    super.key,
    required this.label,
    required this.avatar,
    required this.background,
    required this.border,
    required this.ink,
    this.selected = false,
    this.onTap,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.md);
    final chip = Container(
      height: visual,
      padding: const EdgeInsetsDirectional.only(start: 6, end: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: Border.all(color: border, width: selected ? 2 : 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          avatar,
          const SizedBox(width: 6),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: ink)),
        ],
      ),
    );
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: SizedBox(
        height: target,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            // Only as wide as the chip: a bare Center would stretch it to
            // the row, one carer per line.
            child: Center(widthFactor: 1, child: chip),
          ),
        ),
      ),
    );
  }
}

/// A round avatar with letters: a carer's is filled with their colour, a
/// child's is NEUTRAL with a ring (owner, 29/09/2026) — colour keeps meaning
/// "who has the child", never "which child".
class MiniAvatar extends StatelessWidget {
  final double diameter;
  final String letters;
  final Color fill;
  final Color ink;
  final Color? ring;
  final double letterScale;

  const MiniAvatar({
    super.key,
    required this.diameter,
    required this.letters,
    required this.fill,
    required this.ink,
    this.ring,
    this.letterScale = 0.55,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: diameter,
        height: diameter,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: ring == null ? null : Border.all(color: ring!, width: 1.5),
        ),
        child: Text(
          letters,
          maxLines: 1,
          overflow: TextOverflow.clip,
          textScaler: TextScaler.noScaling,
          style: TextStyle(
            fontSize: diameter * letterScale,
            height: 1,
            fontWeight: FontWeight.w500,
            color: ink,
          ),
        ),
      );
}
