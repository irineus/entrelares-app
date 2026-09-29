import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/child.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/analytics_service.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/ui/ui.dart';

/// `/family/children` — the child entity's page (F-55 PR 1).
///
/// Read at rest, edited in a sheet (U-21): the name sits on the page and the
/// admin's pencil opens the editor, which also carries *Remover* as its one
/// destructive action (U-38). Every member reads; only an admin writes — the
/// server refuses anyone else, and with `feature.child_agenda` off it refuses
/// everyone, so the row that leads here only exists while the flag is on.
///
/// F-07 (28/09/2026): more than one child. The add door stays open up to
/// `children.max_per_family`; from `children.free_max` on, a free family meets
/// the Premium gate as a banner that carries its own action (U-49), landing on
/// `/family/plan` (U-35). A downgrade takes no child away — `add_child` only
/// refuses the NEXT one, and [ChildRules.addBlock] mirrors exactly that.
class FamilyChildrenScreen extends StatefulWidget {
  final CustodyDataSource dataSource;

  /// Where the Premium gate lands (`/family/plan`). Null hides the action.
  final VoidCallback? onOpenPlan;
  final AnalyticsService? analytics;

  const FamilyChildrenScreen({
    super.key,
    required this.dataSource,
    this.onOpenPlan,
    this.analytics,
  });

  @override
  State<FamilyChildrenScreen> createState() => _FamilyChildrenScreenState();
}

enum _SheetOutcome { saved, removed }

class _FamilyChildrenScreenState extends State<FamilyChildrenScreen> {
  bool _loading = true;
  bool _loadFailed = false;
  bool _isAdmin = false;
  bool _isPremium = false;
  String _mode = ScheduleModeRules.single;
  PublicSettings _settings = PublicSettings.unloaded;
  List<Child> _children = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final results = await Future.wait([
        widget.dataSource.fetchChildren(),
        widget.dataSource.fetchOwnProfile(),
        widget.dataSource.fetchOwnFamily(),
        widget.dataSource.fetchPublicSettings(),
      ]);
      if (!mounted) return;
      final me = results[1] as Member?;
      setState(() {
        _children = results[0] as List<Child>;
        _isAdmin = me != null && me.isAdmin && !me.hasLeft;
        final family = results[2] as Family?;
        // F-32 mirror, fail-closed: no family row → free.
        _isPremium = Family.isPremiumFamily(family, DateTime.now().toUtc());
        _mode = family?.scheduleMode ?? ScheduleModeRules.single;
        _settings = PublicSettings(results[3] as Map<String, String>);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _openAdd(Localization l) async {
    final outcome = await showAppSheet<_SheetOutcome>(
      context: context,
      builder: (_) => _ChildNameSheet(
        title: l[KApp.childAdd],
        initialName: '',
        onSave: (name) async {
          await widget.dataSource.addChild(name);
        },
      ),
    );
    await _afterSheet(l, outcome, savedKey: KApp.childAdded);
  }

  Future<void> _openEdit(Localization l, Child child) async {
    final outcome = await showAppSheet<_SheetOutcome>(
      context: context,
      builder: (_) => _ChildNameSheet(
        title: l[KApp.childRename],
        initialName: child.firstName,
        onSave: (name) => widget.dataSource
            .renameChild(childId: child.id, firstName: name),
        onRemove: () => widget.dataSource.removeChild(child.id),
      ),
    );
    await _afterSheet(l, outcome, savedKey: KApp.childRenamed);
  }

  Future<void> _afterSheet(Localization l, _SheetOutcome? outcome,
      {required String savedKey}) async {
    if (outcome == null || !mounted) return;
    showAppSnack(context,
        l[outcome == _SheetOutcome.removed ? KApp.childRemoved : savedKey]);
    await _load();
  }

  void _goToPremium() {
    widget.analytics?.trackEvent(AnalyticsEvents.premiumGateClick,
        props: {'gate': 'extra-child'});
    widget.onOpenPlan?.call();
  }

  /// The admin's door under the list: the add button, the Premium gate, or
  /// the ceiling — whichever `add_child` would answer next.
  Widget _addDoor(BuildContext context, Localization l) {
    final block = ChildRules.addBlock(
      childrenTaken: _children.length,
      isPremium: _isPremium,
      freeMax: _settings.childrenFreeMax,
      maxPerFamily: _settings.childrenMaxPerFamily,
    );
    final free = _settings.childrenFreeMax;
    return switch (block) {
      ChildAddBlock.none => Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            key: const ValueKey('child-add-another'),
            onPressed: () => _openAdd(l),
            icon: const Icon(Icons.add),
            label: Text(l[KApp.childAddAnother]),
          ),
        ),
      ChildAddBlock.freeCap => AppBanner(
          key: const ValueKey('child-free-cap'),
          tone: context.tokens.info,
          icon: Icons.lock_outline,
          // U-57: the number is the live `children.free_max`.
          message: l.format(
              free == 1 ? KApp.childFreeCapOne : KApp.childFreeCapMany, [free]),
          actionLabel: widget.onOpenPlan == null ? null : l[K.famSeePremium],
          actionIcon: widget.onOpenPlan == null ? null : Icons.auto_awesome,
          onAction: widget.onOpenPlan == null ? null : _goToPremium,
        ),
      ChildAddBlock.maxCap => Text(
          l.format(KApp.childMaxCap, [_settings.childrenMaxPerFamily]),
          key: const ValueKey('child-max-cap'),
          style: Theme.of(context).textTheme.bodySmall),
    };
  }

