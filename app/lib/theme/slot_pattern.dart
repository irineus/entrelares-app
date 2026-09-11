/// U-27 — the non-chromatic half of a calendar slot's identity.
///
/// The two-colour pair the web chose (blue / rose) was picked to survive
/// deuteranopia and protanopia; the third and fourth slots have no such
/// guarantee, and a family with four active carers is exactly the family whose
/// grid is hardest to read. So every slot also carries a texture: with the
/// patterns on, the grid is readable with no colour vision at all.
///
/// Slot 1 keeps `none` on purpose — "no texture" is one of the distinguishable
/// states, and the two-member family (the overwhelmingly common case) then
/// reads as one clean fill against one hatched one.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tokens.dart';

/// Paints [pattern] in [color] over whatever already filled the shape.
class SlotPatternPainter extends CustomPainter {
  final SlotPattern pattern;
  final Color color;

  /// Patterns are texture, not information in their own right — they sit under
  /// the day number and must never compete with it.
  static const double patternOpacity = 0.55;
  static const double _step = 6;

  const SlotPatternPainter(this.pattern, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (pattern == SlotPattern.none) return;
    final paint = Paint()
      ..color = color.withValues(alpha: patternOpacity)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    canvas.clipRect(Offset.zero & size);

    switch (pattern) {
      case SlotPattern.none:
        return;
      case SlotPattern.verticalHatch:
        for (double x = 0; x <= size.width; x += _step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
        }
      case SlotPattern.diagonalHatch:
        final span = size.width + size.height;
        for (double d = 0; d <= span; d += _step) {
          canvas.drawLine(Offset(d, 0), Offset(d - size.height, size.height),
              paint);
        }
      case SlotPattern.backDiagonalHatch:
        final span = size.width + size.height;
        for (double d = -size.height; d <= span; d += _step) {
          canvas.drawLine(Offset(d, 0), Offset(d + size.height, size.height),
              paint);
        }
      case SlotPattern.dots:
        final dot = Paint()
          ..color = color.withValues(alpha: patternOpacity)
          ..style = PaintingStyle.fill;
        for (double y = _step / 2; y < size.height; y += _step) {
          for (double x = _step / 2; x < size.width; x += _step) {
            canvas.drawCircle(Offset(x, y), 1, dot);
          }
        }
    }
  }

  @override
  bool shouldRepaint(SlotPatternPainter old) =>
      old.pattern != pattern || old.color != color;

  // Decoration never takes a tap. `RenderCustomPaint.hitTestSelf` is
  // `painter.hitTest(position) ?? true`, so the default null would make this
  // texture absorb every press on the day it decorates.
  @override
  bool? hitTest(Offset position) => false;
}

/// A dashed rounded border — what an approved swap wears instead of a colour
/// of its own (web parity: `.swapped` is amber with `2px dashed`).
class DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dash;
  final double gap;

  const DashedBorderPainter({
    required this.color,
    required this.radius,
    this.strokeWidth = 2,
    this.dash = 4,
    this.gap = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    ).deflate(strokeWidth / 2);
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final end = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  bool shouldRepaint(DashedBorderPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;

  /// Same reason as [SlotPatternPainter.hitTest] — and here it matters more:
  /// this one sits ON TOP of the cell, so absorbing would make every swapped
  /// day untappable.
  @override
  bool? hitTest(Offset position) => false;
}

/// The legend's swatch: the same fill, border and texture a day cell wears, so
/// the pattern is learnable from the legend instead of having to be guessed.
class SlotSwatch extends StatelessWidget {
  final SlotColors slot;
  final bool dashedBorder;
  final double size;

  const SlotSwatch({
    super.key,
    required this.slot,
    this.dashedBorder = false,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: slot.tone.container,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: dashedBorder
                  ? null
                  : Border.all(color: slot.tone.border),
            ),
            child: CustomPaint(
              painter: SlotPatternPainter(slot.pattern, slot.tone.border),
            ),
          ),
          if (dashedBorder)
            CustomPaint(
              painter: DashedBorderPainter(
                color: slot.tone.border,
                radius: Radii.sm,
              ),
            ),
        ],
      ),
    );
  }
}
