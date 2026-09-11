/// U-23 — the first-run surfaces: the launcher bar, the checklist sheet, the
/// "Como funciona a troca" sheet and the 4-stop guided tour.
///
/// The tour is the parity map's "redesign leve": the web spotlights a CSS
/// selector from `tour.js`, which has no equivalent here. A stop names a
/// [TourTarget] instead, the screens register a key per target, and a target
/// with no registered widget degrades to a card with no highlight — exactly
/// the failure mode the web chose, and never a broken tour.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

import 'app_l10n.dart';
import 'ui/ui.dart';
import 'rich_label.dart';


/// Where the tour's targets live. One instance is created by the shell and
/// shared with every screen that owns a target, because they sit in different
/// widget subtrees (the notifications tab belongs to the shell, the rest to the
/// calendar).
class TourKeys {
  final Map<TourTarget, GlobalKey> _keys = {};

  GlobalKey keyFor(TourTarget target) =>
      _keys.putIfAbsent(target, () => GlobalKey());

  /// Which targets currently have a widget on screen — the tour skips the
  /// spotlight for the others rather than pointing at nothing.
  bool isMounted(TourTarget target) =>
      _keys[target]?.currentContext?.findRenderObject() != null;

  /// The target's rectangle, or null when it is not on screen. Measured
  /// relative to [ancestor] when given, in global (window) coordinates
  /// otherwise.
  ///
  /// The spotlight passes the OVERLAY that hosts the tour as the ancestor.
  /// On the web the app sits in a width-capped, centred box (`AppWidthCap`),
  /// so the overlay's origin is not the window's: a rect measured against the
  /// window landed one margin to the right of the target, and the first
  /// stop's hole was cut over empty scrim beside the today card (owner,
  /// 09/09/2026). Measured against the overlay both spaces agree everywhere.
  Rect? rectOf(TourTarget target, {RenderObject? ancestor}) {
    final context = _keys[target]?.currentContext;
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: ancestor) & box.size;
  }
}

/// The compact bar that stays in the calendar's layout. The web learned this
/// the expensive way: the full card cost ~290px out of a fixed-height column,
/// so the content moved into a sheet and only this strip stayed.
class OnboardingLauncher extends StatelessWidget {
  final OnboardingSignals signals;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;

  const OnboardingLauncher({
    super.key,
    required this.signals,
    required this.onOpen,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Text('🚀'),
              const SizedBox(width: 8),
              Expanded(
                child: Text(l[K.onbChecklistTitle],
                    style: theme.textTheme.bodyMedium),
              ),
              Text(
                l.format(K.onbChecklistProgress, [
                  OnboardingSteps.doneCount(signals),
                  OnboardingSteps.visibleIn(signals).length,
                ]),
                style: theme.textTheme.bodySmall,
              ),
              IconButton(
                tooltip: l[K.onbChecklistDismissAria],
                icon: const Icon(Icons.close, size: 18),
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the checklist asked for. The action survives completion on purpose —
/// "Convidar" is still useful after the first invitation went out.
enum OnboardingAction { invite, plan, explainSwaps, enablePush, replayTour }

Future<OnboardingAction?> showOnboardingChecklist({
  required BuildContext context,
  required OnboardingSignals signals,
}) =>
    showAppSheet<OnboardingAction>(
      context: context,
      builder: (context) {
        final l = AppL10n.of(context).l;
        final theme = Theme.of(context);
        // Scrolls like its sibling below: four steps with two-line hints do
        // not fit a small phone, and a Column that cannot scroll overflowed
        // by one hint line the day the invite hint grew (F-56 QA).
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l[K.onbChecklistTitle],
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(l[K.onbChecklistIntro],
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                for (final step in OnboardingSteps.visibleIn(signals))
                  _StepTile(step: step, signals: signals),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context).pop(OnboardingAction.replayTour),
                  child: Text(l[K.onbChecklistReplayTour]),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l[K.commonClose]),
                ),
              ],
            ),
          ),
        );
      },
    );

class _StepTile extends StatelessWidget {
  final OnboardingStep step;
  final OnboardingSignals signals;

  const _StepTile({required this.step, required this.signals});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final done = OnboardingSteps.isDone(step, signals);
    final action = switch (step) {
      OnboardingStep.inviteCoCaregiver => OnboardingAction.invite,
      OnboardingStep.planTheDays => OnboardingAction.plan,
      OnboardingStep.understandSwaps => OnboardingAction.explainSwaps,
      OnboardingStep.enablePush => OnboardingAction.enablePush,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The mark is decorative; the state is announced in text, so a
          // screen reader never has to interpret an emoji.
          ExcludeSemantics(child: Text(done ? '✅' : '⬜')),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: '${l[step.titleKey]} — '
                      '${l[done ? K.onbStepDone : K.onbStepTodo]}',
                  child: Text(l[step.titleKey],
                      style: Theme.of(context).textTheme.titleSmall),
                ),
                Text(
                    l[done
                        ? OnboardingSteps.doneHintKeyFor(step, signals)
                        : step.hintKey],
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(action),
            child: Text(l[step.actionKey]),
          ),
        ],
      ),
    );
  }
}