  /// F-07 (PR 3) — the plan's mode: one plan for every child, or one per
  /// child. Everyone reads the state; the switch is the admin's, through a
  /// sheet that says what moves (today on) and what never does (the past).
  Widget _planCard(BuildContext context, Localization l) {
    final offer = ScheduleModeRules.offer(
      flagOn: _settings.perChildScheduleEnabled,
      mode: _mode,
      childCount: _children.length,
    );
    if (offer == ScheduleModeOffer.hidden) return const SizedBox.shrink();
    final textTheme = Theme.of(context).textTheme;
    final perChild = offer == ScheduleModeOffer.toSingle;
    return AppCard(
      key: const ValueKey('child-plan-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l[KApp.childPlanTitle], style: textTheme.titleSmall),
          const SizedBox(height: Spacing.xs),
          Text(
              l[perChild ? KApp.childPlanPerChild : KApp.childPlanSingle],
              key: const ValueKey('child-plan-state'),
              style: textTheme.bodyMedium),
          if (offer == ScheduleModeOffer.needsTwoChildren) ...[
            const SizedBox(height: Spacing.xs),
            Text(l[KApp.childPlanNeedsTwo], style: textTheme.bodySmall),
          ],
          if (_isAdmin &&
              (offer == ScheduleModeOffer.toPerChild || perChild)) ...[
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                key: const ValueKey('child-plan-switch'),
                onPressed: () => _openModeSheet(l, toPerChild: !perChild),
                child: Text(l[perChild
                    ? KApp.childPlanToSingle
                    : KApp.childPlanToPerChild]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openModeSheet(Localization l, {required bool toPerChild}) async {
    final switched = await showAppSheet<bool>(
      context: context,
      builder: (_) => _PlanModeSheet(
        toPerChild: toPerChild,
        children: _children,
        onSwitch: (baseChildId) => widget.dataSource.setScheduleMode(
            toPerChild ? ScheduleModeRules.perChild : ScheduleModeRules.single,
            baseChildId: baseChildId),
      ),
    );
    if (switched != true || !mounted) return;
    showAppSnack(context, l[KApp.childPlanSwitched]);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      appBar: AppBar(title: Text(l[KApp.childTitle])),
      body: _body(context, l),
    );
  }

  Widget _body(BuildContext context, Localization l) {
    if (_loading) return AppSkeletonList(semanticsLabel: l[KApp.childTitle]);
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l[KApp.childErrLoad]),
            const SizedBox(height: Spacing.sm + Spacing.xs),
            FilledButton(onPressed: _load, child: Text(l[K.layoutErrorReload])),
          ],
        ),
      );
    }
    final textTheme = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(l[KApp.childLead], style: textTheme.bodyMedium),
          const SizedBox(height: Spacing.md),
          if (_children.isEmpty)
            AppEmptyState(
              key: const ValueKey('children-empty'),
              icon: Icons.child_care_outlined,
              title: l[KApp.childEmpty],
              body: _isAdmin ? null : l[KApp.childAdminOnly],
              actionLabel: _isAdmin ? l[KApp.childAdd] : null,
              onAction: _isAdmin ? () => _openAdd(l) : null,
            )
          else ...[
            for (final child in _children)
              Card(
                key: ValueKey('child-${child.id}'),
                margin: const EdgeInsets.only(bottom: Spacing.sm),
                child: ListTile(
                  leading: const Icon(Icons.child_care_outlined),
                  title: Text(child.firstName),
                  trailing: _isAdmin
                      ? IconButton(
                          key: ValueKey('child-edit-${child.id}'),
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: l[KApp.childRename],
                          onPressed: () => _openEdit(l, child),
                        )
                      : null,
                ),
              ),
            if (_isAdmin) ...[
              const SizedBox(height: Spacing.sm),
              _addDoor(context, l),
            ] else
              Text(l[KApp.childAdminOnly], style: textTheme.bodySmall),
            const SizedBox(height: Spacing.md),
            _planCard(context, l),
          ],
        ],
      ),
    );
  }
}

