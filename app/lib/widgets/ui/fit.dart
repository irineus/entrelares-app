/// U-48 — a line that shrinks to fit, with a FLOOR.
///
/// A `FittedBox` that only ever scales DOWN is the wrong tool for text: it answers a
/// reader who turned the system font up by turning it straight back down, as
/// far as it takes, with no floor and no reason. Four sites did that (the
/// summary's paired stats, the today card's date, the login's legal links),
/// each with a comment explaining why a shrink beat a wrap at ORDINARY
/// scales — true, and beside the point at 1.3×, where the shrink quietly
/// undid the whole setting. A child that is a TAP TARGET may shrink only at
/// the reader's default scale (`floor: 1.0` under large text): the U-32 gate
/// measured the login's links at 41 dp under a 0.85 shrink at 1.3×, and a
/// smaller target is the wrong answer to "make my text bigger".
///
/// The shape U-39 settled for the day cell — a ceiling with a floor and a
/// reason — is what this widget gives every one-liner: shrink by at most
/// `1 - floor` (0.85× by default, the couple of percent the sites always
/// meant), and past that hand the child the width it would have at the floor
/// and let it answer for itself. A `Text` with `maxLines: 1` ellipsizes; a
/// `Wrap` breaks into a second line. Either is honest about the space; a 0.6×
/// line is not.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Lays [child] out at its natural width; scales it down to fit the incoming
/// width, never below [floor]; at the floor, re-lays it out at
/// `maxWidth / floor` so the child wraps or ellipsizes on its own terms.
///
/// The child is painted with the transform, hit-tested through it, and its
/// semantics carry it — a shrunken link is still a link where it is drawn.
class AppShrinkToFit extends SingleChildRenderObjectWidget {
  /// The smallest scale ever applied. `0.85` is the product's floor (U-48).
  final double floor;

  /// Where the (possibly narrower) child sits inside the box the parent
  /// forces — a `Center` above it makes this moot, a `Row` cell does not.
  final AlignmentGeometry alignment;

  const AppShrinkToFit({
    super.key,
    this.floor = defaultFloor,
    this.alignment = AlignmentDirectional.centerStart,
    required Widget super.child,
  }) : assert(floor > 0 && floor <= 1);

  /// The floor the card set: no line reads under 85 % of its design size.
  static const double defaultFloor = 0.85;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderShrinkToFit(
    floor: floor,
    alignment: alignment,
    textDirection: Directionality.of(context),
  );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderShrinkToFit renderObject,
  ) => renderObject
    ..floor = floor
    ..alignment = alignment
    ..textDirection = Directionality.of(context);
}

/// The render object behind [AppShrinkToFit]; public only because the
/// widget's `updateRenderObject` names it.
class RenderShrinkToFit extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  RenderShrinkToFit({
    required this._floor,
    required this._alignment,
    required this._textDirection,
  });

  double _floor;
  double get floor => _floor;
  set floor(double value) {
    if (value == _floor) return;
    _floor = value;
    markNeedsLayout();
  }

  AlignmentGeometry _alignment;
  AlignmentGeometry get alignment => _alignment;
  set alignment(AlignmentGeometry value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  TextDirection get textDirection => _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsLayout();
  }

  /// The scale the last layout applied — 1.0 whenever the child fits.
  double scale = 1;

  /// Where the scaled child was placed inside [size].
  Offset _childOffset = Offset.zero;

  Matrix4 get _transform =>
      Matrix4.translationValues(_childOffset.dx, _childOffset.dy, 0)
        ..scaleByDouble(scale, scale, 1, 1);

  /// The child's constraints at its NATURAL width: no width bound at all,
  /// the parent's height bound kept.
  BoxConstraints _natural(BoxConstraints c) =>
      BoxConstraints(maxHeight: c.maxHeight);

  /// The child's constraints once the floor is hit: the width it would get
  /// at the floor, which is where a `Text` ellipsizes and a `Wrap` wraps.
  BoxConstraints _atFloor(BoxConstraints c) =>
      BoxConstraints(maxWidth: c.maxWidth / floor, maxHeight: c.maxHeight);

  ({Size child, double scale}) _plan(
    BoxConstraints constraints,
    Size Function(BoxConstraints) layout,
  ) {
    var childSize = layout(_natural(constraints));
    var s = 1.0;
    final maxW = constraints.maxWidth;
    if (maxW.isFinite && childSize.width > maxW && childSize.width > 0) {
      s = maxW / childSize.width;
      if (s < floor) {
        s = floor;
        childSize = layout(_atFloor(constraints));
      }
    }
    return (child: childSize, scale: s);
  }

  @override
  void performLayout() {
    final c = child;
    if (c == null) {
      size = constraints.smallest;
      scale = 1;
      return;
    }
    final plan = _plan(constraints, (bc) {
      c.layout(bc, parentUsesSize: true);
      return c.size;
    });
    scale = plan.scale;
    final scaled = plan.child * scale;
    size = constraints.constrain(scaled);
    _childOffset = alignment
        .resolve(textDirection)
        .alongOffset(size - scaled as Offset);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final c = child;
    if (c == null) return constraints.smallest;
    final plan = _plan(constraints, c.getDryLayout);
    return constraints.constrain(plan.child * plan.scale);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      (child?.getMinIntrinsicWidth(height) ?? 0) * floor;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      child?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final d = child?.getDistanceToActualBaseline(baseline);
    return d == null ? null : d * scale + _childOffset.dy;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    if (scale == 1 && _childOffset == Offset.zero) {
      context.paintChild(c, offset);
      return;
    }
    context.pushTransform(
      needsCompositing,
      offset,
      _transform,
      (context, offset) => context.paintChild(c, offset),
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => c.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }
}
