import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/child.dart';
import 'package:entrelares_db_contracts/models/expense.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import '../widgets/account_button.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/ui/ui.dart';

/// `/expenses` — the shared expenses (F-34), its own tab.
///
/// Splitwise's logic with ONE difference: a payment between caregivers counts
/// in the balance only once the one who RECEIVED confirms it. The server holds
/// the facts (expenses, shares, settlements) and refuses every write it must
/// — flag off, a viewer, no Premium; the balance and the "fewest payments"
/// suggestion are computed here from the rows ([ExpenseLedger]).
///
/// One group per child. A viewer never sees this tab (the shell hides it and
/// RLS returns nothing); a family without Premium reads what it has, and the
/// writes are replaced by the Premium banner.
class ExpensesScreen extends StatefulWidget {
  final CustodyDataSource dataSource;

  /// Opens `/family/plan` — every Premium gate CTA lands there (U-35).
  final VoidCallback? onOpenPlan;

  final DateTime Function() now;

  const ExpensesScreen({
    super.key,
    required this.dataSource,
    this.onOpenPlan,
    this.now = DateTime.now,
  });

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

/// The group key of the expenses with no child (a family without a
/// registered child keeps its expenses here).
const int _familyGroup = -1;

class _ExpensesScreenState extends State<ExpensesScreen> {
  bool _loading = true;
  bool _loadFailed = false;
  PublicSettings _settings = PublicSettings.unloaded;
  Member? _me;
  Family? _family;
  List<Member> _members = const [];
  List<Child> _children = const [];
  List<Expense> _expenses = const [];
  List<ExpenseSettlement> _settlements = const [];
  int _group = _familyGroup;

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
      final results = await Future.wait<Object?>([
        widget.dataSource.fetchPublicSettings(),
        widget.dataSource.fetchOwnProfile(),
      ]);
      final settings = PublicSettings(results[0] as Map<String, String>);
      final me = results[1] as Member?;
      var members = const <Member>[];
      var children = const <Child>[];
      var expenses = const <Expense>[];
      var settlements = const <ExpenseSettlement>[];
      Family? family;
      if (settings.expensesEnabled && me != null && !me.isViewer) {
        final more = await Future.wait<Object?>([
          widget.dataSource.fetchMembers(),
          widget.dataSource.fetchOwnFamily(),
          widget.dataSource.fetchExpenses(),
          widget.dataSource.fetchSettlements(),
          widget.dataSource
              .fetchChildren()
              .catchError((Object _) => const <Child>[]),
        ]);
        members = more[0] as List<Member>;
        family = more[1] as Family?;
        expenses = more[2] as List<Expense>;
        settlements = more[3] as List<ExpenseSettlement>;
        children = more[4] as List<Child>;
      }
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _me = me;
        _members = members;
        _family = family;
        _children = children;
        _expenses = expenses;
        _settlements = settlements;
        final groups = _groups;
        if (!groups.contains(_group)) _group = groups.first;
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

  // ── derived ────────────────────────────────────────────────────────────

  /// The children's groups, then the family's own when it has anything (or
  /// when there is no child at all).
  List<int> get _groups {
    final hasFamilyRows = _expenses.any((e) => e.childId == null) ||
        _settlements.any((s) => s.childId == null);
    return [
      for (final c in _children) c.id,
      if (_children.isEmpty || hasFamilyRows) _familyGroup,
    ];
  }

  int? get _groupChildId => _group == _familyGroup ? null : _group;

  bool _inGroup(int? childId) => (childId ?? _familyGroup) == _group;

  bool get _canWrite {
    final me = _me;
    if (me == null || me.isViewer || me.hasLeft) return false;
    if (!_settings.expensesPremiumOnly) return true;
    return Family.isPremiumFamily(_family, widget.now().toUtc());
  }

  /// Who may pay, take part or receive: a caregiver with an account — the
  /// server's `expense_member_ok`.
  List<Member> get _eligible => [
        for (final m in _members)
          if (m.isActiveMember && !m.isViewer) m
      ];

