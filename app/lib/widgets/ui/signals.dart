/// U-27 — the components that carry STATE: a banner, a badge, an empty state.
///
/// Each of these existed three or four times over, copied between screens with
/// small drifts: the audit tab's error banner and the summary tab's were the
/// same widget with different padding, and three screens had their own empty
/// state that differed only in whether the body text was centred. The drift is
/// the argument — one implementation cannot drift from itself.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'surfaces.dart';

/// A tone-coloured block that says something about the whole screen or the
/// whole form: an admin override in effect, a read that failed, a warning about
/// what the next tap will do.
class AppBanner extends StatelessWidget {
  /// The tone decides the colour AND the meaning — pass `context.tokens.danger`
  /// for something that went wrong, `warning` for something about to.
  final ToneColors tone;
  final String message;
  final String? title;

  /// The vector mark before the text, in the tone's own ink. U-31: never an
  /// emoji — the catalog owns the WORDS, the call site owns the mark.
  final IconData? icon;

  /// Whether the banner draws its border. Off inside an already-bordered card.
  final bool bordered;

  /// U-49: the one thing the reader can DO about what the banner says — the
  /// "Ver Premium" of a gate. Both or neither, like [AppEmptyState]'s pair;
  /// [actionIcon] is the optional mark before the label. Drawn as a text
  /// button in the tone's own ink, under the message: three gate cards each
  /// glued their own `TextButton.icon` under a tinted `Card`, and none of
  /// them was a component.
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  /// U-55: a ✕ in the top corner for a banner the reader may send away for
  /// good (an OFFER, never a state — a gate or an error cannot be dismissed).
  /// Both or neither: the tooltip is the button's accessible name.
  final VoidCallback? onClose;
  final String? closeTooltip;

  const AppBanner({
    super.key,
    required this.tone,
    required this.message,
    this.title,
    this.icon,
    this.bordered = true,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.onClose,
    this.closeTooltip,
  })  : assert((actionLabel == null) == (onAction == null),
            'actionLabel and onAction come together'),
        assert((onClose == null) == (closeTooltip == null),
            'onClose and closeTooltip come together'),
        assert(actionIcon == null || actionLabel != null,
            'an action icon needs an action to sit on');

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Text(
            title!,
            style: textTheme.titleSmall?.copyWith(color: tone.onContainer),
          ),
        if (title != null) const SizedBox(height: Spacing.xs),
        Text(
          message,
          style: textTheme.bodyMedium?.copyWith(color: tone.onContainer),
        ),
        if (actionLabel != null) ...[
          const SizedBox(height: Spacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: actionIcon == null
                ? TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: tone.onContainer),
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  )
                : TextButton.icon(
                    style: TextButton.styleFrom(
                        foregroundColor: tone.onContainer),
                    onPressed: onAction,
                    icon: Icon(actionIcon, size: 18),
                    label: Text(actionLabel!),
                  ),
          ),
        ],
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.sm + Spacing.xs),
      decoration: BoxDecoration(
        color: tone.container,
        border: bordered ? Border.all(color: tone.border) : null,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: icon == null && onClose == null
          ? text
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (icon != null) ...[
                  Padding(
                    // Sits on the first line's x-height, not the block's top.
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(icon, size: 20, color: tone.onContainer),
                  ),
                  const SizedBox(width: Spacing.sm),
                ],
                Expanded(child: text),
                if (onClose != null)
                  // The full 48 dp target, pulled into the padding so the
                  // glyph lines up with the first line instead of pushing it.
                  Transform.translate(
                    offset: const Offset(Spacing.sm, -Spacing.sm),
                    child: IconButton(
                      onPressed: onClose,
                      tooltip: closeTooltip,
                      color: tone.onContainer,
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ),
              ],
            ),
    );
  }
}

/// A pill: one short word about ONE row — pending, urgent, automatic, created.
class AppBadge extends StatelessWidget {
  final String text;
  final ToneColors tone;

