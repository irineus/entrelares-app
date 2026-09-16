import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'app_l10n.dart';
import 'ui/ui.dart';

/// U-44 — "Você é…", shared by the register form and the OAuth onboarding, so
/// the two doors into a new family ask the question the same way.
///
/// The common roles are chips ([RoleCatalog.shortlist]); every other built-in
/// sits behind "Outro…", a sheet that lists them one per row. It replaced a
/// wrap of all 21 chips, which the closed alpha of 09/09/2026 named as the
/// screen's wall. A common role is one tap; any of the 21 is two.
///
/// A role picked in the sheet shows up as a SELECTED chip before "Outro…", so
/// the answer stays on screen — a sheet that closes over a choice nobody can
/// see reads as a choice that did not happen.
class RolePicker extends StatelessWidget {
  /// The canonical name of the chosen role, or null before a choice.
  final String? selected;
  final ValueChanged<String> onSelected;

  const RolePicker({
    super.key,
    required this.selected,
    required this.onSelected,
  });

  /// "Outro…", addressable without a localized finder.
  static const otherKey = Key('role-picker-other');

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final picked = selected == null ? null : RoleCatalog.find(selected!);
    final pickedOther = picked != null &&
        !RoleCatalog.signUpShortlist.contains(picked.canonicalName);
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final role in RoleCatalog.shortlist)
          ChoiceChip(
            label: Text(role.labelFor(l.current)),
            selected: selected == role.canonicalName,
            onSelected: (_) => onSelected(role.canonicalName),
          ),
        if (pickedOther)
          ChoiceChip(
            label: Text(picked.labelFor(l.current)),
            selected: true,
            onSelected: (_) => _openOthers(context),
          ),
        ActionChip(
          key: otherKey,
          label: Text(l[KApp.roleOther]),
          onPressed: () => _openOthers(context),
        ),
      ],
    );
  }

  Future<void> _openOthers(BuildContext context) async {
    final l = AppL10n.of(context).l;
    final chosen = await showAppSheet<String>(
      context: context,
      builder: (sheetContext) => AppSheetFrame(
        title: l[KApp.roleOtherTitle],
        onClose: () => Navigator.of(sheetContext).pop(),
        closeLabel: l[K.commonClose],
        children: [
          for (final role in RoleCatalog.others)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(role.labelFor(l.current)),
              selected: selected == role.canonicalName,
              trailing: selected == role.canonicalName
                  ? const Icon(Icons.check)
                  : null,
              onTap: () => Navigator.of(sheetContext).pop(role.canonicalName),
            ),
        ],
      ),
    );
    if (chosen != null) onSelected(chosen);
  }
}
