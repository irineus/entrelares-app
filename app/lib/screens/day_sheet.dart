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
import '../widgets/slot_pill.dart';

/// What the sheet did — the caller picks the toast, mirroring the web's four
/// success paths (`toastSaved` · `toastDayCleared` · `toastSwapRequested` ·
/// `toastRevertRequested`).
enum DaySheetOutcome { saved, cleared, swapRequested, revertRequested }

/// U-25: the pencil that turns the summary into the editor — keyed so a flow
/// test reaches it without a localized finder.
const daySheetEditKey = Key('day-sheet-edit');

/// F-67 Part B: "Corrigir o planejamento" on a past day, for an admin with the
/// mode off — the door the mode used to hide behind an unlabelled shield.
const daySheetCorrectPlanKey = Key('day-sheet-correct-plan');

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
///
/// U-25 (closed alpha, 12/08/2026: *"essa lista suspensa está muito poluído…
/// falta um botão voltar"*): an assigned day opens as a SUMMARY — who has the
/// child, the swap and the handoff as one row of pills, and the day's note —
/// with the editor one pencil away and a ✕ that is always there. An empty day
/// has nothing to summarize and opens straight in the editor. No rule moved:
/// the same form, the same save routing, one tap deeper.
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
  AdminModeOfferer? adminOffer,
  int? ownProfileId,
  Member? myProfile,
  List<Member> allProfiles = const [],
  bool? isPremium,
  PublicSettings settings = PublicSettings.unloaded,
  Iterable<DateTime> frozenDates = const [],
  bool offline = false,
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
      adminOffer: adminOffer,
      ownProfileId: ownProfileId,
      myProfile: myProfile,
      allProfiles: allProfiles,
      isPremium: isPremium,
      settings: settings,
      frozenDates: frozenDates,
      offline: offline,
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

  /// F-67 Part B: non-null only when the reader is an admin — the sheet then
  /// ASKS where it would otherwise hide or refuse (see [AdminModeAction]).
  final AdminModeOfferer? adminOffer;
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

  /// T-18: the app had no connection when the day was opened. The sheet is
  /// the read-only one — nothing typed here could be saved, and every rule
  /// that would judge it (the T-35 token, a freeze, the horizon) lives on the
  /// server, so no write is attempted or parked for later.
  final bool offline;

  const _DaySheet({
    required this.date,
    required this.day,
    required this.previousDay,
    required this.members,
    required this.memberViews,
    required this.today,
    required this.dataSource,
    required this.adminBypass,
    this.adminOffer,
    required this.ownProfileId,
    required this.myProfile,
    required this.allProfiles,
    required this.isPremium,
    required this.settings,
    required this.frozenDates,
    this.offline = false,
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

  /// F-14 bypass as THIS sheet sees it: the calendar's answer when the sheet
  /// opened, turned true when the admin accepts the F-67 offer here — the
  /// sheet stays open and carries the action through instead of making the
  /// reader close it, find the shield and come back.
  late bool _bypass = widget.adminBypass;

  /// F-67 Part B: the question on screen, and what to do on "Ativar".
  AdminModeAction? _offering;
  VoidCallback? _afterOffer;

  /// U-25: the editor is on screen. Starts false on an assigned day (the
  /// summary) and true on an empty one, where the only thing to do is assign.
  late bool _editing;

  /// Where "Cancelar" goes: back to the summary the editor was opened from,
  /// or — an empty day has no summary — out of the sheet.
  late final bool _startedInSummary;

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

  /// Nothing planned: no row, or a row that names nobody.
  bool get _isEmptyDay {
    final day = widget.day;
    return day == null ||
        (day.scheduledParentId == 0 && day.actualParentId == null);
  }

  /// Past without the admin bypass, frozen, or offline: nothing can be saved,
  /// so there is no editor to reach.
  bool get _readOnly => _saveBlocked || widget.offline;
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
      adminBypass: _bypass, isPast: _isPast, isFrozen: _isFrozen);

  /// F-40 proactive mirror: the admin override cannot reach this far back.
  bool get _beyondRetroReach =>
      _bypass &&
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
      !_bypass;

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
    _notes = TextEditingController();
    _swapMessage = TextEditingController();
    _resetDraft();
    _editing = !_readOnly && _isEmptyDay;
    _startedInSummary = !_editing;
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

  /// The editor's fields as the stored day has them — on open, and again when
  /// "Cancelar" returns to the summary, so a draft never survives a cancel.
  void _resetDraft() {
    final day = widget.day;
    _scheduledParentId =
        (day != null && day.scheduledParentId != 0) ? day.scheduledParentId : null;
    _actualParentId = day?.actualParentId ?? 0;
    _notes.text = day?.notes ?? '';
    _swapMessage.clear();
    final handoff = parseTimeOfDay(day?.handoffTime);
    _handoff = handoff == null
        ? null
        : TimeOfDay(hour: handoff.hour, minute: handoff.minute);
    _error = null;
    _showAdminConfirm = false;
    _adminConfirmed = false;
    _showRevertConfirm = false;
    _revertNotesChoice = null;
    _revertSnapshotText = null;
    _revertCurrentText = null;
  }

  /// F-67 Part B: what an admin with the mode off is offered for [action]
  /// here. [AdminModeOfferKind.none] for everyone else — including every
  /// non-admin, who has no offerer at all.
  AdminModeOfferKind _offerKind(AdminModeAction action,
          {Iterable<DateTime> dates = const []}) =>
      widget.adminOffer == null || widget.offline
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

  bool _canOffer(AdminModeAction action) =>
      _offerKind(action) == AdminModeOfferKind.offer;

  /// The past day's own answer: offer, gate or the limit sentence.
  AdminModeOfferKind get _pastDayOffer => _isPast
      ? _offerKind(AdminModeAction.editPastDay, dates: [widget.date])
      : AdminModeOfferKind.none;

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

  void _openPlan() {
    Navigator.of(context).pop();
    widget.adminOffer?.openPlan();
  }

  void _cancelEdit() {
    if (!_startedInSummary) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _resetDraft();
      _editing = false;
    });
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
        isClearDayBlocked(adminBypass: _bypass) ||
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
  Widget _banner(String text, {required IconData icon, ToneColors? tone}) =>
      AppBanner(
          tone: tone ?? context.tokens.warning, icon: icon, message: text);

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final day = widget.day;
    final assignment = _assignment;

    final banners = _guardBanners(l, assignment);
    // U-28 QA: the day is READ-ONLY here, and the owner's review said the
    // stripped-down version of this sheet was the best thing on the screen.
    // U-25 made that version the DEFAULT: every assigned day opens as it, and
    // the form is one pencil away wherever a save is possible.
    final readOnly = _readOnly;
    final editing = _editing && !readOnly;
    return AppSheetFrame(
      title: _capitalize('${formatHandoffDate(widget.date, l)} · '
          '${daysUntilLabel(widget.date, widget.today, l)}'),
      // U-25: the visible way out, in both modes.
      onClose: () => Navigator.of(context).pop(),
      closeLabel: l[K.commonClose],
      headerActions: [
        if (!readOnly && !editing)
          IconButton(
            key: daySheetEditKey,
            icon: const Icon(Icons.edit_outlined),
            tooltip: l[K.editorAriaLabel],
            color: context.tokens.textMuted,
            onPressed: () => setState(() => _editing = true),
          ),
      ],
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
      // U-38: a failure is pinned under the title, and a question the save
      // raised takes the action row's place — both where the reader can see
      // them from the pinned "Salvar" they just tapped.
      error: _error,
      confirmation: _offering != null
          ? AdminModeOfferConfirmation(
              action: _offering!,
              onActivate: _acceptOffer,
              onCancel: _declineOffer,
            )
          : editing
              ? _confirmation(l)
              : null,
      primaryLabel: !editing ? null : l[K.commonSave],
      onPrimary: _scheduledParentId == null || _deleting || _beyondRetroReach
          ? null
          : _save,
      secondaryLabel: !editing ? null : l[K.commonCancel],
      onSecondary: _deleting ? null : _cancelEdit,
      busy: _saving,
      extraAction: !editing
          ? _correctPlanAction(l)
          : widget.day == null ||
                  (isClearDayBlocked(adminBypass: _bypass) &&
                      !_canOffer(AdminModeAction.clearDay))
              ? null
              : AppSheetDangerAction(
                  label: l[K.editorClearDay],
                  busy: _deleting,
                  onPressed: _saving
                      ? null
                      : isClearDayBlocked(adminBypass: _bypass)
                          ? () => _ask(AdminModeAction.clearDay, _clearDay)
                          : _clearDay,
                ),
      children: [
        if (!editing) _summary(l, day, assignment),
        if (editing) ..._form(l),
      ],
    );
  }

  /// F-67 Part B: the past day's door for an admin with the mode off. The
  /// SECONDARY look on purpose: when the relato (Part A) lands beside it, the
  /// primary belongs to "Relatar o que aconteceu", and a correction of the
  /// plan must not read as the way to tell what happened.
  Widget? _correctPlanAction(Localization l) {
    if (!_readOnly || _pastDayOffer != AdminModeOfferKind.offer) return null;
    return OutlinedButton.icon(
      key: daySheetCorrectPlanKey,
      icon: const Icon(Icons.shield_outlined),
      label: Text(l[KApp.adminOfferCorrectPlan]),
      onPressed: () => _ask(
          AdminModeAction.editPastDay, () => setState(() => _editing = true)),
    );
  }

  /// The sheet's title starts a sentence, so it starts with a capital: the
  /// formatter returns "sáb, 22/08" because that is how a date reads INSIDE a
  /// sentence, and this is not inside one.
  String _capitalize(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  /// U-25: the day in one glance — the pills say what the grid cell says, in
  /// words, and the lines under them say what the cell CANNOT: whom the day
  /// was planned for, and the note.
  Widget _summary(
      Localization l, CareSchedule? day, DayAssignment? assignment) {
    if (day == null || assignment == null || _isEmptyDay) {
      return Text(l[KApp.sheetNoResponsible]);
    }
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final swapped = isSwapped(assignment);
    final effective = assignment.effectiveParentId;
    final notes = day.notes?.trim() ?? '';
    const pillHeight = 28.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Spacing.sm,
          runSpacing: Spacing.xs,
          children: [
            // U-28 QA defect: this once printed the INITIAL ("Responsável: I").
            // An initial is what a 40 dp cell can afford; a sheet has room for
            // the name, and the name is what the reader came for.
            SlotPill(
              key: const ValueKey('day-summary-responsible'),
              slot: tokens.slot(profileSlotIndex(effective, widget.memberViews)),
              label: _summaryName(effective, l),
              height: pillHeight,
              patterned: true,
              maxWidth: 220,
            ),
            if (swapped)
              SlotPill(
                key: const ValueKey('day-summary-swapped'),
                slot: tokens.swapped,
                label: l[K.calSwapped],
                height: pillHeight,
                dashed: true,
              ),
            // T-27/T-45: the database keeps a time only on a transition day,
            // so a stored time IS the transition — no previous day to fetch.
            if (day.handoffTime != null)
              SlotPill(
                key: const ValueKey('day-summary-handoff'),
                slot: SlotColors(
                    tone: tokens.neutral, pattern: SlotPattern.none),
                icon: Icons.schedule,
                // U-24: the wire's HH:mm:ss renders per language
                // (14:30 · 2:30 PM) — never a raw substring.
                label: l.format(KApp.sheetHandoffAt,
                    [l.formatTimeString(day.handoffTime!)]),
                height: pillHeight,
              ),
          ],
        ),
        if (swapped)
          Padding(
            padding: const EdgeInsets.only(top: Spacing.xs),
            child: Text(
              l.format(KApp.sheetPlanned,
                  [_summaryName(day.scheduledParentId, l)]),
              style: textTheme.bodySmall?.copyWith(color: tokens.textMuted),
            ),
          ),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: Spacing.md),
          Text(l[K.editorDayNote],
              style: textTheme.labelMedium?.copyWith(color: tokens.textMuted)),
          const SizedBox(height: 2),
          Text(notes, style: textTheme.bodyMedium),
        ],
      ],
    );
  }

  /// The name with the member's state beside it: F-56's "(pendente)" for a
  /// carer with no account yet, S-11's "(saiu)" for one who left — the grid
  /// paints both, and the summary must not drop what it paints.
  String _summaryName(int? id, Localization l) {
    final name = _nameOf(id);
    for (final v in widget.memberViews) {
      if (v.id != id) continue;
      if (v.isPendingMember) return '$name ${l[KApp.calMemberPending]}';
      if (!v.isAssignable) return '$name ${l[K.calMemberLeft]}';
    }
    return name;
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
    if (widget.offline) {
      widgets.add(_banner(l[KApp.offlineWriteBlocked],
          icon: Icons.cloud_off_outlined));
    }
    if (_bypass && (_isPast || isApprovedSwapDay(assignment))) {
      widgets.add(_banner(l[K.editorAdminOverride],
          icon: Icons.shield_outlined, tone: context.tokens.danger));
      if (_beyondRetroReach) {
        widgets.add(_banner(
            widget.isPremium!
                ? l.format(KApp.editorRetroBeyondPremium,
                    [widget.settings.overridePremiumMonths])
                : l.format(KApp.editorRetroBeyondFree, [
                    widget.settings.overrideFreeDays,
                    widget.settings.overridePremiumMonths,
                  ]),
            icon: Icons.error_outline,
            tone: context.tokens.danger));
      }
    } else if (_isPast) {
      widgets.add(
          _banner(l[K.editorPastReadonly], icon: Icons.lock_outline));
      // F-67 Part B: an admin whose mode would NOT reach this day is told
      // why instead of being asked — Premium would (the U-49 gate, with its
      // CTA), or nothing would (the F-40 limit sentence).
      final canOpenPlan = widget.adminOffer?.onOpenPlan != null;
      switch (_pastDayOffer) {
        case AdminModeOfferKind.gate:
          widgets.add(AppBanner(
            tone: context.tokens.info,
            icon: Icons.lock_outline,
            message: l.format(KApp.editorRetroBeyondFree, [
              widget.settings.overrideFreeDays,
              widget.settings.overridePremiumMonths,
            ]),
            actionLabel: canOpenPlan ? l[K.famSeePremium] : null,
            actionIcon: canOpenPlan ? Icons.auto_awesome : null,
            onAction: canOpenPlan ? _openPlan : null,
          ));
        case AdminModeOfferKind.outOfWindow:
          widgets.add(_banner(
              l.format(KApp.editorRetroBeyondPremium,
                  [widget.settings.overridePremiumMonths]),
              icon: Icons.error_outline));
        case AdminModeOfferKind.none || AdminModeOfferKind.offer:
          break;
      }
    } else if (_isFrozen) {
      widgets.add(
          _banner(l[K.editorFrozenReadonly], icon: Icons.lock_outline));
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
                    ? (_canOffer(AdminModeAction.changePlannedParent)
                        ? (id) => _ask(AdminModeAction.changePlannedParent,
                            () => setState(() => _scheduledParentId = id))
                        : null)
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
        _banner(
            l.format(KApp.sheetSwapUnavailablePending, [
              _nameOf(_scheduledParentId),
            ]),
            icon: Icons.person_off_outlined)
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
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline,
                              size: 16, color: context.tokens.textMuted),
                          const SizedBox(width: Spacing.xs),
                          Expanded(
                            child: Text(l[K.editorNoTransitionHint],
                                style: Theme.of(context).textTheme.bodySmall),
                          ),
                        ],
                      ),
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

    ];
  }

  /// U-38: the two questions a save can raise. They used to render at the END
  /// of the form while the frame's action row disappeared — so the reader
  /// tapped the pinned "Salvar", the button vanished and the question was born
  /// below the fold. The frame now puts them where the button was.
  Widget? _confirmation(Localization l) {
    if (_showAdminConfirm) {
      return AppSheetConfirmation.destructive(
        message: l[K.editorAdminChangeWarning],
        yesLabel: l[K.editorYesChange],
        busy: _saving,
        onYes: () {
          setState(() {
            _showAdminConfirm = false;
            _adminConfirmed = true;
          });
          _save();
        },
        noLabel: l[K.editorNoGoBack],
        onNo: () => setState(() => _showAdminConfirm = false),
      );
    }
    if (_showRevertConfirm) {
      // F-47: reverting undoes the swap and replays the day's pre-swap state
      // — but the observation may have been rewritten since. Only asked when
      // the two texts differ.
      final textTheme = Theme.of(context).textTheme;
      final ink = context.tokens.warning.onContainer;
      return AppSheetConfirmation(
        tone: context.tokens.warning,
        icon: Icons.edit_note,
        message: l[K.editorRevertNotesQuestion],
        details: [
          for (final (labelKey, value) in [
            (K.editorRevertNotesCurrent, _revertCurrentText),
            (K.editorRevertNotesBefore, _revertSnapshotText),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.xs),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${l[labelKey]} ',
                    style: textTheme.bodySmall?.copyWith(
                        color: ink, fontWeight: FontWeight.w600)),
                TextSpan(
                    text: (value == null || value.trim().isEmpty)
                        ? l[K.editorNoNote]
                        : value,
                    style: textTheme.bodySmall?.copyWith(color: ink)),
              ])),
            ),
        ],
        actions: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: Spacing.sm,
              runSpacing: Spacing.xs,
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
      );
    }
    return null;
  }
}
