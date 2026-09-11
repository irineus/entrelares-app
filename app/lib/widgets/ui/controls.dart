/// U-27 — the components the reader ACTS through: the field, the choice, the
/// pair of buttons that ends a form, and the avatar that says whose row this is.
library;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// A text field with a label that is always visible.
///
/// That is the accessibility decision of this item, not a style preference: the
/// field border is a light hairline (`#E5E7EB` measures ≈1.2:1 against the card
/// it sits on, where WCAG 1.4.11 asks 3:1), and the norm's other accepted
/// closure is a persistent visible label. A bare placeholder that disappears the
/// moment someone types would leave the field with no accessible name at all.
class AppTextField extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final String? initialValue;
  final String? hint;
  final String? helper;

  /// A helper here is a sentence, not a word — `register`'s family-name hint is
  /// three lines long — so the default is generous instead of Material's one.
  final int helperMaxLines;
  final String? errorText;
  final bool obscureText;
  final bool enabled;
  final int? maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final Widget? suffixIcon;
  final bool autofocus;
  final bool readOnly;

  /// Passed straight through: the browser and the OS keychain fill these, and
  /// the invite flow's e-mail field is `readOnly` precisely because the
  /// database trigger refuses any address but the invited one.
  final List<String>? autofillHints;
  final TextCapitalization textCapitalization;

  /// A counter under the field is noise when the limit exists to protect the
  /// column, not to pace the writer — the app hides it everywhere it caps a
  /// name, so hiding is the default here.
  final bool showCounter;

  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.initialValue,
    this.hint,
    this.helper,
    this.helperMaxLines = 3,
    this.errorText,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.suffixIcon,
    this.autofocus = false,
    this.readOnly = false,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.showCounter = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: initialValue,
      obscureText: obscureText,
      enabled: enabled,
      maxLines: obscureText ? 1 : maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onChanged: onChanged,
      onFieldSubmitted: onSubmitted,
      validator: validator,
      autofocus: autofocus,
      readOnly: readOnly,
      autofillHints: autofillHints,
      textCapitalization: textCapitalization,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: helperMaxLines,
        errorText: errorText,
        suffixIcon: suffixIcon,
        counterText: showCounter || maxLength == null ? null : '',
      ),
    );
  }
}

/// One choice among a few, as a segmented control — the app's default for a
/// filter with two to four options.
///
/// It deliberately does NOT decide to become a dropdown past some count: how
/// many options still fit is a screen's judgement, and silently changing a
/// four-tab filter into a menu would change how people navigate it.
class AppSegmented<T> extends StatelessWidget {
  final List<({T value, String label})> options;
  final T selected;
  final ValueChanged<T> onChanged;

  /// Read out instead of the segments when the control's purpose is not
  /// obvious from the labels alone (the PDF period picker leans on this).
  final String? semantics;

  /// A filter that is mid-load takes no new choice — the audit tab would
  /// otherwise fire a second read over the first.
  final bool enabled;

  const AppSegmented({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.semantics,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = SegmentedButton<T>(
      segments: [
        for (final o in options)
          ButtonSegment(value: o.value, label: Text(o.label)),
      ],
      selected: {selected},
      // The check mark eats the label's room on a phone, and the fill already
      // says which one is chosen.
      showSelectedIcon: false,
      onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
    );
    return semantics == null
        ? button
        : Semantics(label: semantics, child: button);
  }
}

/// The pair of buttons that ends a form or a confirmation, in THIS app's order:
/// the confirming action FIRST, the way out after it.
///
/// That is not Material's default order, and it is deliberate — it is the order
/// the Blazor app has used since it shipped (`bulk-delete-actions`, every
/// `AlertDialog` here), and the people who meet the Flutter app at the cutover
/// arrive with that muscle memory. Parity is the floor; a silently mirrored
/// confirmation is exactly the kind of change that costs a wrong tap.
///
/// [busy] disables both and puts a spinner in the primary — a form mid-save
/// must not offer a cancel that races the write it cannot recall.
class AppActionPair extends StatelessWidget {
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool busy;

  /// A destructive primary (delete, leave, revoke) takes the danger tone.
  final bool destructive;

  const AppActionPair({
    super.key,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
    this.busy = false,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final primary = FilledButton(
      onPressed: busy ? null : onPrimary,
      style: destructive
          ? FilledButton.styleFrom(
              backgroundColor: tokens.danger.solid,
              foregroundColor: tokens.danger.onSolid)
          : null,
      child: busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : Text(primaryLabel),
    );
    if (secondaryLabel == null) {
      return SizedBox(width: double.infinity, child: primary);
    }
    return Row(
      children: [
        primary,
        const SizedBox(width: Spacing.sm),
        OutlinedButton(
          onPressed: busy ? null : onSecondary,
          child: Text(secondaryLabel!),
        ),
      ],
    );
  }
}

/// Whose row this is. When a [slot] is given the avatar wears that carer's
/// calendar identity — the same fill, the same texture — so the person is
/// recognisable across the grid, the legend and every list that names them.
class AppAvatar extends StatelessWidget {
  final String initials;
  final SlotColors? slot;
  final double radius;

  const AppAvatar({
    super.key,
    required this.initials,
    this.slot,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    final tone = slot?.tone;
    final label = Text(
      initials,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: tone?.onSolid,
            fontSize: radius * 0.7,
          ),
    );
    if (slot == null) return CircleAvatar(radius: radius, child: label);
    return CircleAvatar(
      radius: radius,
      backgroundColor: tone!.solid,
      child: label,
    );
  }
}