  String _name(int profileId, Localization l) {
    for (final m in _members) {
      if (m.id == profileId) {
        final name = m.fullName.trim();
        return name.isEmpty ? l[KApp.expenseFormerMember] : name;
      }
    }
    return l[KApp.expenseFormerMember];
  }

  String _money(int cents, Localization l) =>
      ExpenseRules.brl(cents, english: l.isEnglish);

  // ── actions ────────────────────────────────────────────────────────────

  Future<void> _openEditor(Localization l, {Expense? editing}) async {
    final saved = await showAppSheet<bool>(
      context: context,
      builder: (_) => ExpenseEditorSheet(
        dataSource: widget.dataSource,
        settings: _settings,
        eligible: _eligible,
        me: _me!,
        childId: editing?.childId ?? _groupChildId,
        editing: editing,
        today: widget.now(),
      ),
    );
    if (saved != true || !mounted) return;
    showAppSnack(context, l[KApp.expenseSaved]);
    await _load();
  }

  Future<void> _openSettle(Localization l,
      {int? toProfileId, int? amountCents}) async {
    final sent = await showAppSheet<bool>(
      context: context,
      builder: (_) => _SettleSheet(
        dataSource: widget.dataSource,
        settings: _settings,
        candidates: [
          for (final m in _eligible)
            if (m.id != _me!.id) m
        ],
        childId: _groupChildId,
        toProfileId: toProfileId,
        amountCents: amountCents,
      ),
    );
    if (sent != true || !mounted) return;
    showAppSnack(context, l[KApp.expenseSettleSent]);
    await _load();
  }

  Future<void> _runSettlement(
      Localization l, Future<void> Function() action, String doneKey) async {
    try {
      await action();
      if (!mounted) return;
      showAppSnack(context, l[doneKey]);
    } catch (e) {
      if (!mounted) return;
      showAppSnack(
          context, translateSaveError(e.toString(), l[K.errSaveFailed], l));
    }
    await _load();
  }

  Future<void> _openDetail(Localization l, Expense expense) async {
    final outcome = await showAppSheet<String>(
      context: context,
      builder: (_) => _ExpenseDetailSheet(
        dataSource: widget.dataSource,
        expense: expense,
        nameOf: (id) => _name(id, l),
        canWrite: _canWrite,
      ),
    );
    if (!mounted) return;
    if (outcome == 'edit') {
      await _openEditor(l, editing: expense);
    } else if (outcome == 'deleted') {
      showAppSnack(context, l[KApp.expenseDeleted]);
      await _load();
    }
  }