/// "Como funciona a troca" — four ideas that explain the whole app. Opening it
/// IS completing step 3, and the caller stamps that before this renders.
Future<void> showHowSwapsWork(BuildContext context) =>
    showAppSheet<void>(
      context: context,
      builder: (context) {
        final l = AppL10n.of(context).l;
        final theme = Theme.of(context);
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l[K.onbSwapSheetTitle],
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(l[K.onbSwapSheetIntro],
                    style: theme.textTheme.bodySmall),
                const SizedBox(height: 16),
                for (final (title, body) in [
                  (K.onbSwapPlannedTitle, K.onbSwapPlannedBody),
                  (K.onbSwapApprovalTitle, K.onbSwapApprovalBody),
                  (K.onbSwapFrozenTitle, K.onbSwapFrozenBody),
                  (K.onbSwapHistoryTitle, K.onbSwapHistoryBody),
                ]) ...[
                  Text(l[title], style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  // These four bodies emphasize a word inline (U-13 catalog
                  // markup) — rendered as spans, never as visible tags.
                  RichLabel.of(l, body, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 16),
                ],
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l[K.onbSwapSheetGotIt]),
                ),
              ],
            ),
          ),
        );
      },
    );

/// The 4-stop tour. The card is PINNED near the bottom rather than anchored to
/// the target: at 344px wide there is often no side of a highlighted element
/// with room for a balloon. The one exception is a target that lives at the
/// bottom itself — step 4 spotlights the notifications tab in the bottom
/// navigation — where the card flips to the top instead of covering the very
/// thing it is describing (U-29, owner-reported, round 3).
Future<void> showGuidedTour({
  required BuildContext context,
  required TourKeys keys,
}) =>
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      // U-29: the spotlight paints target rects measured in GLOBAL
      // coordinates, but the default `useSafeArea: true` insets the dialog
      // below the status bar — every hole landed one status bar too low
      // (the legend spotlight lit the weekday row). The overlay must cover
      // the whole screen so the two coordinate spaces agree.
      useSafeArea: false,
      builder: (context) => _GuidedTour(keys: keys),
    );

class _GuidedTour extends StatefulWidget {
  final TourKeys keys;

  const _GuidedTour({required this.keys});

  @override
  State<_GuidedTour> createState() => _GuidedTourState();
}

class _GuidedTourState extends State<_GuidedTour> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final step = TourSteps.at(_index);
    // Defensive: the tour ends by popping, so a null step here means something
    // advanced past the end — close rather than render nothing.
    if (step == null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => Navigator.of(context).maybePop());
      return const SizedBox.shrink();
    }

    // Both the hole and the card are laid out in the overlay's space, so the
    // target is measured against the overlay too — see [TourKeys.rectOf].
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final target = widget.keys.rectOf(step.target, ancestor: overlayBox);
    final theme = Theme.of(context);
    final isLast = _index == TourSteps.count - 1;

    // A target in the lower band of the screen would sit under the
    // bottom-pinned card — flip the card to the top for that stop. The
    // overlay ignores the safe area (see [showGuidedTour]), so the status
    // bar inset is added back by hand.
    final screen = overlayBox?.hasSize == true
        ? overlayBox!.size
        : MediaQuery.sizeOf(context);
    final flipToTop =
        target != null && target.center.dy > screen.height * 0.62;

    return Semantics(
      label: l[K.tourAriaLabel],
      child: Stack(
        children: [
          // The dim, with a hole punched over the target when it is on screen.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                  painter: _SpotlightPainter(target, context.tokens.scrim)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: flipToTop ? MediaQuery.paddingOf(context).top + 16 : null,
            bottom: flipToTop ? null : 24,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.format(K.tourProgress, [_index + 1, TourSteps.count]),
                        style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Text(l[step.titleKey], style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(l[step.bodyKey], style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        TextButton(
                          // Skipping and finishing are the same fact: the tour
                          // was offered, and it does not come back on its own.
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(l[K.tourSkip]),
                        ),
                        const Spacer(),
                        if (_index > 0)
                          TextButton(
                            onPressed: () => setState(() => _index--),
                            child: Text(l[K.tourPrevious]),
                          ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: isLast
                              ? () => Navigator.of(context).pop()
                              : () => setState(() => _index++),
                          child: Text(l[isLast ? K.tourFinish : K.tourNext]),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? target;

  /// U-27: a painter has no BuildContext, so the token travels in.
  final Color scrim;

  const _SpotlightPainter(this.target, this.scrim);

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = scrim;
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    if (target == null) {
      // No target on screen: dim everything rather than pretend to point at
      // something.
      canvas.drawRect(full, dim);
      return;
    }
    final hole = RRect.fromRectAndRadius(
        target!.inflate(6), const Radius.circular(12));
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(full),
        Path()..addRRect(hole),
      ),
      dim,
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.target != target || oldDelegate.scrim != scrim;
}
