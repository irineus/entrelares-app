import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';

import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import '../services/custody_data_source.dart';
import '../widgets/app_l10n.dart';

/// What the panel did — the caller picks the toast, mirroring the six success
/// paths of `Home.razor`'s frozen-panel handlers.
enum FrozenDayOutcome {
  approved,
  rejected,
  cancelled,
  revertConfirmed,
  revertRejected,
  revertCancelled,
}

/// The toast key for each outcome (web: ToastSwapApproved … ToastRevertCancelled).
String frozenOutcomeToastKey(FrozenDayOutcome outcome) => switch (outcome) {
      FrozenDayOutcome.approved => K.toastSwapApproved,
      FrozenDayOutcome.rejected => K.toastSwapRejected,
      FrozenDayOutcome.cancelled => K.toastRequestCancelled,
      FrozenDayOutcome.revertConfirmed => K.toastRevertConfirmed,
      FrozenDayOutcome.revertRejected => K.toastRevertRejected,
      FrozenDayOutcome.revertCancelled => K.toastRevertCancelled,
    };

/// The frozen-day panel (F-12) — port of `FrozenDayPanel.razor` as a native
/// bottom sheet. Tapping a day with an open request lands here instead of the
/// editor; the three roles see three different panels: the TARGET approves or
/// rejects (with the dual-purpose F-44 note), the REQUESTER cancels, everyone
/// else observes. The database enforces every transition regardless.
Future<FrozenDayOutcome?> showFrozenDaySheet({
  required BuildContext context,
  required SwapRequest request,
  required List<Member> allProfiles,
  required int? ownProfileId,
  required CustodyDataSource dataSource,
  bool offline = false,
  String? childName,
  List<SwapRequest> siblings = const [],
  VoidCallback? onViewDay,
}) {
  return showAppSheet<FrozenDayOutcome>(
    context: context,
    builder: (context) => _FrozenDaySheet(
      request: request,
      allProfiles: allProfiles,
      ownProfileId: ownProfileId,
      dataSource: dataSource,
      offline: offline,
      childName: childName,
      siblings: siblings,
      onViewDay: onViewDay,
    ),
  );
}

class _FrozenDaySheet extends StatefulWidget {
  final SwapRequest request;
  final List<Member> allProfiles;
  final int? ownProfileId;
  final CustodyDataSource dataSource;

  /// T-18: opened with no connection — the request is shown, and no answer
  /// to it is offered. An approval parked for later could be refused when it
  /// finally went out (the request answered from the other phone, the 48 h
  /// cron resolving it), and "approved" that evaporates is worse than an
  /// honest "connect first".
  final bool offline;

  /// F-07: whose day this is, in a per-child plan.
  final String? childName;

  /// F-07 (PR 4b): the same requester's OTHER pending swap requests to me for
  /// this date, one per child — approved together from here.
  final List<SwapRequest> siblings;

  /// F-95: "Ver o dia" — the day this request froze, read-only (its agenda,
  /// note and relatos were unreachable while the request waited). Null where
  /// the caller has no day to show.
  final VoidCallback? onViewDay;

  const _FrozenDaySheet({
    required this.request,
    required this.allProfiles,
    required this.ownProfileId,
    required this.dataSource,
    this.offline = false,
    this.childName,
    this.siblings = const [],
    this.onViewDay,
  });

  @override
  State<_FrozenDaySheet> createState() => _FrozenDaySheetState();
}

class _FrozenDaySheetState extends State<_FrozenDaySheet> {
  // F-44: one dual-purpose field — sent as the approval note on approve and
  // as the rejection reason on reject (web decision: no second input).
  late final TextEditingController _approverNote;
  bool _acting = false;

  /// Which button carries the spinner while [_acting] disables them all.
  String? _pendingAction;
  String? _error;

