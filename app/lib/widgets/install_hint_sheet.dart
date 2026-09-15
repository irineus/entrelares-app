import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_l10n.dart';
import 'rich_label.dart';
import 'ui/ui.dart';

/// U-51 — the two steps that put the web app on an iPhone's Home Screen,
/// opened from the shell's install strip.
///
/// Text only, on purpose. The landing draws the Share sheet as a schematic
/// (L-19); a drawing in the app would have to be re-checked against Apple's
/// guide on its own schedule, and the steps are what a reader follows — the
/// landing's diagram is `aria-hidden` for the same reason. The copy lives in
/// the catalog beside a note saying where it was checked and when.
///
/// A read-only sheet: one *Fechar* and the drag handle. Nothing here is a
/// question the reader has to answer.
Future<void> showInstallHintSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    builder: (context) => const InstallHintSheet(),
  );
}

class InstallHintSheet extends StatelessWidget {
  const InstallHintSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    return AppSheetFrame(
      title: l[KApp.installHintTitle],
      subtitle: l[KApp.installHintSubtitle],
      primaryLabel: l[K.commonClose],
      onPrimary: () => Navigator.of(context).pop(),
      secondaryLabel: null,
      children: [
        _Step(number: 1, text: l[KApp.installHintStepShare]),
        const SizedBox(height: Spacing.md),
        _Step(number: 2, text: l[KApp.installHintStepAdd]),
        const SizedBox(height: Spacing.lg),
        Text(
          l[KApp.installHintNote],
          style: textTheme.bodySmall?.copyWith(color: tokens.textMuted),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;

  const _Step({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tone = context.tokens.info;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: tone.container,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: textTheme.labelLarge?.copyWith(color: tone.onContainer),
          ),
        ),
        const SizedBox(width: Spacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: RichLabel(text, style: textTheme.bodyMedium),
          ),
        ),
      ],
    );
  }
}
