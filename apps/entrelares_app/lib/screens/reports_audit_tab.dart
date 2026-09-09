import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';

import 'package:entrelares_db_contracts/models/account_log.dart';
import 'package:entrelares_db_contracts/models/activity_log.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import '../services/custody_data_source.dart';
import '../widgets/app_l10n.dart';
import '../widgets/rich_label.dart';

/// "Histórico de Ajustes" — port of `ReportsAudit.razor`.
///
/// Four tabs over two different trails: the calendar's own `activity_logs`
/// (Recentes / Por Mês / Por Ano) and the S-10 account operations (Conta).
/// Both are immutable records written by triggers and definer RPCs — this
/// screen only reads and presents them.
///
/// **F-45 lands here** (deferred from lote 3 to arrive with the audit mirror):
/// a change produced by a swap workflow names its origin and carries the two
/// F-44 texts. The lookup is enrichment — when it fails, the timeline stays.
class ReportsAuditTab extends StatefulWidget {
  final CustodyDataSource dataSource;

  /// Injected by the tests; production reads the clock.
  final DateTime Function() now;

  const ReportsAuditTab({
    super.key,
    required this.dataSource,
    this.now = DateTime.now,
  });

  @override
  State<ReportsAuditTab> createState() => _ReportsAuditTabState();
}

enum _AuditTab { recent, month, year, account }

class _ReportsAuditTabState extends State<ReportsAuditTab> {
  _AuditTab _tab = _AuditTab.recent;
  late int _month = widget.now().month;
  late int _year = widget.now().year;

  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;

  /// Raw failures, formatted at RENDER time — the first load starts from
  /// [initState], where the inherited localization is not reachable yet.
  String? _errorRaw;
  String? _moreErrorRaw;

  List<Member> _members = const [];
  List<Role> _roles = const [];
  List<ActivityLog> _activity = const [];
  List<AccountLog> _account = const [];
  Family? _family;