/// The name editor. [onSave] / [onRemove] THROW on a server refusal: the sheet
/// shows the sentence and stays open (the U-21 contract of profile_sheets).
class _ChildNameSheet extends StatefulWidget {
  final String title;
  final String initialName;
  final Future<void> Function(String name) onSave;
  final Future<void> Function()? onRemove;

  const _ChildNameSheet({
    required this.title,
    required this.initialName,
    required this.onSave,
    this.onRemove,
  });

  @override
  State<_ChildNameSheet> createState() => _ChildNameSheetState();
}

class _ChildNameSheetState extends State<_ChildNameSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);
  String? _error;
  bool _busy = false;
  bool _confirmingRemove = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _run(Localization l, Future<void> Function() action,
      _SheetOutcome outcome) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop(outcome);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _confirmingRemove = false;
        _error = translateSaveError(e.toString(), l[K.errSaveFailed], l);
      });
    }
  }

  void _save(Localization l) {
    // The client's half: the two cheap checks, in the RPC's own words.
    final error = ChildRules.validateName(_name.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    _run(l, () => widget.onSave(ChildRules.normalize(_name.text)),
        _SheetOutcome.saved);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final onRemove = widget.onRemove;
    return AppSheetFrame(
      title: widget.title,
      busy: _busy,
      primaryLabel: l[K.commonSave],
      onPrimary: () => _save(l),
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      extraAction: onRemove == null
          ? null
          : AppSheetDangerAction(
              key: const ValueKey('child-remove'),
              label: l[KApp.childRemove],
              icon: Icons.delete_outline,
              onPressed: _busy
                  ? null
                  : () => setState(() => _confirmingRemove = true),
            ),
      confirmation: onRemove == null || !_confirmingRemove
          ? null
          : AppSheetConfirmation.destructive(
              key: const ValueKey('child-remove-confirm'),
              message:
                  l.format(KApp.childRemoveConfirm, [widget.initialName]),
              yesLabel: l[KApp.childRemove],
              onYes: () => _run(l, onRemove, _SheetOutcome.removed),
              noLabel: l[K.commonCancel],
              onNo: () => setState(() => _confirmingRemove = false),
              busy: _busy,
            ),
      children: [
        AppTextField(
          key: const ValueKey('child-name-field'),
          label: l[KApp.childNameLabel],
          controller: _name,
          maxLength: ChildRules.maxNameLength,
          errorText: _error,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(l),
        ),
      ],
    );
  }
}

/// F-07 (PR 3) — the plan-mode switch. To one plan per child it only
/// confirms; back to one plan for everyone it asks WHOSE plan becomes the
/// family's (the server refuses without one). [onSwitch] throws on a refusal
/// (a pending request, the flag): the sheet shows the sentence and stays open.
class _PlanModeSheet extends StatefulWidget {
  final bool toPerChild;
  final List<Child> children;
  final Future<void> Function(int? baseChildId) onSwitch;

  const _PlanModeSheet({
    required this.toPerChild,
    required this.children,
    required this.onSwitch,
  });

  @override
  State<_PlanModeSheet> createState() => _PlanModeSheetState();
}

class _PlanModeSheetState extends State<_PlanModeSheet> {
  int? _base;
  bool _busy = false;
  String? _error;

  Future<void> _go(Localization l) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSwitch(widget.toPerChild ? null : _base);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = translateSaveError(e.toString(), l[K.errSaveFailed], l);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final base = widget.children.where((c) => c.id == _base).firstOrNull;
    final ready = widget.toPerChild || base != null;
    return AppSheetFrame(
      title: l[KApp.childPlanTitle],
      busy: _busy,
      error: _error,
      primaryLabel: widget.toPerChild
          ? l[KApp.childPlanToPerChild]
          : base == null
              ? l[KApp.childPlanToSingle]
              : l.format(KApp.childPlanUseChild, [base.firstName]),
      onPrimary: ready ? () => _go(l) : null,
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      children: [
        Text(l[widget.toPerChild
            ? KApp.childPlanToPerChildConfirm
            : KApp.childPlanToSingleLead]),
        if (!widget.toPerChild) ...[
          const SizedBox(height: Spacing.md),
          Wrap(
            key: const ValueKey('child-plan-base'),
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final c in widget.children)
                ChoiceChip(
                  key: ValueKey('child-plan-base-${c.id}'),
                  label: Text(c.firstName),
                  selected: _base == c.id,
                  onSelected:
                      _busy ? null : (_) => setState(() => _base = c.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
