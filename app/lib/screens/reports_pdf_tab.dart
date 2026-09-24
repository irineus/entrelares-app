import 'dart:async';

import 'dart:typed_data';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';
import 'package:printing/printing.dart';
import 'package:crypto/crypto.dart' show sha256;

import '../env.dart';
import 'package:entrelares_db_contracts/models/account_log.dart';
import 'package:entrelares_db_contracts/models/day_account.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/report_attestation.dart';
import '../services/custody_data_source.dart';
import '../services/report_pdf.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/rich_label.dart';

/// "Relatório do histórico em PDF" (F-33) — port of `ReportsPdf.razor`, and
/// **the redesign of the batch**: the web previews HTML and lets the browser
/// print it; here the document is a real PDF built on the device and handed to
/// the system share sheet or the native print dialog.
///
/// The gate is the F-32 mirror (`is_premium()` is the server's word; this only
/// decides what the UI offers). Until the billing batch (lote 5) the upsell is
/// **neutral** — it explains the feature and stops there, with no checkout
/// link, which is exactly what the store build requires (T-38).
class ReportsPdfTab extends StatefulWidget {
  final CustodyDataSource dataSource;

  /// Injected by the tests; production reads the clock.
  final DateTime Function() now;

  /// Injected by the tests; production hands the bytes to the system.
  final Future<void> Function(Uint8List bytes, String fileName)? onShare;
  final Future<void> Function(Uint8List bytes, String fileName)? onPrint;

  const ReportsPdfTab({
    super.key,
    required this.dataSource,
    this.now = DateTime.now,
    this.onShare,
    this.onPrint,
  });

  @override
  State<ReportsPdfTab> createState() => _ReportsPdfTabState();
}

enum _PeriodKind { month, year, custom }

class _ReportsPdfTabState extends State<ReportsPdfTab> {
  bool _loading = true;
  bool _generating = false;
  bool _isPremium = false;

  Member? _me;
  String? _loadErrorRaw;
  String? _errorText;

  _PeriodKind _kind = _PeriodKind.month;
  late int _month = widget.now().month;
  late int _year = widget.now().year;
  late DateTime _customStart =
      DateTime(widget.now().year, widget.now().month, 1);
  late DateTime _customEnd = DateTime(
      widget.now().year, widget.now().month, widget.now().day);

  final _childName = TextEditingController();

  /// F-55: with the flag on and a child registered, the PDF prints the
  /// registered name(s) and the free field disappears (owner, 24/09/2026).
  /// Null keeps today's free field — flag off, or no child yet.
  String? _registeredChildNames;

  /// F-55: the agenda is on for this build — the PDF prints section 5.
  bool _agendaOn = false;

  /// F-34: the expenses are on for this build — the PDF prints their section
  /// (never for a viewer, who reads no expense).
  bool _expensesOn = false;

  /// F-64: `feature.report_attestation` — the PDF goes out with its QR.
  bool _attestOn = false;
  List<ReportAttestation> _attestations = const [];
  bool _includeFutureSwaps = false;

