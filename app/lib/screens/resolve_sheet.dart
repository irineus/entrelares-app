import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import '../widgets/app_l10n.dart';

/// The "🔔 Resolver" sheet — port of `Home.razor`'s bulk-workflow sheet. Three
/// subsets of the SELECTED days, each with its batch action: requests awaiting
/// my response (approve/reject, one shared F-44 reason), requests I sent
/// (cancel) and approved swaps (request revert — F-47 by decision: a batch
/// never restores day observations). A per-item failure is counted and
/// skipped so the batch is never left half-applied.
///
/// Pops with the summary string ("N aprovadas · M ignoradas") — the caller
/// clears the selection, reloads and shows it, mirroring `RunBulkWorkflowAsync`.
Future<String?> showResolveSheet({
  required BuildContext context,
  required Set<DateTime> selectedDays,
  required List<SwapRequest> openRequests,
  required Map<String, CareSchedule> daysByIso,
  required DateTime today,
  required int? ownProfileId,
  required Member? myProfile,
  required List<Member> allProfiles,
  required CustodyDataSource dataSource,
}) {
  return showAppSheet<String>(
    context: context,
    builder: (context) => _ResolveSheet(
      selectedDays: selectedDays,
      openRequests: openRequests,
      daysByIso: daysByIso,
      today: today,
      ownProfileId: ownProfileId,
      myProfile: myProfile,
      allProfiles: allProfiles,
      dataSource: dataSource,
    ),
  );
}

class _ResolveSheet extends StatefulWidget {
  final Set<DateTime> selectedDays;
  final List<SwapRequest> openRequests;
  final Map<String, CareSchedule> daysByIso;
  final DateTime today;
  final int? ownProfileId;
  final Member? myProfile;
  final List<Member> allProfiles;
  final CustodyDataSource dataSource;

  const _ResolveSheet({
    required this.selectedDays,
    required this.openRequests,
    required this.daysByIso,
    required this.today,
    required this.ownProfileId,
    required this.myProfile,
    required this.allProfiles,
    required this.dataSource,
  });

  @override
  State<_ResolveSheet> createState() => _ResolveSheetState();
}

enum _WfAction { none, approve, reject, cancel, revert }

class _ResolveSheetState extends State<_ResolveSheet> {
  late final TextEditingController _rejectReason;
  bool _acting = false;
  _WfAction _active = _WfAction.none;
  String? _error;
  double _progress = 0;
  String _progressLabel = '';

  @override
  void initState() {
    super.initState();
    _rejectReason = TextEditingController();
  }

  @override
  void dispose() {
    _rejectReason.dispose();
    super.dispose();
  }

  Map<int, SwapRequest> get _byId =>
      {for (final r in widget.openRequests) r.id: r};

  List<SwapRequestView> get _views =>
      [for (final r in widget.openRequests) r.toView()];

  List<SwapRequest> get _pendingForMe => [
        for (final v in selectedPendingForMe(
          openRequests: _views,
          selectedDates: widget.selectedDays,
          myProfileId: widget.ownProfileId,
        ))
          _byId[v.id]!,
      ];

  List<SwapRequest> get _sentByMe => [
        for (final v in selectedSentByMe(
          openRequests: _views,
          selectedDates: widget.selectedDays,
          myProfileId: widget.ownProfileId,
        ))
          _byId[v.id]!,
      ];

  List<CareSchedule> get _revertable {
    final frozenDates = [for (final r in widget.openRequests) r.scheduleDate];
    return [
      for (final d in widget.selectedDays)
        if (widget.daysByIso[CareSchedule.isoDate(d)] case final row?)
          if (isRevertCandidate(
            scheduleDate: row.scheduleDate,
            scheduledParentId: row.scheduledParentId,
            actualParentId: row.actualParentId,
            today: widget.today,
            frozenDates: frozenDates,
          ))
            row,
    ];
  }

  String? get _reason =>
      _rejectReason.text.trim().isEmpty ? null : _rejectReason.text;

