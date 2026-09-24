import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/day_agenda.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/day_account.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/admin_mode.dart';
import '../services/custody_data_source.dart';
import '../widgets/admin_mode_offer.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/slot_pill.dart';

/// What the sheet did — the caller picks the toast, mirroring the web's four
/// success paths (`toastSaved` · `toastDayCleared` · `toastSwapRequested` ·
/// `toastRevertRequested`).
enum DaySheetOutcome { saved, cleared, swapRequested, revertRequested }

/// U-25: the pencil that turns the summary into the editor — keyed so a flow
/// test reaches it without a localized finder. Since U-56 it exists only on a
/// PAST day under the admin mode: every other day the reader can change opens
/// in the editor.
const daySheetEditKey = Key('day-sheet-edit');

/// F-67 Part B: "Corrigir o planejamento" on a past day, for an admin with the
/// mode off — the door the mode used to hide behind an unlabelled shield.
const daySheetCorrectPlanKey = Key('day-sheet-correct-plan');

/// F-67 Part A: the relato's text field, and the "Corrigir" of one relato
/// (suffixed with its id).
const daySheetReportFieldKey = Key('day-sheet-report-field');
String daySheetCorrectAccountKey(int id) => 'day-sheet-correct-account-$id';

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
///
/// U-56 (owner, 23/09/2026: *"a maioria das pessoas acaba clicando sempre
/// duas vezes"*): that tap deeper was paid by almost every reader, so a day
/// the reader can change, today or ahead, opens in the EDITOR again
/// ([daySheetOpening]). The clutter U-25 hid is removed instead: the summary's
/// pills sit on top of the form as the day's current state, the planned-parent
/// field leaves when the reader cannot change it (S-09), and "Salvar" lights
/// only when the draft differs from the stored day ([dayDraftChanged]). The
/// summary stays for the days nothing can be saved on, and for a past day,
/// whose primary is the relato (F-67).
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
  VoidCallback? onOpenPlan,
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
      onOpenPlan: onOpenPlan,
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

  /// F-55: where the agenda's Premium CTA lands (`/family/plan`).
  final VoidCallback? onOpenPlan;

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
    this.onOpenPlan,
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

  // ── F-67 Part A: the relatos of a past day ──
  /// Null while loading (or when the day is not past), then the day's list.
  List<DayAccount>? _accounts;
  bool _accountsFailed = false;

  /// The relato editor is on screen — a third mode beside the summary and the
  /// plan editor, and never at the same time as either.
  bool _reporting = false;

  /// The relato being corrected, or null for a first account.
  DayAccount? _correcting;
  late final TextEditingController _accountBody;
  bool _savingAccount = false;

  /// Relatos this author wrote today (the RPC's cap counts these) — null
  /// until read; a failed read just skips the "N left" line.
  int? _writtenToday;

  /// U-56: how the day tap opened this sheet — decides the first mode and is
  /// the `mode` of `day-sheet-closed`.
  late final DaySheetOpening _opening;

  /// U-56: how the sheet ended, reported when it goes away. Stays [none]
  /// when the reader only looked.
  DaySheetResult _result = DaySheetResult.none;

  /// U-56: what the last build painted for "Salvar", so typing in the note
  /// rebuilds only when the answer flips.
  bool _paintedDraftChanged = false;

  /// U-25: the editor is on screen. Since U-56 it starts true wherever a save
  /// is possible, except on a past assigned day (the relato's summary).
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

  /// F-67: an active member with an account, a day inside D-1 … D-30, and a
  /// connection. The RPC is the enforcement.
  bool get _canWriteAccount {
    final me = widget.myProfile;
    return me != null &&
        !widget.offline &&
        canWriteDayAccount(
          hasAccount: (me.userId ?? '').isNotEmpty,
          hasLeft: me.hasLeft,
          date: widget.date,
          today: widget.today,
          maxDaysBack: widget.settings.dayAccountMaxDaysBack,
        );
  }

  /// The day is past but outside the window, for someone who could otherwise
  /// write — the one case the sheet explains instead of offering.
  bool get _accountWindowClosed {
    final me = widget.myProfile;
    return _isPast &&
        me != null &&
        (me.userId ?? '').isNotEmpty &&
        !me.hasLeft &&
        !isDayAccountDate(
            widget.date, widget.today, widget.settings.dayAccountMaxDaysBack);
  }

  List<DayAccountEntry> get _entries => [
        for (final a in _accounts ?? const <DayAccount>[])
          (
            id: a.id,
            authorId: a.authorProfileId,
            correctsId: a.correctsId,
            createdAt: a.createdAt,
          ),
      ];

  int get _capLeft => widget.settings.dayAccountDailyCap - (_writtenToday ?? 0);

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
    _accountBody = TextEditingController();
    _resetDraft();
    _notes.addListener(_onNotesChanged);
    if (_isPast) _loadAccounts();
    _opening = daySheetOpening(
        canSave: !_readOnly, isEmptyDay: _isEmptyDay, isPast: _isPast);
    _editing = _opening.opensEditor;
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

  /// U-56: the draft differs from the stored day — the only time "Salvar"
  /// has something to write.
  bool get _draftChanged {
    final day = widget.day;
    final handoff = _handoff;
    return dayDraftChanged(
      storedScheduledParentId: day?.scheduledParentId,
      storedActualParentId: day?.actualParentId,
      storedNotes: day?.notes,
      storedHandoffTime: day?.handoffTime,
      draftScheduledParentId: _scheduledParentId,
      draftActualParentId: _actualParentId,
      draftNotes: _notes.text,
      draftHandoff: handoff == null
          ? null
          : (hour: handoff.hour, minute: handoff.minute),
    );
  }

  void _onNotesChanged() {
    if (mounted && _draftChanged != _paintedDraftChanged) setState(() {});
  }

  /// U-56: the sheet closes on a write — the outcome goes to the caller for
  /// its toast and to `day-sheet-closed` for the count.
  void _finish(DaySheetOutcome outcome) {
    _result = switch (outcome) {
      DaySheetOutcome.saved => DaySheetResult.saved,
      DaySheetOutcome.cleared => DaySheetResult.cleared,
      DaySheetOutcome.swapRequested => DaySheetResult.swap,
      DaySheetOutcome.revertRequested => DaySheetResult.revert,
    };
    Navigator.of(context).pop(outcome);
  }

  /// U-56: the planned-parent field is a question only for whoever can answer
  /// it — an empty day, the admin mode, or an admin who will be offered the
  /// mode on the tap. For everyone else it was a row of locked chips (S-09)
  /// repeating the pill on top.
  bool get _showPlannedField =>
      !_scheduledLocked || _canOffer(AdminModeAction.changePlannedParent);

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

  // ── F-67 Part A ──

  Future<void> _loadAccounts() async {
    try {
      final rows =
          await widget.dataSource.fetchDayAccounts(widget.date, widget.date);
      if (!mounted) return;
      setState(() {
        _accounts = rows;
        _accountsFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accounts = const [];
        _accountsFailed = true;
      });
    }
  }

  Future<void> _startReport({DayAccount? correcting}) async {
    setState(() {
      _error = null;
      _reporting = true;
      _correcting = correcting;
      _accountBody.text = correcting?.body ?? '';
    });
    final me = widget.myProfile;
    if (me == null) return;
    try {
      final n = await widget.dataSource.countDayAccountsWrittenToday(me.id);
      if (mounted) setState(() => _writtenToday = n);
    } catch (_) {
      // The line is a courtesy; the RPC still says no at the cap.
    }
  }

  void _cancelReport() => setState(() {
        _reporting = false;
        _correcting = null;
        _error = null;
        _accountBody.clear();
      });

  Future<void> _saveAccount() async {
    if (_savingAccount) return;
    final l = AppL10n.of(context).l;
    final maxChars = widget.settings.dayAccountMaxChars;
    final errorKey = dayAccountBodyErrorKey(_accountBody.text, maxChars);
    if (errorKey != null) {
      setState(() => _error = l.format(errorKey, [maxChars]));
      return;
    }
    setState(() {
      _savingAccount = true;
      _error = null;
    });
    try {
      await widget.dataSource.addDayAccount(
        date: widget.date,
        body: normalizeDayAccountBody(_accountBody.text),
        correctsId: _correcting?.id,
      );
      if (!mounted) return;
      setState(() {
        _savingAccount = false;
        _reporting = false;
        _correcting = null;
        _accountBody.clear();
        _writtenToday = (_writtenToday ?? 0) + 1;
        _result = DaySheetResult.report;
      });
      showAppSnack(context, l[KApp.dayAccountSaved]);
      await _loadAccounts();
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      setState(() {
        _savingAccount = false;
        _error = isSessionExpired(raw)
            ? sessionExpiredMessage(l)
            : translateSaveError(raw, l[KApp.dayAccountErrSave], l);
      });
    }
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
    // U-56: one event per sheet, fired where the answer is known — never from
    // build (T-76).
    unawaited(widget.dataSource.analytics?.trackEvent(
            AnalyticsEvents.daySheetClosed,
            props: {'mode': _opening.wire, 'outcome': _result.wire}) ??
        Future<void>.value());
    _notes.removeListener(_onNotesChanged);
    _notes.dispose();
    _swapMessage.dispose();
    _accountBody.dispose();
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
        if (mounted) _finish(DaySheetOutcome.revertRequested);
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
        _trackNote(existing?.notes, notesText);
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
        if (mounted) _finish(DaySheetOutcome.swapRequested);
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
      _trackNote(existing?.notes, notesText);
      if (mounted) _finish(DaySheetOutcome.saved);
    } catch (e) {
      _fail(e.toString(), l[KApp.errDaySave]);
    }
  }

  /// T-78: `day-note-saved` when a save CHANGED the Observação — written or
  /// cleared; a save that only moved the carer or the time is not a note.
  void _trackNote(String? before, String after) {
    if ((before ?? '').trim() == after) return;
    unawaited(widget.dataSource.analytics?.trackEvent(
            AnalyticsEvents.dayNoteSaved,
            props: {'state': after.isEmpty ? 'cleared' : 'set'}) ??
        Future<void>.value());
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
    // F-55: with the agenda on the observation is read-only and the revert
    // moves no text (the server ignores the choice too).
    if (_agendaOn) return false;
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
      if (mounted) _finish(DaySheetOutcome.cleared);
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

    // F-67: the guards are about the PLAN; while a relato is being written
    // "Dia passado — apenas visualização" would contradict the field under it.
    final banners =
        _reporting ? const <Widget>[] : _guardBanners(l, assignment);
    // U-28 QA: the day is READ-ONLY here, and the owner's review said the
    // stripped-down version of this sheet was the best thing on the screen.
    // U-25 made that version the DEFAULT: every assigned day opens as it, and
    // the form is one pencil away wherever a save is possible.
    final readOnly = _readOnly;
    final editing = _editing && !readOnly && !_reporting;
    final reporting = _reporting;
    // F-67: on a past day inside the window the summary's primary is the
    // relato — the one door every active member has; "Corrigir o
    // planejamento" (Part B) stays the secondary, admin-only one.
    final offerReport = !editing && !reporting && _isPast && _canWriteAccount;
    final draftChanged = _paintedDraftChanged = _draftChanged;
    return AppSheetFrame(
      title: _capitalize('${formatHandoffDate(widget.date, l)} · '
          '${daysUntilLabel(widget.date, widget.today, l)}'),
      // U-25: the visible way out, in both modes.
      onClose: () => Navigator.of(context).pop(),
      closeLabel: l[K.commonClose],
      headerActions: [
        if (!readOnly && !editing && !reporting)
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
      primaryLabel: reporting
          ? l[KApp.dayAccountSave]
          : offerReport
              ? l[KApp.dayAccountAction]
              : !editing
                  ? null
                  : l[K.commonSave],
      onPrimary: reporting
          ? (_writtenToday != null && _capLeft <= 0 ? null : _saveAccount)
          : offerReport
              ? () => _startReport()
              : _scheduledParentId == null ||
                      !draftChanged ||
                      _deleting ||
                      _beyondRetroReach
                  ? null
                  : _save,
      secondaryLabel: reporting
          ? l[K.commonCancel]
          : !editing
              ? null
              : l[K.commonCancel],
      onSecondary: reporting
          ? (_savingAccount ? null : _cancelReport)
          : _deleting
              ? null
              : _cancelEdit,
      busy: _saving || _savingAccount,
      extraAction: reporting
          ? null
          : !editing
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
        if (reporting)
          ..._reportForm(l)
        else if (!editing) ...[
          _summary(l, day, assignment),
          if (_agendaOn) _agenda(),
          ..._accountsSection(l),
        ],
        if (editing) ...[
          // U-56: the summary's pills lead the form — the day as it IS, above
          // the controls that change it. An empty day has no state to show.
          if (!_isEmptyDay && day != null && assignment != null) ...[
            _statePills(l, day, assignment),
            const SizedBox(height: Spacing.md),
          ],
          ..._form(l),
          if (_agendaOn) _agenda(),
        ],
      ],
    );
  }

  /// F-55: the agenda is on for this family's build (`feature.child_agenda`).
  bool get _agendaOn => widget.settings.childAgendaEnabled;

  Widget _agenda() => DayAgendaSection(
        date: widget.date,
        today: widget.today,
        dataSource: widget.dataSource,
        settings: widget.settings,
        isPremium: widget.isPremium,
        me: widget.myProfile,
        allProfiles: widget.allProfiles,
        offline: widget.offline,
        onOpenPlan: widget.onOpenPlan == null
            ? null
            : () {
                Navigator.of(context).pop();
                widget.onOpenPlan!();
              },
      );

  /// F-67: the day's relatos under the summary, in the order they were
  /// written; a corrected one stays, in the undone style, with the instant
  /// of its correction. Read by everyone who can open the day.
  List<Widget> _accountsSection(Localization l) {
    if (!_isPast) return const [];
    final accounts = _accounts;
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final entries = _entries;
    final superseded = supersededDayAccountIds(entries);
    final ordered =
        dayAccountsInOrder(accounts ?? const <DayAccount>[], (a) => a.createdAt);
    return [
      if (accounts != null && (accounts.isNotEmpty || _accountsFailed)) ...[
        const SizedBox(height: Spacing.md),
        Text(l[KApp.dayAccountSection],
            style: textTheme.labelMedium?.copyWith(color: tokens.textMuted)),
        const SizedBox(height: Spacing.xs),
      ],
      if (_accountsFailed)
        Text(l[KApp.dayAccountErrLoad],
            style: textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
      for (final a in ordered)
        _accountTile(l, a, entries, superseded.contains(a.id)),
      if (_accountWindowClosed) ...[
        const SizedBox(height: Spacing.sm),
        Text(
            l.format(KApp.dayAccountOutOfWindow,
                [widget.settings.dayAccountMaxDaysBack]),
            style: textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
      ],
    ];
  }

  Widget _accountTile(Localization l, DayAccount a,
      List<DayAccountEntry> entries, bool isSuperseded) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final entry = entries.firstWhere((e) => e.id == a.id);
    final correction = correctionOf(a.id, entries);
    final canCorrect = canCorrectDayAccount(
      entry: entry,
      sameDay: entries,
      myProfileId: widget.myProfile?.id,
      canWrite: _canWriteAccount,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: Spacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // What colour alone would say (U-32): a corrected text is struck
            // AND says so in words, on the line under it.
            Text(a.body,
                style: isSuperseded
                    ? textTheme.bodyMedium?.copyWith(
                        color: tokens.textMuted,
                        decoration: TextDecoration.lineThrough)
                    : textTheme.bodyMedium),
            const SizedBox(height: Spacing.xs),
            Text(
                dayAccountByline(l,
                    authorName: _nameOf(a.authorProfileId),
                    writtenAt: a.createdAt),
                style: textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
            if (correction != null)
              Text(dayAccountCorrectedLine(l, correctedAt: correction.createdAt),
                  style:
                      textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
            if (canCorrect)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: Key(daySheetCorrectAccountKey(a.id)),
                  onPressed: () => _startReport(correcting: a),
                  child: Text(l[KApp.dayAccountCorrect]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// F-67: the relato editor — one field, and the sentence that says what
  /// cannot be undone BEFORE the tap, not after it.
  List<Widget> _reportForm(Localization l) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.tokens;
    final correcting = _correcting;
    final capLeft = _capLeft;
    return [
      if (correcting != null) ...[
        Text(
            l.format(KApp.dayAccountCorrecting,
                [l.formatDateTime(correcting.createdAt.toLocal())]),
            style: textTheme.labelMedium?.copyWith(color: tokens.textMuted)),
        const SizedBox(height: Spacing.sm),
      ],
      AppTextField(
        key: daySheetReportFieldKey,
        label: l[KApp.dayAccountFieldLabel],
        hint: l[KApp.dayAccountFieldHint],
        controller: _accountBody,
        maxLines: 6,
        maxLength: widget.settings.dayAccountMaxChars,
        keyboardType: TextInputType.multiline,
        autofocus: true,
      ),
      const SizedBox(height: Spacing.sm),
      Text(l[KApp.dayAccountAppendOnly],
          style: textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
      // Said before it blocks (the F-52 shape): the last three are counted
      // out loud, and the cap itself replaces the save.
      if (_writtenToday != null && capLeft <= 3) ...[
        const SizedBox(height: Spacing.sm),
        Text(
            capLeft <= 0
                ? l.format(KApp.dayAccountCapReached,
                    [widget.settings.dayAccountDailyCap])
                : capLeft == 1
                    ? l[KApp.dayAccountCapLeftOne]
                    : l.format(KApp.dayAccountCapLeftMany, [capLeft]),
            style: textTheme.bodySmall?.copyWith(color: tokens.textMuted)),
      ],
    ];
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
    final notes = day.notes?.trim() ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statePills(l, day, assignment),
        if (notes.isNotEmpty && !_agendaOn) ...[
          const SizedBox(height: Spacing.md),
          Text(l[K.editorDayNote],
              style: textTheme.labelMedium?.copyWith(color: tokens.textMuted)),
          const SizedBox(height: 2),
          Text(notes, style: textTheme.bodyMedium),
        ],
      ],
    );
  }

  /// U-25's pills — the real carer, *Trocado*, the handoff time — and, on a
  /// swapped day, whom it was planned for. U-56 puts the same block on top of
  /// the editor, so the form and the summary say the day's state one way.
  Widget _statePills(
      Localization l, CareSchedule day, DayAssignment assignment) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final swapped = isSwapped(assignment);
    final effective = assignment.effectiveParentId;
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
      // and the next began. U-56: a card nobody here can answer is not shown —
      // the pill on top already names the carer.
      if (_showPlannedField) ...[
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
      ],

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
      // U-28 QA put the "Trocado" fact on this label as a badge, because the
      // form had lost every line that said it. U-56: the pills lead the form
      // again and the dashed "Trocado" pill says it right above — a badge here
      // said it twice.
      AppFieldLabel(
        l[K.editorActualParent],
        info: l[K.editorActualParentHint],
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
      // F-55: with the agenda on, the observation IS the agenda's Nota — the
      // field leaves, and the section under the form takes its place.
      if (!_agendaOn) ...[
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
      ],

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
