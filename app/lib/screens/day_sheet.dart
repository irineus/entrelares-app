import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/custody_data_source.dart';
import '../widgets/app_l10n.dart';

/// What the sheet did — the caller picks the toast, mirroring the web's four
/// success paths (`toastSaved` · `toastDayCleared` · `toastSwapRequested` ·
/// `toastRevertRequested`).
enum DaySheetOutcome { saved, cleared, swapRequested, revertRequested }

/// The day sheet — a native modal bottom sheet (owner directive: use the
/// platform where it improves on the web's inline panel). Since lote 2 this is
/// the FULL editor of `Home.razor`: planned parent (S-09 locked on assigned
/// days), day note, handoff time (T-27 transition-only), clear day
/// (admin-only) and the F-12/F-13/F-14 guard mirrors, including the F-40
/// tier-aware retroactive reach shown proactively (decision 19/08/2026).
///
/// Since lote 3 the save mirrors `SaveChanges`' full routing: an actual-parent
/// change on today/future opens a SWAP REQUEST (F-28 gate via the field's own
/// filter), undoing an approved swap opens a REVERT (with the F-47 observation
/// question when the answer changes something) — the direct write only happens
/// when no workflow applies. The database enforces all of it regardless.
Future<DaySheetOutcome?> showDaySheet({
  required BuildContext context,
  required DateTime date,
  required CareSchedule? day,
  required CareSchedule? previousDay,
  required List<Member> members,
  required List<MemberView> memberViews,
  required DateTime today,
  required CustodyDataSource dataSource,
  bool adminBypass = false,
  int? ownProfileId,
  Member? myProfile,
  List<Member> allProfiles = const [],
  bool? isPremium,
  PublicSettings settings = PublicSettings.unloaded,
  Iterable<DateTime> frozenDates = const [],
}) {
  return showAppSheet<DaySheetOutcome>(
    context: context,
    builder: (context) => _DaySheet(
      date: date,
      day: day,
      previousDay: previousDay,
      members: members,
      memberViews: memberViews,
      today: today,
      dataSource: dataSource,
      adminBypass: adminBypass,
      ownProfileId: ownProfileId,
      myProfile: myProfile,
      allProfiles: allProfiles,
      isPremium: isPremium,
      settings: settings,
      frozenDates: frozenDates,
    ),
  );
}

class _DaySheet extends StatefulWidget {
  final DateTime date;
  final CareSchedule? day;
  final CareSchedule? previousDay;
  final List<Member> members;
  final List<MemberView> memberViews;
  final DateTime today;
  final CustodyDataSource dataSource;
  final bool adminBypass;
  final int? ownProfileId;

  /// The signed-in member and the FULL profile roster (inactive included) —
  /// the workflow mutations need them for requester identity and the U-13
  /// notification composition.
  final Member? myProfile;
  final List<Member> allProfiles;

  /// null = entitlement unknown (read failed): the proactive F-40 gate is
  /// skipped and the trigger's own refusal propagates — never a wrongful
  /// client-side block.
  final bool? isPremium;
  final PublicSettings settings;
  final Iterable<DateTime> frozenDates;

  const _DaySheet({
    required this.date,
    required this.day,
    required this.previousDay,
    required this.members,
    required this.memberViews,
    required this.today,
    required this.dataSource,
    required this.adminBypass,
    required this.ownProfileId,
    required this.myProfile,
    required this.allProfiles,
    required this.isPremium,
    required this.settings,
    required this.frozenDates,
  });

  @override
  State<_DaySheet> createState() => _DaySheetState();
}

class _DaySheetState extends State<_DaySheet> {
  int? _scheduledParentId;
  int _actualParentId = 0; // 0 = same as planned (web sentinel)
  late final TextEditingController _notes;
  late final TextEditingController _swapMessage; // F-44
  /// U-37: one value, picked by the platform; null is "no handoff time".
  TimeOfDay? _handoff;
  bool _saving = false;
  bool _deleting = false;
  String? _error;
  bool _showAdminConfirm = false;
  bool _adminConfirmed = false;

  // F-47: the observation question. The answer belongs to ONE save attempt;
  // dismissing is not an answer — the next attempt asks again.
  bool _showRevertConfirm = false;
  bool? _revertNotesChoice;
  String? _revertSnapshotText;
  String? _revertCurrentText;

