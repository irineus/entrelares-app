import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/admin_mode.dart';
import '../services/custody_data_source.dart';
import '../widgets/admin_mode_offer.dart';
import '../widgets/app_l10n.dart';

/// The bulk-edit sheet (F-11/S-09/T-27) — the biggest screen of lote 2,
/// mirroring `Home.razor`'s bulk sheet with the pure rules in
/// `entrelares_core/bulk_rules.dart`. Since lote 3 the save routes each day
/// to the correct path (F-11): an actual-parent change that needs approval
/// opens a SWAP REQUEST (with the per-day F-28 gate skipping, never failing),
/// undoing an approved swap opens a REVERT (F-47 by decision: a batch never
/// restores day observations), and only no-workflow days write directly.
///
/// Pops with the summary string (`BulkSummary` + suffixes) — the caller shows
/// it and reloads, mirroring `FinishBulkSave`.
Future<String?> showBulkSheet({
  required BuildContext context,
  required Set<DateTime> selectedDays,
  required Map<String, CareSchedule> daysByIso,
  required List<Member> activeMembers,
  required DateTime today,
  required CustodyDataSource dataSource,
  required bool adminBypass,
  AdminModeOfferer? adminOffer,
  bool? isPremium,
  PublicSettings settings = PublicSettings.unloaded,
  Iterable<DateTime> frozenDates = const [],
  Member? myProfile,
  List<Member> allProfiles = const [],
}) {
  return showAppSheet<String>(
    context: context,
    builder: (context) => _BulkSheet(
      selectedDays: selectedDays,
      daysByIso: daysByIso,
      activeMembers: activeMembers,
      today: today,
      dataSource: dataSource,
      adminBypass: adminBypass,
      adminOffer: adminOffer,
      isPremium: isPremium,
      settings: settings,
      frozenDates: frozenDates,
      myProfile: myProfile,
      allProfiles: allProfiles,
    ),
  );
}

class _BulkSheet extends StatefulWidget {
  final Set<DateTime> selectedDays;
  final Map<String, CareSchedule> daysByIso;
  final List<Member> activeMembers;
  final DateTime today;
  final CustodyDataSource dataSource;
  final bool adminBypass;

  /// F-67 Part B: non-null only for an admin. With the F-40 inputs, it lets
  /// the sheet ASK where the mode is off: "Limpar dias", and the past days
  /// and assigned planned parents the edit would otherwise leave alone.
  final AdminModeOfferer? adminOffer;
  final bool? isPremium;
  final PublicSettings settings;

  /// F-12: the month's frozen dates — days with an open swap request never
  /// join the bulk write set (wired since lote 3).
  final Iterable<DateTime> frozenDates;

  /// The signed-in member (workflow requester) and the FULL profile roster
  /// (U-13 notification composition).
  final Member? myProfile;
  final List<Member> allProfiles;

  const _BulkSheet({
    required this.selectedDays,
    required this.daysByIso,
    required this.activeMembers,
    required this.today,
    required this.dataSource,
    required this.adminBypass,
    this.adminOffer,
    this.isPremium,
    this.settings = PublicSettings.unloaded,
    required this.frozenDates,
    required this.myProfile,
    required this.allProfiles,
  });

  @override
  State<_BulkSheet> createState() => _BulkSheetState();
}

/// The bulk rules' view of a `care_schedules` row.
BulkDayFields _fields(CareSchedule s) {
  HandoffTime? handoff;
  final wire = s.handoffTime;
  if (wire != null) {
    final parts = wire.split(':');
    final hour = int.tryParse(parts[0]);
    if (hour != null) {
      handoff = (
        hour: hour,
        minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
      );
    }
  }
  return BulkDayFields(
    scheduledParentId: s.scheduledParentId,
    actualParentId: s.actualParentId,
    notes: s.notes,
    handoffTime: handoff,
  );
}

class _BulkSheetState extends State<_BulkSheet> {
  int _scheduledParentId = 0;
  int _actualParentId = 0; // 0 = same as planned (web sentinel)
  late final TextEditingController _notes;
  late final TextEditingController _swapMessage; // F-44
  /// U-37: one value, picked by the platform; null is "no common handoff".
  TimeOfDay? _handoff;
  bool _clearNotes = false;
  bool _clearHandoff = false;
  bool _clearActual = false;

