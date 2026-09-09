import 'dart:typed_data';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';
import 'package:printing/printing.dart';

import '../env.dart';
import 'package:entrelares_db_contracts/models/account_log.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/custody_data_source.dart';
import '../services/report_pdf.dart';
import '../widgets/app_l10n.dart';
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
      if (!mounted) return;
      setState(() {
        _me = me;
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
        childName: _childName.text,
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
      );

      final bytes = await buildReportPdf(report, l);
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

    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 8),
            Text(l[K.pdfLoading]),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Text(l[K.pdfHeading],
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(l[K.pdfSubtitle],
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 12),
        if (_loadErrorRaw != null)
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
              Text(l[K.pdfUpsellBadge],
                  style: Theme.of(context).textTheme.labelMedium),
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
                            for (var y = widget.now().year - 2;
                                y <= widget.now().year + 1;
                                y++)
                              DropdownMenuItem(value: y, child: Text('$y')),
                          ],
                          onChanged: (y) => setState(() => _year = y ?? _year),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              AppTextField(
                label: '${l[K.pdfChildName]} ${l[K.pdfChildOptional]}',
                hint: l[K.pdfChildPlaceholder],
                controller: _childName,
                maxLength: 80,
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
                Text('⚠️ $_errorText',
                    style: TextStyle(
                        color: context.tokens.danger.onContainer)),
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
            OutlinedButton(
              onPressed: _print,
              child: Text(l[K.pdfPrintButton]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _banner(String message) => AppBanner(
        tone: context.tokens.danger,
        leading: '⚠️',
        message: message,
      );
}