  /// T-27: the previous day's effective responsible. Resolved from the loaded
  /// month; on the 1st the previous month's last day is fetched (mirror of
  /// the web's GetEffectiveParentForDateAsync).
  late Future<int?> _prevEffective;

  bool get _isPast => isDayInPast(widget.date, widget.today);
  bool get _isFrozen => isDayFrozen(widget.date, widget.frozenDates);

  DayAssignment? get _assignment {
    final day = widget.day;
    return day == null
        ? null
        : DayAssignment(
            scheduledParentId: day.scheduledParentId,
            actualParentId: day.actualParentId,
          );
  }

  bool get _saveBlocked => isSaveDayBlocked(
      adminBypass: widget.adminBypass, isPast: _isPast, isFrozen: _isFrozen);

  /// F-40 proactive mirror: the admin override cannot reach this far back.
  bool get _beyondRetroReach =>
      widget.adminBypass &&
      _isPast &&
      widget.isPremium != null &&
      !isWithinAdminRetroactiveReach(
        date: widget.date,
        today: widget.today,
        isPremium: widget.isPremium!,
        overrideFreeDays: widget.settings.overrideFreeDays,
        overridePremiumMonths: widget.settings.overridePremiumMonths,
      );

  /// S-09: the planned parent of an assigned day is locked for non-admins.
  bool get _scheduledLocked =>
      widget.day != null && widget.day!.scheduledParentId != 0 &&
      !widget.adminBypass;

  /// F-44: mirrors the save's workflow detection so the message field only
  /// appears when saving will open a swap or revert request (mirror of
  /// `EditorWillOpenWorkflow`).
  bool get _willOpenWorkflow {
    final scheduled = _scheduledParentId;
    if (scheduled == null || scheduled == 0 || _saveBlocked) return false;
    // F-56: no counterpart, no workflow — the actual-parent controls are not
    // even rendered on that day.
    if (_swapUnavailableForPending) return false;
    final currentActual = widget.day?.actualParentId;
    final proposed = _actualParentId == 0 ? null : _actualParentId;
    if (shouldRequestRevert(
      scheduleDate: widget.date,
      currentActualParentId: currentActual,
      newActualParentId: proposed,
      scheduledParentId: scheduled,
      today: widget.today,
    )) {
      return true;
    }
    return proposed != null &&
        shouldTriggerWorkflow(
          scheduleDate: widget.date,
          currentActualParentId: currentActual,
          scheduledParentId: scheduled,
          proposedActualParentId: proposed,
          today: widget.today,
        );
  }

  @override
  void initState() {
    super.initState();
    final day = widget.day;
    _scheduledParentId =
        (day != null && day.scheduledParentId != 0) ? day.scheduledParentId : null;
    _actualParentId = day?.actualParentId ?? 0;
    _notes = TextEditingController(text: day?.notes ?? '');
    _swapMessage = TextEditingController();
    final handoff = parseTimeOfDay(day?.handoffTime);
    if (handoff != null) {
      _handoff = TimeOfDay(hour: handoff.hour, minute: handoff.minute);
    }
    final previous = widget.previousDay;
    if (previous != null) {
      _prevEffective = Future.value(previous.effectiveParentId);
    } else if (widget.date.day == 1) {
      // The previous month is not loaded — ask the server, best-effort (a
      // failed read behaves like "no previous day": transition, T-27 keeps
      // the time and the T-45 DB rule remains the enforcement).
      _prevEffective = widget.dataSource
          .fetchDay(widget.date.subtract(const Duration(days: 1)))
          .then((s) => s?.effectiveParentId)
          .catchError((_) => null);
    } else {
      _prevEffective = Future.value(null);
    }
  }

  @override
  void dispose() {
    _notes.dispose();
    _swapMessage.dispose();
    super.dispose();
  }

  int get _effectiveBeingSaved =>
      _actualParentId != 0 ? _actualParentId : (_scheduledParentId ?? 0);

