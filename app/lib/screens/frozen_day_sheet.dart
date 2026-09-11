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
}) {
  return showAppSheet<FrozenDayOutcome>(
    context: context,
    builder: (context) => _FrozenDaySheet(
      request: request,
      allProfiles: allProfiles,
      ownProfileId: ownProfileId,
      dataSource: dataSource,
    ),
  );
}

class _FrozenDaySheet extends StatefulWidget {
  final SwapRequest request;
  final List<Member> allProfiles;
  final int? ownProfileId;
  final CustodyDataSource dataSource;

  const _FrozenDaySheet({
    required this.request,
    required this.allProfiles,
    required this.ownProfileId,
    required this.dataSource,
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

  @override
  void initState() {
    super.initState();
    _approverNote = TextEditingController();
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
        _error = isSessionExpired(e.toString())
            ? sessionExpiredMessage(l)
            : l.format(errorKey, [e.toString()]);
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
    final tag = request.toView().priorityTag(DateTime.now());

    final requesterName = _nameOf(request.requestingProfileId);
    final targetName = _nameOf(request.targetProfileId);
    final proposedName = _nameOf(request.proposedActualParentId);

    final headerIcon = switch (tag) {
      SwapPriorityTag.overdue => '⏰',
      SwapPriorityTag.urgent => '⚠️',
      SwapPriorityTag.none => isRevert ? '↩️' : '⏳',
    };

    final handoff = parseTimeOfDay(request.proposedHandoffTime);
    final createdAtLocal = request.createdAt == null
        ? null
        : DateTime.tryParse(request.createdAt!)?.toLocal();

    Widget infoRow(String labelKey, String value, {bool isMessage = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                  child: Text(l[labelKey],
                      style: Theme.of(context).textTheme.bodySmall)),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.end,
                    style: isMessage
                        ? Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontStyle: FontStyle.italic)
                        : Theme.of(context).textTheme.bodyMedium),
              ),
            ],
          ),
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
        return OutlinedButton(
          onPressed: _acting ? null : onPressed,
          style: OutlinedButton.styleFrom(
              foregroundColor: context.tokens.danger.onContainer),
          child: child,
        );
      }
      return OutlinedButton(onPressed: _acting ? null : onPressed, child: child);
    }

    final urgencyTone = tag == SwapPriorityTag.overdue
        ? context.tokens.danger
        : context.tokens.warning;

    return AppSheetFrame(
      // The emoji rides in the title string, which is where this app keeps
      // emoji: inside the sentences it writes, never as structural chrome.
      title: '$headerIcon '
          '${l[isRevert ? K.frozenRevertTitle : K.frozenSwapTitle]}',
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
              child: Text(
                l[tag == SwapPriorityTag.overdue
                    ? K.frozenOverdue
                    : K.frozenUrgent],
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: urgencyTone.onContainer,
                    fontWeight: FontWeight.w700),
              ),
            ),
      extraAction: _actionRow(context, l,
          request: request,
          isRevert: isRevert,
          iAmTarget: iAmTarget,
          iAmRequester: iAmRequester,
          targetName: targetName,
          actionButton: actionButton),
      children: [
              Text(
                  l.format(
                      K.frozenDay, [l.formatDate(request.scheduleDate)]),
                  style: Theme.of(context).textTheme.bodyMedium),
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
                    if (handoff != null)
                      infoRow(
                          K.frozenProposedTime,
                          '${handoff.hour.toString().padLeft(2, '0')}:'
                          '${handoff.minute.toString().padLeft(2, '0')}'),
                    // F-44: the requester's message travels with the request.
                    if ((request.requestMessage ?? '').isNotEmpty)
                      infoRow(
                          K.frozenRequesterMessage, request.requestMessage!,
                          isMessage: true),
                    if (createdAtLocal != null)
                      infoRow(K.frozenRequestedAt,
                          l.formatDateTime(createdAtLocal)),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: Spacing.sm),
                Text('⚠️ $_error',
                    style: TextStyle(
                        color: context.tokens.danger.onContainer)),
              ],
              const SizedBox(height: Spacing.sm),
              if (iAmTarget) ...[
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
    if (iAmTarget) {
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
}