  /// F-95: the request is no longer open — answered, cancelled or
  /// auto-approved since the push or the list was read. The panel says so
  /// and offers nothing to act on.
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _approverNote = TextEditingController();
    _refresh();
  }

  /// F-95: read the request again on open — a push from yesterday must not
  /// offer "Aprovar" on a request the 48 h cron already approved.
  Future<void> _refresh() async {
    try {
      final fresh = await widget.dataSource.fetchSwapRequest(widget.request.id);
      if (!mounted || fresh == null) return;
      if (fresh.status != 'pending' && fresh.status != 'revert_pending') {
        setState(() => _resolved = true);
      }
    } catch (_) {/* the server still refuses a stale answer */}
  }

  @override
  void dispose() {
    _approverNote.dispose();
    super.dispose();
  }

  String? _nameOf(int? id) {
    for (final p in widget.allProfiles) {
      if (p.id == id) return p.fullName;
    }
    return null;
  }

  /// Web parity: blank collapses to null here, but the text goes through RAW
  /// — the service normalizes the approval note itself, while the rejection
  /// reason lands on the row exactly as typed.
  String? get _note =>
      _approverNote.text.trim().isEmpty ? null : _approverNote.text;

  Future<void> _run(
    String actionKey,
    String errorKey,
    Future<FrozenDayOutcome> Function() action,
  ) async {
    final l = AppL10n.of(context).l;
    setState(() {
      _acting = true;
      _pendingAction = actionKey;
      _error = null;
    });
    try {
      final outcome = await action();
      if (mounted) Navigator.of(context).pop(outcome);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _pendingAction = null;
        final raw = e.toString();
        // F-95: a request settled meanwhile is a state, not a failure; and no
        // raw `PostgrestException(... P0001 ...)` ever reaches the reader.
        if (isSwapAlreadyAnswered(raw)) {
          _resolved = true;
          _error = null;
        } else {
          _error = isSessionExpired(raw)
              ? sessionExpiredMessage(l)
              : translateSaveError(raw, l[errorKey], l);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final request = widget.request;
    final isRevert = request.status == 'revert_pending';
    final iAmRequester = widget.ownProfileId == request.requestingProfileId;
    final iAmTarget = widget.ownProfileId == request.targetProfileId;
    // F-20: computed at render time — the panel always shows a pending request.
    final tag = request.toView().priorityTag(FamilyTime.now());

    final requesterName = _nameOf(request.requestingProfileId);
    final targetName = _nameOf(request.targetProfileId);
    final proposedName = _nameOf(request.proposedActualParentId);

    final handoff = parseTimeOfDay(request.proposedHandoffTime);
    final createdAtLocal = request.createdAt == null
        ? null
        : DateTime.tryParse(request.createdAt!)?.toLocal();

    // U-49: the shared label/value row — this sheet kept a private copy with
    // its own column split. A quoted message keeps its italic through
    // `valueWidget`; everything else is the row's own text.
    Widget infoRow(String labelKey, String value, {bool isMessage = false}) =>
        AppListRow(
          label: l[labelKey],
          value: isMessage ? null : value,
          valueWidget: isMessage
              ? Text(value,
                  textAlign: TextAlign.end,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontStyle: FontStyle.italic))
              : null,
        );

    Widget actionButton({
      required String actionKey,
      required String labelKey,
      required VoidCallback onPressed,
      bool filled = false,
      bool destructive = false,
    }) {
      final child = _pendingAction == actionKey
          ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Text(l[labelKey]);
      if (filled) {
        return FilledButton(onPressed: _acting ? null : onPressed, child: child);
      }
      if (destructive) {
        // U-38: the destructive look every sheet shares — danger ink on a
        // danger outline, not on the neutral border the others wear.
        return OutlinedButton(
          onPressed: _acting ? null : onPressed,
          style: AppSheetDangerAction.styleOf(context),
          child: child,
        );
      }
      return OutlinedButton(onPressed: _acting ? null : onPressed, child: child);
    }

    final urgencyTone = tag == SwapPriorityTag.overdue
        ? context.tokens.danger
        : context.tokens.warning;

    return AppSheetFrame(
      // U-31: the title is words only. The urgency it used to carry as an
      // emoji is the pinned notice below, which says it in a sentence.
      title: l[isRevert ? K.frozenRevertTitle : K.frozenSwapTitle],
      subtitle: widget.childName,
      // U-25: a tap on a day opens this sheet or the day sheet, and both carry
      // the same visible way out — the reader cannot tell in advance which one
      // a day will open.
      onClose: () => Navigator.of(context).pop(),
      closeLabel: l[K.commonClose],
      // U-38: the approve/reject/cancel row is pinned, so its failure is too.
      error: _error,
      // U-28 QA: the urgency line is CENTRED and BOLD, as the web has it. It is
      // the one sentence on the sheet that changes what the reader should do
      // next, and it was rendering as a left-aligned run of body text.
      pinnedNotice: tag == SwapPriorityTag.none
          ? null
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md, vertical: Spacing.sm),
              decoration: BoxDecoration(
                color: urgencyTone.container,
                border: Border.all(color: urgencyTone.border),
                borderRadius: BorderRadius.circular(Radii.md),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      tag == SwapPriorityTag.overdue
                          ? Icons.alarm
                          : Icons.warning_amber_rounded,
                      size: 20,
                      color: urgencyTone.onContainer),
                  const SizedBox(width: Spacing.sm),
                  Flexible(
                    child: Text(
                      // U-63: a day with no time "started", it is not late.
                      l[tag == SwapPriorityTag.overdue
                          ? (request.toView().dayStartedWithoutTime(
                                  FamilyTime.now())
                              ? KApp.frozenDayStarted
                              : K.frozenOverdue)
                          : K.frozenUrgent],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: urgencyTone.onContainer,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
      extraAction: widget.offline || _resolved
          ? null
          : _actionRow(context, l,
          request: request,
          isRevert: isRevert,
          iAmTarget: iAmTarget,
          iAmRequester: iAmRequester,
          targetName: targetName,
          actionButton: actionButton),
      children: [
              // F-95: settled since this panel's data was read.
              if (_resolved) ...[
                AppBanner(
                  key: const ValueKey('frozen-resolved'),
                  tone: context.tokens.info,
                  icon: Icons.task_alt,
                  message: l[KApp.frozenAlreadyResolved],
                ),
                const SizedBox(height: Spacing.sm),
              ],
              Text(
                  l.format(
                      K.frozenDay, [l.formatDate(request.scheduleDate)]),
                  style: Theme.of(context).textTheme.bodyMedium),
              // F-95: the day itself — its agenda, note and relatos — read-only.
              if (widget.onViewDay != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const ValueKey('frozen-view-day'),
                    icon: const Icon(Icons.event_note_outlined),
                    label: Text(l[KApp.frozenViewDay]),
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onViewDay!();
                    },
                  ),
                ),
              const SizedBox(height: Spacing.sm),
              // U-28 QA: the request's facts in their own panel. Loose on the
              // sheet, a label on the left and its value on the right had
              // nothing holding the pair together.
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    infoRow(K.frozenRequester, requesterName ?? '—'),
                    infoRow(
                        isRevert ? K.frozenRevertTo : K.frozenProposedParent,
                        proposedName ?? '—'),
                    // U-42 (a U-24 fix that rode along): the wire string is
                    // `HH:mm:ss`; the READER's clock decides how it renders
                    // — `14:30` in PT-BR, `2:30 PM` in English. A hand-made
                    // padLeft was a third copy of the 24 h format, bypassing
                    // `formatTimeString` on the one sheet where the time is
                    // the whole question.
                    if (handoff != null)
                      infoRow(K.frozenProposedTime,
                          l.formatTimeString(request.proposedHandoffTime!)),
                    // F-44: the requester's message travels with the request.
                    if ((request.requestMessage ?? '').isNotEmpty)
                      infoRow(
                          K.frozenRequesterMessage, request.requestMessage!,
                          isMessage: true),
                    if (createdAtLocal != null)
                      infoRow(K.frozenRequestedAt,
                          l.formatDateTime(createdAtLocal)),
                    // F-60: the deadline the reminder promises, on the screen
                    // where the person decides. It is the DAY's clock
                    // (`expiry + 48h`, the F-24 anchor) and never a window
                    // measured from the request — which is what the old
                    // "em 24h" copy described and no request ever had.
                    // U-63: said as a person says it — "sábado, 10/10, à 0h".
                    infoRow(
                        K.frozenAutoApproval,
                        l.formatFamilyDeadline(autoApprovalDeadline(
                            request.scheduleDate,
                            request.proposedHandoffTime))),
                  ],
                ),
              ),
              const SizedBox(height: Spacing.sm),
              if (widget.offline)
                AppBanner(
                    tone: context.tokens.warning,
                    icon: Icons.cloud_off_outlined,
                    message: l[KApp.offlineWriteBlocked]),
              if (iAmTarget && !widget.offline) ...[
                // U-27: the label used to float above the field as its own
                // Text; folded into the field, it is the accessible name too.
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: l[K.frozenNoteLabel],
                        hint: l[K.frozenNotePlaceholder],
                        controller: _approverNote,
                        maxLength: 200,
                        enabled: !_acting,
                      ),
                    ),
                    AppInfoTip(message: l[K.frozenNoteHint]),
                  ],
                ),
              ],
            ],
          );
  }

  /// The sheet's answer, pinned by the frame instead of riding at the end of
  /// the scroll — which is where the owner found it missing.
  Widget _actionRow(
    BuildContext context,
    Localization l, {
    required SwapRequest request,
    required bool isRevert,
    required bool iAmTarget,
    required bool iAmRequester,
    required String? targetName,
    required Widget Function({
      required String actionKey,
      required String labelKey,
      required VoidCallback onPressed,
      bool filled,
      bool destructive,
    }) actionButton,
  }) {
    if (iAmTarget && !isRevert && widget.siblings.isNotEmpty) {
      // F-07 (PR 4b): every child's request of this day, approved in one tap
      // — each one still through its own two-party workflow.
      final all = [request, ...widget.siblings];
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(
            key: const ValueKey('frozen-approve-all'),
            onPressed: _acting
                ? null
                : () => _run('approve-all', K.errApproveFailed, () async {
                      // S-25: each answer is atomic on the server, and one
                      // already settled (approved on a first attempt, or
                      // cancelled meanwhile) is skipped — so a failure half
                      // way can simply be tapped again.
                      for (final r in all) {
                        try {
                          await widget.dataSource.approveSwap(r.id,
                              approvalNote: _note,
                              allProfiles: widget.allProfiles);
                        } on SwapAlreadyAnswered {
                          continue;
                        }
                      }
                      return FrozenDayOutcome.approved;
                    }),
            child: _pendingAction == 'approve-all'
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(l.format(KApp.frozenApproveAll, [all.length])),
          ),
          const SizedBox(height: 8),
          _targetRow(context, l,
              request: request, isRevert: isRevert, actionButton: actionButton),
        ],
      );
    }
    if (iAmTarget) {
      return _targetRow(context, l,
          request: request, isRevert: isRevert, actionButton: actionButton);
    }
    if (iAmRequester) {
      return actionButton(
                  actionKey: 'cancel',
                  labelKey:
                      isRevert ? K.frozenCancelRevert : K.frozenCancelRequest,
                  destructive: true,
                  onPressed: () => _run(
                      'cancel',
                      isRevert ? K.errCancelRevertFailed : K.errCancelFailed,
                      () async {
                        if (isRevert) {
                          await widget.dataSource.cancelRevert(request.id,
                              allProfiles: widget.allProfiles);
                          return FrozenDayOutcome.revertCancelled;
                        }
                        await widget.dataSource.cancelSwap(request.id,
                            allProfiles: widget.allProfiles);
                        return FrozenDayOutcome.cancelled;
                      }),
      );
    }
    return Text(
      l.format(K.frozenObserver, [targetName ?? l[K.calOtherCaregiver]]),
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    );
  }

  /// Approve / reject for the request's target.
  Widget _targetRow(
    BuildContext context,
    Localization l, {
    required SwapRequest request,
    required bool isRevert,
    required Widget Function({
      required String actionKey,
      required String labelKey,
      required VoidCallback onPressed,
      bool filled,
      bool destructive,
    }) actionButton,
  }) {
    return Row(
                  children: [
                    Expanded(
                      child: isRevert
                          ? actionButton(
                              actionKey: 'approve',
                              labelKey: K.frozenConfirmRevert,
                              filled: true,
                              onPressed: () => _run(
                                  'approve',
                                  K.errConfirmRevertFailed,
                                  () async {
                                    await widget.dataSource.approveRevert(
                                        request.id,
                                        approvalNote: _note,
                                        allProfiles: widget.allProfiles);
                                    return FrozenDayOutcome.revertConfirmed;
                                  }),
                            )
                          : actionButton(
                              actionKey: 'approve',
                              labelKey: K.frozenApprove,
                              filled: true,
                              onPressed: () => _run(
                                  'approve',
                                  K.errApproveFailed,
                                  () async {
                                    await widget.dataSource.approveSwap(
                                        request.id,
                                        approvalNote: _note,
                                        allProfiles: widget.allProfiles);
                                    return FrozenDayOutcome.approved;
                                  }),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: actionButton(
                        actionKey: 'reject',
                        labelKey: K.frozenRejectAction,
                        onPressed: () => _run(
                            'reject',
                            isRevert
                                ? K.errRejectRevertFailed
                                : K.errRejectFailed,
                            () async {
                              if (isRevert) {
                                await widget.dataSource.rejectRevert(
                                    request.id,
                                    reason: _note,
                                    allProfiles: widget.allProfiles);
                                return FrozenDayOutcome.revertRejected;
                              }
                              await widget.dataSource.rejectSwap(request.id,
                                  reason: _note,
                                  allProfiles: widget.allProfiles);
                              return FrozenDayOutcome.rejected;
                            }),
                      ),
                    ),
                  ],
                );
  }
}