  /// Mirror of `RunBulkWorkflowAsync`: determinate progress, per-item
  /// try/catch counting failures, then pop with the summary.
  Future<void> _run<T>(
    List<T> items,
    Future<void> Function(T) action,
    String successSingularKey,
    String successPluralKey,
    _WfAction kind,
  ) async {
    if (items.isEmpty || _acting) return;
    final l = AppL10n.of(context).l;
    setState(() {
      _acting = true;
      _active = kind;
      _error = null;
      _progress = 0;
      _progressLabel = '';
    });
    try {
      var succeeded = 0;
      var failed = 0;
      for (var i = 0; i < items.length; i++) {
        setState(() {
          _progress = i / items.length;
          _progressLabel =
              l.format(KApp.wfProgressProcessing, [i + 1, items.length]);
        });
        try {
          await action(items[i]);
          succeeded++;
        } catch (_) {
          // Partial failure: skip this item and keep going.
          failed++;
        }
      }
      final parts = [
        bulkPluralize(l, succeeded, successSingularKey, successPluralKey),
        if (failed > 0)
          bulkPluralize(l, failed, K.sumIgnoredOne, K.sumIgnoredMany),
      ];
      if (mounted) Navigator.of(context).pop(parts.join(' · '));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _active = _WfAction.none;
        _error = isSessionExpired(e.toString())
            ? sessionExpiredMessage(l)
            : l.format(K.errBulkWorkflowFailed, [e.toString()]);
      });
    }
  }

  Member _requireMyProfile() {
    final my = widget.myProfile;
    if (my == null) throw StateError('Perfil do utilizador não encontrado.');
    return my;
  }

  Widget _actionButton({
    required _WfAction kind,
    required String label,
    required VoidCallback onPressed,
    bool filled = false,
  }) {
    final child = _acting && _active == kind
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2))
        : Text(label);
    return filled
        ? FilledButton(onPressed: _acting ? null : onPressed, child: child)
        : OutlinedButton(onPressed: _acting ? null : onPressed, child: child);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final pendingForMe = _pendingForMe;
    final sentByMe = _sentByMe;
    final revertable = _revertable;

    // U-28 QA: framed like every other sheet — capped height, scrolling body,
    // and the way out pinned instead of buried under the action groups.
    return AppSheetFrame(
      title: l[K.wfTitle],
      primaryLabel: l[K.wfClose],
      onPrimary: _acting ? null : () => Navigator.of(context).pop(),
      busy: _acting,
      children: [
              if (pendingForMe.isNotEmpty) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                AppFieldLabel(l.format(K.wfAwaitingYou, [pendingForMe.length])),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: l[K.wfMessage],
                        hint: l[K.wfRejectPlaceholder],
                        controller: _rejectReason,
                        maxLength: 200,
                        enabled: !_acting,
                      ),
                    ),
                    AppInfoTip(message: l[K.wfRejectHint]),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _actionButton(
                        kind: _WfAction.approve,
                        label: l.format(K.wfApprove, [pendingForMe.length]),
                        filled: true,
                        onPressed: () => _run(
                          pendingForMe,
                          (SwapRequest req) => req.isRevertPending
                              ? widget.dataSource.approveRevert(req.id,
                                  allProfiles: widget.allProfiles)
                              : widget.dataSource.approveSwap(req.id,
                                  allProfiles: widget.allProfiles),
                          K.sumApprovedOne,
                          K.sumApprovedMany,
                          _WfAction.approve,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionButton(
                        kind: _WfAction.reject,
                        label: l.format(K.wfReject, [pendingForMe.length]),
                        onPressed: () => _run(
                          pendingForMe,
                          (SwapRequest req) => req.isRevertPending
                              ? widget.dataSource.rejectRevert(req.id,
                                  reason: _reason,
                                  allProfiles: widget.allProfiles)
                              : widget.dataSource.rejectSwap(req.id,
                                  reason: _reason,
                                  allProfiles: widget.allProfiles),
                          K.sumRejectedOne,
                          K.sumRejectedMany,
                          _WfAction.reject,
                        ),
                      ),
                    ),
                  ],
                ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),
              ],

              if (sentByMe.isNotEmpty) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                AppFieldLabel(l.format(
                    sentByMe.length == 1
                        ? K.wfSentByYouOne
                        : K.wfSentByYouMany,
                    [sentByMe.length])),
                _actionButton(
                  kind: _WfAction.cancel,
                  label: l.format(K.wfCancel, [sentByMe.length]),
                  onPressed: () => _run(
                    sentByMe,
                    (SwapRequest req) => req.isRevertPending
                        ? widget.dataSource.cancelRevert(req.id,
                            allProfiles: widget.allProfiles)
                        : widget.dataSource.cancelSwap(req.id,
                            allProfiles: widget.allProfiles),
                    K.sumCancelledOne,
                    K.sumCancelledMany,
                    _WfAction.cancel,
                  ),
                ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),
              ],

              if (revertable.isNotEmpty) ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                AppFieldLabel(l.format(K.wfApprovedSwaps, [revertable.length])),
                _actionButton(
                  kind: _WfAction.revert,
                  label: l.format(K.wfRequestRevert, [revertable.length]),
                  onPressed: () => _run(
                    revertable,
                    // F-47, by decision: a batch never restores the day
                    // observations (asking once for N days would apply one
                    // answer to N different texts).
                    (CareSchedule sched) => widget.dataSource.requestRevert(
                      scheduleDate: sched.scheduleDate,
                      currentActualProfileId: sched.actualParentId!,
                      scheduledParentId: sched.scheduledParentId,
                      myProfile: _requireMyProfile(),
                      allProfiles: widget.allProfiles,
                    ),
                    K.sumRevertOne,
                    K.sumRevertMany,
                    _WfAction.revert,
                  ),
                ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),
              ],

              if (_acting) ...[
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 4),
                Text(_progressLabel,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.sm),
                  child: Text('⚠️ $_error',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ),
      ],
    );
  }
}
