import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/custody_data_source.dart';
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
  int _handoffHour = -1;
  int _handoffMinute = 0;
  bool _clearNotes = false;
  bool _clearHandoff = false;
  bool _clearActual = false;

  bool _saving = false;
  bool _showDeleteAllConfirm = false;
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
  /// their planned parent for non-admins (🔒 hint).
  int get _assignedCount => widget.selectedDays
      .where((d) => (_existingFor(d)?.scheduledParentId ?? 0) != 0)
      .length;

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
    _handoffHour = prefill.handoffHour;
    _handoffMinute = prefill.handoffMinute;
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
          overwriteScheduled: widget.adminBypass,
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
      adminBypass: widget.adminBypass,
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
        adminBypass: widget.adminBypass,
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
      if (widget.adminBypass && overwriteCount > 0 && !_overwriteConfirmed) {
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
          overwriteScheduled: widget.adminBypass,
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
          bulkHour: _handoffHour,
          bulkMinute: _handoffMinute,
          clearHandoff: _clearHandoff,
          existing: existing?.handoffTime,
        );
        if (_handoffHour >= 0) {
          final effectiveBeingSaved = proposedActual ?? dayScheduled;
          final prevEffective = await _prevEffective(date, inSelection);
          if (!isTransitionDay(prevEffective, effectiveBeingSaved)) {
            proposedHandoff = null;
            handoffCleared++;
          } else {
            handoffApplied++;
          }
        }

        final notesText = _notes.text.trim();
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
          clearNotes: _clearNotes,
          bulkHour: _handoffHour,
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
      if (_handoffHour >= 0 && handoffCleared > 0) {
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
    final confirming = _showDeleteAllConfirm || _showOverwriteConfirm;
    return AppSheetFrame(
      title: l.format(count == 1 ? K.bulkTitleOne : K.bulkTitleMany, [count]),
      primaryLabel: confirming ? null : l[K.commonSave],
      onPrimary: _scheduledParentId == 0 ? null : _save,
      secondaryLabel: confirming ? null : l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      busy: _saving,
      children: [
              if (_showDeleteAllConfirm)
                _confirmBox(
                  l[K.bulkDeleteAllWarning],
                  yesLabel: l[K.bulkYesDelete],
                  onYes: () {
                    setState(() => _showDeleteAllConfirm = false);
                    _save(clearScheduled: true);
                  },
                  onNo: () => setState(() => _showDeleteAllConfirm = false),
                )
              else ...[
                // U-29: this sheet had missed the U-28 QA pass — bare
                // underline `DropdownButton`s, loose labels and no grouping,
                // exactly what the day sheet and the wizard were converted
                // away from. Same conventions now: one AppCard per question,
                // AppFieldLabel (the "Limpar" checkboxes ride as trailing),
                // and bordered form fields.
                //
                // ── Planned parent ──
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: AppFieldLabel(
                                  l[K.editorScheduledParent],
                                  info:
                                      l[K.editorScheduledParentHint])),
                          // QA: clearing assigned days is admin-only (S-09).
                          if (widget.adminBypass)
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(
                                      () => _showDeleteAllConfirm = true),
                              style: TextButton.styleFrom(
                                  foregroundColor:
                                      Theme.of(context).colorScheme.error,
                                  visualDensity: VisualDensity.compact),
                              child: Text(l[K.bulkClearDaysAction]),
                            ),
                        ],
                      ),
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
                      if (!widget.adminBypass && _assignedCount > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: Spacing.xs),
                          child: Text(
                            l.format(
                                _assignedCount == 1
                                    ? K.bulkKeptScheduledOne
                                    : K.bulkKeptScheduledMany,
                                [_assignedCount]),
                            style: Theme.of(context).textTheme.bodySmall,
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
                      Row(
                        children: [
                          Expanded(
                              child: AppFieldLabel(l[K.editorHandoffTime])),
                          _clearCheckbox(
                            l,
                            value: _clearHandoff,
                            unavailable: _handoffHour >= 0,
                            enabled: fieldsEnabled,
                            onChanged: (v) =>
                                setState(() => _clearHandoff = v),
                          ),
                        ],
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              key: const Key('bulkHandoffHour'),
                              decoration: InputDecoration(
                                  labelText: l[K.editorHourLabel]),
                              initialValue: _handoffHour,
                              items: [
                                const DropdownMenuItem(
                                    value: -1, child: Text('--')),
                                for (var h = 0; h < 24; h++)
                                  DropdownMenuItem(
                                      value: h,
                                      child:
                                          Text(h.toString().padLeft(2, '0'))),
                              ],
                              onChanged: !fieldsEnabled
                                  ? null
                                  : (v) => setState(() {
                                        _handoffHour = v ?? -1;
                                        if (_handoffHour >= 0) {
                                          _clearHandoff = false;
                                        }
                                      }),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: Spacing.sm, vertical: 16),
                            child: Text(':'),
                          ),
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              key: const Key('bulkHandoffMinute'),
                              decoration: InputDecoration(
                                  labelText: l[K.editorMinuteLabel]),
                              initialValue: _handoffMinute,
                              items: [
                                for (var m = 0; m < 60; m++)
                                  DropdownMenuItem(
                                      value: m,
                                      child:
                                          Text(m.toString().padLeft(2, '0'))),
                              ],
                              onChanged: !fieldsEnabled || _handoffHour < 0
                                  ? null
                                  : (v) =>
                                      setState(() => _handoffMinute = v ?? 0),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Spacing.md),

                      // ── Day note + Limpar ──
                      //
                      // U-29 (QA over the owner's screenshots): the loose
                      // section label above the field REPEATED the field's
                      // own integrated label — the checkbox rides beside the
                      // field instead, the way the day sheet parks its ⓘ.
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
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('⚠️ $_error',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                if (_showOverwriteConfirm)
                  _confirmBox(
                    l.format(
                        _overwriteCount == 1
                            ? K.bulkOverwriteWarningOne
                            : K.bulkOverwriteWarningMany,
                        [_overwriteCount]),
                    yesLabel: l[K.editorYesChange],
                    onYes: () {
                      setState(() {
                        _showOverwriteConfirm = false;
                        _overwriteConfirmed = true;
                      });
                      _save();
                    },
                    onNo: () =>
                        setState(() => _showOverwriteConfirm = false),
                  )
                ,
              ],
      ],
    );
  }

  Widget _clearCheckbox(Localization l,
      {required bool value,
      required bool unavailable,
      required bool enabled,
      required ValueChanged<bool> onChanged}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: unavailable || !enabled
              ? null
              : (v) => onChanged(v ?? false),
          visualDensity: VisualDensity.compact,
        ),
        Text(l[K.bulkClear], style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Widget _confirmBox(String warning,
      {required String yesLabel,
      required VoidCallback onYes,
      required VoidCallback onNo}) {
    final l = AppL10n.of(context).l;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Spacing.sm + Spacing.xs),
      decoration: BoxDecoration(
        color: context.tokens.danger.container,
        border: Border.all(color: context.tokens.danger.border),
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(warning,
              style: TextStyle(
                  fontSize: 13, color: context.tokens.danger.onContainer)),
          const SizedBox(height: Spacing.sm),
          AppActionPair(
            primaryLabel: yesLabel,
            destructive: true,
            busy: _saving,
            onPrimary: onYes,
            secondaryLabel: l[K.editorNoGoBack],
            onSecondary: onNo,
          ),
        ],
      ),
    );
  }
}