  // ── build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      appBar: AppBar(
        title: Text(l[KApp.expenseNav]),
        actions: const [AppAccountButton()],
      ),
      body: _body(context, l),
    );
  }

  Widget _body(BuildContext context, Localization l) {
    if (_loading) return AppSkeletonList(semanticsLabel: l[KApp.expenseNav]);
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l[KApp.expenseErrLoad]),
            const SizedBox(height: Spacing.sm + Spacing.xs),
            FilledButton(
                onPressed: _load, child: Text(l[K.layoutErrorReload])),
          ],
        ),
      );
    }
    if (!_settings.expensesEnabled || _me == null) {
      return AppEmptyState(
        key: const ValueKey('expenses-off'),
        icon: Icons.receipt_long_outlined,
        title: l[KApp.expenseOff],
      );
    }
    if (_me!.isViewer) {
      return AppEmptyState(
        key: const ValueKey('expenses-viewer'),
        icon: Icons.receipt_long_outlined,
        title: l[KApp.expenseViewer],
      );
    }

    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final groups = _groups;
    final expenses = [
      for (final e in _expenses)
        if (_inGroup(e.childId)) e
    ];
    final settlements = [
      for (final s in _settlements)
        if (_inGroup(s.childId)) s
    ];
    final net = ExpenseLedger.net(
      [
        for (final e in expenses)
          (
            paidBy: e.paidBy,
            amountCents: e.amountCents,
            shares: {for (final s in e.shares) s.profileId: s.shareCents},
          )
      ],
      [
        for (final s in settlements)
          if (s.isConfirmed)
            (from: s.fromProfile, to: s.toProfile, amountCents: s.amountCents)
      ],
    );
    final suggestions = ExpenseLedger.simplify(net);
    final pending = [
      for (final s in settlements)
        if (s.isPending) s
    ];
    final canWrite = _canWrite;
    final me = _me!;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
        children: [
          Text(l[KApp.expenseLead], style: textTheme.bodyMedium),
          const SizedBox(height: Spacing.md),
          if (!canWrite) ...[
            AppBanner(
              key: const ValueKey('expenses-premium'),
              tone: tokens.info,
              icon: Icons.workspace_premium_outlined,
              message: l[KApp.expensePremium],
              actionLabel:
                  widget.onOpenPlan == null ? null : l[K.famSeePremium],
              onAction: widget.onOpenPlan,
            ),
            const SizedBox(height: Spacing.md),
          ],
          if (groups.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: AppSegmented<int>(
                key: const ValueKey('expenses-group'),
                semantics: l[KApp.expenseGroupLabel],
                options: [
                  for (final g in groups)
                    (
                      value: g,
                      label: g == _familyGroup
                          ? l[KApp.expenseGroupFamily]
                          : [
                              for (final c in _children)
                                if (c.id == g) c.firstName
                            ].first,
                    )
                ],
                selected: _group,
                onChanged: (g) => setState(() => _group = g),
              ),
            ),
            const SizedBox(height: Spacing.md),
          ],
          AppCard(
            key: const ValueKey('expenses-balance'),
            title: l[KApp.expenseBalance],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (suggestions.isEmpty)
                  Text(l[KApp.expenseBalanceEven])
                else ...[
                  for (final e in net.entries)
                    if (e.value != 0)
                      Text(
                        l.format(
                            e.value > 0
                                ? KApp.expenseNetGets
                                : KApp.expenseNetOwes,
                            [_name(e.key, l), _money(e.value, l)]),
                        style: textTheme.bodySmall,
                      ),
                  const SizedBox(height: Spacing.sm),
                  for (final p in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.xs),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              l.format(KApp.expensePays, [
                                _name(p.from, l),
                                _money(p.amountCents, l),
                                _name(p.to, l),
                              ]),
                              key: ValueKey('expenses-pays-${p.from}-${p.to}'),
                              style: textTheme.titleSmall,
                            ),
                          ),
                          if (canWrite && p.from == me.id)
                            TextButton(
                              key: ValueKey('expenses-settle-${p.to}'),
                              onPressed: () => _openSettle(l,
                                  toProfileId: p.to,
                                  amountCents: p.amountCents),
                              child: Text(l[KApp.expenseSettle]),
                            ),
                        ],
                      ),
                    ),
                ],
                if (canWrite && suggestions.every((p) => p.from != me.id))
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const ValueKey('expenses-settle'),
                      onPressed: () => _openSettle(l),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(l[KApp.expenseSettle]),
                    ),
                  ),
              ],
            ),
          ),
          if (pending.isNotEmpty) ...[
            AppSectionHeader(title: l[KApp.expensePending]),
            for (final s in pending)
              Card(
                key: ValueKey('settlement-${s.id}'),
                margin: const EdgeInsets.only(bottom: Spacing.sm),
                child: Padding(
                  padding: const EdgeInsets.all(Spacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.toProfile == me.id
                          ? l.format(KApp.expensePendingToMe,
                              [_name(s.fromProfile, l), _money(s.amountCents, l)])
                          : s.fromProfile == me.id
                              ? l.format(KApp.expensePendingFromMe,
                                  [_money(s.amountCents, l), _name(s.toProfile, l)])
                              : l.format(KApp.expensePendingOthers, [
                                  _name(s.fromProfile, l),
                                  _money(s.amountCents, l),
                                  _name(s.toProfile, l),
                                ])),
                      if (canWrite && s.toProfile == me.id) ...[
                        const SizedBox(height: Spacing.sm),
                        Wrap(
                          spacing: Spacing.sm,
                          runSpacing: Spacing.xs,
                          children: [
                            FilledButton(
                              key: ValueKey('settlement-confirm-${s.id}'),
                              onPressed: () => _runSettlement(
                                  l,
                                  () => widget.dataSource
                                      .answerSettlement(s.id, received: true),
                                  KApp.expenseConfirmed),
                              child: Text(l[KApp.expenseConfirm]),
                            ),
                            OutlinedButton(
                              key: ValueKey('settlement-reject-${s.id}'),
                              onPressed: () => _runSettlement(
                                  l,
                                  () => widget.dataSource
                                      .answerSettlement(s.id, received: false),
                                  KApp.expenseRejected),
                              child: Text(l[KApp.expenseReject]),
                            ),
                          ],
                        ),
                      ],
                      if (canWrite && s.fromProfile == me.id)
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            key: ValueKey('settlement-cancel-${s.id}'),
                            onPressed: () => _runSettlement(
                                l,
                                () => widget.dataSource.cancelSettlement(s.id),
                                KApp.expenseTakenBack),
                            child: Text(l[KApp.expenseTakeBack]),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
          AppSectionHeader(
            title: l[KApp.expenseListSection],
            trailing: canWrite
                ? TextButton.icon(
                    key: const ValueKey('expenses-add'),
                    onPressed: () => _openEditor(l),
                    icon: const Icon(Icons.add),
                    label: Text(l[KApp.expenseAdd]),
                  )
                : null,
          ),
          if (expenses.isEmpty)
            AppEmptyState(
              key: const ValueKey('expenses-empty'),
              icon: Icons.receipt_long_outlined,
              title: l[KApp.expenseEmpty],
              body: canWrite ? l[KApp.expenseEmptyBody] : null,
            )
          else
            for (final e in expenses)
              Card(
                key: ValueKey('expense-${e.id}'),
                margin: const EdgeInsets.only(bottom: Spacing.sm),
                child: ListTile(
                  onTap: () => _openDetail(l, e),
                  title: Text(e.description,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(l.format(KApp.expenseRow, [
                    l.formatDate(e.spentOn),
                    l[(ExpenseCategory.parse(e.category) ??
                            ExpenseCategory.other)
                        .labelKey],
                    _name(e.paidBy, l),
                  ])),
                  trailing: Text(_money(e.amountCents, l),
                      style: textTheme.titleSmall),
                ),
              ),
        ],
      ),
    );
  }
}