  /// The reader-facing label when the pill's own text is an abbreviation. The
  /// app already leans on this in the notification list, where "Atrasado" is
  /// the pill and the full state is what a screen reader should hear.
  final String? semantics;

  /// `false` paints the solid instead of the container — for a badge that has
  /// to win against a busy row.
  final bool soft;

  const AppBadge({
    super.key,
    required this.text,
    required this.tone,
    this.semantics,
    this.soft = true,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm, vertical: Spacing.xs / 2),
        decoration: BoxDecoration(
          color: soft ? tone.container : tone.solid,
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: soft ? tone.onContainer : tone.onSolid,
              ),
        ),
      ),
    );
  }
}

/// Nothing to show, said properly: what is empty, and — when there is one — the
/// reason it is empty. Three screens had their own copy of this.
///
/// U-40: an empty state may also say what to DO about it — [actionLabel] +
/// [onAction] render one tonal button under the words. It is optional on
/// purpose: an empty audit trail is a fact with nothing to fix, while an
/// empty Resumo has a calendar to fill.
class AppEmptyState extends StatelessWidget {
  /// A vector icon, sized up and muted — the words carry the meaning, the
  /// icon only says which kind of nothing this is (U-31: never an emoji).
  final IconData icon;
  final String title;
  final String? body;

  /// The next step, when there is one. Both or neither: a label with no
  /// callback would be a button that does nothing.
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
  }) : assert((actionLabel == null) == (onAction == null),
            'actionLabel and onAction come together');

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xl),
      child: Column(
        children: [
          Icon(icon, size: 40, color: context.tokens.textMuted),
          const SizedBox(height: Spacing.sm),
          Text(title,
              textAlign: TextAlign.center, style: textTheme.titleMedium),
          if (body != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(body!,
                textAlign: TextAlign.center, style: textTheme.bodySmall),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: Spacing.md),
            FilledButton.tonal(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// The block that ends a screen able to destroy something: leaving the family,
/// deleting it, revoking a member.
///
/// It is a component and not a convention because the port proved the
/// convention does not hold — the same block was a red bordered card on the
/// web and became loose paragraphs plus a text link in Flutter, on BOTH screens
/// that carry one. A destructive action that looks like a link is the one place
/// where visual weight is a safety feature, not decoration.
class AppDangerZone extends StatelessWidget {
  final String title;

  /// The sentence that introduces the notices ("Ao confirmar você declara estar
  /// ciente de que:").
  final String? intro;

  /// What the reader is declaring they understand. Rendered as a bulleted list
  /// in the danger tone.
  final List<String> notices;

  /// Anything the action needs before it can run — the "novo administrador"
  /// picker on the leaving screen is the reason this exists.
  final Widget? child;

  final String actionLabel;

  /// `null` disables the action — the leaving screen keeps it off until a
  /// successor is chosen.
  final VoidCallback? onAction;

  final bool busy;

  const AppDangerZone({
    super.key,
    required this.title,
    required this.notices,
    required this.actionLabel,
    required this.onAction,
    this.intro,
    this.child,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final tone = context.tokens.danger;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.md),
      decoration: BoxDecoration(
        color: tone.container,
        border: Border.all(color: tone.border),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: textTheme.titleSmall?.copyWith(color: tone.onContainer)),
          if (intro != null) ...[
            const SizedBox(height: Spacing.xs),
            Text(intro!,
                style:
                    textTheme.bodySmall?.copyWith(color: tone.onContainer)),
          ],
          if (notices.isNotEmpty) ...[
            const SizedBox(height: Spacing.sm),
            AppBulletList(items: notices, color: tone.onContainer),
          ],
          if (child != null) ...[
            const SizedBox(height: Spacing.md),
            child!,
          ],
          const SizedBox(height: Spacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: busy ? null : onAction,
              style: FilledButton.styleFrom(
                  backgroundColor: tone.solid, foregroundColor: tone.onSolid),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(actionLabel),
            ),
          ),
        ],
      ),
    );
  }
}
