import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The web's three toast types (`ToastService`), same visual language.
enum AppSnackType { success, error, info }

/// The Flutter face of the web's toast: one at a time (a new call replaces the
/// current one, as `ToastService.Show` overwrites), duration scaling with the
/// reading load ([snackDismissDelayMs]), and tappable to dismiss — a user who
/// already read a long summary doesn't have to wait it out.
///
/// [message] must come from the catalog (`l[K.x]`), never a literal — the
/// `no_literal_snack_test` gate scans call sites, as the web's
/// `NoToast_CarriesALiteralString` does.
void showAppSnack(BuildContext context, String message,
    {AppSnackType type = AppSnackType.success}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();

  // The web palette (MainLayout.razor.css .toast-*), now as U-27 tones — same
  // light values, and a dark set that exists because the tokens carry one.
  final t = context.tokens;
  final (tone, icon) = switch (type) {
    AppSnackType.success => (t.success, '✅'),
    AppSnackType.error => (t.danger, '❌'),
    AppSnackType.info => (t.info, 'ℹ️'),
  };

  messenger.showSnackBar(SnackBar(
    duration: Duration(milliseconds: snackDismissDelayMs(message.length)),
    behavior: SnackBarBehavior.floating,
    backgroundColor: tone.container,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radii.md),
      side: BorderSide(color: tone.border),
    ),
    content: GestureDetector(
      onTap: messenger.hideCurrentSnackBar,
      // QA (July 2026, inherited): the message never truncates — it wraps,
      // and the timer scales instead.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon),
          const SizedBox(width: Spacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  color: tone.onContainer,
                  fontSize: TypeScale.bodySmall,
                  fontWeight: FontWeight.w500,
                  height: 1.45),
            ),
          ),
        ],
      ),
    ),
  ));
}