/// The expense editor — add ([editing] null) or edit. Checks the client's
/// half of the split before the tap reaches the server; a server refusal
/// shows its sentence pinned under the title and the sheet stays open.
class ExpenseEditorSheet extends StatefulWidget {
  final CustodyDataSource dataSource;
  final PublicSettings settings;
  final List<Member> eligible;
  final Member me;
  final int? childId;
  final Expense? editing;
  final DateTime today;

  const ExpenseEditorSheet({
    super.key,
    required this.dataSource,
    required this.settings,
    required this.eligible,
    required this.me,
    required this.childId,
    required this.today,
    this.editing,
  });

  @override
  State<ExpenseEditorSheet> createState() => _ExpenseEditorSheetState();
}

class _ExpenseEditorSheetState extends State<ExpenseEditorSheet> {
  late final TextEditingController _desc =
      TextEditingController(text: widget.editing?.description ?? '');
  late final TextEditingController _amount = TextEditingController();
  late ExpenseCategory _category =
      ExpenseCategory.parse(widget.editing?.category) ?? ExpenseCategory.other;
  late DateTime _date = widget.editing?.spentOn ??
      DateTime(widget.today.year, widget.today.month, widget.today.day);
  late int _paidBy = widget.editing?.paidBy ?? widget.me.id;
  late SplitMethod _method =
      SplitMethod.parse(widget.editing?.splitMethod) ?? SplitMethod.equal;