  CustodyReport? _report;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _childName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadErrorRaw = null;
    });
    try {
      final me = await widget.dataSource.fetchOwnProfile();
      final family = await widget.dataSource.fetchOwnFamily();
      final registered = await _loadRegisteredChildNames();
      if (!mounted) return;
      setState(() {
        _me = me;
        _registeredChildNames = registered;
        // F-32 mirror, fail-closed: no family row → free.
        _isPremium = Family.isPremiumFamily(family, widget.now().toUtc());
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadErrorRaw = e.toString();
        _loading = false;
      });
    }
  }

  /// Best-effort: a failure keeps the free field, which is how the PDF has
  /// always named the child.
  Future<String?> _loadRegisteredChildNames() async {
    try {
      final settings =
          PublicSettings(await widget.dataSource.fetchPublicSettings());
      _agendaOn = settings.childAgendaEnabled;
      _expensesOn = settings.expensesEnabled;
      _attestOn = settings.reportAttestationEnabled;
      if (_attestOn) unawaited(_loadAttestations());
      if (!settings.childAgendaEnabled) return null;
      final children = await widget.dataSource.fetchChildren();
      if (!mounted) return null;
      return ChildRules.joinNames([for (final c in children) c.firstName],
          and: AppL10n.of(context).l[KApp.childAnd]);
    } catch (_) {
      return null;
    }
  }

  /// F-34: the period's live expenses, each caregiver's totals, the payments
  /// the receiver confirmed in the period, and the edits and deletions made
  /// in it (the append-only trail).
  Future<ReportExpenses> _reportExpenses(Localization l, DateTime start,
      DateTime end, List<Member> members) async {
    String name(int? id) {
      for (final m in members) {
        if (m.id == id && m.fullName.trim().isNotEmpty) return m.fullName;
      }
      return l[KApp.expenseFormerMember];
    }

    String money(int c) => ExpenseRules.brl(c, english: l.isEnglish);
    final all = await widget.dataSource
        .fetchExpenses(from: start, to: end, includeDeleted: true);
    final live = [
      for (final e in all)
        if (!e.isDeleted) e
    ]..sort((a, b) => a.spentOn.compareTo(b.spentOn));
    final paid = <int, int>{};
    final share = <int, int>{};
    for (final e in live) {
      paid[e.paidBy] = (paid[e.paidBy] ?? 0) + e.amountCents;
      for (final s in e.shares) {
        share[s.profileId] = (share[s.profileId] ?? 0) + s.shareCents;
      }
    }
    final people = {...paid.keys, ...share.keys}.toList()..sort();
    final endExclusive = DateTime(end.year, end.month, end.day + 1);
    bool inPeriod(DateTime local) =>
        !local.isBefore(start) && local.isBefore(endExclusive);
    final settlements = await widget.dataSource.fetchSettlements();
    final history = await widget.dataSource
        .fetchExpenseHistory([for (final e in all) e.id]);
    return ReportExpenses(
      lines: [
        for (final e in live)
          ReportExpenseLine(
            date: e.spentOn,
            description: e.description,
            categoryLabel: l[
                (ExpenseCategory.parse(e.category) ?? ExpenseCategory.other)
                    .labelKey],
            amountCents: e.amountCents,
            paidByName: name(e.paidBy),
          ),
      ],
      totals: [
        for (final id in people)
          ReportExpenseTotal(
              name: name(id),
              paidCents: paid[id] ?? 0,
              shareCents: share[id] ?? 0),
      ],
      payments: [
        for (final s in settlements)
          if (s.isConfirmed &&
              s.answeredAt != null &&
              inPeriod(s.answeredAt!.toLocal()))
            ReportExpensePayment(
              date: s.answeredAt!.toLocal(),
              fromName: name(s.fromProfile),
              toName: name(s.toProfile),
              amountCents: s.amountCents,
            ),
      ],
      changes: [
        for (final h in history)
          if (h.action != 'created' && h.oldData != null)
            ReportExpenseChange(
              atLocal: h.at.toLocal(),
              actorName: name(h.actorId),
              text: l.format(
                  h.action == 'updated'
                      ? KApp.expensePdfUpdated
                      : KApp.expensePdfDeleted,
                  [
                    '${h.oldData!['description'] ?? ''}',
                    money(int.tryParse('${h.oldData!['amount_cents']}') ?? 0),
                  ]),
            ),
      ],
    );
  }

  (DateTime, DateTime)? _resolvePeriod(Localization l) {
    switch (_kind) {
      case _PeriodKind.month:
        return (DateTime(_year, _month, 1), DateTime(_year, _month + 1, 0));
      case _PeriodKind.year:
        return (DateTime(_year, 1, 1), DateTime(_year, 12, 31));
      case _PeriodKind.custom:
        if (_customEnd.isBefore(_customStart)) {
          setState(() => _errorText = l[K.pdfErrEndBeforeStart]);
          return null;
        }
        return (_customStart, _customEnd);
    }
  }

  Future<void> _generate(Localization l) async {
    if (_generating) return;
    setState(() {
      _errorText = null;
      _report = null;
      _bytes = null;
    });

    final period = _resolvePeriod(l);
    if (period == null) return;
    final (start, end) = period;

    setState(() => _generating = true);
    try {
      final members = await widget.dataSource.fetchMembers();
      final roles = await widget.dataSource.fetchRoles();
      final family = await widget.dataSource.fetchOwnFamily();
      final days = await widget.dataSource.fetchSchedulesForPeriod(start, end);
      final logs =
          await widget.dataSource.fetchActivityLogsForPeriod(start, end);
      // F-45: which of those logs a swap resolution produced. Enrichment —
      // a failure costs the origin lines, never the report.
      var origins = const <int, SwapOrigin>{};
      try {
        origins = await widget.dataSource
            .fetchResolutionOrigins([for (final log in logs) log.id]);
      } catch (_) {/* the report stays useful without the origins */}
      // F-61: the caregivers' account trail for section 2 — the same
      // contract: a failure costs the section's lines, never the document.
      var accountEvents = const <AccountLog>[];
      try {
        accountEvents = await widget.dataSource
            .fetchAccountLogsByAction(caregiverTimelineActions);
      } catch (_) {/* section 2 prints its empty line */}
      // F-67: section 4, the same contract — a failure costs its lines.
      var dayAccounts = const <DayAccount>[];
      try {
        dayAccounts = await widget.dataSource.fetchDayAccounts(start, end);
      } catch (_) {/* section 4 prints its empty line */}

      // F-55: section 5 — the live events of the period. A failure prints the
      // section's empty line, like the other enrichments.
      List<ReportAgendaItem>? agenda;
      if (_agendaOn) {
        agenda = const [];
        try {
          final events = await widget.dataSource.fetchChildEvents(start, end);
          final children = await widget.dataSource.fetchChildren();
          agenda = [
            for (final e in events)
              ReportAgendaItem(
                date: e.eventDate,
                timeRange: AgendaRules.timeRange(e.startTime, e.endTime),
                start: e.startTime,
                kindLabel: l[(AgendaKind.parse(e.kind) ?? AgendaKind.other)
                    .labelKey],
                childName: [
                  for (final c in children)
                    if (c.id == e.childId) c.firstName
                ].firstOrNull,
                body: e.body,
                createdAt: e.createdAt,
              ),
          ];
        } catch (_) {/* section 5 prints its empty line */}
      }

      // F-34: the expenses section — the same contract: a failure prints
      // the section's empty line.
      ReportExpenses? expenses;
      if (_expensesOn && !(_me?.isViewer ?? false)) {
        expenses = const ReportExpenses();
        try {
          expenses = await _reportExpenses(l, start, end, members);
        } catch (_) {/* the section prints its empty line */}
      }

      String roleLabelOf(int profileId) {
        for (final m in members) {
          if (m.id != profileId) continue;
          for (final role in roles) {
            if (role.id == m.roleId) return role.displayLabel(l.current);
          }
        }
        return '';
      }

      final report = buildCustodyReport(
        familyName: family?.name ?? l[K.pdfDocFallbackFamily],
        childName: _registeredChildNames ?? _childName.text,
        start: start,
        end: end,
        today: widget.now(),
        days: [
          for (final d in days)
            ReportDay(
              scheduleDate: d.scheduleDate,
              scheduledParentId: d.scheduledParentId,
              actualParentId: d.actualParentId,
            ),
        ],
        members: [for (final m in members) m.toView()],
        auditLogs: [for (final log in logs) log.view],
        roleLabelOf: roleLabelOf,
        diffFor: (log) => computeAuditDiff(
            log: log, profiles: [for (final m in members) m.toView()], l: l),
        generatedBy: _me?.fullName ?? '',
        generatedAtLocal: widget.now(),
        appVersion: Env.appVersion,
        l: l,
        resolutionOrigins: origins,
        includeAcceptedFutureSwaps: _includeFutureSwaps,
        accounts: [
          for (final m in members)
            CaregiverAccountView(
              profileId: m.id,
              email: m.email,
              createdAtLocal: m.createdAt?.toLocal(),
              leftAtLocal: m.leftAt == null
                  ? null
                  : DateTime.tryParse(m.leftAt!)?.toLocal(),
              isPending: m.isPendingMember,
            ),
        ],
        accountEvents: [
          for (final e in accountEvents)
            AccountEventView(
              action: e.action,
              actorProfileId: e.actorProfileId,
              targetProfileId: e.targetProfileId,
              newValue: e.newValue,
              createdAtLocal: e.createdAt.toLocal(),
            ),
        ],
        agenda: agenda,
        expenses: expenses,
        dayAccounts: [
          for (final a in dayAccounts)
            ReportDayAccount(
              accountDate: a.accountDate,
              writtenAtLocal: a.createdAt.toLocal(),
              authorName: [
                for (final m in members)
                  if (m.id == a.authorProfileId) m.fullName
              ].firstOrNull ?? l[K.pdfDocSystem],
              body: a.body,
              isCorrection: a.correctsId != null,
              correctedAtLocal: [
                for (final c in dayAccounts)
                  if (c.correctsId == a.id) c.createdAt.toLocal()
              ].firstOrNull,
            ),
        ],
      );

      // F-64: the server attests the period FIRST, so the QR can be inside
      // the bytes it fingerprints. A refusal (flag, Premium, a viewer) is
      // not an error: the PDF goes out as it always did, without the QR.
      String? attestId;
      ReportStamp? stamp;
      if (_attestOn && _isPremium && _me?.isViewer != true) {
        try {
          final issued =
              await widget.dataSource.issueReportAttestation(start, end);
          attestId = issued.id;
          stamp = ReportStamp(
            url: AttestationRules.url(Env.current.webOrigin, issued.id),
            address: AttestationRules.address(Env.current.webOrigin, issued.id),
            untilLocal: issued.expiresAt.toLocal(),
          );
        } catch (_) {/* no QR — the document itself stands */}
      }
      final bytes = await buildReportPdf(report, l, stamp: stamp);
      var hashFailed = false;
      if (attestId != null) {
        try {
          await widget.dataSource
              .attachReportHash(attestId, sha256.convert(bytes).toString());
        } catch (_) {
          hashFailed = true;
        }
        unawaited(_loadAttestations());
      }
      if (hashFailed && mounted) {
        showAppSnack(context, l[KApp.attestHashFailed], type: AppSnackType.info);
      }
      // T-78: the period KIND only — never the dates or the header name.
      unawaited(widget.dataSource.analytics?.trackEvent(
              AnalyticsEvents.pdfExport,
              props: {'period': _kind.name}) ??
          Future<void>.value());
      if (!mounted) return;
      setState(() {
        _report = report;
        _bytes = bytes;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = isSessionExpired(e.toString())
          ? sessionExpiredMessage(l)
          : l.format(K.pdfErrGenerate, [e.toString()]));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _share() async {
    final bytes = _bytes, report = _report;
    if (bytes == null || report == null) return;
    final name = reportFileName(report);
    final share = widget.onShare ??
        (Uint8List b, String f) => Printing.sharePdf(bytes: b, filename: f);
    await share(bytes, name);
  }

  Future<void> _print() async {
    final bytes = _bytes, report = _report;
    if (bytes == null || report == null) return;
    final name = reportFileName(report);
    final printer = widget.onPrint ??
        (Uint8List b, String f) =>
            Printing.layoutPdf(onLayout: (_) async => b, name: f);
    await printer(bytes, name);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text(l[K.pdfHeading],
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l[K.pdfSubtitle],
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        // U-49 (U-29's R4): the tab knows the shape of what it is about to
        // show — the filter card — so the wait draws that shape, not a
        // spinner (U-27: skeletons, not spinners). The heading above stays,
        // because it never depended on the read.
        if (_loading)
          _filterSkeleton(l)
        else if (_loadErrorRaw != null)
          _banner(isSessionExpired(_loadErrorRaw!)
              ? sessionExpiredMessage(l)
              : l.format(K.pdfErrLoad, [_loadErrorRaw!]))
        else if (!_isPremium)
          _upsell(l)
        else ...[
          _filterCard(l),
          if (_report != null && _bytes != null) ...[
            const SizedBox(height: 12),
            _readyCard(l),
          ],
          if (_attestOn && _attestations.isNotEmpty) ...[
            const SizedBox(height: 12),
            _attestationsCard(l),
          ],
        ],
      ],
    );
  }

  /// The F-33 gate. **Neutral by design** (T-38): it says what the report is
  /// and stops — the plan/checkout surface belongs to the billing batch, and a
  /// store build may never carry an external checkout link.
  Widget _upsell(Localization l) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 16, color: context.tokens.accent.solid),
                  const SizedBox(width: Spacing.xs),
                  Text(l[K.pdfUpsellBadge],
                      style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
              const SizedBox(height: 4),
              Text(l[K.pdfUpsellTitle],
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              RichLabel.of(l, K.pdfUpsellText,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      );

  /// The filter card's outline while the premium check is in flight: the
  /// segmented control, the two selectors, the name field, the toggle and the
  /// button — in that order and at those heights, so nothing jumps when the
  /// real card lands.
  Widget _filterSkeleton(Localization l) => Semantics(
        label: l[K.pdfLoading],
        excludeSemantics: true,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppSkeleton(height: 40, radius: Radii.md),
                const SizedBox(height: 8),
                Row(
                  children: const [
                    Expanded(child: AppSkeleton(height: 56)),
                    SizedBox(width: 8),
                    Expanded(child: AppSkeleton(height: 56)),
                  ],
                ),
                const SizedBox(height: 8),
                const AppSkeleton(height: 56),
                const SizedBox(height: 8),
                const AppSkeleton(height: 40),
                const SizedBox(height: 8),
                const AppSkeleton(height: 40, radius: Radii.lg),
              ],
            ),
          ),
        ),
      );

  Widget _filterCard(Localization l) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppSegmented<_PeriodKind>(
                semantics: l[K.pdfPeriodAria],
                options: [
                  (value: _PeriodKind.month, label: l[K.pdfByMonth]),
                  (value: _PeriodKind.year, label: l[K.pdfByYear]),
                  (value: _PeriodKind.custom, label: l[K.pdfCustom]),
                ],
                selected: _kind,
                onChanged: (v) => setState(() => _kind = v),
              ),
              const SizedBox(height: 8),
              if (_kind == _PeriodKind.custom)
                _customRange(l)
              else
                Row(
                  children: [
                    if (_kind == _PeriodKind.month) ...[
                      Expanded(
                        child: Semantics(
                          label: l[K.pdfByMonth],
                          child: DropdownButtonFormField<int>(
                            initialValue: _month,
                            items: [
                              for (var m = 1; m <= 12; m++)
                                DropdownMenuItem(
                                    value: m, child: Text(l.monthName(m))),
                            ],
                            onChanged: (m) =>
                                setState(() => _month = m ?? _month),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: Semantics(
                        label: l[K.pdfByYear],
                        child: DropdownButtonFormField<int>(
                          initialValue: _year,
                          items: [
                            // U-49: one range for the three report tabs.
                            for (final y in reportYearRange(widget.now().year))
                              DropdownMenuItem(value: y, child: Text('$y')),
                          ],
                          onChanged: (y) => setState(() => _year = y ?? _year),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              if (_registeredChildNames == null)
                AppTextField(
                  label: '${l[K.pdfChildName]} ${l[K.pdfChildOptional]}',
                  hint: l[K.pdfChildPlaceholder],
                  controller: _childName,
                  maxLength: 80,
                )
              else
                AppListRow(
                  key: const ValueKey('pdf-registered-child'),
                  label: l[K.pdfChildName],
                  value: _registeredChildNames,
                ),
              // U-20: the same option as the on-screen Resumo — the numbers of
              // the two must agree.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _includeFutureSwaps,
                title: Text(l[K.pdfIncludeFutureSwaps],
                    style: Theme.of(context).textTheme.bodySmall),
                onChanged: (v) => setState(() => _includeFutureSwaps = v),
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 4),
                AppBanner(
                    tone: context.tokens.danger,
                    icon: Icons.error_outline,
                    message: _errorText!),
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _generating ? null : () => _generate(l),
                child: Text(l[_generating ? K.pdfGenerating : K.pdfGenerate]),
              ),
            ],
          ),
        ),
      );

  Widget _customRange(Localization l) => Row(
        children: [
          Expanded(
            child: _dateField(l, l[K.pdfFrom], _customStart,
                (d) => setState(() => _customStart = d)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dateField(l, l[K.pdfTo], _customEnd,
                (d) => setState(() => _customEnd = d)),
          ),
        ],
      );

  Widget _dateField(Localization l, String label, DateTime value,
          ValueChanged<DateTime> onPicked) =>
      OutlinedButton(
        onPressed: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(widget.now().year - 5),
            lastDate: DateTime(widget.now().year + 5, 12, 31),
          );
          if (picked != null) onPicked(picked);
        },
        child: Text('$label ${l.formatDate(value)}'),
      );

  /// What the web calls the preview. A PDF viewer inside the tab would be a
  /// second reader of the same document; the useful native step is handing the
  /// file to the system — share sheet or the print dialog (which is where
  /// Android's own "Save as PDF" lives).
  Future<void> _loadAttestations() async {
    try {
      final rows = await widget.dataSource.fetchReportAttestations();
      if (!mounted) return;
      setState(() => _attestations = rows);
    } catch (_) {/* the list is a convenience; the PDF never waits on it */}
  }

  AttestationState _stateOf(ReportAttestation a) {
    if (a.revokedAt != null) return AttestationState.revoked;
    if (!a.expiresAt.isAfter(widget.now().toUtc())) {
      return AttestationState.expired;
    }
    return a.sha256 == null ? AttestationState.pending : AttestationState.valid;
  }

  /// F-64: the family's issued reports; the admin revokes one that should no
  /// longer count (the QR then says "revogado").
  Widget _attestationsCard(Localization l) {
    final theme = Theme.of(context);
    final canRevoke = _me?.isAdmin == true;
    String period(ReportAttestation a) => a.periodFrom == null
        ? ''
        : '${l.formatDate(a.periodFrom!)} – ${l.formatDate(a.periodTo!)}';
    String stateLabel(AttestationState st) => l[switch (st) {
          AttestationState.valid => KApp.attestStateValid,
          AttestationState.pending => KApp.attestStatePending,
          AttestationState.revoked => KApp.attestStateRevoked,
          _ => KApp.attestStateExpired,
        }];
    return AppCard(
      key: const ValueKey('attestations-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l[KApp.attestSection], style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(l[KApp.attestSectionLead], style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final a in _attestations)
            Row(
              key: ValueKey('attestation-${a.id}'),
              children: [
                Expanded(
                  child: Text(l.format(KApp.attestRowState,
                      [period(a), stateLabel(_stateOf(a))])),
                ),
                if (canRevoke &&
                    (_stateOf(a) == AttestationState.valid ||
                        _stateOf(a) == AttestationState.pending))
                  TextButton(
                    key: ValueKey('attestation-revoke-${a.id}'),
                    onPressed: () => _revoke(a, l, period(a)),
                    child: Text(l[KApp.attestRevoke]),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _revoke(
      ReportAttestation a, Localization l, String periodText) async {
    final yes = await showDestructiveConfirm(
      context: context,
      title: l[KApp.attestRevoke],
      message: l.format(KApp.attestRevokeConfirm, [periodText]),
      yesLabel: l[KApp.attestRevoke],
      noLabel: l[K.commonCancel],
    );
    if (!yes || !mounted) return;
    try {
      await widget.dataSource.revokeReportAttestation(a.id);
      if (!mounted) return;
      showAppSnack(context, l[KApp.attestRevoked2]);
      await _loadAttestations();
    } catch (e) {
      if (!mounted) return;
      showAppSnack(
          context, translateSaveError(e.toString(), l[K.errSaveFailed], l),
          type: AppSnackType.error);
    }
  }

  Widget _readyCard(Localization l) {
    final report = _report!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l[K.pdfDocTitle],
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              l.format(K.pdfDocPeriodValue, [
                l.formatDate(report.periodStart),
                l.formatDate(report.periodEnd),
                report.totalDays,
              ]),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            RichLabel.of(
              l,
              report.includesFutureSwaps
                  ? K.pdfDocTotalSwapsFuture
                  : K.pdfDocTotalSwaps,
              args: [report.totalSwaps],
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _share,
              // U-29: the Material share glyph — `Icons.ios_share` was the one
              // iOS-styled icon in an Android-first app, and the família
              // screen already shares with this one.
              icon: const Icon(Icons.share_outlined),
              label: Text(l[KApp.commonShare]),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _print,
              icon: const Icon(Icons.print_outlined),
              label: Text(l[K.pdfPrintButton]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner(String message) => AppBanner(
        tone: context.tokens.danger,
        icon: Icons.error_outline,
        message: message,
      );
}