  bool _saving = false;
  bool _showDeleteAllConfirm = false;

  /// F-14 bypass as THIS sheet sees it — turned true by the F-67 offer, so
  /// the selection and the draft survive the answer.
  late bool _bypass = widget.adminBypass;
  AdminModeAction? _offering;
  VoidCallback? _afterOffer;
  bool _showOverwriteConfirm = false;
  bool _overwriteConfirmed = false;
  int _overwriteCount = 0;
  String? _error;
  double _progress = 0;
  String _progressLabel = '';

  CareSchedule? _existingRow(DateTime date) =>
      widget.daysByIso[CareSchedule.isoDate(date)];

  BulkDayFields? _existingFor(DateTime date) {
    final row = _existingRow(date);
    return row == null ? null : _fields(row);
  }

  /// S-09: assigned days in the selection — the bulk choice will not touch
  /// their planned parent for non-admins (the lock hint).
  int get _assignedCount => widget.selectedDays
      .where((d) => (_existingFor(d)?.scheduledParentId ?? 0) != 0)
      .length;

  AdminModeOfferKind _offerKind(AdminModeAction action,
          {Iterable<DateTime> dates = const []}) =>
      widget.adminOffer == null
          ? AdminModeOfferKind.none
          : adminModeOfferFor(
              action: action,
              isAdmin: true,
              adminModeActive: _bypass,
              today: widget.today,
              isPremium: widget.isPremium,
              overrideFreeDays: widget.settings.overrideFreeDays,
              overridePremiumMonths: widget.settings.overridePremiumMonths,
              dates: dates,
            );

  /// F-67 Part B: the mode would change what this edit does — a past day it
  /// would skip is inside the admin's F-40 reach, or an assigned day ahead
  /// would keep its planned parent. A past day beyond reach is not a reason
  /// to ask: the mode would skip it too (the trigger refuses it).
  bool get _offerOverwrite {
    if (widget.adminOffer == null || _bypass) return false;
    final past = [
      for (final d in widget.selectedDays)
        if (isDayInPast(d, widget.today)) d,
    ];
    if (past.isNotEmpty &&
        _offerKind(AdminModeAction.bulkOverwrite, dates: past) ==
            AdminModeOfferKind.offer) {
      return true;
    }
    return widget.selectedDays.any((d) =>
        !isDayInPast(d, widget.today) &&
        (_existingFor(d)?.scheduledParentId ?? 0) != 0);
  }

  void _ask(AdminModeAction action, VoidCallback resume) => setState(() {
        _error = null;
        _offering = action;
        _afterOffer = resume;
      });

  void _acceptOffer() {
    final action = _offering;
    final resume = _afterOffer;
    if (action == null) return;
    widget.adminOffer?.accept(action);
    setState(() {
      _bypass = true;
      _offering = null;
      _afterOffer = null;
    });
    resume?.call();
  }

  void _declineOffer() {
    final action = _offering;
    if (action != null) widget.adminOffer?.decline(action);
    setState(() {
      _offering = null;
      _afterOffer = null;
    });
  }

  @override
  void initState() {
    super.initState();
    // Mirror of OpenBulkSheet: pre-fill with the common values.
    final prefill = bulkPrefill([
      for (final d in widget.selectedDays)
        if (_existingFor(d) != null) _existingFor(d)!,
    ]);
    _scheduledParentId = prefill.scheduledParentId;
    _actualParentId = prefill.actualParentId;
    _notes = TextEditingController(text: prefill.notes ?? '');
    _swapMessage = TextEditingController();
    _handoff = prefill.handoffHour < 0
        ? null
        : TimeOfDay(hour: prefill.handoffHour, minute: prefill.handoffMinute);
  }

  @override
  void dispose() {
    _notes.dispose();
    _swapMessage.dispose();
    super.dispose();
  }

  /// Web parity: `GetCurrentProfileAsync` throws when the profile is missing.
  Member _requireMyProfile() {
    final my = widget.myProfile;
    if (my == null) throw StateError('Perfil do utilizador não encontrado.');
    return my;
  }

  void _step(int done, int total, String label) {
    setState(() {
      _progress = total == 0 ? 0 : (done - 1) / total;
      _progressLabel = label;
    });
  }

