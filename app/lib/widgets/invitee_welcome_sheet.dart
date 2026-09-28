import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_l10n.dart';
import 'ui/ui.dart';

/// U-58 — opens the invitee's welcome. Awaited by the calendar, so the tour
/// that follows starts only after the sheet is gone.
Future<void> showInviteeWelcomeSheet(
  BuildContext context, {
  required InviteeWelcome welcome,
  required bool viewer,
}) =>
    showAppSheet<void>(
      context: context,
      builder: (context) =>
          InviteeWelcomeSheet(welcome: welcome, viewer: viewer),
    );

/// Which family, who invited, and the three points [InviteeWelcomeRules]
/// picks for a caregiver or a Visualizador. One action: *Ver o calendário* —
/// the reader is already on it, so the action closes the sheet.
class InviteeWelcomeSheet extends StatelessWidget {
  final InviteeWelcome welcome;
  final bool viewer;

  const InviteeWelcomeSheet(
      {super.key, required this.welcome, required this.viewer});

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final textTheme = Theme.of(context).textTheme;
    return AppSheetFrame(
      title: l.format(KApp.welcomeTitle, [welcome.familyName]),
      subtitle: l.format(KApp.welcomeLead, [welcome.inviterName]),
      primaryLabel: l[KApp.welcomeAction],
      onPrimary: () => Navigator.of(context).pop(),
      secondaryLabel: null,
      children: [
        for (final key in InviteeWelcomeRules.pointKeys(viewer: viewer))
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.md),
            child: Text(l[key], style: textTheme.bodyMedium),
          ),
      ],
    );
  }
}
