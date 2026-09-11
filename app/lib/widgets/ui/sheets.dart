/// U-28 QA — how a bottom sheet behaves in this app.
///
/// The owner reviewed five sheets and found the same three faults in each, which
/// is the signature of a missing component rather than of five mistakes:
///
/// * **They grew to fill the screen**, leaving nothing to tap to dismiss and no
///   sign that the thing was a sheet at all. The web's kept a strip of page
///   visible above it.
/// * **The action row scrolled away.** On the rotation wizard and the day sheet
///   in admin mode, "Salvar" sat below the fold — a form whose commit you have
///   to go looking for.
/// * **"Cancelar" was simply gone**, so dragging the sheet down was the only way
///   out of a form.
///
/// [showAppSheet] fixes the first; [AppSheetFrame] fixes the other two by
/// construction: content scrolls, actions do not.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// How much of the screen a sheet may take. The remaining tenth is not spare
/// room — it is the target a reader taps to get out, and the visual cue that
/// there is a page underneath.
const double _maxSheetHeightFactor = 0.9;

/// Every modal sheet in the app opens through here.
///
/// It is a function and not a convention because the convention did not hold:
/// all five call sites passed `isScrollControlled: true` with no constraints,
/// which is precisely the combination that lets a sheet reach the status bar.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * _maxSheetHeightFactor,
    ),
    builder: builder,
  );
}

/// The inside of a sheet: a title, a scrolling body, and an action row pinned to
/// the bottom.
///
/// The pinning is the point. A sheet's actions are the answer to the question
/// the sheet asks, and they must be reachable without the reader first proving
/// they can scroll.
class AppSheetFrame extends StatelessWidget {
  final String title;
  final String? subtitle;

  /// Sits between the title and the scrolling body, outside the scroll — for a
  /// banner that must not be scrolled past ("this day is locked", "admin mode
  /// is on").
  final Widget? pinnedNotice;

  final List<Widget> children;

  /// The confirming action. Null renders no action row at all, which is right
  /// for a read-only sheet — the drag handle is then the only affordance and
  /// the only one needed.
  final String? primaryLabel;
  final VoidCallback? onPrimary;

  /// Defaults to the catalog's "Cancelar" at the call site; passing null keeps
  /// the row to one button (a destructive-only sheet, say).
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  /// A third action that belongs with the others but is not the answer — the
  /// day sheet's "Limpar dia".
  final Widget? extraAction;

  final bool busy;

  const AppSheetFrame({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.pinnedNotice,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.extraAction,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    return AnimatedPadding(
      duration: Motion.micro,
      // The keyboard pushes the sheet, it does not cover it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, 0, Spacing.md, Spacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: Spacing.xs),
                  Text(subtitle!,
                      style: textTheme.bodySmall
                          ?.copyWith(color: tokens.textMuted)),
                ],
              ],
            ),
          ),
          if (pinnedNotice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, 0, Spacing.md, Spacing.sm),
              child: pinnedNotice,
            ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, 0, Spacing.md, Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
          if (primaryLabel != null || extraAction != null)
            _actions(context, tokens),
        ],
      ),
    );
  }

  Widget _actions(BuildContext context, AppTokens tokens) => Container(
        decoration: BoxDecoration(
          color: tokens.surfaceAlt,
          border: Border(top: BorderSide(color: tokens.outline)),
        ),
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
        child: SafeArea(
          top: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (primaryLabel != null)
                Row(
                  children: [
                    // U-27's order, kept: the CONFIRMATION first, the way out
                    // after it. Both take half the row, so they line up.
                    Expanded(
                      child: FilledButton(
                        onPressed: busy ? null : onPrimary,
                        child: busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(primaryLabel!),
                      ),
                    ),
                    if (secondaryLabel != null) ...[
                      const SizedBox(width: Spacing.sm),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: busy ? null : onSecondary,
                          child: Text(secondaryLabel!),
                        ),
                      ),
                    ],
                  ],
                ),
              if (extraAction != null) ...[
                if (primaryLabel != null) const SizedBox(height: Spacing.sm),
                extraAction!,
              ],
            ],
          ),
        ),
      );
}

/// U-28 QA — the app's answer to "(fica no dia, mesmo após trocas)".
///
/// The owner asked for those parenthetical explanations to leave the labels and
/// become tooltips. On Android a plain `Tooltip` only appears on a LONG PRESS,
/// which nobody discovers, so the explanation would have been hidden rather than
/// moved. This is the affordance that actually works: a small ⓘ next to the
/// label, and the tooltip opens on a normal tap.
class AppInfoTip extends StatelessWidget {
  final String message;

  const AppInfoTip({super.key, required this.message});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: message,
        triggerMode: TooltipTriggerMode.tap,
        showDuration: const Duration(seconds: 6),
        preferBelow: false,
        margin: const EdgeInsets.symmetric(horizontal: Spacing.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.xs),
          child: Icon(Icons.info_outline,
              size: TypeScale.subtitle, color: context.tokens.textMuted),
        ),
      );
}

/// The label above a control that is not an [AppTextField] — a dropdown, a pair
/// of time pickers, a row of chips.
///
/// It carries the two things U-28 QA settled: the explanation moves into an
/// [AppInfoTip], and whether a field is OPTIONAL is said in one consistent
/// place. Required is the default and goes unmarked — most fields in this app
/// are required, so marking them would be noise on every screen.
class AppFieldLabel extends StatelessWidget {
  final String text;

  /// What used to live in parentheses after the label.
  final String? info;

  /// Renders the "opcional" marker. The catalog owns the word.
  final String? optionalLabel;

  /// A badge that belongs to the label rather than to the control under it —
  /// the day sheet marks a swapped day here.
  final Widget? trailing;

  const AppFieldLabel(this.text,
      {super.key, this.info, this.optionalLabel, this.trailing});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.xs),
      child: Row(
        children: [
          Flexible(child: Text(text, style: textTheme.titleSmall)),
          if (optionalLabel != null) ...[
            const SizedBox(width: Spacing.xs),
            Text(optionalLabel!,
                style: textTheme.labelSmall?.copyWith(color: tokens.textMuted)),
          ],
          if (info != null) AppInfoTip(message: info!),
          if (trailing != null) ...[
            const SizedBox(width: Spacing.xs),
            trailing!,
          ],
        ],
      ),
    );
  }
}