  /// T-27: what a day's effective responsible will be AFTER this bulk edit
  /// lands — used for transitions when the previous day is in the selection.
  int _effectiveAfterBulk(DateTime d) {
    final existing = _existingFor(d);
    final actual = bulkProposedActual(
      bulkActualParentId: _actualParentId,
      clearActual: _clearActual,
      existingActualParentId: existing?.actualParentId,
    );
    return actual ??
        bulkDayScheduled(
          overwriteScheduled: _bypass,
          existing: existing,
          bulkScheduledParentId: _scheduledParentId,
        );
  }

  Future<int?> _prevEffective(DateTime date, Set<DateTime> inSelection) async {
    final prev = DateTime(date.year, date.month, date.day - 1);
    if (inSelection.contains(prev)) return _effectiveAfterBulk(prev);
    final loaded = _existingRow(prev);
    if (loaded != null) return loaded.effectiveParentId;
    // Outside the loaded month (the 1st): ask the server, best-effort.
    if (date.day == 1) {
      try {
        return (await widget.dataSource.fetchDay(prev))?.effectiveParentId;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _saveDeletePath(Localization l) async {
    final eligibility = bulkEligibleDays(
      selectedDates: widget.selectedDays,
      today: widget.today,
      adminBypass: _bypass,
      frozenDates: widget.frozenDates,
      existingFor: _existingFor,
      clearScheduledParent: true,
    );
    if (eligibility.eligible.isEmpty) {
      setState(() {
        _saving = false;
        _error = l[K.bulkErrNoEligibleDays];
      });
      return;
    }
    final toDelete = [
      for (final d in eligibility.eligible)
        if (_existingRow(d) case final CareSchedule row) row,
    ];
    var deleted = 0;
    for (final row in toDelete) {
      deleted++;
      _step(deleted, toDelete.length,
          l.format(K.bulkProgressDeleting, [deleted, toDelete.length]));
      await widget.dataSource.deleteDay(row.id);
    }
    if (!mounted) return;
    Navigator.of(context).pop(bulkSummary(l,
        directCount: toDelete.length,
        directSingularKey: K.sumDeletedOne,
        directPluralKey: K.sumDeletedMany,
        skippedCount: eligibility.skipped));
  }

  Future<void> _save({bool clearScheduled = false}) async {
    if (_saving) return;
    final l = AppL10n.of(context).l;
    setState(() {
      _saving = true;
      _error = null;
      _progress = 0;
      _progressLabel = '';
    });

    try {
      if (clearScheduled) {
        await _saveDeletePath(l);
        return;
      }

      final eligibility = bulkEligibleDays(
        selectedDates: widget.selectedDays,
        today: widget.today,
        adminBypass: _bypass,
        frozenDates: widget.frozenDates,
        existingFor: _existingFor,
        clearScheduledParent: false,
      );
      final finalDays = eligibility.eligible;
      final skippedCount = eligibility.skipped;
      if (finalDays.isEmpty) {
        setState(() {
          _saving = false;
          _error = l[K.bulkErrNoEligibleDays];
        });
        return;
      }

      if (_scheduledParentId == 0) {
        setState(() {
          _saving = false;
          _error = l[K.bulkErrPickScheduled];
        });
        return;
      }

      // S-09: only admin mode may rewrite the planned parent of assigned
      // days, and only after an explicit confirmation.
      final overwriteCount = bulkOverwriteCount(
        days: finalDays,
        existingFor: _existingFor,
        bulkScheduledParentId: _scheduledParentId,
      );
      if (_bypass && overwriteCount > 0 && !_overwriteConfirmed) {
        setState(() {
          _saving = false;
          _overwriteCount = overwriteCount;
          _showOverwriteConfirm = true;
        });
        return;
      }
      _overwriteConfirmed = false;

      final inSelection = finalDays.toSet();
      var directCount = 0;
      var swapCount = 0;
      var revertCount = 0;
      var unchangedCount = 0;
      var conflictCount = 0;
      var handoffApplied = 0;
      var handoffCleared = 0;
      var scheduledKept = 0;
      var processed = 0;
      var skipped = skippedCount;

      bool isWorkflowConflict(String raw) =>
          isDayConflict(raw) ||
          raw.contains('swap_requests_one_pending_per_date');

      for (final date in finalDays) {
        processed++;
        _step(processed, finalDays.length,
            l.format(KApp.bulkProgressSaving, [processed, finalDays.length]));

        final existingRow = _existingRow(date);
        final existing = existingRow == null ? null : _fields(existingRow);

        final dayScheduled = bulkDayScheduled(
          overwriteScheduled: _bypass,
          existing: existing,
          bulkScheduledParentId: _scheduledParentId,
        );
        if (dayScheduled != _scheduledParentId) scheduledKept++;

        // The actual parent this bulk edit would end up applying to the day.
        final proposedActual = bulkProposedActual(
          bulkActualParentId: _actualParentId,
          clearActual: _clearActual,
          existingActualParentId: existing?.actualParentId,
        );

        // T-27: like the wizard, a bulk-set handoff lands only on TRANSITION
        // days; the others get null (and the summary says where it landed).
        HandoffTime? proposedHandoff = bulkProposedHandoff(
          bulkHour: _handoff?.hour ?? -1,
          bulkMinute: _handoff?.minute ?? 0,
          clearHandoff: _clearHandoff,
          existing: existing?.handoffTime,
        );
        if (_handoff != null) {
          final effectiveBeingSaved = proposedActual ?? dayScheduled;
          final prevEffective = await _prevEffective(date, inSelection);
          if (!isTransitionDay(prevEffective, effectiveBeingSaved)) {
            proposedHandoff = null;
            handoffCleared++;
          } else {
            handoffApplied++;
          }
        }

        // F-55: with the agenda on the observation is read-only — the batch
        // neither writes nor clears it.
        final notesText =
            widget.settings.childAgendaEnabled ? '' : _notes.text.trim();
        final handoffWire = proposedHandoff == null
            ? null
            : '${proposedHandoff.hour.toString().padLeft(2, '0')}:'
                '${proposedHandoff.minute.toString().padLeft(2, '0')}:00';

        // ── Case 1 — an actual-parent change that needs approval: write the
        //    base schedule (scheduled + notes) and defer the actual change to
        //    a pending swap request, mirroring the single-day editor ──
        if (_actualParentId != 0 &&
            shouldTriggerWorkflow(
              scheduleDate: date,
              currentActualParentId: existing?.actualParentId,
              scheduledParentId: dayScheduled,
              proposedActualParentId: _actualParentId,
              today: widget.today,
            )) {
          // F-28: scenario-C gate per day — a bulk proposing someone ELSE
          // only reaches days where the user is the planned responsible;
          // other days are skipped (not failed).
          final my = widget.myProfile;
          if (my != null &&
              !requesterParticipates(
                requesterId: my.id,
                scheduledParentId: dayScheduled,
                proposedActualParentId: _actualParentId,
              )) {
            skipped++;
            continue;
          }

          final base = CareSchedule(
            id: existingRow?.id ?? 0,
            scheduleDate: date,
            handoffTime: existingRow?.handoffTime,
            scheduledParentId: dayScheduled,
            actualParentId: existingRow?.actualParentId,
            notes: notesText.isNotEmpty
                ? notesText
                : _clearNotes
                    ? null
                    : existingRow?.notes,
            revision: existingRow?.revision ?? 0,
            revisionToken: existingRow?.revisionToken ?? '',
          );
          // T-33: a conflicted day (someone else saved/requested first) is
          // counted and skipped — the rest of the batch proceeds.
          try {
            if (existingRow == null) {
              await widget.dataSource.insertDay(base);
            } else {
              await widget.dataSource.updateDay(base);
            }
            final refreshed = await widget.dataSource.fetchDay(date);
            await widget.dataSource.createSwapRequest(
              schedule: refreshed ?? base,
              proposedActualParentId: _actualParentId,
              proposedHandoffTime: handoffWire,
              requestMessage: _swapMessage.text,
              myProfile: _requireMyProfile(),
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
          continue;
        }

        // ── Case 2 — undoing an already-approved swap needs the revert
        //    workflow (F-47: a batch keeps every day's current observation) ──
        if (shouldRequestRevert(
          scheduleDate: date,
          currentActualParentId: existing?.actualParentId,
          newActualParentId: proposedActual,
          scheduledParentId: dayScheduled,
          today: widget.today,
        )) {
          try {
            await widget.dataSource.requestRevert(
              scheduleDate: date,
              currentActualProfileId: existing!.actualParentId!,
              scheduledParentId: dayScheduled,
              requestMessage: _swapMessage.text,
              myProfile: _requireMyProfile(),
              allProfiles: widget.allProfiles,
            );
            revertCount++;
          } catch (e) {
            if (isWorkflowConflict(e.toString())) {
              conflictCount++;
            } else {
              rethrow;
            }
          }
          continue;
        }

        // ── Case 3 — a plain, non-workflow update: apply every field ──
        final proposed = bulkComposeDay(
          existing: existing,
          dayScheduled: dayScheduled,
          bulkActualParentId: _actualParentId,
          clearActual: _clearActual,
          bulkNotes: notesText.isEmpty ? null : notesText,
          clearNotes: _clearNotes && !widget.settings.childAgendaEnabled,
          bulkHour: _handoff?.hour ?? -1,
          clearHandoff: _clearHandoff,
          proposedHandoff: proposedHandoff,
        );

        if (existing != null && bulkDayIsNoOp(existing, proposed)) {
          unchangedCount++;
          continue;
        }

        final rowHandoffWire = proposed.handoffTime == null
            ? null
            : '${proposed.handoffTime!.hour.toString().padLeft(2, '0')}:'
                '${proposed.handoffTime!.minute.toString().padLeft(2, '0')}:00';
        final row = CareSchedule(
          id: existingRow?.id ?? 0,
          scheduleDate: date,
          handoffTime: rowHandoffWire,
          scheduledParentId: proposed.scheduledParentId,
          actualParentId: proposed.actualParentId,
          notes: proposed.notes,
          revision: existingRow?.revision ?? 0,
          revisionToken: existingRow?.revisionToken ?? '',
        );
        try {
          if (existingRow == null) {
            await widget.dataSource.insertDay(row);
          } else {
            await widget.dataSource.updateDay(row);
          }
          directCount++;
        } catch (e) {
          // T-33: a conflicted day is counted and skipped — the rest of the
          // batch proceeds; the reload shows the winners' versions.
          if (isWorkflowConflict(e.toString())) {
            conflictCount++;
          } else {
            rethrow;
          }
        }
      }

      var summary = bulkSummary(l,
          directCount: directCount,
          directSingularKey: K.sumUpdatedOne,
          directPluralKey: K.sumUpdatedMany,
          swapCount: swapCount,
          revertCount: revertCount,
          unchangedCount: unchangedCount,
          skippedCount: skipped);
      if (conflictCount > 0) {
        summary += l.format(
            conflictCount == 1
                ? K.bulkConflictSuffixOne
                : K.bulkConflictSuffixMany,
            [conflictCount]);
      }
      if (_handoff != null && handoffCleared > 0) {
        summary += l.format(
            K.bulkHandoffSuffix, [handoffApplied, handoffApplied + handoffCleared]);
      }
      if (scheduledKept > 0) {
        summary += l.format(
            scheduledKept == 1 ? K.bulkKeptSuffixOne : K.bulkKeptSuffixMany,
            [scheduledKept]);
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
    final count = widget.selectedDays.length;
    final fieldsEnabled = _scheduledParentId != 0 && !_saving;
    // U-28 QA: same frame as every other sheet — capped height so a strip of
    // calendar stays visible and tappable, and the action row pinned rather
    // than sitting at the end of a long form.
    return AppSheetFrame(
      title: l.format(count == 1 ? K.bulkTitleOne : K.bulkTitleMany, [count]),
      // U-38: the failure pinned under the title and the question in the
      // action row's place — the batch is saved from the pinned row, and both
      // used to appear at the end of this long form.
      error: _error,
      confirmation: _offering != null
          ? AdminModeOfferConfirmation(
              action: _offering!,
              onActivate: _acceptOffer,
              onCancel: _declineOffer,
            )
          : _confirmation(l),
      primaryLabel: l[K.commonSave],
      onPrimary: _scheduledParentId == 0 ? null : _save,
      secondaryLabel: l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      busy: _saving,
      // U-38: "Limpar dias" left the planned parent's label row, where it was
      // a small red text button beside a dropdown, for the frame's one
      // destructive slot. Clearing assigned days stays admin-only (S-09).
      extraAction: !_bypass &&
              _offerKind(AdminModeAction.bulkClearDays) !=
                  AdminModeOfferKind.offer
          ? null
          : AppSheetDangerAction(
              key: const Key('bulkClearDays'),
              label: l[K.bulkClearDaysAction],
              onPressed: _saving
                  ? null
                  : _bypass
                      ? () => setState(() => _showDeleteAllConfirm = true)
                      // F-67: the mode first, then the sheet's own
                      // "apagar N dias?" — activating never deletes.
                      : () => _ask(AdminModeAction.bulkClearDays,
                          () => setState(() => _showDeleteAllConfirm = true)),
            ),
      children: [
                // F-67 Part B: what the edit will leave alone without the
                // mode, said BEFORE the save — the summary toast used to be
                // the first place an admin learned the past days were
                // skipped.
                if (_offerOverwrite) ...[
                  AppBanner(
                    key: const Key('bulkAdminOffer'),
                    tone: context.tokens.info,
                    icon: Icons.shield_outlined,
                    message: l[KApp.adminOfferBulkBanner],
                    actionLabel: l[K.navAdminEnter],
                    onAction: _saving
                        ? null
                        : () => _ask(AdminModeAction.bulkOverwrite, () {}),
                  ),
                  const SizedBox(height: Spacing.sm),
                ],
                // U-29: this sheet had missed the U-28 QA pass — bare
                // underline `DropdownButton`s, loose labels and no grouping,
                // exactly what the day sheet and the wizard were converted
                // away from. Same conventions now: one AppCard per question,
                // AppFieldLabel (the "Limpar" toggles ride as trailing),
                // and bordered form fields.
                //
                // ── Planned parent ──
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppFieldLabel(l[K.editorScheduledParent],
                          info: l[K.editorScheduledParentHint]),
                      DropdownButtonFormField<int>(
                        key: const Key('bulkScheduled'),
                        isExpanded: true,
                        decoration: const InputDecoration(),
                        initialValue: _scheduledParentId,
                        items: [
                          DropdownMenuItem(
                              value: 0,
                              child: Text(l[K.editorSelectPlaceholder])),
                          for (final m in widget.activeMembers)
                            DropdownMenuItem(
                                value: m.id, child: Text(m.fullName)),
                        ],
                        onChanged: _saving
                            ? null
                            : (v) =>
                                setState(() => _scheduledParentId = v ?? 0),
                      ),
                      if (!_bypass && _assignedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.xs),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.lock_outline,
                                  size: 16, color: context.tokens.textMuted),
                              const SizedBox(width: Spacing.xs),
                              Expanded(
                                child: Text(
                                  l.format(
                                      _assignedCount == 1
                                          ? K.bulkKeptScheduledOne
                                          : K.bulkKeptScheduledMany,
                                      [_assignedCount]),
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),

                // ── Actual parent + Limpar (lote 3: workflow routing) ──
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: AppFieldLabel(l[K.editorActualParent],
                                  info: l[K.editorActualParentHint])),
                          _clearCheckbox(
                            l,
                            value: _clearActual,
                            unavailable: _actualParentId != 0,
                            enabled: fieldsEnabled,
                            onChanged: (v) =>
                                setState(() => _clearActual = v),
                          ),
                        ],
                      ),
                      DropdownButtonFormField<int>(
                        key: const Key('bulkActual'),
                        isExpanded: true,
                        decoration: const InputDecoration(),
                        initialValue: _actualParentId,
                        items: [
                          DropdownMenuItem(
                              value: 0,
                              child: Text(l[K.editorSameAsPlanned])),
                          for (final m in widget.activeMembers)
                            DropdownMenuItem(
                                value: m.id, child: Text(m.fullName)),
                        ],
                        onChanged: !fieldsEnabled
                            ? null
                            : (v) => setState(() {
                                  _actualParentId = v ?? 0;
                                  if (_actualParentId != 0) {
                                    _clearActual = false;
                                  }
                                }),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Spacing.sm),

                // ── Handoff time and the day note, one card (day-sheet
                //    grouping) ──
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // U-37: one field, the platform's picker; *Limpar*
                      // keeps its meaning ("clear the time on every selected
                      // day") and rides the label row, where it already was.
                      AppTimeField(
                        fieldKey: const Key('bulkHandoff'),
                        label: l[K.editorHandoffTime],
                        trailing: _clearCheckbox(
                          l,
                          value: _clearHandoff,
                          unavailable: _handoff != null,
                          enabled: fieldsEnabled,
                          onChanged: (v) => setState(() => _clearHandoff = v),
                        ),
                        value: _handoff,
                        enabled: fieldsEnabled,
                        emptyText: l[K.editorHandoffEmpty],
                        clearLabel: l[K.editorHandoffClear],
                        formatValue: (t) =>
                            l.formatTime(DateTime(2000, 1, 1, t.hour, t.minute)),
                        onChanged: (t) => setState(() {
                          _handoff = t;
                          if (t != null) _clearHandoff = false;
                        }),
                      ),
                      const SizedBox(height: Spacing.md),

                      // ── Day note + Limpar ──
                      //
                      // U-29 (QA over the owner's screenshots): the loose
                      // section label above the field REPEATED the field's
                      // own integrated label — the checkbox rides beside the
                      // field instead, the way the day sheet parks its ⓘ.
                      // F-55: with the agenda on, the observation is read-only.
                      if (!widget.settings.childAgendaEnabled)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: AppTextField(
                              label: l[K.editorDayNote],
                              hint: l[K.bulkNotePlaceholder],
                              controller: _notes,
                              maxLength: 100,
                              enabled: fieldsEnabled,
                              onChanged: (v) {
                                if (v.isNotEmpty && _clearNotes) {
                                  setState(() => _clearNotes = false);
                                }
                              },
                            ),
                          ),
                          _clearCheckbox(
                            l,
                            value: _clearNotes,
                            unavailable: _notes.text.isNotEmpty,
                            enabled: fieldsEnabled,
                            onChanged: (v) =>
                                setState(() => _clearNotes = v),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── F-44: shown only when the batch can open swap/revert
                //    requests; one message rides every request it creates ──
                if (_actualParentId != 0 || _clearActual) ...[
                  const SizedBox(height: Spacing.sm),
                  AppCard(
                    child: AppTextField(
                      label:
                          '${l[K.editorMessageLabel]} ${l[K.bulkMessageHint]}',
                      hint: l[K.bulkMessagePlaceholder],
                      controller: _swapMessage,
                      maxLength: 200,
                      enabled: fieldsEnabled,
                    ),
                  ),
                ],
                const SizedBox(height: Spacing.md),

                if (_saving) ...[
                  LinearProgressIndicator(value: _progress),
                  const SizedBox(height: 4),
                  Text(_progressLabel,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                ],
      ],
    );
  }

  /// U-38: the two questions this sheet asks before it writes — clearing the
  /// selected days, and overwriting planned parents (S-09).
  Widget? _confirmation(Localization l) {
    if (_showDeleteAllConfirm) {
      return AppSheetConfirmation.destructive(
        message: l[K.bulkDeleteAllWarning],
        yesLabel: l[K.bulkYesDelete],
        busy: _saving,
        onYes: () {
          setState(() => _showDeleteAllConfirm = false);
          _save(clearScheduled: true);
        },
        noLabel: l[K.editorNoGoBack],
        onNo: () => setState(() => _showDeleteAllConfirm = false),
      );
    }
    if (_showOverwriteConfirm) {
      return AppSheetConfirmation.destructive(
        message: l.format(
            _overwriteCount == 1
                ? K.bulkOverwriteWarningOne
                : K.bulkOverwriteWarningMany,
            [_overwriteCount]),
        yesLabel: l[K.editorYesChange],
        busy: _saving,
        onYes: () {
          setState(() {
            _showOverwriteConfirm = false;
            _overwriteConfirmed = true;
          });
          _save();
        },
        noLabel: l[K.editorNoGoBack],
        onNo: () => setState(() => _showOverwriteConfirm = false),
      );
    }
    return null;
  }

  /// U-38: the shared [AppClearToggle]; `unavailable` is the field already
  /// holding a value, which a clear would contradict.
  Widget _clearCheckbox(Localization l,
      {required bool value,
      required bool unavailable,
      required bool enabled,
      required ValueChanged<bool> onChanged}) {
    return AppClearToggle(
      label: l[K.bulkClear],
      value: value,
      onChanged: unavailable || !enabled ? null : onChanged,
    );
  }
}
