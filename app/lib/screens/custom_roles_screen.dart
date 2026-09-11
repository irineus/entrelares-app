import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import '../services/analytics_service.dart';
import '../services/custody_data_source.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';

/// F-41 custom family roles — port of `CustomRolesPage.razor`.
///
/// Three asymmetries the port must keep, because each one is a decision:
///
/// * **Custom role names are never translated.** They are family data, not
///   product vocabulary, so a row shows exactly what was typed in every
///   language ([RoleCatalog] passes unknown values through).
/// * **Create and edit are Premium; delete is not.** A family whose Premium
///   lapses keeps its roles and can still clean them up — being unable to
///   delete would be a trap, not a gate.
/// * **The client validates only length and emoji.** Duplicates, the admin
///   check, the Premium gate and "role still in use" are the DB's, and its
///   sentences reach the user verbatim.
class CustomRolesScreen extends StatefulWidget {
  final CustodyDataSource dataSource;

  /// T-37 — optional: the funnel signal never gates the screen.
  final AnalyticsService? analytics;

  /// Takes the admin to the Premium section of the Família page. Null leaves
  /// the gate card as a plain explanation (which is all the web's is when the
  /// section is a scroll away).
  final VoidCallback? onSeePremium;

  const CustomRolesScreen({
    super.key,
    required this.dataSource,
    this.analytics,
    this.onSeePremium,
  });

  @override
  State<CustomRolesScreen> createState() => _CustomRolesScreenState();
}

class _CustomRolesScreenState extends State<CustomRolesScreen> {
  bool _loading = true;
  bool _isPremium = false;
  bool _isAdmin = false;
  List<Role> _roles = const [];

  final _label = TextEditingController();
  String? _emoji;
  int? _editingRoleId;
  int? _confirmingDeleteRoleId;
  String? _formError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  List<Role> get _customRoles =>
      _roles.where((role) => role.isCustom).toList();

  Future<void> _load() async {
    setState(() => _loading = true);
    final results = await Future.wait([
      widget.dataSource.fetchRoles(),
      widget.dataSource.fetchOwnFamily(),
      widget.dataSource.fetchOwnProfile(),
    ]);
    if (!mounted) return;
    setState(() {
      _roles = results[0] as List<Role>;
      _isPremium =
          Family.isPremiumFamily(results[1] as Family?, DateTime.now().toUtc());
      _isAdmin = (results[2] as dynamic)?.isAdmin == true;
      _loading = false;
    });
  }

  void _beginEdit(Role role) {
    setState(() {
      _editingRoleId = role.id;
      _label.text = role.roleName;
      _emoji = role.emoji;
      _formError = null;
      _confirmingDeleteRoleId = null;
    });
  }

  void _cancelEdit() {
    setState(() {
      _editingRoleId = null;
      _label.clear();
      _emoji = null;
      _formError = null;
    });
  }

