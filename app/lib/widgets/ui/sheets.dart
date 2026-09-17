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
///
/// U-38 finished the thought. A pinned "Salvar" means the finger is at the
/// BOTTOM of the sheet and the eyes may be anywhere in the scroll, so whatever
/// that tap produces must appear where it can be seen from there: a failure is
/// pinned under the title ([AppSheetFrame.error]), a question takes the action
/// row's own place ([AppSheetFrame.confirmation]), and a destructive action has
/// one slot and one look ([AppSheetDangerAction]).
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import 'signals.dart';

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

  /// U-38: what went wrong with the sheet's last action — a danger [AppBanner]
  /// pinned under the title, never at the end of the scroll, where a tap on the
  /// pinned action row produced a failure nobody saw. A parameter rather than a
  /// convention, so a sheet cannot put it anywhere else.
  final String? error;

  /// U-38: a question the last tap raised ("this rewrites 3 planned days…").
  /// It REPLACES the action row, in the action row's place, because the finger
  /// is already there. While it is set neither the action row nor
  /// [extraAction] is drawn: the question's own buttons are the way out.
  final Widget? confirmation;

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

  /// A third action that belongs with the others but is not the answer. U-38:
  /// this is THE place for a destructive-but-legitimate action ("Limpar dia",
  /// "Limpar dias", "Cancelar solicitação"), drawn as an [AppSheetDangerAction]
  /// — never a red text button tucked into a field's label row.
  final Widget? extraAction;

  final bool busy;

  /// U-25: a visible way out, at the end of the title row. The closed alpha's
  /// "falta um botão voltar" was said over a sheet that already closed on a
  /// backdrop tap and on a drag — neither was found. Null draws no ✕; a sheet
  /// that must not be dismissed simply does not pass it.
  final VoidCallback? onClose;

  /// The ✕'s tooltip and its screen-reader name — the catalog's "Fechar".
  final String? closeLabel;

  /// U-25: small icon actions that sit BEFORE the ✕ on the title row — the day
  /// sheet's pencil. Chrome, not the sheet's answer: that stays in the pinned
  /// action row.
  final List<Widget> headerActions;

  const AppSheetFrame({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.pinnedNotice,
    this.error,
    this.confirmation,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.extraAction,
    this.busy = false,
    this.onClose,
    this.closeLabel,
    this.headerActions = const [],
  });

  /// The ✕'s key, so a flow test can close any sheet without a localized
  /// finder.
  static const closeKey = Key('sheet-close');

  /// The pinned failure banner, so a test can measure where it sits.
  static const errorKey = Key('sheet-error');

  /// The strip that holds a [confirmation], for the same reason.
  static const confirmationKey = Key('sheet-confirmation');

  /// The scrolling body — what "pinned" is measured against.
  static const bodyKey = Key('sheet-body');

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
            padding: EdgeInsets.fromLTRB(Spacing.md, 0,
                onClose == null && headerActions.isEmpty ? Spacing.md : Spacing.xs,
                Spacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
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
                ...headerActions,
                if (onClose != null)
                  IconButton(
                    key: closeKey,
                    icon: const Icon(Icons.close),
                    tooltip: closeLabel,
                    color: tokens.textMuted,
                    // A save in flight is not abandoned by a stray tap; the
                    // ✕ comes back with the result.
                    onPressed: busy ? null : onClose,
                  ),
              ],
            ),
          ),
          // U-38: the failure comes first — it is about the tap just made, and
          // the guards under it were on screen before that tap.
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, 0, Spacing.md, Spacing.sm),
              child: Semantics(
                liveRegion: true,
                child: AppBanner(
                    key: errorKey,
                    tone: tokens.danger,
                    icon: Icons.error_outline,
                    message: error!),
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
              key: bodyKey,
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, 0, Spacing.md, Spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
          if (confirmation != null)
            _confirmation(context, tokens)
          else if (primaryLabel != null || extraAction != null)
            _actions(context, tokens),
        ],
      ),
    );
  }

  /// The action row's own surface, holding the question instead. Capped at
  /// half the screen and scrollable inside: a question that quotes two notes
  /// (F-47) must not squeeze the sheet's body to nothing.
  Widget _confirmation(BuildContext context, AppTokens tokens) => Container(
        key: confirmationKey,
        decoration: BoxDecoration(
          color: tokens.surfaceAlt,
          border: Border(top: BorderSide(color: tokens.outline)),
        ),
        constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.5),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                Spacing.md, Spacing.sm, Spacing.md, Spacing.sm),
            child: confirmation,
          ),
        ),
      );

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

/// U-38: the question a sheet's pinned action raised, for
/// [AppSheetFrame.confirmation]. Three sheets carried private copies of this
/// box (the day sheet, the bulk sheet twice, the wizard), and every copy
/// rendered inside the scroll while the action row vanished.
///
/// The [tone] is the question's weight: danger (the default) for "this
/// rewrites planned days", warning for "which note should the revert keep"
/// (F-47). [details] sits between the sentence and the [actions].
class AppSheetConfirmation extends StatelessWidget {
  final String message;
  final ToneColors? tone;
  final IconData icon;
  final List<Widget> details;
  final Widget actions;