  /// Who takes part, and the text typed for each (method-dependent).
  final Set<int> _in = {};
  final Map<int, TextEditingController> _values = {};

  String? _error;
  bool _busy = false;
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final english = AppL10n.of(context).l.isEnglish;
    final e = widget.editing;
    if (e != null) {
      _amount.text =
          ExpenseRules.formatHundredths(e.amountCents, english: english);
    }
    for (final m in widget.eligible) {
      _values[m.id] = TextEditingController();
    }
    if (e == null) {
      _in.addAll([for (final m in widget.eligible) m.id]);
    } else {
      for (final s in e.shares) {
        _in.add(s.profileId);
        final c = _values.putIfAbsent(s.profileId, TextEditingController.new);
        c.text = switch (_method) {
          SplitMethod.equal => '',
          SplitMethod.shares => '${s.weight}',
          _ => ExpenseRules.formatHundredths(s.weight, english: english),
        };
      }
    }
  }

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    for (final c in _values.values) {
      c.dispose();
    }
    super.dispose();
  }

  int? _valueOf(int profileId) {
    final text = _values[profileId]?.text ?? '';
    return switch (_method) {
      SplitMethod.equal => 1,
      SplitMethod.shares => int.tryParse(text.trim()),
      _ => ExpenseRules.parseHundredths(text),
    };
  }

  /// The split as it stands, or the reason it cannot be one.
  ({List<SplitShare>? shares, String? error}) _preview(Localization l) {
    final amount = ExpenseRules.parseHundredths(_amount.text);
    if (amount == null || amount <= 0) {
      return (shares: null, error: l[KApp.expenseErrAmount]);
    }
    final parts = <SplitPart>[];
    for (final m in widget.eligible) {
      if (!_in.contains(m.id)) continue;
      final v = _valueOf(m.id);
      if (v == null) return (shares: null, error: l[KApp.expenseErrZero]);
      parts.add((profileId: m.id, value: v));
    }
    try {
      return (
        shares: ExpenseSplit.split(amount, _method, parts),
        error: null,
      );
    } on SplitException catch (e) {
      String money(int c) => ExpenseRules.brl(c, english: l.isEnglish);
      return (
        shares: null,
        error: switch (e.error) {
          SplitError.noParts => l[KApp.expenseErrNoParts],
          SplitError.exactMismatch =>
            l.format(KApp.expenseErrExact, [money(e.total), money(amount)]),
          SplitError.percentNot100 => l[KApp.expenseErrPercent],
          _ => l[KApp.expenseErrZero],
        },
      );
    }
  }

  Future<void> _save(Localization l) async {
    if (_busy) return;
    final desc = _desc.text.trim();
    final maxChars = widget.settings.expenseDescriptionMaxChars;
    final maxAmount = widget.settings.expenseMaxAmountCents;
    final amount = ExpenseRules.parseHundredths(_amount.text);
    String? error;
    if (desc.isEmpty) {
      error = l[KApp.expenseErrDesc];
    } else if (desc.length > maxChars) {
      error = l.format(KApp.expenseErrDescLong, [maxChars]);
    } else if (amount != null && amount > maxAmount) {
      error = l.format(KApp.expenseErrMax,
          [ExpenseRules.brl(maxAmount, english: l.isEnglish)]);
    } else {
      error = _preview(l).error;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final parts = [
      for (final m in widget.eligible)
        if (_in.contains(m.id)) (profileId: m.id, value: _valueOf(m.id)!)
    ];
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final e = widget.editing;
      if (e == null) {
        await widget.dataSource.addExpense(
          childId: widget.childId,
          description: desc,
          category: _category.name,
          amountCents: amount!,
          paidBy: _paidBy,
          spentOn: _date,
          method: _method.name,
          parts: parts,
        );
      } else {
        await widget.dataSource.updateExpense(
          id: e.id,
          childId: widget.childId,
          description: desc,
          category: _category.name,
          amountCents: amount!,
          paidBy: _paidBy,
          spentOn: _date,
          method: _method.name,
          parts: parts,
        );
      }
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

  String _valueLabel(Localization l, Member m) => l.format(
      switch (_method) {
        SplitMethod.exact => KApp.expenseValueExact,
        SplitMethod.percent => KApp.expenseValuePercent,
        _ => KApp.expenseValueShares,
      },
      [m.fullName]);

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final preview = _preview(l);
    final shareOf = {
      for (final s in preview.shares ?? const <SplitShare>[])
        s.profileId: s.shareCents
    };
    final textTheme = Theme.of(context).textTheme;
    return AppSheetFrame(
      title: l[widget.editing == null ? KApp.expenseAdd : KApp.expenseEdit],
      error: _error,
      busy: _busy,
      primaryLabel: l[K.commonSave],
      onPrimary: () => _save(l),
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      children: [
        AppTextField(
          key: const ValueKey('expense-desc'),
          label: l[KApp.expenseDesc],
          controller: _desc,
          maxLength: widget.settings.expenseDescriptionMaxChars,
          textCapitalization: TextCapitalization.sentences,
        ),
        const SizedBox(height: Spacing.sm),
        AppTextField(
          key: const ValueKey('expense-amount'),
          label: l[KApp.expenseAmount],
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: Spacing.sm),
        DropdownButtonFormField<ExpenseCategory>(
          key: const ValueKey('expense-category'),
          initialValue: _category,
          decoration: InputDecoration(labelText: l[KApp.expenseCategory]),
          items: [
            for (final c in ExpenseCategory.values)
              DropdownMenuItem(value: c, child: Text(l[c.labelKey])),
          ],
          onChanged: (c) => setState(() => _category = c ?? _category),
        ),
        const SizedBox(height: Spacing.sm),
        OutlinedButton.icon(
          key: const ValueKey('expense-date'),
          icon: const Icon(Icons.event_outlined),
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _date,
              firstDate: DateTime(widget.today.year - 5),
              lastDate: DateTime(widget.today.year + 1, 12, 31),
            );
            if (picked != null) setState(() => _date = picked);
          },
          label: Text('${l[KApp.expenseDate]}: ${l.formatDate(_date)}'),
        ),
        const SizedBox(height: Spacing.sm),
        DropdownButtonFormField<int>(
          key: const ValueKey('expense-paid-by'),
          initialValue: widget.eligible.any((m) => m.id == _paidBy)
              ? _paidBy
              : null,
          decoration: InputDecoration(labelText: l[KApp.expensePaidBy]),
          items: [
            for (final m in widget.eligible)
              DropdownMenuItem(value: m.id, child: Text(m.fullName)),
          ],
          onChanged: (id) => setState(() => _paidBy = id ?? _paidBy),
        ),
        const SizedBox(height: Spacing.md),
        AppFieldLabel(l[KApp.expenseSplit]),
        AppSegmented<SplitMethod>(
          key: const ValueKey('expense-method'),
          semantics: l[KApp.expenseSplit],
          options: [
            (value: SplitMethod.equal, label: l[KApp.expenseSplitEqual]),
            (value: SplitMethod.exact, label: l[KApp.expenseSplitExact]),
            (value: SplitMethod.percent, label: l[KApp.expenseSplitPercent]),
            (value: SplitMethod.shares, label: l[KApp.expenseSplitShares]),
          ],
          selected: _method,
          onChanged: (m) => setState(() => _method = m),
        ),
        const SizedBox(height: Spacing.sm),
        AppFieldLabel(l[KApp.expenseParticipants]),
        for (final m in widget.eligible) ...[
          CheckboxListTile(
            key: ValueKey('expense-part-${m.id}'),
            contentPadding: EdgeInsets.zero,
            value: _in.contains(m.id),
            title: Text(m.fullName),
            subtitle: shareOf[m.id] == null
                ? null
                : Text(l.format(KApp.expenseShareOf, [
                    ExpenseRules.brl(shareOf[m.id]!, english: l.isEnglish)
                  ])),
            onChanged: (v) => setState(() {
              if (v == true) {
                _in.add(m.id);
              } else {
                _in.remove(m.id);
              }
            }),
          ),
          if (_method != SplitMethod.equal && _in.contains(m.id))
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.sm),
              child: AppTextField(
                key: ValueKey('expense-value-${m.id}'),
                label: _valueLabel(l, m),
                controller: _values[m.id],
                keyboardType: TextInputType.numberWithOptions(
                    decimal: _method != SplitMethod.shares),
                onChanged: (_) => setState(() {}),
              ),
            ),
        ],
        if (preview.error != null && _amount.text.trim().isNotEmpty)
          Text(preview.error!,
              key: const ValueKey('expense-preview-error'),
              style: textTheme.bodySmall),
      ],
    );
  }
}