  Future<void> _save(Localization l) async {
    // The client's half: length and emoji only. The message is the RPC's own
    // PT-BR wording, so a rule that trips here and one that trips server-side
    // read identically.
    final error = CustomRoleRules.validate(_label.text, _emoji);
    if (error != null) {
      setState(() => _formError = error);
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    final editingId = _editingRoleId;
    try {
      if (editingId != null) {
        await widget.dataSource.updateCustomRole(
            roleId: editingId, label: _label.text, emoji: _emoji);
      } else {
        await widget.dataSource
            .createCustomRole(label: _label.text, emoji: _emoji);
      }
      if (!mounted) return;
      showAppSnack(context,
          l[editingId != null ? KApp.rolesToastUpdated : K.rolesToastCreated]);
      _cancelEdit();
      setState(() => _saving = false);
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // Duplicate, not-admin, not-Premium, foreign role — all of these are
        // the RPC's sentences, and each one names the actual problem.
        _formError = translateSaveError(e.toString(), l[K.errSaveFailed], l);
      });
    }
  }

  Future<void> _delete(Role role, Localization l) async {
    setState(() => _confirmingDeleteRoleId = null);
    try {
      await widget.dataSource.deleteCustomRole(role.id);
      if (!mounted) return;
      if (_editingRoleId == role.id) _cancelEdit();
      await _load();
    } catch (e) {
      if (!mounted) return;
      // "This role is in use by a member or invitation" lives here.
      showAppSnack(context, translateSaveError(e.toString(), l[K.errDeleteFailed], l),
          type: AppSnackType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      appBar: AppBar(title: Text(l[K.rolesHeading])),
      body: _loading
          ? AppSkeletonList(
              rows: 3, leading: false, semanticsLabel: l[K.famLoading])
          : !_isAdmin
              // Admin-only, and the DB agrees — showing the form to a
              // non-admin would only produce a refusal they cannot act on.
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(l[K.famOnlyAdminsInvite],
                        textAlign: TextAlign.center),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text(l[K.rolesIntro],
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 16),
                    if (_customRoles.isEmpty)
                      Text(l[K.rolesEmpty])
                    else
                      ..._customRoles.map((role) => _roleRow(role, l)),
                    const SizedBox(height: 24),
                    if (_isPremium)
                      _form(l)
                    else
                      Card(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(l[K.rolesPremiumGate]),
                              if (widget.onSeePremium != null)
                                TextButton(
                                  // F-41: same funnel family as the other
                                  // gates (T-37), told apart by `gate`.
                                  onPressed: () {
                                    widget.analytics?.trackEvent(
                                        'premium-gate-click',
                                        props: {'gate': 'custom-roles'});
                                    widget.onSeePremium!();
                                  },
                                  child: Text(l[K.famSeePremium]),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _roleRow(Role role, Localization l) {
    final confirming = _confirmingDeleteRoleId == role.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          children: [
            Row(
              children: [
                // The RAW name, never translated — it is this family's word.
                Expanded(
                    child: Text(CustomRoleRules.displayLabel(
                        role.roleName, role.emoji))),
                if (_isPremium)
                  IconButton(
                    tooltip: l[K.rolesEditRole],
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _beginEdit(role),
                  ),
                IconButton(
                  tooltip: l[K.rolesDeleteRole],
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () =>
                      setState(() => _confirmingDeleteRoleId = role.id),
                ),
              ],
            ),
            if (confirming)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(child: Text(l[K.rolesDeleteConfirm])),
                    // U-29: the destructive answer wears the danger colour,
                    // like every other delete confirm in the app.
                    TextButton(
                      style: TextButton.styleFrom(
                          foregroundColor: context.tokens.danger.solid),
                      onPressed: () => _delete(role, l),
                      child: Text(l[K.rolesYes]),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _confirmingDeleteRoleId = null),
                      child: Text(l[K.rolesNo]),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _form(Localization l) {
    final editing = _editingRoleId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l[editing ? KApp.rolesEditTitle : KApp.rolesCreateTitle],
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        AppTextField(
          label: l[K.rolesNameLabel],
          hint: l[K.rolesNamePlaceholder],
          controller: _label,
          maxLength: CustomRoleRules.maxLabelLength,
          errorText: _formError,
          onChanged: (_) {
            if (_formError != null) setState(() => _formError = null);
          },
        ),
        const SizedBox(height: 12),
        Text(l[K.rolesEmojiLabel],
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            ChoiceChip(
              label: Text(l[KApp.rolesNoEmoji]),
              selected: _emoji == null || _emoji!.isEmpty,
              onSelected: (_) => setState(() => _emoji = null),
            ),
            for (final emoji in CustomRoleRules.emojiPalette)
              ChoiceChip(
                label: Text(emoji),
                selected: _emoji == emoji,
                onSelected: (_) => setState(() => _emoji = emoji),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : () => _save(l),
          child: Text(_saving
              ? l[K.rolesSaving]
              : l[editing ? K.rolesSaveEdit : K.rolesCreate]),
        ),
        if (editing) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: _saving ? null : _cancelEdit,
            child: Text(l[K.commonCancel]),
          ),
        ],
      ],
    );
  }
}