  const AppSheetConfirmation({
    super.key,
    required this.message,
    required this.actions,
    this.tone,
    this.icon = Icons.warning_amber_rounded,
    this.details = const [],
  });

  /// The common case: a destructive yes and a way back — the confirmation
  /// first, the way out after it (U-27).
  factory AppSheetConfirmation.destructive({
    Key? key,
    required String message,
    required String yesLabel,
    required VoidCallback onYes,
    required String noLabel,
    required VoidCallback onNo,
    bool busy = false,
  }) =>
      AppSheetConfirmation(
        key: key,
        message: message,
        actions: _HalfAndHalf(
          yesLabel: yesLabel,
          onYes: onYes,
          noLabel: noLabel,
          onNo: onNo,
          busy: busy,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = tone ?? context.tokens.danger;
    // The box the private copies drew, kept: the owner reviewed it (U-28 QA)
    // and its weight is the point — only its PLACE was wrong.
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Spacing.sm + Spacing.xs),
        decoration: BoxDecoration(
          color: t.container,
          border: Border.all(color: t.border),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: t.onContainer),
                const SizedBox(width: Spacing.sm),
                Expanded(
                  child: Text(message,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: t.onContainer)),
                ),
              ],
            ),
            if (details.isNotEmpty) ...[
              const SizedBox(height: Spacing.sm),
              ...details,
            ],
            const SizedBox(height: Spacing.sm),
            actions,
          ],
        ),
      ),
    );
  }
}

/// The yes/no of [AppSheetConfirmation.destructive], shaped like the action
/// row it stands in for: two halves, so a long label wraps inside its button
/// instead of pushing the pair off a narrow phone (AppActionPair sizes to its
/// labels, which suits a wide dialog and not this row).
class _HalfAndHalf extends StatelessWidget {
  final String yesLabel;
  final VoidCallback onYes;
  final String noLabel;
  final VoidCallback onNo;
  final bool busy;

  const _HalfAndHalf({
    required this.yesLabel,
    required this.onYes,
    required this.noLabel,
    required this.onNo,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            onPressed: busy ? null : onYes,
            style: FilledButton.styleFrom(
                backgroundColor: tokens.danger.solid,
                foregroundColor: tokens.danger.onSolid),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(yesLabel, textAlign: TextAlign.center),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : onNo,
            child: Text(noLabel, textAlign: TextAlign.center),
          ),
        ),
      ],
    );
  }
}

/// U-38: the one look of a destructive action in a sheet — outlined, in the
/// danger tone, in [AppSheetFrame.extraAction]. "Limpar dia" had it, "Limpar
/// dias" was a red text button in a label row, and "Cancelar solicitação" was
/// danger ink on a neutral border: three looks for one meaning.
class AppSheetDangerAction extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// A spinner in place of the icon while THIS action is in flight.
  final bool busy;

  const AppSheetDangerAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.delete_outline,
    this.busy = false,
  });

  /// The same outline for a destructive button that shares a row with others.
  static ButtonStyle styleOf(BuildContext context) => OutlinedButton.styleFrom(
        foregroundColor: context.tokens.danger.onContainer,
        side: BorderSide(color: context.tokens.danger.border),
      );

  @override
  Widget build(BuildContext context) {
    const spinner = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2));
    if (icon == null) {
      return OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: styleOf(context),
        child: busy ? spinner : Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: busy ? null : onPressed,
      style: styleOf(context),
      icon: busy ? spinner : Icon(icon),
      label: Text(label),
    );
  }
}

/// U-38: "Limpar" trailing a field's label in a batch editor — ticked, the
/// batch CLEARS that field on every selected day instead of leaving it alone.
/// The bulk sheet has three; the next batch editor takes this control rather
/// than writing a fourth copy.
///
/// Not for an OPTION that changes what a whole action does (the wizard's
/// "substituir dias planejados", F-51): that is a checkbox with a hint, and a
/// different question.
class AppClearToggle extends StatelessWidget {
  final String label;
  final bool value;

  /// Null disables it — the field holds a value that makes clearing
  /// meaningless, or the sheet is busy.
  final ValueChanged<bool>? onChanged;

  const AppClearToggle({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged:
                  onChanged == null ? null : (v) => onChanged!(v ?? false),
              visualDensity: VisualDensity.compact,
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
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
          // U-48: the explanation rides the LABEL's semantics as its hint —
          // "Observação do dia, fica no dia mesmo depois de trocas" — so a
          // screen reader gets it where the label is read, on every channel.
          // The ⓘ stays the sighted reader's door and is excluded from the
          // tree: a `Tooltip` announces its message on the web only while
          // it is open, and it closes itself after six seconds, so the same
          // sentence twice from one node and never from the other was the
          // worst of both.
          Flexible(
            child: Semantics(
              hint: info,
              child: Text(text, style: textTheme.titleSmall),
            ),
          ),
          if (optionalLabel != null) ...[
            const SizedBox(width: Spacing.xs),
            Text(optionalLabel!,
                style: textTheme.labelSmall?.copyWith(color: tokens.textMuted)),
          ],
          if (info != null) ExcludeSemantics(child: AppInfoTip(message: info!)),
          if (trailing != null) ...[
            const SizedBox(width: Spacing.xs),
            trailing!,
          ],
        ],
      ),
    );
  }
}
