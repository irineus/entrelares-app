import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';
import '../widgets/ui/ui.dart';

/// F-65 — the confirmation of a quick swap. The plan is already decided
/// (`quickSwapPlan`, core): this sheet only SAYS what it does, in plain
/// words — who takes which days, how many requests open and who approves
/// them — takes the optional F-44 message, and runs the requests.
///
/// Each request goes through the SAME path the day sheet and the bulk sheet
/// use: upsert the base row (unchanged here, but it refreshes the F-26
/// pre-edit snapshot the revert restores from), then `createSwapRequest`.
/// A per-day conflict (someone requested first — T-33) is counted and
/// skipped, never fatal; the summary says so.
///
/// Pops with the summary string the caller toasts, like the bulk sheet.
Future<String?> showQuickSwapSheet({
  required BuildContext context,
  required QuickSwapPlan plan,
  required Map<String, CareSchedule> daysByIso,
  required CustodyDataSource dataSource,
  required Member myProfile,
  required List<Member> allProfiles,
}) {
  return showAppSheet<String>(
    context: context,
    builder: (context) => _QuickSwapSheet(
      plan: plan,
      daysByIso: daysByIso,
      dataSource: dataSource,
      myProfile: myProfile,
      allProfiles: allProfiles,
    ),
  );
}

class _QuickSwapSheet extends StatefulWidget {
  final QuickSwapPlan plan;
  final Map<String, CareSchedule> daysByIso;
  final CustodyDataSource dataSource;
  final Member myProfile;
  final List<Member> allProfiles;

  const _QuickSwapSheet({
    required this.plan,
    required this.daysByIso,
    required this.dataSource,
    required this.myProfile,
    required this.allProfiles,
  });

  @override
  State<_QuickSwapSheet> createState() => _QuickSwapSheetState();
}

class _QuickSwapSheetState extends State<_QuickSwapSheet> {
  late final TextEditingController _message = TextEditingController();
  bool _saving = false;
  double _progress = 0;
  String _progressLabel = '';
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  String get _counterpartName =>
      widget.allProfiles
          .where((m) => m.id == widget.plan.counterpartId)
          .firstOrNull
          ?.fullName ??
      '';

  String _dates(Localization l, List<DateTime> days) =>
      days.map(l.formatDateShort).join(', ');

  void _step(int done, int total, String label) {
    if (!mounted) return;
    setState(() {
      _progress = total == 0 ? 0 : done / total;
      _progressLabel = label;
    });
  }

  Future<void> _confirm() async {
    if (_saving) return;
    final l = AppL10n.of(context).l;
    setState(() {
      _saving = true;
      _error = null;
      _progress = 0;
      _progressLabel = '';
    });

    bool isWorkflowConflict(String raw) =>
        isDayConflict(raw) ||
        raw.contains('swap_requests_one_pending_per_date');

    try {
      final requests = widget.plan.requests;
      var swapCount = 0;
      var conflictCount = 0;
      var processed = 0;
      for (final r in requests) {
        processed++;
        _step(processed, requests.length,
            l.format(KApp.bulkProgressSaving, [processed, requests.length]));

        final existing = widget.daysByIso[CareSchedule.isoDate(r.date)];
        // The planned parent of a day is the one who is NOT proposed on it;
        // the row says the same when it exists (the plan required it to).
        final planned = r.proposedActualParentId == widget.plan.counterpartId
            ? widget.plan.requesterId
            : widget.plan.counterpartId;
        final base = CareSchedule(
          id: existing?.id ?? 0,
          scheduleDate: r.date,
          handoffTime: existing?.handoffTime,
          scheduledParentId: existing?.scheduledParentId ?? planned,
          actualParentId: existing?.actualParentId,
          notes: existing?.notes,
          revision: existing?.revision ?? 0,
          revisionToken: existing?.revisionToken ?? '',
        );
        try {
          if (existing == null) {
            await widget.dataSource.insertDay(base);
          } else {
            await widget.dataSource.updateDay(base);
          }
          final refreshed = await widget.dataSource.fetchDay(r.date);
          // No handoff is proposed: the T-27 triggers re-evaluate the
          // transitions when the request is approved.
          await widget.dataSource.createSwapRequest(
            schedule: refreshed ?? base,
            proposedActualParentId: r.proposedActualParentId,
            requestMessage: _message.text,
            myProfile: widget.myProfile,
            allProfiles: widget.allProfiles,
          );
          swapCount++;
        } catch (e) {
          if (isWorkflowConflict(e.toString())) {
            conflictCount++;
          } else {
            rethrow;
          }
        }
      }

      var summary = bulkSummary(l,
          directCount: 0,
          directSingularKey: K.sumUpdatedOne,
          directPluralKey: K.sumUpdatedMany,
          swapCount: swapCount);
      if (conflictCount > 0) {
        summary += l.format(
            conflictCount == 1
                ? K.bulkConflictSuffixOne
                : K.bulkConflictSuffixMany,
            [conflictCount]);
      }
      if (mounted) Navigator.of(context).pop(summary);
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _saving = false;
        _error = isSessionExpired(raw)
            ? sessionExpiredMessage(l)
            : translateSaveError(raw, l[K.errSaveFailed], l);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final plan = widget.plan;
    final textTheme = Theme.of(context).textTheme;
    return AppSheetFrame(
      title: l.format(K.quickSwapTitle, [plan.dayCount]),
      primaryLabel: l[K.quickSwapConfirm],
      onPrimary: _confirm,
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      busy: _saving,
      // U-38: pinned under the title, not after the message field.
      error: _error,
      children: [
        // ── What changes hands, in calendar order, and who approves ──
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.format(K.quickSwapTheyTake,
                    [_counterpartName, _dates(l, plan.requesterDays)]),
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: Spacing.xs),
              Text(
                l.format(K.quickSwapYouTake, [_dates(l, plan.counterpartDays)]),
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: Spacing.sm),
              Text(
                l.format(
                    K.quickSwapRequests, [plan.dayCount, _counterpartName]),
                style: textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(height: Spacing.sm),
        // ── F-44: one message rides every request of the batch ──
        AppCard(
          child: AppTextField(
            label: '${l[K.editorMessageLabel]} ${l[K.bulkMessageHint]}',
            hint: l[K.bulkMessagePlaceholder],
            controller: _message,
            maxLength: 200,
            enabled: !_saving,
          ),
        ),
        const SizedBox(height: Spacing.md),
        if (_saving) ...[
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 4),
          Text(_progressLabel, style: textTheme.bodySmall),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
