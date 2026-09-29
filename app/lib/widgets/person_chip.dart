import 'package:flutter/material.dart';

import '../theme/slot_pattern.dart';
import '../theme/tokens.dart';

/// F-07 (owner's QA, 29/09/2026) — one chip for every person above the
/// calendar: the carers' legend and the children's lanes wear the same shape
/// (an avatar and a short name), so the row reads as one family.
///
/// 32 dp drawn, 40 dp to touch — the legend's named exception in the U-32
/// gate (`accessibility_guidelines_test`), the Google button's own floor
/// (U-45): two rows at Material's 48 would take the height the month grid
/// needs.
///
/// A null [label] is the COMPACT chip (owner, 29/09/2026, round 3): the
/// avatar alone, for a row whose names do not fit one line on a small phone.
/// Its name moves to the screen reader and to a long-press tooltip, and its
/// touch target stays 40 × 40 around the 32 dp circle.
class PersonChip extends StatelessWidget {
  final String? label;
  final Widget avatar;
  final Color background;
  final Color border;
  final Color ink;
  final bool selected;
  final VoidCallback? onTap;

  /// What a screen reader says (and the compact chip's tooltip); the label
  /// when null.
  final String? semanticsLabel;

  static const double visual = 32;
  static const double target = 40;

  /// The avatar's diameter inside a chip.
  static const double avatarSize = 20;

  static const double _start = 6;
  static const double _gap = 6;
  static const double _end = 10;

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

  static TextStyle? _style(BuildContext context) =>
      Theme.of(context).textTheme.labelMedium;

  /// The width a chip with [label] draws, at the reader's text scale — what
  /// a row measures to decide whether its names fit (the compact chip is
  /// [visual] wide, [target] to touch). Counts the selected border, so the
  /// answer does not flip with the selection.
  static double widthOf(BuildContext context, String? label) {
    if (label == null) return visual;
    final painter = TextPainter(
      text: TextSpan(text: label, style: _style(context)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = 4 + _start + avatarSize + _gap + painter.width + _end;
    painter.dispose();
    return width.ceilToDouble();
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(Radii.md);
    final compact = label == null;
    final chip = Container(
      height: visual,
      width: compact ? visual : null,
      alignment: compact ? Alignment.center : null,
      padding: compact
          ? EdgeInsets.zero
          : const EdgeInsetsDirectional.only(start: _start, end: _end),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: Border.all(color: border, width: selected ? 2 : 1),
      ),
      child: compact
          ? avatar
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                avatar,
                const SizedBox(width: _gap),
                Text(label!, style: _style(context)?.copyWith(color: ink)),
              ],
            ),
    );
    final spoken = semanticsLabel ?? label ?? '';
    Widget hit = SizedBox(
      height: target,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: compact ? target : 0),
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
    if (compact) hit = Tooltip(message: spoken, child: hit);
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: spoken,
      excludeSemantics: true,
      onTap: onTap,
      child: hit,
    );
  }
}

/// A round avatar with letters: a carer's is filled with their colour, a
/// child's is NEUTRAL with a ring (owner, 29/09/2026) — colour keeps meaning
/// "who has the child", never "which child".
///
/// [dashedRing] is the PENDING carer's (owner, 29/09/2026, round 3): hollow,
/// the letters and a dashed ring in their colour — someone with a place in
/// the key who has not joined yet, said without the "(pendente)" the legend
/// could not afford.
class MiniAvatar extends StatelessWidget {
  final double diameter;
  final String letters;
  final Color fill;
  final Color ink;
  final Color? ring;
  final Color? dashedRing;
  final double letterScale;

  const MiniAvatar({
    super.key,
    required this.diameter,
    required this.letters,
    required this.fill,
    required this.ink,
    this.ring,
    this.dashedRing,
    this.letterScale = 0.55,
  });

  @override
  Widget build(BuildContext context) {
    final circle = Container(
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
    if (dashedRing == null) return circle;
    return CustomPaint(
      foregroundPainter: DashedBorderPainter(
          color: dashedRing!,
          radius: diameter / 2,
          strokeWidth: 1.5,
          dash: 3,
          gap: 2),
      child: circle,
    );
  }
}
