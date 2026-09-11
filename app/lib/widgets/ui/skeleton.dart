/// U-27 — skeletons: the shape of what is coming, instead of a spinner or the
/// word "Carregando".
///
/// The difference is not decoration. A spinner says "wait"; a skeleton says
/// "wait, and here is what will be here" — the reader's eye lands where the
/// content will land, and the page does not jump when it arrives. The web app
/// had a whole `.skel-*` family with shimmer; the port had none, and every load
/// was either a centred spinner or the literal word.
///
/// What does NOT become a skeleton, deliberately:
///
/// * **A button mid-action.** The spinner inside a pressed button is about THAT
///   press, not about content arriving.
/// * **A determinate bar.** The bulk save and the wizard know their progress;
///   throwing that information away for a shimmer would be a downgrade.
/// * **A wait with no known shape.** The splash before routing, and the premium
///   return screen polling the payment processor, have nothing to outline.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// One shimmering block. Everything else here is composed of these.
///
/// The shimmer is a pure horizontal translation — no scale, no opacity pulse —
/// so it reads as light passing over a surface rather than as something
/// blinking for attention.
class AppSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const AppSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = Radii.sm,
  });

  /// A circle, for where an avatar will be.
  const AppSkeleton.circle({Key? key, double size = 40})
      : this(key: key, width: size, height: size, radius: size);

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.skeleton,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = Motion.skeletonCurve.transform(_controller.value);
          return DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              gradient: LinearGradient(
                // The sweep travels a full width beyond each edge so the
                // highlight enters and leaves instead of appearing mid-block.
                begin: Alignment(-1 - 2 * (1 - t), 0),
                end: Alignment(1 - 2 * (1 - t), 0),
                colors: [
                  tokens.skeletonBase,
                  tokens.skeletonHighlight,
                  tokens.skeletonBase,
                ],
                stops: const [0.35, 0.5, 0.65],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The shape of a list that is loading: a few rows, each an avatar-sized block
/// beside two lines of text.
class AppSkeletonList extends StatelessWidget {
  final int rows;
  final bool leading;
  final EdgeInsetsGeometry padding;

  /// What a screen reader hears instead of four rows of nothing. It comes from
  /// the CALL SITE because it is user-facing text, and user-facing text lives
  /// in the catalog (`l[K.famLoading]`), never in a widget.
  final String? semanticsLabel;

  const AppSkeletonList({
    super.key,
    this.rows = 4,
    this.leading = true,
    this.padding = const EdgeInsets.all(Spacing.md),
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      // One announcement for the whole block, and the blocks themselves are
      // excluded: a reader must not hear four rows of nothing.
      label: semanticsLabel,
      excludeSemantics: true,
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        itemCount: rows,
        separatorBuilder: (_, _) => const SizedBox(height: Spacing.md),
        itemBuilder: (_, index) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (leading) ...[
              const AppSkeleton.circle(),
              const SizedBox(width: Spacing.sm + Spacing.xs),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Alternating widths: a column of identical bars looks like
                  // a table, and this is meant to look like rows of prose.
                  AppSkeleton(height: 14, width: index.isEven ? 160 : 200),
                  const SizedBox(height: Spacing.sm),
                  const AppSkeleton(height: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The shape of the month grid: the weekday strip and six weeks of cells, at the
/// same aspect ratio the real grid uses, so nothing shifts when the days land.
class AppSkeletonCalendar extends StatelessWidget {
  final int weeks;
  final double childAspectRatio;

  const AppSkeletonCalendar({
    super.key,
    this.weeks = 6,
    this.childAspectRatio = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Spacing.sm + Spacing.xs),
      child: Column(
        children: [
          // U-28: no weekday row here. The screen already prints the real
          // initials above this widget, and the skeleton was drawing a second,
          // grey one under them — the loading state showed a header the loaded
          // state does not have.
          GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            shrinkWrap: true,
            itemCount: weeks * 7,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: childAspectRatio,
              mainAxisSpacing: Spacing.xs,
              crossAxisSpacing: Spacing.xs,
            ),
            itemBuilder: (_, _) =>
                const AppSkeleton(height: double.infinity, radius: Radii.md),
          ),
        ],
      ),
    );
  }
}

/// The shape of a stack of cards — the summary's per-carer statistics, the
/// premium history, a panel that is still reading.
class AppSkeletonCards extends StatelessWidget {
  final int count;
  final double height;

  /// Same rule as [AppSkeletonList.semanticsLabel]: user-facing text comes from
  /// the catalog, at the call site.
  final String? semanticsLabel;

  const AppSkeletonCards({
    super.key,
    this.count = 3,
    this.height = 88,
    this.semanticsLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Column(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(height: Spacing.sm + Spacing.xs),
              AppSkeleton(height: height, radius: Radii.md),
            ],
          ],
        ),
      ),
    );
  }
}