  Future<void> _save() async {
    final scheduled = _scheduledParentId;
    if (scheduled == null || _saving || _deleting) return;
    final l = AppL10n.of(context).l;
    if (_saveBlocked) {
      // Defensive mirror of SaveChanges — the button is disabled anyway.
      setState(() =>
          _error = l[_isPast ? K.errPastDay : K.errFrozenDay]);
      return;
    }

    // S-09: rewriting the planned parent of an assigned day asks first.
    if (needsAdminScheduleChangeConfirm(
      existingScheduledParentId: widget.day?.scheduledParentId,
      editingScheduledParentId: scheduled,
      alreadyConfirmed: _adminConfirmed,
    )) {
      setState(() => _showAdminConfirm = true);
      return;
    }
    _adminConfirmed = false;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // T-27: a handoff time on a non-transition day is meaningless — clear it
      // (the editor showed the hint upfront). T-45 made this a DB rule too;
      // clearing here keeps the saved value equal to what the user was warned
      // about, instead of letting the server silently rewrite it.
      String? handoffWire;
      final handoff = _handoff;
      if (handoff != null) {
        final prev = await _prevEffective;
        if (isTransitionDay(prev, _effectiveBeingSaved)) {
          handoffWire =
              '${handoff.hour.toString().padLeft(2, '0')}:'
              '${handoff.minute.toString().padLeft(2, '0')}:00';
        }
      }

      final notesText = _notes.text.trim();
      final existing = widget.day;
      final currentActual = existing?.actualParentId;
      final proposed = _actualParentId == 0 ? null : _actualParentId;

      // ── Revert branch: undoing an approved swap goes through approval ──
      if (shouldRequestRevert(
        scheduleDate: widget.date,
        currentActualParentId: currentActual,
        newActualParentId: proposed,
        scheduledParentId: scheduled,
        today: widget.today,
      )) {
        // F-47: the restore replays the pre-swap snapshot, observation
        // included. Ask before sending — but only when the answer would
        // change something, and only once per save attempt.
        if (_revertNotesChoice == null && await _shouldAskRevertNotes()) {
          if (mounted) {
            setState(() {
              _saving = false;
              _showRevertConfirm = true;
            });
          }
          return;
        }
        await widget.dataSource.requestRevert(
          scheduleDate: widget.date,
          currentActualProfileId: currentActual!,
          scheduledParentId: scheduled,
          requestMessage: _swapMessage.text,
          restoreNotes: _revertNotesChoice ?? false,
          myProfile: _requireMyProfile(),
          allProfiles: widget.allProfiles,
        );
        if (mounted) {
          Navigator.of(context).pop(DaySheetOutcome.revertRequested);
        }
        return;
      }

      // ── Swap branch: an actual-parent change that needs approval ──
      if (proposed != null &&
          shouldTriggerWorkflow(
            scheduleDate: widget.date,
            currentActualParentId: currentActual,
            scheduledParentId: scheduled,
            proposedActualParentId: proposed,
            today: widget.today,
          )) {
        // Ensure the base row exists BEFORE the request — scheduled parent +
        // note only; the actual change waits for the approval (web parity).
        final base = CareSchedule(
          id: existing?.id ?? 0,
          scheduleDate: widget.date,
          handoffTime: existing?.handoffTime,
          scheduledParentId: scheduled,
          actualParentId: existing?.actualParentId,
          notes: notesText.isEmpty ? null : notesText,
          revision: existing?.revision ?? 0,
          revisionToken: existing?.revisionToken ?? '',
        );
        if (existing == null) {
          await widget.dataSource.insertDay(base);
        } else {
          await widget.dataSource.updateDay(base);
        }
        // Reload to get the id (and fresh tokens) if it was just inserted.
        final refreshed = await widget.dataSource.fetchDay(widget.date);
        await widget.dataSource.createSwapRequest(
          schedule: refreshed ?? base,
          proposedActualParentId: proposed,
          proposedHandoffTime: handoffWire,
          requestMessage: _swapMessage.text,
          myProfile: _requireMyProfile(),
          allProfiles: widget.allProfiles,
        );
        if (mounted) {
          Navigator.of(context).pop(DaySheetOutcome.swapRequested);
        }
        return;
      }

      // ── Standard save ──
      final row = CareSchedule(
        id: existing?.id ?? 0,
        scheduleDate: widget.date,
        handoffTime: handoffWire,
        scheduledParentId: scheduled,
        actualParentId: proposed,
        notes: notesText.isEmpty ? null : notesText,
        revision: existing?.revision ?? 0,
        revisionToken: existing?.revisionToken ?? '',
      );
      if (existing == null) {
        await widget.dataSource.insertDay(row);
      } else {
        // Full-row update carrying the T-33/T-35 echo (see CareSchedule).
        await widget.dataSource.updateDay(row);
      }
      if (mounted) Navigator.of(context).pop(DaySheetOutcome.saved);
    } catch (e) {
      _fail(e.toString(), l[KApp.errDaySave]);
    }
  }

  /// Web parity: `GetCurrentProfileAsync` throws when the profile is missing —
  /// the message propagates to the error banner like any server text.
  Member _requireMyProfile() {
    final my = widget.myProfile;
    if (my == null) throw StateError('Perfil do utilizador não encontrado.');
    return my;
  }

  /// F-47: true only when there IS a snapshot to restore from and its
  /// observation differs from the one on the day today (the STORED text, not
  /// the editor's — a revert does not save the editor's fields).
  Future<bool> _shouldAskRevertNotes() async {
    final snapshot =
        await widget.dataSource.fetchPreEditNotes(widget.date);
    if (snapshot == null) return false;
    final current = widget.day?.notes;
    if (!notesDifferForRevert(current, snapshot.notes)) return false;
    _revertSnapshotText = snapshot.notes;
    _revertCurrentText = current;
    return true;
  }

  Future<void> _clearDay() async {
    final existing = widget.day;
    if (existing == null ||
        isClearDayBlocked(adminBypass: widget.adminBypass) ||
        _saving ||
        _deleting) {
      return;
    }
    final l = AppL10n.of(context).l;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await widget.dataSource.deleteDay(existing.id);
      if (mounted) Navigator.of(context).pop(DaySheetOutcome.cleared);
    } catch (e) {
      _fail(e.toString(), l[K.errDeleteFailed]);
    }
  }

  void _fail(String raw, String fallback) {
    if (!mounted) return;
    final l = AppL10n.of(context).l;
    setState(() {
      _saving = false;
      _deleting = false;
      // T-35 first — reloading the month cannot fix a stale build (web order).
      _error = isStaleClientBuild(raw)
          ? l[K.errStaleClient]
          : isSessionExpired(raw)
              ? sessionExpiredMessage(l)
              : isDayConflict(raw)
                  ? l[KApp.errConcurrentSaveRetry]
                  : translateSaveError(raw, fallback, l);
    });
  }

  MemberView? _inactiveViewFor(int? profileId) {
    if (profileId == null || profileId <= 0) return null;
    for (final v in widget.memberViews) {
      // F-56: a pending member is NOT a ghost — it is in `members`, with a
      // colour of its own. Only the S-11 tombstone renders as one.
      if (v.id == profileId && !v.isAssignable) return v;
    }
    return null;
  }

  /// F-56: the planned parent of the day being edited has no account yet, so
  /// the "real responsible" question has no counterpart to answer it. The
  /// sheet says so instead of offering a swap the database would refuse.
  bool get _swapUnavailableForPending =>
      !swapAvailableForScheduled(_scheduledParentId, widget.memberViews);

  String _chipLabel(Member m, Localization l) {
    final first = m.fullName.split(' ').first;
    return m.isPendingMember ? '$first ${l[KApp.calMemberPending]}' : first;
  }

  Widget _memberChip(int id, String label, {required bool selected,
      required ValueChanged<int>? onSelected}) {
    final slot =
        context.tokens.slot(profileSlotIndex(id, widget.memberViews));
    return ChoiceChip(
      // The carer wears the same identity here as on the grid — same fill, so
      // the chip and the day they own are recognisably the same person.
      avatar: AppAvatar(
        initials: displayInitials(id, widget.memberViews),
        slot: slot,
        radius: 14,
      ),
      // U-29: the check REPLACED the avatar on the selected chip — the one
      // chip whose identity matters most lost its initial and colour. The
      // fill already says "selected" (the same reason AppSegmented turned
      // its icon off).
      showCheckmark: false,
      label: Text(label),
      selected: selected,
      onSelected: onSelected == null ? null : (_) => onSelected(id),
    );
  }

  /// U-29: the shared [AppBanner] — this sheet carried a private copy of it,
  /// which is exactly the drift U-27 argued a component exists to prevent.
  Widget _banner(String text, {ToneColors? tone}) =>
      AppBanner(tone: tone ?? context.tokens.warning, message: text);

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final day = widget.day;
    final assignment = _assignment;

    final banners = _guardBanners(l, assignment);
    // U-28 QA: the day is READ-ONLY here, and the owner's review said the
    // stripped-down version of this sheet is the best thing on the screen — so
    // it keeps exactly what it had. The responsible line survives only in this
    // branch: with the form on screen it repeats what "Agendado" and "Real"
    // already say two lines below.
    final readOnly = _saveBlocked;
    return AppSheetFrame(
      title: _capitalize('${formatHandoffDate(widget.date, l)} · '
          '${daysUntilLabel(widget.date, widget.today, l)}'),
      // A guard is the reason the sheet looks the way it does; it must not be
      // something the reader can scroll past.
      pinnedNotice: banners.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final b in banners)
                  Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.xs),
                      child: b),
              ],
            ),
      primaryLabel: readOnly || _showAdminConfirm ? null : l[K.commonSave],
      onPrimary: _scheduledParentId == null || _deleting || _beyondRetroReach
          ? null
          : _save,
      secondaryLabel:
          readOnly || _showAdminConfirm ? null : l[K.commonCancel],
      onSecondary: () => Navigator.of(context).pop(),
      busy: _saving,
      extraAction: readOnly ||
              _showAdminConfirm ||
              widget.day == null ||
              isClearDayBlocked(adminBypass: widget.adminBypass)
          ? null
          : OutlinedButton.icon(
              onPressed: _saving || _deleting ? null : _clearDay,
              style: OutlinedButton.styleFrom(
                foregroundColor: context.tokens.danger.onContainer,
                side: BorderSide(color: context.tokens.danger.border),
              ),
              icon: _deleting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.delete_outline),
              label: Text(l[K.editorClearDay]),
            ),
      children: [
        if (readOnly) _readView(l, day, assignment),
        if (!readOnly) ..._form(l),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.sm),
            child: Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
      ],
    );
  }

  /// The sheet's title starts a sentence, so it starts with a capital: the
  /// formatter returns "sáb, 22/08" because that is how a date reads INSIDE a
  /// sentence, and this is not inside one.
  String _capitalize(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  Widget _readView(
      Localization l, CareSchedule? day, DayAssignment? assignment) {
    if (day == null) return Text(l[KApp.sheetNoResponsible]);
    final previous = widget.previousDay;
    final isTransition = isTransitionDay(
      previous?.effectiveParentId,
      assignment!.effectiveParentId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // U-28 QA defect: this printed the INITIAL ("Responsável: I"). An
        // initial is what a 40 dp calendar cell can afford; a sheet has room
        // for the name, and the name is what the reader came for.
        Text(
            l.format(KApp.sheetResponsible, [
                  _nameOf(assignment.effectiveParentId)
                ]) +
                (isSwapped(assignment) ? l[KApp.sheetSwappedSuffix] : ''),
            style: Theme.of(context).textTheme.titleSmall),
        if (isTransition)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              day.handoffTime != null
                  // U-24: the wire's HH:mm:ss renders per language
                  // (14:30 · 2:30 PM) — never a raw substring.
                  ? l.format(KApp.sheetTransitionAt,
                      [l.formatTimeString(day.handoffTime!)])
                  : l[KApp.sheetTransition],
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  /// The carer's name, or their initial as the last resort — a member the
  /// client does not know (an old row, a departed profile) must not render an
  /// empty label.
  String _nameOf(int? id) {
    for (final v in widget.memberViews) {
      if (v.id == id) return v.fullName;
    }
    return id == null ? '' : displayInitials(id, widget.memberViews);
  }

  List<Widget> _guardBanners(Localization l, DayAssignment? assignment) {
    final widgets = <Widget>[];
    if (widget.adminBypass && (_isPast || isApprovedSwapDay(assignment))) {
      widgets.add(_banner(l[K.editorAdminOverride],
          tone: context.tokens.danger));
      if (_beyondRetroReach) {
        widgets.add(_banner(
            widget.isPremium!
                ? l.format(KApp.editorRetroBeyondPremium,
                    [widget.settings.overridePremiumMonths])
                : l.format(KApp.editorRetroBeyondFree, [
                    widget.settings.overrideFreeDays,
                    widget.settings.overridePremiumMonths,
                  ]),
            tone: context.tokens.danger));
      }
    } else if (_isPast) {
      widgets.add(_banner(l[K.editorPastReadonly]));
    } else if (_isFrozen) {
      widgets.add(_banner(l[K.editorFrozenReadonly]));
    }
    return widgets;
  }

  List<Widget> _form(Localization l) {
    final scheduledGhost = _inactiveViewFor(_scheduledParentId);
    final actualGhost = _inactiveViewFor(
        _actualParentId == 0 ? null : _actualParentId);
    return [
      // ── Planned parent (S-09: locked on assigned days for non-admins) ──
      //
      // U-28 QA: each block of this form is a card now. Loose on the sheet they
      // read as one long list of controls with no idea where one question ended
      // and the next began.
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
      // U-29: the "(Planejado)" explainer left the label for the ⓘ, as the
      // English catalog had already done. The S-09 lock hint outranks it.
      AppFieldLabel(l[K.editorScheduledParent],
          info: _scheduledLocked
              ? l[K.editorLockedHint]
              : l[K.editorScheduledParentHint]),
      Wrap(
        spacing: 8,
        children: [
          // S-11 QA: a departed assignee still shows by name (consult).
          if (scheduledGhost != null)
            _memberChip(scheduledGhost.id,
                '${scheduledGhost.fullName.split(' ').first} ${l[K.calMemberLeft]}',
                selected: true, onSelected: null),
          for (final m in widget.members)
            _memberChip(m.id, _chipLabel(m, l),
                selected: _scheduledParentId == m.id,
                onSelected: _scheduledLocked
                    ? null
                    : (id) => setState(() => _scheduledParentId = id)),
        ],
      ),
          ],
        ),
      ),
      const SizedBox(height: Spacing.sm),

      // ── Actual parent — general since lote 3: changing it on today/future
      //    opens a swap request; the direct write survives only where the DB
      //    allows it (admin past-day correction, no-workflow saves) ──
      // F-56: on a pending member's day there is nobody to approve, so the
      // question is replaced by the reason (the DB refuses the swap anyway).
      if (_swapUnavailableForPending)
        _banner(l.format(KApp.sheetSwapUnavailablePending, [
          _nameOf(_scheduledParentId),
        ]))
      else
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
      // U-28 QA: the redundant "Responsável: X" line went away, and with it the
      // "(trocado)" suffix it carried. The FACT is not redundant, only the
      // sentence was — so it rides here, on the label of the field that owns it.
      AppFieldLabel(
        l[K.editorActualParent],
        info: l[K.editorActualParentHint],
        trailing: isSwapped(_assignment)
            ? AppBadge(
                text: l[K.calSwapped], tone: context.tokens.swapped.tone)
            : null,
      ),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text(l[K.editorSameAsPlanned]),
            selected: _actualParentId == 0,
            onSelected: (_) => setState(() => _actualParentId = 0),
          ),
          if (actualGhost != null)
            _memberChip(actualGhost.id,
                '${actualGhost.fullName.split(' ').first} ${l[K.calMemberLeft]}',
                selected: true, onSelected: null),
          for (final m in widget.members)
            // F-28 scenario gate — same filter as the web's select.
            if (canOfferAsActual(
              candidateId: m.id,
              userProfileId: widget.ownProfileId,
              editingScheduledParentId: _scheduledParentId ?? 0,
              existingActualParentId: widget.day?.actualParentId,
            ))
              _memberChip(m.id, m.fullName.split(' ').first,
                  selected: _actualParentId == m.id,
                  onSelected: (id) => setState(() => _actualParentId = id)),
        ],
      ),
          ],
        ),
      ),
      const SizedBox(height: Spacing.sm),

      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
      // ── Day note ──
      //
      // U-28 QA: the explanation left the helper line for an ⓘ on the label.
      // `AppTextField` keeps the integrated label, which the owner named as the
      // best thing the port brought — so it stays a field, with a tip beside it.
      Row(
        children: [
          Expanded(
            child: AppTextField(
              label: l[K.editorDayNote],
              hint: l[K.editorDayNotePlaceholder],
              controller: _notes,
              maxLength: 100,
            ),
          ),
          AppInfoTip(message: l[K.editorDayNoteHint]),
        ],
      ),
      const SizedBox(height: Spacing.md),

      // ── Handoff time (T-27: transition days only) ──
      //
      // U-37: one field, the platform's picker. The hour + minute dropdown
      // pair was the Blazor `<select>` pair ported literally — on a phone the
      // minute list was a three-screen scroll to reach "30".
      AppTimeField(
        fieldKey: const Key('handoff'),
        label: l[K.editorHandoffTime],
        info: l[K.editorHandoffHint],
        optionalLabel: l[K.commonOptional],
        value: _handoff,
        emptyText: l[K.editorHandoffEmpty],
        clearLabel: l[K.editorHandoffClear],
        formatValue: (t) => l.formatTime(DateTime(2000, 1, 1, t.hour, t.minute)),
        onChanged: (t) => setState(() => _handoff = t),
      ),
      if (_handoff != null && _scheduledParentId != null)
        FutureBuilder<int?>(
          future: _prevEffective,
          builder: (context, snapshot) =>
              snapshot.connectionState == ConnectionState.done &&
                      !isTransitionDay(snapshot.data, _effectiveBeingSaved)
                  ? Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(l[K.editorNoTransitionHint],
                          style: Theme.of(context).textTheme.bodySmall),
                    )
                  : const SizedBox.shrink(),
        ),
          ],
        ),
      ),

      // ── F-44: only shown when saving will actually open a swap/revert
      //    request — keeps it apart from the day-scoped "Observação do dia" ──
      if (_willOpenWorkflow) ...[
        const SizedBox(height: Spacing.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppFieldLabel(l[K.editorMessageLabel],
                  info: l[K.editorWorkflowHint],
                  optionalLabel: l[K.commonOptional]),
              AppTextField(
                label: l[K.editorMessageLabel],
                hint: l[K.editorMessagePlaceholder],
                controller: _swapMessage,
                maxLength: 200,
              ),
            ],
          ),
        ),
      ],

      // ── The admin confirmation stays IN the scroll: it is a question about
      //    what is on screen, not the sheet's own action row (which the frame
      //    pins and which this branch hides).
      if (_showAdminConfirm)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.tokens.danger.container,
            border: Border.all(color: context.tokens.danger.border),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l[K.editorAdminChangeWarning],
                  style: TextStyle(
                      fontSize: 13,
                      color: context.tokens.danger.onContainer)),
              const SizedBox(height: Spacing.sm),
              AppActionPair(
                primaryLabel: l[K.editorYesChange],
                destructive: true,
                busy: _saving,
                onPrimary: () {
                  setState(() {
                    _showAdminConfirm = false;
                    _adminConfirmed = true;
                  });
                  _save();
                },
                secondaryLabel: l[K.editorNoGoBack],
                onSecondary: () => setState(() => _showAdminConfirm = false),
              ),
            ],
          ),
        )
      else if (_showRevertConfirm)
        // F-47: reverting undoes the swap and replays the day's pre-swap
        // state — but the observation may have been rewritten since. Only
        // asked when the two texts differ.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.tokens.warning.container,
            border: Border.all(color: context.tokens.warning.border),
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l[K.editorRevertNotesQuestion],
                  style: TextStyle(
                      fontSize: 13,
                      color: context.tokens.warning.onContainer)),
              const SizedBox(height: 8),
              for (final (labelKey, value) in [
                (K.editorRevertNotesCurrent, _revertCurrentText),
                (K.editorRevertNotesBefore, _revertSnapshotText),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(
                        text: '${l[labelKey]} ',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    TextSpan(
                        text: (value == null || value.trim().isEmpty)
                            ? l[K.editorNoNote]
                            : value,
                        style: const TextStyle(fontSize: 12)),
                  ])),
                ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  FilledButton(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _showRevertConfirm = false;
                              _revertNotesChoice = false;
                            });
                            _save();
                          },
                    child: Text(l[K.editorKeepCurrent]),
                  ),
                  OutlinedButton(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _showRevertConfirm = false;
                              _revertNotesChoice = true;
                            });
                            _save();
                          },
                    child: Text(l[K.editorRestorePrevious]),
                  ),
                ],
              ),
              // Dismissing is not an answer: nothing is sent and the next
              // attempt asks again from the fail-safe default.
              TextButton(
                onPressed: _saving
                    ? null
                    : () => setState(() {
                          _showRevertConfirm = false;
                          _revertNotesChoice = null;
                          _revertSnapshotText = null;
                          _revertCurrentText = null;
                        }),
                child: Text(l[K.commonCancel]),
              ),
            ],
          ),
        )
    ];
  }
}
