import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import '../services/custody_data_source.dart';
import '../services/pdf_pick.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/ui/ui.dart';

/// F-64 — `/verificar/<id>`: the public check of a verifiable report.
///
/// Whoever holds the paper opens it from the QR, with no account. It shows
/// what the SERVER attested (issue, period, a summary with initials and
/// counts, the fingerprint) and compares a PDF the reader chooses or drops —
/// hashed HERE, never uploaded. A revoked or expired report says so; an
/// unknown id says that, never a blank page.
class VerifyReportScreen extends StatefulWidget {
  final String id;
  final CustodyDataSource dataSource;

  const VerifyReportScreen(
      {super.key, required this.id, required this.dataSource});

  @override
  State<VerifyReportScreen> createState() => _VerifyReportScreenState();
}

class _VerifyReportScreenState extends State<VerifyReportScreen> {
  Map<String, dynamic>? _answer;
  bool _failed = false;
  bool? _match;
  void Function()? _stopDrop;

  @override
  void initState() {
    super.initState();
    _load();
    _stopDrop = listenForDroppedPdf(_compare);
  }

  /// The router reuses this state when one QR's page leads to another's.
  @override
  void didUpdateWidget(VerifyReportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      setState(() {
        _answer = null;
        _failed = false;
        _match = null;
      });
      _load();
    }
  }

  @override
  void dispose() {
    _stopDrop?.call();
    super.dispose();
  }

  Future<void> _load() async {
    if (!AttestationRules.isId(widget.id)) {
      setState(() => _answer = const {'state': 'unknown'});
      return;
    }
    try {
      final answer =
          await widget.dataSource.verifyReportAttestation(widget.id.toLowerCase());
      if (!mounted) return;
      setState(() => _answer = answer);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  AttestationState get _state => AttestationState.parse(_answer?['state']);

  void _compare(Uint8List bytes) {
    final expected = _answer?['sha256'] as String?;
    if (expected == null || !mounted) return;
    setState(() => _match = AttestationRules.sameFingerprint(
        sha256.convert(bytes).toString(), expected));
  }

  Future<void> _pick() async {
    final bytes = await pickPdfBytes();
    if (bytes != null) _compare(bytes);
  }

  DateTime? _time(String key) {
    final raw = _answer?[key] as String?;
    return raw == null ? null : DateTime.parse(raw).toLocal();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(l[KApp.attestPageTitle])),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(Spacing.md),
              children: [
                if (_failed)
                  AppBanner(
                    tone: tokens.warning,
                    icon: Icons.cloud_off_outlined,
                    message: l[KApp.attestError],
                  )
                else if (_answer == null)
                  const LinearProgressIndicator()
                else
                  ..._body(l, tokens, textTheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body(Localization l, AppTokens tokens, TextTheme textTheme) {
    final state = _state;
    final issued = _time('issued_at');
    final until = _time('expires_at');
    final (tone, icon, message) = switch (state) {
      AttestationState.valid =>
        (tokens.success, Icons.verified_outlined, l[KApp.attestValid]),
      AttestationState.pending =>
        (tokens.warning, Icons.hourglass_empty, l[KApp.attestPending]),
      AttestationState.revoked => (
          tokens.danger,
          Icons.block,
          l.format(KApp.attestRevoked,
              [l.formatDate(_time('revoked_at') ?? DateTime.now())])
        ),
      AttestationState.expired => (
          tokens.neutral,
          Icons.event_busy_outlined,
          l.format(KApp.attestExpired, [l.formatDate(until ?? DateTime.now())])
        ),
      AttestationState.unknown =>
        (tokens.neutral, Icons.help_outline, l[KApp.attestUnknown]),
    };
    final summary = _answer?['summary'] as Map?;
    final sha = _answer?['sha256'] as String?;
    final from = _answer?['period_from'] as String?;
    final to = _answer?['period_to'] as String?;
    return [
      AppBanner(
        key: ValueKey('verify-state-${state.name}'),
        tone: tone,
        icon: icon,
        message: message,
      ),
      const SizedBox(height: Spacing.md),
      if (issued != null)
        AppListRow(
            label: l[KApp.attestIssuedAt], value: l.formatDateTime(issued)),
      if (from != null && to != null)
        AppListRow(
          label: l[KApp.attestPeriod],
          value:
              '${l.formatIsoDate(from)} – ${l.formatIsoDate(to)}',
        ),
      if (until != null && state != AttestationState.expired)
        AppListRow(
            label: l[KApp.attestValidUntil], value: l.formatDate(until)),
      if (summary != null) ...[
        const SizedBox(height: Spacing.md),
        Text(l[KApp.attestSummary], style: textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        Text(l.format(KApp.attestDaysPlanned, ['${summary['days_planned']}'])),
        for (final c in (summary['days_by_caregiver'] as List? ?? const []))
          Text(l.format(KApp.attestDaysBy, ['${c['initials']}', '${c['days']}'])),
        Text(l.format(
            KApp.attestDaysSwapped, ['${summary['days_changed_by_swap']}'])),
        Text(l.format(KApp.attestSwaps, [
          '${(summary['swaps'] as Map? ?? const {}).values.fold<num>(0, (a, b) => a + (b as num))}'
        ])),
        Text(l.format(
            KApp.attestDayAccounts, ['${summary['day_accounts']}'])),
        const SizedBox(height: Spacing.xs),
        Text(l[KApp.attestInitialsNote],
            style: textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
      ],
      if (sha != null) ...[
        const SizedBox(height: Spacing.md),
        Text(l[KApp.attestFingerprint], style: textTheme.titleSmall),
        const SizedBox(height: Spacing.xs),
        SelectableText(AttestationRules.groupFingerprint(sha),
            key: const ValueKey('verify-fingerprint'),
            style: textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')),
      ],
      if (state == AttestationState.valid) ...[
        const SizedBox(height: Spacing.md),
        if (canPickPdf) ...[
          FilledButton.icon(
            key: const ValueKey('verify-compare'),
            onPressed: _pick,
            icon: const Icon(Icons.upload_file),
            label: Text(l[KApp.attestCompare]),
          ),
          const SizedBox(height: Spacing.xs),
          Text(l[KApp.attestCompareHint],
              style: textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
        ] else
          Text(l[KApp.attestNoPicker],
              style: textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
        if (_match != null) ...[
          const SizedBox(height: Spacing.sm),
          AppBanner(
            key: ValueKey('verify-match-$_match'),
            tone: _match! ? tokens.success : tokens.danger,
            icon: _match! ? Icons.check_circle_outline : Icons.error_outline,
            message: l[_match! ? KApp.attestMatch : KApp.attestMismatch],
          ),
        ],
      ],
    ];
  }
}