/// "I paid X to Y" — waits for Y to confirm (the F-34 difference).
class _SettleSheet extends StatefulWidget {
  final CustodyDataSource dataSource;
  final PublicSettings settings;
  final List<Member> candidates;
  final int? childId;
  final int? toProfileId;
  final int? amountCents;

  const _SettleSheet({
    required this.dataSource,
    required this.settings,
    required this.candidates,
    required this.childId,
    this.toProfileId,
    this.amountCents,
  });

  @override
  State<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends State<_SettleSheet> {
  late int? _to = widget.toProfileId ??
      (widget.candidates.length == 1 ? widget.candidates.first.id : null);
  final TextEditingController _amount = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final cents = widget.amountCents;
    if (cents != null) {
      _amount.text = ExpenseRules.formatHundredths(cents,
          english: AppL10n.of(context).l.isEnglish);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _send(Localization l) async {
    if (_busy) return;
    final amount = ExpenseRules.parseHundredths(_amount.text);
    final maxAmount = widget.settings.expenseMaxAmountCents;
    String? error;
    if (_to == null) {
      error = l[KApp.expenseSettleTo];
    } else if (amount == null || amount <= 0) {
      error = l[KApp.expenseErrAmount];
    } else if (amount > maxAmount) {
      error = l.format(KApp.expenseErrMax,
          [ExpenseRules.brl(maxAmount, english: l.isEnglish)]);
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.dataSource.requestSettlement(
          childId: widget.childId, toProfileId: _to!, amountCents: amount!);
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
    final none = widget.candidates.isEmpty;
    return AppSheetFrame(
      title: l[KApp.expenseSettleTitle],
      error: _error,
      busy: _busy,
      primaryLabel: none ? null : l[KApp.expenseSettle],
      onPrimary: none ? null : () => _send(l),
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      children: [
        Text(l[none ? KApp.expenseSettleNobody : KApp.expenseSettleLead]),
        if (!none) ...[
          const SizedBox(height: Spacing.md),
          DropdownButtonFormField<int>(
            key: const ValueKey('settle-to'),
            initialValue: _to,
            decoration: InputDecoration(labelText: l[KApp.expenseSettleTo]),
            items: [
              for (final m in widget.candidates)
                DropdownMenuItem(value: m.id, child: Text(m.fullName)),
            ],
            onChanged: (id) => setState(() => _to = id),
          ),
          const SizedBox(height: Spacing.sm),
          AppTextField(
            key: const ValueKey('settle-amount'),
            label: l[KApp.expenseAmount],
            controller: _amount,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
      ],
    );
  }
}

/// One expense read at rest: the split, and its changes (the append-only
/// trail, fetched on open). Edit and delete sit here for a writer; the
/// delete asks first. Pops `'edit'` or `'deleted'`.
class _ExpenseDetailSheet extends StatefulWidget {
  final CustodyDataSource dataSource;
  final Expense expense;
  final String Function(int profileId) nameOf;
  final bool canWrite;

  const _ExpenseDetailSheet({
    required this.dataSource,
    required this.expense,
    required this.nameOf,
    required this.canWrite,
  });

  @override
  State<_ExpenseDetailSheet> createState() => _ExpenseDetailSheetState();
}

class _ExpenseDetailSheetState extends State<_ExpenseDetailSheet> {
  List<ExpenseHistoryEntry>? _trail;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    widget.dataSource
        .fetchExpenseHistory([widget.expense.id])
        .then((t) {
          if (mounted) setState(() => _trail = t);
        })
        .catchError((Object _) {
          if (mounted) setState(() => _trail = const []);
        });
  }

  Future<void> _delete(Localization l) async {
    final yes = await showDestructiveConfirm(
      context: context,
      title: l[KApp.expenseDelete],
      message: l.format(KApp.expenseDeleteConfirm, [widget.expense.description]),
      yesLabel: l[KApp.expenseDelete],
      noLabel: l[K.commonCancel],
    );
    if (!yes || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.dataSource.deleteExpense(widget.expense.id);
      if (!mounted) return;
      Navigator.of(context).pop('deleted');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = translateSaveError(e.toString(), l[K.errSaveFailed], l);
      });
    }
  }

  String _changeLine(Localization l, ExpenseHistoryEntry h) {
    final who = h.actorId == null
        ? l[KApp.expenseFormerMember]
        : widget.nameOf(h.actorId!);
    final when = l.formatDateTime(h.at.toLocal());
    return l.format(
        switch (h.action) {
          'created' => KApp.expenseChangeCreated,
          'updated' => KApp.expenseChangeUpdated,
          _ => KApp.expenseChangeDeleted,
        },
        [who, when]);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final e = widget.expense;
    final textTheme = Theme.of(context).textTheme;
    String money(int c) => ExpenseRules.brl(c, english: l.isEnglish);
    return AppSheetFrame(
      title: e.description,
      subtitle: '${money(e.amountCents)} · ${l.formatDate(e.spentOn)}',
      error: _error,
      busy: _busy,
      primaryLabel: widget.canWrite ? l[KApp.expenseEdit] : null,
      onPrimary:
          widget.canWrite ? () => Navigator.of(context).pop('edit') : null,
      secondaryLabel: widget.canWrite ? l[K.commonCancel] : null,
      onSecondary:
          widget.canWrite ? () => Navigator.of(context).pop() : null,
      extraAction: widget.canWrite
          ? AppSheetDangerAction(
              key: const ValueKey('expense-delete'),
              label: l[KApp.expenseDelete],
              icon: Icons.delete_outline,
              onPressed: _busy ? null : () => _delete(l),
            )
          : null,
      onClose: () => Navigator.of(context).pop(),
      closeLabel: l[K.commonClose],
      children: [
        AppListRow(
            label: l[KApp.expenseCategory],
            value: l[(ExpenseCategory.parse(e.category) ??
                    ExpenseCategory.other)
                .labelKey]),
        AppListRow(label: l[KApp.expensePaidBy], value: widget.nameOf(e.paidBy)),
        AppSectionHeader(title: l[KApp.expenseDetailSplit]),
        for (final s in e.shares)
          AppListRow(label: widget.nameOf(s.profileId), value: money(s.shareCents)),
        AppSectionHeader(title: l[KApp.expenseChanges]),
        if (_trail == null)
          const LinearProgressIndicator()
        else
          for (final h in _trail!) ...[
            Text(_changeLine(l, h),
                key: ValueKey('expense-change-${h.id}'),
                style: textTheme.bodySmall),
            if (h.action == 'updated' && h.oldData != null)
              Padding(
                padding: const EdgeInsets.only(left: Spacing.md),
                child: Text(
                  l.format(KApp.expenseChangeBefore, [
                    '${h.oldData!['description'] ?? ''}',
                    money(int.tryParse('${h.oldData!['amount_cents']}') ?? 0),
                  ]),
                  style: textTheme.bodySmall,
                ),
              ),
          ],
      ],
    );
  }
}