  /// F-45: log id → the request whose resolution produced that log.
  Map<int, SwapOrigin> _origins = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) get _period => _tab == _AuditTab.month
      ? (DateTime(_year, _month, 1), DateTime(_year, _month + 1, 0))
      : (DateTime(_year, 1, 1), DateTime(_year, 12, 31));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorRaw = null;
      _moreErrorRaw = null;
      _hasMore = false;
      _activity = const [];
      _account = const [];
      _origins = const {};
    });
    try {
      final members = await widget.dataSource.fetchMembers();
      final roles = await widget.dataSource.fetchRoles();
      var activity = const <ActivityLog>[];
      var account = const <AccountLog>[];
      var hasMore = false;
      Family? family = _family;

      switch (_tab) {
        case _AuditTab.account:
          account = await widget.dataSource.fetchAccountLogs();
          hasMore = account.length == auditPageSize;
          // F-58 QA 2: the trial's end writes no row anywhere — the timeline
          // computes it from the family itself.
          family ??= await widget.dataSource.fetchOwnFamily();
        case _AuditTab.recent:
          activity = await widget.dataSource.fetchRecentActivityLogs();
          hasMore = activity.length == auditPageSize;
        case _AuditTab.month:
        case _AuditTab.year:
          final (start, end) = _period;
          activity =
              await widget.dataSource.fetchActivityLogsForPeriod(start, end);
      }

      final origins = await _originsFor(activity);
      if (!mounted) return;
      setState(() {
        _members = members;
        _roles = roles;
        _activity = activity;
        _account = account;
        _family = family;
        _origins = origins;
        _hasMore = hasMore;
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

  Future<void> _loadMore() async {
    if (_loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreErrorRaw = null;
    });
    try {
      if (_tab == _AuditTab.account) {
        final next =
            await widget.dataSource.fetchAccountLogs(offset: _account.length);
        if (!mounted) return;
        setState(() {
          _account = [..._account, ...next];
          _hasMore = next.length == auditPageSize;
        });
      } else {
        final next = await widget.dataSource
            .fetchRecentActivityLogs(offset: _activity.length);
        final origins = await _originsFor(next);
        if (!mounted) return;
        setState(() {
          _activity = [..._activity, ...next];
          // Merged, never replaced: "Carregar mais" keeps earlier origins.
          _origins = {..._origins, ...origins};
          _hasMore = next.length == auditPageSize;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _moreErrorRaw = e.toString());
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Best-effort by contract: a failed lookup costs the origin line, never the
  /// timeline itself.
  Future<Map<int, SwapOrigin>> _originsFor(List<ActivityLog> logs) async {
    if (logs.isEmpty) return const {};
    try {
      return await widget.dataSource
          .fetchResolutionOrigins([for (final l in logs) l.id]);
    } catch (_) {
      return const {};
    }
  }

  List<MemberView> get _views => [for (final m in _members) m.toView()];

  String _nameOf(int? profileId, String fallback) {
    if (profileId == null) return fallback;
    for (final m in _members) {
      if (m.id == profileId) return m.fullName;
    }
    return fallback;
  }

  String _translateRole(String roleName, AppLanguage language) {
    for (final role in _roles) {
      if (role.roleName == roleName) return role.displayLabel(language);
    }
    return RoleCatalog.translate(roleName, language);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          // U-28: the tab names itself, the way the PDF tab already did. With
          // only "Relatórios" on the app bar, a description scrolled halfway
          // up read as an orphan sentence under the tab strip.
          Text(l[K.auditHeading],
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Spacing.xs),
          Text(l[K.auditSubtitle],
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          _filterCard(l),
          const SizedBox(height: 12),
          if (_errorRaw != null)
            _banner(l[K.repErrorTitle], _message(l, K.auditErrLoad, _errorRaw!))
          else if (_loading)
            AppSkeletonList(rows: 4, semanticsLabel: l[K.famLoading])
          else ...[
            ..._timeline(l),
            if (_moreErrorRaw != null) ...[
              const SizedBox(height: 8),
              _banner(l[K.repErrorTitle],
                  _message(l, K.auditErrLoadMore, _moreErrorRaw!)),
            ],
            if (_hasMore) ...[
              const SizedBox(height: 8),
              Center(
                child: OutlinedButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child: Text(l[
                      _loadingMore ? K.auditLoadingMore : K.auditLoadMore]),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _message(Localization l, String errorKey, String raw) =>
      isSessionExpired(raw)
          ? sessionExpiredMessage(l)
          : l.format(errorKey, [raw]);

  Widget _filterCard(Localization l) {
    final thisYear = widget.now().year;
    final needsSelectors =
        _tab == _AuditTab.month || _tab == _AuditTab.year;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppSegmented<_AuditTab>(
              options: [
                (value: _AuditTab.recent, label: l[K.auditTabRecent]),
                (value: _AuditTab.month, label: l[K.repByMonth]),
                (value: _AuditTab.year, label: l[K.repByYear]),
                (value: _AuditTab.account, label: l[K.auditTabAccount]),
              ],
              selected: _tab,
              enabled: !_loading,
              onChanged: (v) {
                setState(() => _tab = v);
                _load();
              },
            ),
            if (needsSelectors) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (_tab == _AuditTab.month) ...[
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
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _timeline(Localization l) =>
      _tab == _AuditTab.account ? _accountTimeline(l) : _scheduleTimeline(l);

  // ── The calendar trail ────────────────────────────────────────────────────

  List<Widget> _scheduleTimeline(Localization l) {
    if (_activity.isEmpty) {
      return [_emptyState('🗂️', l[K.auditEmptyTitle], l[K.auditEmptyBody])];
    }
    return [
      for (final log in _activity) _scheduleItem(log, l),
    ];
  }

  Widget _scheduleItem(ActivityLog log, Localization l) {
    final view = log.view;
    final actor = _nameOf(log.performedById, l[K.auditSystemTrigger]);
    final changes = computeAuditDiff(log: view, profiles: _views, l: l);
    final origin = _origins[log.id];
    final authorship = authorshipLines(log: view, profiles: _views, l: l);
    final badge = scheduleActionBadge(log.action);

    return _item(
      badge: badge,
      icon: switch (badge) {
        AuditBadge.created => '＋',
        AuditBadge.deleted => '✕',
        AuditBadge.updated => '✏️',
      },
      children: [
        Text(l.format(K.auditDayLabel, [l.formatDate(view.affectedDate)]),
            style: Theme.of(context).textTheme.labelSmall),
        RichLabel.of(l, K.auditScheduleChange,
            args: [actor, scheduleActionLabel(log.action, l)]),
        if (origin != null) _originBlock(origin, l),
        if (authorship.isNotEmpty) _authorshipBlock(authorship),
        for (final change in changes)
          _diffRow(change.label, change.from, change.to),
      ],
      timestamp: l.formatDateTime(view.createdAtLocal),
    );
  }

  /// F-61: the dated facts beyond the diff — an assignee who had no account
  /// at that instant, the admin's direct change. Same block shape as the
  /// origin, in the NEUTRAL tone on purpose: the record states, it does not
  /// warn.
  Widget _authorshipBlock(List<String> lines) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.tokens.neutral.container,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final line in lines)
              Text('👤 $line',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      );

  /// F-45: where the change came from, and the two F-44 texts that carry the
  /// motivation — the part that makes the paid report genuinely richer.
  Widget _originBlock(SwapOrigin origin, Localization l) => Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: context.tokens.slot(0).tone.container,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('🔁 ${resolutionOriginText(origin, _views, l)}',
                style: Theme.of(context).textTheme.bodySmall),
            if ((origin.requestMessage ?? '').isNotEmpty)
              _originDetail(l[K.auditRequesterMessage], origin.requestMessage!),
            if ((origin.approvalNote ?? '').isNotEmpty)
              _originDetail(l[K.auditApproverMessage], origin.approvalNote!),
          ],
        ),
      );

  Widget _originDetail(String label, String value) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: '$label ',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: value),
          ]),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );

  // ── The S-10 account trail ────────────────────────────────────────────────

  List<Widget> _accountTimeline(Localization l) {
    if (_account.isEmpty) {
      return [
        _emptyState('🗂️', l[K.auditEmptyAccountTitle],
            l[K.auditEmptyAccountBody])
      ];
    }

    final trialEnded = trialEndedEntry(
      plan: _family?.plan,
      trialEndsAtUtc: _family?.trialEndsAt,
      compPremiumAtUtc: _family?.compPremiumAt,
      nowUtc: widget.now().toUtc(),
    );

    final items = <Widget>[];
    var trialRendered = false;
    for (final log in _account) {
      // F-58 QA 2: interleave the synthetic entry at its chronological place.
      if (!trialRendered &&
          trialEnded != null &&
          !trialEnded.isBefore(log.createdAt)) {
        trialRendered = true;
        items.add(_trialEndedItem(trialEnded, l));
      }
      items.add(_accountItem(log, l));
    }
    // Older than every loaded row: render at the end, but only once the
    // timeline is fully loaded (no page cut-off).
    if (!trialRendered && trialEnded != null && !_hasMore) {
      items.add(_trialEndedItem(trialEnded, l));
    }
    return items;
  }

  Widget _accountItem(AccountLog log, Localization l) {
    final (badge, icon) = accountActionBadge(log.action);
    final actor = _nameOf(log.actorProfileId, l[K.auditSystemActor]);
    final target = log.targetProfileId != null &&
            log.targetProfileId != log.actorProfileId
        ? _nameOf(log.targetProfileId, '')
        : '';
    String? display(String? value) => accountLogValueDisplay(
        log.action, value, (role) => _translateRole(role, l.current));

    return _item(
      badge: badge,
      icon: icon,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(
                text: actor,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: ' — ${accountActionLabel(log.action, l)}'),
            if (target.isNotEmpty) TextSpan(text: ' · $target'),
          ]),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (log.oldValue != null || log.newValue != null)
          _diffRow(null, display(log.oldValue), display(log.newValue)),
      ],
      timestamp: l.formatDateTime(log.createdAt.toLocal()),
    );
  }

  Widget _trialEndedItem(DateTime endedAtUtc, Localization l) => _item(
        badge: AuditBadge.updated,
        icon: '⏳',
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: l[K.auditSystemActor],
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: ' — ${l[K.auditTrialEnded]}'),
            ]),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        timestamp: l.formatDateTime(endedAtUtc.toLocal()),
      );

  // ── Shared timeline chrome ────────────────────────────────────────────────

  Widget _item({
    required AuditBadge badge,
    required String icon,
    required List<Widget> children,
    String timestamp = '',
    bool isLast = false,
  }) {
    // U-28: an audit log is read for SEQUENCE and it is read in bulk. As
    // stacked cards it showed four entries per screen where the web shows
    // eleven, and nothing joined one entry to the next. The rail carries the
    // order; the density comes back from dropping the card around every row.
    final tone = switch (badge) {
      AuditBadge.created => context.tokens.success,
      AuditBadge.deleted => context.tokens.danger,
      AuditBadge.updated => context.tokens.neutral,
    };
    return AppTimelineEntry(
      tone: tone,
      marker: icon,
      isLast: isLast,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
      timestamp: timestamp,
    );
  }

  /// A field difference: `de → para`, or the lone value when there is only
  /// one. A lone OLD value renders as what it IS — the value being undone —
  /// never as a fresh one (F-58 QA 4).
  Widget _diffRow(String? label, String? from, String? to) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Wrap(
          spacing: Spacing.xs,
          runSpacing: Spacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (label != null)
              Text('$label:',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
            if (from != null)
              _valueChip(from, context.tokens.danger, struck: true),
            if (from != null && to != null)
              Icon(Icons.arrow_forward,
                  size: TypeScale.label, color: context.tokens.textMuted),
            if (to != null) _valueChip(to, context.tokens.success),
          ],
        ),
      );

  /// U-28 — the value that changed, as a chip.
  ///
  /// The web highlights both sides with a background; the port left them as
  /// coloured runs inside a sentence, which a reader has to scan for. A chip is
  /// found, not read.
  Widget _valueChip(String text, ToneColors tone, {bool struck = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.xs + 2, vertical: 1),
        decoration: BoxDecoration(
          color: tone.container,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tone.onContainer,
                decoration: struck ? TextDecoration.lineThrough : null,
              ),
        ),
      );

  Widget _emptyState(String icon, String title, String body) =>
      AppEmptyState(icon: icon, title: title, body: body);

  Widget _banner(String title, String message) => AppBanner(
        tone: context.tokens.danger,
        leading: '⚠️',
        title: title,
        message: message,
      );
}
