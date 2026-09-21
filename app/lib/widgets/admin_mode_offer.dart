import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'app_l10n.dart';
import 'ui/ui.dart';

/// F-67 Part B: the question, for flow tests and for the U-32 scene.
const adminModeOfferKey = Key('admin-mode-offer');

/// F-67 Part B — *"(ação) exige o modo administrador. Ativar agora?"* in a
/// sheet's action row (U-38: the question a tap raised takes the row's place,
/// where the finger is). The danger weight is the mode's own: its shield turns
/// the danger ink and the shell's banner is danger-toned while it is on.
///
/// The sheet decides what "carry through" means; this only asks.
class AdminModeOfferConfirmation extends StatelessWidget {
  final AdminModeAction action;
  final VoidCallback onActivate;
  final VoidCallback onCancel;

  const AdminModeOfferConfirmation({
    super.key = adminModeOfferKey,
    required this.action,
    required this.onActivate,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return AppSheetConfirmation.destructive(
      message: l[adminModeOfferMessageKey(action)],
      icon: Icons.shield_outlined,
      details: [
        Text(l[KApp.adminOfferHow],
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: context.tokens.danger.onContainer)),
      ],
      yesLabel: l[K.navAdminEnter],
      onYes: onActivate,
      noLabel: l[K.commonCancel],
      onNo: onCancel,
    );
  }
}

/// The same question where there is no sheet to hold it — the calendar's ⋮
/// menu ("Limpar mês"). The dialog shape `_clearMonth` already uses: the
/// confirming action first, in the danger ink, the way out after it (U-27).
Future<bool> showAdminModeOfferDialog(
    BuildContext context, AdminModeAction action) async {
  final l = AppL10n.of(context).l;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      key: adminModeOfferKey,
      icon: const Icon(Icons.shield_outlined),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l[adminModeOfferMessageKey(action)]),
          const SizedBox(height: Spacing.sm),
          Text(l[KApp.adminOfferHow],
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
                foregroundColor: context.tokens.danger.onContainer),
            child: Text(l[K.navAdminEnter])),
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l[K.commonCancel])),
      ],
    ),
  );
  return yes == true;
}
