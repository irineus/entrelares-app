import 'package:flutter/material.dart';

import 'sheets.dart';

/// The one question a destructive action asks, as a sheet whose pinned row IS
/// the question (U-38's shape): the danger "yes" and the way back where a
/// sheet's actions always sit. Returns true only on "yes".
Future<bool> showDestructiveConfirm({
  required BuildContext context,
  required String title,
  required String message,
  required String yesLabel,
  required String noLabel,
}) async {
  final confirmed = await showAppSheet<bool>(
    context: context,
    builder: (context) => AppSheetFrame(
      title: title,
      confirmation: AppSheetConfirmation.destructive(
        message: message,
        yesLabel: yesLabel,
        onYes: () => Navigator.of(context).pop(true),
        noLabel: noLabel,
        onNo: () => Navigator.of(context).pop(false),
      ),
      children: const [],
    ),
  );
  return confirmed == true;
}
