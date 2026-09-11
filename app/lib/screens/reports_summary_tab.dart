import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import '../services/custody_data_source.dart';
import '../widgets/app_l10n.dart';
import '../widgets/rich_label.dart';

/// "Resumo do Período" — port of `ReportsSummary.razor`.
///
/// Every number on screen comes from [caregiverStats], the same pure function
/// the F-33 document calls: the web keeps the two in step by comment, this
/// keeps them in step by construction.
///
/// Two native improvements the owner directive allows: changing a filter
/// reloads immediately (the web needs a "Filtrar" tap) and the period can be
/// pulled to refresh. The U-20 projection toggle recomputes from the rows
/// already loaded, exactly as the web does — it is a reading of the same data,
/// never a new query.
class ReportsSummaryTab extends StatefulWidget {
  final CustodyDataSource dataSource;

  /// Injected by the tests; production reads the clock.
  final DateTime Function() now;

  const ReportsSummaryTab({
    super.key,
    required this.dataSource,
    this.now = DateTime.now,
  });

  @override
  State<ReportsSummaryTab> createState() => _ReportsSummaryTabState();
}

class _ReportsSummaryTabState extends State<ReportsSummaryTab> {
  late int _month = widget.now().month;
  late int _year = widget.now().year;
  bool _byMonth = false; // the web opens on "Por Ano"
  bool _includeFutureSwaps = false;

  bool _loading = true;

  /// The raw failure, formatted at RENDER time — the first load starts from
  /// [initState], where the inherited localization is not reachable yet.
  String? _errorRaw;

  List<Member> _members = const [];
  List<Role> _roles = const [];
  List<CareSchedule> _days = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) get _period => _byMonth
      ? (DateTime(_year, _month, 1), DateTime(_year, _month + 1, 0))
      : (DateTime(_year, 1, 1), DateTime(_year, 12, 31));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorRaw = null;
    });
    try {
      final (start, end) = _period;
      final members = await widget.dataSource.fetchMembers();
      final roles = await widget.dataSource.fetchRoles();
      final days = await widget.dataSource.fetchSchedulesForPeriod(start, end);
      if (!mounted) return;
      setState(() {
        _members = members;
        _roles = roles;
        _days = days;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorRaw = e.toString();
        _loading = false;
      });
    }
  }

  List<MemberView> get _views => [for (final m in _members) m.toView()];

  String _roleLabel(int profileId, AppLanguage language) {
    for (final m in _members) {
      if (m.id != profileId) continue;
      for (final role in _roles) {
        if (role.id == m.roleId) return role.displayLabel(language);
      }
    }
    return '';
  }

  List<CaregiverStat> _stats(AppLanguage language) => caregiverStats(
        members: _views,
        days: [
          for (final d in _days)
            ReportDay(
              scheduleDate: d.scheduleDate,
              scheduledParentId: d.scheduledParentId,
              actualParentId: d.actualParentId,
            ),
        ],
        today: widget.now(),
        includeFutureSwaps: _includeFutureSwaps,
        roleLabelOf: (id) => _roleLabel(id, language),
      );

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final stats = _stats(l.current);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // U-28: the tab names itself, the way the PDF tab already did. With
          // only "Relatórios" on the app bar, a description scrolled halfway
          // up read as an orphan sentence under the tab strip.
          Text(l[K.sumHeading],
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(l[K.sumSubtitle],
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          _filterCard(l),
          const SizedBox(height: 12),
          if (_errorRaw != null)
            _errorBanner(l)
          else if (_loading)
            const AppSkeletonCards()
          else if (!hasSummaryData(stats))
            _emptyState(l)
          else ...[
            // U-28: two columns, as the web has them. One card per row pushed
            // the second carer below the fold on a phone, and the comparison
            // between the two is the entire point of this tab.
            LayoutBuilder(builder: (context, constraints) {
              final columns = constraints.maxWidth >= 640 ? 3 : 2;
              final width =
                  (constraints.maxWidth - Spacing.sm * (columns - 1)) / columns;
              return Wrap(
                spacing: Spacing.sm,
                runSpacing: Spacing.sm,
                children: [
                  for (final stat in stats)
                    SizedBox(width: width, child: _statCard(stat, l)),
                ],
              );
            }),
            const SizedBox(height: Spacing.md),
            Center(
              child: RichLabel.of(
                l,
                _includeFutureSwaps
                    ? K.sumTotalSwapsProjected
                    : K.sumTotalSwaps,
                args: [
                  totalVisibleSwaps(
                    days: [
                      for (final d in _days)
                        ReportDay(
                          scheduleDate: d.scheduleDate,
                          scheduledParentId: d.scheduledParentId,
                          actualParentId: d.actualParentId,
                        ),
                    ],
                    today: widget.now(),
                    includeFutureSwaps: _includeFutureSwaps,
                  )
                ],
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterCard(Localization l) {
    final thisYear = widget.now().year;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // U-29: the shared segmented control — this tab had kept the raw
            // one, the only place in the app still drawing the ✓ inside the
            // selected segment (the fill already says which one is chosen).
            AppSegmented<bool>(
              semantics: l[K.repPeriodAria],
              options: [
                (value: false, label: l[K.repByYear]),
                (value: true, label: l[K.repByMonth]),
              ],
              selected: _byMonth,
              enabled: !_loading,
              onChanged: (v) {
                setState(() => _byMonth = v);
                _load();
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (_byMonth) ...[
                  Expanded(
                    child: Semantics(
                      label: l[K.repByMonth],
                      child: DropdownButtonFormField<int>(
                        initialValue: _month,
                        items: [
                          for (var m = 1; m <= 12; m++)
                            DropdownMenuItem(
                                value: m, child: Text(l.monthName(m))),
                        ],
                        onChanged: _loading
                            ? null
                            : (m) {
                                if (m == null) return;
                                setState(() => _month = m);
                                _load();
                              },
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Semantics(
                    label: l[K.repByYear],
                    child: DropdownButtonFormField<int>(
                      initialValue: _year,
                      items: [
                        // Web parity: last year through two years ahead.
                        for (var y = thisYear - 1; y <= thisYear + 2; y++)
                          DropdownMenuItem(value: y, child: Text('$y')),
                      ],
                      onChanged: _loading
                          ? null
                          : (y) {
                              if (y == null) return;
                              setState(() => _year = y);
                              _load();
                            },
                    ),
                  ),
                ),
              ],
            ),
            // U-20: accepted future swaps already carry actual_parent_id — the
            // default view simply ignores them.
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _includeFutureSwaps,
              title: Text(l[K.sumFutureToggle],
                  style: Theme.of(context).textTheme.bodySmall),
              onChanged: _loading
                  ? null
                  : (v) => setState(() => _includeFutureSwaps = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCard(CaregiverStat stat, Localization l) {
    final slot = context.tokens.slot(profileSlotIndex(stat.profileId, _views));
    final firstName = stat.name.split(' ').first;

    // U-28: the card is TINTED, not striped. The web fills each carer's card
    // with their own colour and prints the name in it, which is what lets a
    // reader tell the two columns apart at a glance; the port had reduced that
    // to a 4 px rule down the left edge with everything else neutral.
    return Card(
      margin: EdgeInsets.zero,
      color: slot.tone.container,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: slot.tone.border),
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              stat.role.isEmpty ? firstName : '$firstName (${stat.role})',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: slot.tone.onContainer),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: Spacing.sm),
            // U-29 round 4 (owner's sketch): two bands of PAIRED stats, each
            // value under its own label — planned beside actual, given beside
            // received. Every card shares the same grid, whatever the
            // reader's font scale does inside a column.
            _statPair(
              l[K.sumPlanned], _daysLabel(stat.plannedDays, l),
              l[K.sumActual], _daysLabel(stat.actualDays, l),
              tone: slot.tone,
            ),
            if (_includeFutureSwaps) ...[
              const SizedBox(height: Spacing.sm),
              _stat(l[K.sumProjected], _daysLabel(stat.projectedDays, l),
                  tone: slot.tone),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Spacing.sm),
              child: Container(height: 1, color: slot.tone.border),
            ),
            // U-07: who gave days away and who received them.
            _statPair(
              l[K.sumGiven], _daysLabel(stat.swapsGiven, l),
              l[K.sumReceived], _daysLabel(stat.swapsReceived, l),
              tone: slot.tone,
            ),
          ],
        ),
      ),
    );
  }

  /// U-13: a plural is not a singular plus "s" in either language, and the
  /// count carries its unit — two catalog entries, exactly like the web.
  String _daysLabel(int count, Localization l) =>
      l.format(count == 1 ? K.sumDaysOne : K.sumDaysMany, [count]);

  /// One stat: label above, value under it — each on EXACTLY one line. A
  /// half-column is narrow enough that at large font scales a whole word
  /// stops fitting ("Agendad / o", owner's device), and a mid-word break is
  /// worse than a fractionally smaller word: the [FittedBox] shrinks the
  /// line only when it would otherwise wrap, so at ordinary scales nothing
  /// changes at all.
  Widget _stat(String label, String value, {required ToneColors tone}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _oneLine(Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tone.onContainer))),
          _oneLine(Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: tone.onContainer))),
        ],
      );

  Widget _oneLine(Widget text) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: text,
      );

  /// Two stats side by side in equal columns — the owner's sketch:
  /// Agendado | Realizado over their values, Cedeu | Recebeu under the rule.
  Widget _statPair(String leftLabel, String leftValue, String rightLabel,
          String rightValue, {required ToneColors tone}) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _stat(leftLabel, leftValue, tone: tone)),
          const SizedBox(width: Spacing.sm),
          Expanded(child: _stat(rightLabel, rightValue, tone: tone)),
        ],
      );

  Widget _emptyState(Localization l) => AppEmptyState(
        icon: '📅',
        title: l[K.sumEmptyTitle],
        body: l[K.sumEmptyBody],
      );

  /// The central mappings the whole app shares: a dead session says so, and a
  /// server error propagates its own text.
  String _errorMessage(Localization l) => isSessionExpired(_errorRaw!)
      ? sessionExpiredMessage(l)
      : l.format(K.sumErrProcess, [_errorRaw!]);

  Widget _errorBanner(Localization l) => AppBanner(
        tone: context.tokens.danger,
        leading: '⚠️',
        title: l[K.repErrorTitle],
        message: _errorMessage(l),
      );
}
