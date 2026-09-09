import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import '../services/admin_mode.dart';
import '../services/analytics_service.dart';
import '../services/custody_data_source.dart';
import '../theme/slot_pattern.dart';
import '../theme/tokens.dart';
import '../widgets/account_button.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/today_card.dart';
import 'bulk_sheet.dart';
import 'day_sheet.dart';
import 'frozen_day_sheet.dart';
import 'resolve_sheet.dart';
import '../services/onboarding_service.dart';
import '../widgets/onboarding.dart';
import 'wizard_sheet.dart';

/// U-28 — what one day of the grid is tall enough to hold: the day number, the
/// carer's initial, and the handoff mark under it. The width follows from the
/// screen; the height is a design decision, so it lives here.
///
/// **U-28 QA: it is a RANGE, not a number.** A fixed height sized for the worst
/// case — six weeks with the admin strip on — left a five-week month with a
/// band of dead space under the grid, and the owner was right that the number
/// we had was the FLOOR rather than the answer. The grid now spends whatever
/// height the screen actually gives it, divided by the weeks the month really
/// has, clamped at both ends.
///
/// The floor is measurement, not taste: the content is 12 + 2 + 18 + 11 = 43 dp
/// with every line's height pinned, inside a 2.5 dp "today" ring — 48 dp, so 50
/// is the floor with two to spare. A six-week month with the admin strip on and
/// a four-carer legend has to fit a 700 dp phone, and
/// `calendar_fits_u28_test` fails if either side of that stops being true.
///
/// The ceiling exists so a five-week month on a tall phone does not turn each
/// day into a letterbox: past about 76 dp the cell is mostly empty and the grid
/// stops reading as a month.
const double _dayCellMinHeight = 50;
const double _dayCellMaxHeight = 76;

/// The vertical gap between two week rows.
const double _daySpacing = 3;

/// U-27 — the F-27 slot palette now lives in [AppTokens.slots], with a
/// [SlotPattern] alongside each hue and a dark set that did not exist before.
/// "Trocado" is the web's amber with a DASHED border, which is also what frees
/// the rose for a role again.
SlotColors _slotOf(BuildContext context, DayPaint paint) => switch (paint) {
      DaySwapped() => context.tokens.swapped,
      DaySlot(slot: final s) => context.tokens.slot(s),
      DayUnassigned() => context.tokens.slot(0),
    };

class CalendarScreen extends StatefulWidget {
  final CustodyDataSource dataSource;

  /// T-37 — optional, and only passed through to the wizard.
  final AnalyticsService? analytics;
  final AdminMode adminMode;

  /// U-23 — the first-run surfaces. Null in tests that do not exercise them
  /// (and in any host that has no tour targets to offer).
  final OnboardingService? onboarding;
  final TourKeys? tourKeys;

  /// Where the checklist's "Convidar" step sends the user.
  final VoidCallback? onOpenFamily;

  /// F-09: the checklist's push step sends the person to Notificações,
  /// where the enable button lives. ONE place owns the OS prompt — a second
  /// entry point would be a second chance to spend a dialog that only
  /// appears once per install.
  final VoidCallback? onOpenNotifications;

  const CalendarScreen(
      {super.key,
      required this.dataSource,
      required this.adminMode,
      this.onboarding,
      this.tourKeys,
      this.analytics,
      this.onOpenFamily,
      this.onOpenNotifications});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with WidgetsBindingObserver {
  // Improvement over the web (owner directive): months are swipeable pages.
  // _basePage maps to the month shown at startup; ±offset navigates.
  static const _basePage = 1200;
  late final PageController _pageController;
  late DateTime _anchorMonth; // month at _basePage — never reassigned
  late DateTime _visibleMonth;

  List<Member> _members = const [];

  /// U-28 — the roles, so the legend and the today card can say "Fernanda
  /// (Mãe)" the way the web does. The port dropped the role everywhere on this
  /// screen, which is what made the legend read as four unexplained colours.
  List<Role> _roles = const [];
  Map<String, CareSchedule> _daysByIso = const {};
  Member? _ownProfile;

  // U-23 — first-run onboarding.
  OnboardingSignals? _onboardingSignals;
  bool _tourShown = false;
  // Today + the next-handoff window ([today, today + 91] — the web scans
  // [tomorrow, tomorrow + 90]; one query serves the card's row and the scan).
  List<CareSchedule> _upcoming = const [];
  // F-12: the visible month's OPEN swap requests — the frozen-day source
  // (paint, guards, panel). Keyed alongside _daysByIso on every load.
  Map<String, SwapRequest> _frozenByIso = const {};
  bool _loading = true;
  String? _loadError;
  void Function()? _unwatch;
  void Function()? _unwatchWorkflow;

  // F-23: the safety poll survives the native Realtime until the socket
  // proves itself under real load (owner decision 19/08/2026). Adaptive
  // cadence (25 s down / 120 s healthy), paused while backgrounded and
  // refreshed on resume — mirror of Home.razor's poll + visibility handling.
  Timer? _pollTimer;
  bool _socketConnected = false;

  // F-39 horizon inputs (T-41 settings + F-32 entitlement), loaded once like
  // the web's OnInitialized. The web call site is deliberately fail-OPEN: a
  // failed entitlement read defaults to premium so paging is never wrongly
  // blocked — the DB enforces the real limit regardless.
  Family? _family;
  bool _entitlementFailed = false;
  PublicSettings _settings = PublicSettings.unloaded;

  DateTime get _today => DateTime.now();

  bool get _isPremiumForPaging => _entitlementFailed ||
      Family.isPremiumFamily(_family, DateTime.now().toUtc());

  DateTime get _horizonDate => addMonthsClamped(
      _today,
      planningHorizonMonths(
        isPremium: _isPremiumForPaging,
        freeMonths: _settings.calendarMonthsFree,
        premiumMonths: _settings.calendarMonthsPremium,
      ));

  /// F-14: bypass only with the mode ON and the profile really an admin.
  bool get _adminBypass => isAdminBypass(
      adminModeActive: widget.adminMode.isActive,
      isAdmin: _ownProfile?.isAdmin ?? false);

  // ── Bulk selection (U-11): long-press arms it; the ☑️ button is the
  //    accessible entry point. Mirror of Home.razor's selection state.
  final Set<DateTime> _selectedDays = {};
  bool _selectionArmed = false;

  bool get _isSelectionMode => isSelectionMode(
      selectedCount: _selectedDays.length, armed: _selectionArmed);

  @override
  void initState() {
    super.initState();
    final now = _today;
    _anchorMonth = DateTime(now.year, now.month, 1);
    _visibleMonth = _anchorMonth;
    _pageController = PageController(initialPage: _basePage);
    WidgetsBinding.instance.addObserver(this);
    widget.adminMode.addListener(_onAdminModeChanged);
    // U-29: the profile's "Ver o tour de novo" and "Rever os primeiros
    // passos" ping this — the State lives on in the tab stack, so nothing
    // else runs when the user lands back.
    widget.onboarding?.addListener(_onOnboardingPing);
    _load();
    _loadHorizonInputs();
    _watch();
    _schedulePoll();
  }

  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = Timer(
        Duration(milliseconds: pollIntervalMs(socketConnected: _socketConnected)),
        () {
      if (mounted) _load(silent: true);
      _schedulePoll();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mirror of OnVisibilityChanged: no polling on a hidden app; a fresh
    // load + a new timer on return.
    if (state == AppLifecycleState.resumed) {
      _load(silent: true);
      _schedulePoll();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _onAdminModeChanged() {
    if (mounted) setState(() {});
  }

  /// Defensive like the web: neither read may break the calendar — entitlement
  /// falls to premium, settings to the seeded fallbacks (no wrongful block).
  Future<void> _loadHorizonInputs() async {
    Family? family;
    var failed = false;
    try {
      family = await widget.dataSource.fetchOwnFamily();
    } catch (_) {
      failed = true;
    }
    var settings = PublicSettings.unloaded;
    try {
      settings = PublicSettings(await widget.dataSource.fetchPublicSettings());
    } catch (_) {/* seeded fallbacks */}
    if (!mounted) return;
    setState(() {
      _family = family;
      _entitlementFailed = failed;
      _settings = settings;
    });
  }

  Future<void> _watch() async {
    // Native Realtime — the whole reason F-29's JS bridge retires. Any change
    // another member saves shows up here without polling. The socket's health
    // drives the F-23 poll cadence.
    _unwatch = await widget.dataSource.watchChanges(
      () {
        if (mounted) _load(silent: true);
      },
      onStatus: (connected) {
        if (!mounted) return;
        if (connected != _socketConnected) {
          _socketConnected = connected;
          if (_pollTimer != null) _schedulePoll();
        }
      },
    );
    // Lote 3: the workflow channel — a request opened/resolved by the other
    // member repaints the frozen days without a manual refresh.
    _unwatchWorkflow = await widget.dataSource.watchWorkflowChanges(() {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.adminMode.removeListener(_onAdminModeChanged);
    widget.onboarding?.removeListener(_onOnboardingPing);
    _unwatch?.call();
    _unwatchWorkflow?.call();
    _pollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) =>
      DateTime(_anchorMonth.year, _anchorMonth.month + (page - _basePage), 1);

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final members = await widget.dataSource.fetchMembers();
      // Best-effort: a family whose roles fail to load still gets its
      // calendar, just without the "(Mãe)" suffix.
      List<Role> roles = _roles;
      try {
        roles = await widget.dataSource.fetchRoles();
      } catch (_) {/* keep whatever we had */}
      final days = await widget.dataSource
          .fetchMonth(_visibleMonth.year, _visibleMonth.month);
      final frozen = await widget.dataSource
          .fetchFrozenRequestsForMonth(_visibleMonth.year, _visibleMonth.month);
      final ownProfile = await widget.dataSource.fetchOwnProfile();
      final upcoming = await widget.dataSource
          .fetchUpcoming(_today, nextHandoffWindowDays + 1);
      if (!mounted) return;
      setState(() {
        _members = members;
        _roles = roles;
        _daysByIso = {
          for (final d in days) CareSchedule.isoDate(d.scheduleDate): d
        };
        // Web parity (Home's frozenRequests.First per day): one request per
        // date matters — the DB's one-pending-per-date index guarantees it.
        _frozenByIso = {
          for (final r in frozen) CareSchedule.isoDate(r.scheduleDate): r
        };
        _ownProfile = ownProfile;
        _upcoming = upcoming;
        _loading = false;
        _loadError = null;
      });
      // U-28: the account button in every tab's app bar wears this.
      AccountScope.identityOf(context)?.adopt(
          fullName: ownProfile?.fullName, colorSlot: ownProfile?.colorSlot);
      unawaited(_refreshOnboarding(ownProfile, members));
    } catch (e) {
      if (!mounted) return;
      final l = AppL10n.of(context).l;
      setState(() {
        _loading = false;
        _loadError = isSessionExpired(e.toString())
            ? sessionExpiredMessage(l)
            : l[KApp.errCalendarLoad];
      });
    }
  }

  // ── U-23: first-run onboarding ──────────────────────────────────────────

  /// The checklist's own signal for "days are planned" costs a query; the
  /// month already in hand answers it for free whenever it is not empty
  /// (the web ORs exactly the same way).
  OnboardingSignals? get _effectiveSignals => _onboardingSignals?.copyWith(
      hasAnyPlannedDay:
          _onboardingSignals!.hasAnyPlannedDay || _daysByIso.isNotEmpty);

  bool get _showChecklist {
    final signals = _effectiveSignals;
    if (signals == null || _loading) return false;
    return OnboardingSteps.shouldShowChecklist(signals,
        reopened: widget.onboarding?.checklistReopened ?? false);
  }

  Future<void> _refreshOnboarding(Member? me, List<Member> members) async {
    final onboarding = widget.onboarding;
    if (onboarding == null || me == null) return;
    final signals =
        await onboarding.loadSignals(me: me, members: members);
    if (!mounted) return;
    setState(() => _onboardingSignals = signals);

    // The tour runs ONCE, on the first authenticated session, and hands over
    // to the checklist when it ends — the web's FinishTour does the same.
    // (Explicit replays arrive through [_onTourReplayRequested] now.)
    if (!_tourShown &&
        widget.tourKeys != null &&
        me.onboardingTourSeenAt == null) {
      _tourShown = true;
      // U-29: the launcher banner the setState above may have inserted shifts
      // the whole column AFTER the spotlight would measure its targets — let
      // the frame settle first, or the holes light where things WERE.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await showGuidedTour(context: context, keys: widget.tourKeys!);
      await onboarding.markTourSeen();
      if (mounted && _showChecklist) await _openChecklist();
    }
  }

  /// One listener, two requests — each guarded by its own flag, so a ping for
  /// one never runs the other by accident.
  void _onOnboardingPing() {
    unawaited(_onTourReplayRequested());
    unawaited(_onChecklistReopenRequested());
  }

  /// U-29 (owner-reported, round 3) — the deterministic reopen path. The
  /// profile's "Rever os primeiros passos" raised the session flag and
  /// cleared the stored dismissal, but nothing told this State — alive in
  /// the shell's IndexedStack — to look again, so the banner only appeared
  /// when a background reload happened to coincide. The service notifies
  /// now, and this reloads the signals so [_showChecklist] flips at once.
  Future<void> _onChecklistReopenRequested() async {
    final onboarding = widget.onboarding;
    final me = _ownProfile;
    if (onboarding == null || me == null || !onboarding.checklistReopened) {
      return;
    }
    // Consumed up front: a second ping mid-flight must not open two sheets.
    final openSheet = onboarding.checklistOpenRequested;
    onboarding.checklistOpenRequested = false;
    final signals = await onboarding.loadSignals(me: me, members: _members);
    if (!mounted) return;
    setState(() => _onboardingSignals = signals);
    if (!openSheet) return;
    // U-29 round 5 (owner): the profile button promises the first steps, not
    // a launcher to tap — land with the checklist sheet OPEN; the banner
    // stays behind as the way back in.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _openChecklist();
  }

  /// U-29 — the deterministic replay path. Before, the flag was only read
  /// inside `_load`, which does not run when the user navigates back from the
  /// profile (this State stays alive in the shell's IndexedStack), so "Ver o
  /// tour de novo" waited for a background refresh — and a second replay in
  /// the same session was blocked by `_tourShown` outright.
  Future<void> _onTourReplayRequested() async {
    final onboarding = widget.onboarding;
    if (onboarding == null ||
        !onboarding.tourReplayRequested ||
        widget.tourKeys == null) {
      return;
    }
    onboarding.tourReplayRequested = false;
    _tourShown = true;
    // Let the navigation back to this tab land before measuring targets.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await showGuidedTour(context: context, keys: widget.tourKeys!);
    await onboarding.markTourSeen();
  }

  Future<void> _openChecklist() async {
    final signals = _effectiveSignals;
    if (signals == null) return;
    final action =
        await showOnboardingChecklist(context: context, signals: signals);
    if (!mounted || action == null) return;
    switch (action) {
      case OnboardingAction.invite:
        widget.onOpenFamily?.call();
      case OnboardingAction.plan:
        await _openWizard();
      case OnboardingAction.explainSwaps:
        await _explainSwaps();
      case OnboardingAction.enablePush:
        widget.onOpenNotifications?.call();
      case OnboardingAction.replayTour:
        if (widget.tourKeys == null) return;
        await showGuidedTour(context: context, keys: widget.tourKeys!);
    }
  }

  /// Opening the explanation IS completing the step — stamped BEFORE the sheet
  /// renders, so a reader who closes it immediately still gets the credit.
  Future<void> _explainSwaps() async {
    await widget.onboarding?.markSwapExplanationSeen();
    if (!mounted) return;
    setState(() => _onboardingSignals =
        _onboardingSignals?.copyWith(hasOpenedSwapExplanation: true));
    await showHowSwapsWork(context);
  }

  Future<void> _dismissChecklist() async {
    // U-29 (owner-reported bug): the reopen flag is what keeps a reopened
    // checklist visible past `allDone`, and nothing ever cleared it — so the
    // ✕ stamped the dismissal and the banner came straight back, for the
    // rest of the session. Dismissing answers the reopen too.
    widget.onboarding?.checklistReopened = false;
    await widget.onboarding?.markChecklistDismissed();
    if (!mounted) return;
    setState(() => _onboardingSignals =
        _onboardingSignals?.copyWith(checklistDismissed: true));
  }

  int _pageForMonth(DateTime month) =>
      _basePage +
      (month.year * 12 + month.month) -
      (_anchorMonth.year * 12 + _anchorMonth.month);

  void _bounceBack() {
    _pageController.animateToPage(_pageForMonth(_visibleMonth),
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// The web's navigation guard: month navigation while days are selected
  /// asks before discarding the selection. Returns whether to proceed.
  Future<bool> _confirmDiscardSelection() async {
    final l = AppL10n.of(context).l;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.format(
            _selectedDays.length == 1
                ? K.navGuardSelectedOne
                : K.navGuardSelectedMany,
            [_selectedDays.length])),
        content: Text(l[K.navGuardBody]),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l[K.navGuardYes])),
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l[K.navGuardNo])),
        ],
      ),
    );
    if (proceed == true) {
      _cancelSelection();
      return true;
    }
    return false;
  }

  Future<void> _onPageChanged(int page) async {
    final month = _monthForPage(page);
    // The bounce-back below re-fires with the month already shown — no-op.
    if (month.year == _visibleMonth.year && month.month == _visibleMonth.month) {
      return;
    }
    // F-39 mirror of the web's NextMonth: paging stops at the family's
    // planning horizon with the tier message instead of advancing. The
    // horizon check comes BEFORE the guard, same order as NextMonth.
    if (!canPageToMonth(month, _horizonDate)) {
      showAppSnack(
          context,
          _isPremiumForPaging
              ? AppL10n.of(context).l.format(
                  K.horizonPremium, [_settings.calendarMonthsPremium])
              : AppL10n.of(context).l.format(K.horizonFree, [
                  _settings.calendarMonthsFree,
                  _settings.calendarMonthsPremium,
                ]));
      _bounceBack();
      return;
    }
    if (_isSelectionMode && !await _confirmDiscardSelection()) {
      _bounceBack();
      return;
    }
    setState(() => _visibleMonth = month);
    _load();
  }

  List<MemberView> get _memberViews =>
      _members.map((m) => m.toView()).toList(growable: false);

  /// F-56: who a day can be planned for — active members AND pending ones
  /// (invited, not yet joined). Only the S-11 tombstone is left out. The
  /// swap workflow is a different question, answered per day by the sheet.
  List<Member> get _assignableMembers =>
      _members.where((m) => !m.hasLeft).toList();

  void _toggleDaySelection(DateTime date) {
    final d = dateOnly(date);
    setState(() {
      if (!_selectedDays.remove(d)) _selectedDays.add(d);
    });
  }

  /// Mirror of LongPressDay: entering selection always ADDS the day.
  void _onDayLongPress(DateTime date) {
    HapticFeedback.mediumImpact();
    setState(() => _selectedDays.add(dateOnly(date)));
  }

  void _onDayTap(DateTime date) {
    if (_isSelectionMode) {
      HapticFeedback.selectionClick();
      _toggleDaySelection(date);
      return;
    }
    // Web parity (HandleDayClick): a day with a pending request opens the
    // frozen panel instead of the editor — for everyone, admins included.
    final frozen = _frozenByIso[CareSchedule.isoDate(date)];
    if (frozen != null) {
      _openFrozenDay(frozen);
      return;
    }
    _openDay(date);
  }

  Future<void> _openFrozenDay(SwapRequest request) async {
    HapticFeedback.selectionClick();
    final outcome = await showFrozenDaySheet(
      context: context,
      request: request,
      allProfiles: _members,
      ownProfileId: _ownProfile?.id,
      dataSource: widget.dataSource,
    );
    if (outcome != null) {
      _load(silent: true);
      if (mounted) {
        showAppSnack(
            context, AppL10n.of(context).l[frozenOutcomeToastKey(outcome)]);
      }
    }
  }

  void _cancelSelection() {
    setState(() {
      _selectedDays.clear();
      _selectionArmed = false;
    });
  }

  Future<void> _openBulkSheet() async {
    final summary = await showBulkSheet(
      context: context,
      selectedDays: Set.of(_selectedDays),
      daysByIso: _daysByIso,
      activeMembers: _assignableMembers,
      today: _today,
      dataSource: widget.dataSource,
      adminBypass: _adminBypass,
      frozenDates: [for (final r in _frozenByIso.values) r.scheduleDate],
      myProfile: _ownProfile,
      allProfiles: _members,
    );
    if (summary != null) {
      // Mirror of FinishBulkSave: the selection clears (armed state stays),
      // the month reloads and the summary is the toast.
      setState(() => _selectedDays.clear());
      _load(silent: true);
      if (mounted) showAppSnack(context, summary);
    }
  }

  /// Mirror of `WorkflowActionableCount`: how many selected days carry an
  /// action for the resolve sheet (awaiting me + sent by me + revertable).
  int get _workflowActionableCount {
    final views = [for (final r in _frozenByIso.values) r.toView()];
    final frozenDates = [for (final r in _frozenByIso.values) r.scheduleDate];
    var revertable = 0;
    for (final d in _selectedDays) {
      final row = _daysByIso[CareSchedule.isoDate(d)];
      if (row != null &&
          isRevertCandidate(
            scheduleDate: row.scheduleDate,
            scheduledParentId: row.scheduledParentId,
            actualParentId: row.actualParentId,
            today: _today,
            frozenDates: frozenDates,
          )) {
        revertable++;
      }
    }
    return selectedPendingForMe(
                openRequests: views,
                selectedDates: _selectedDays,
                myProfileId: _ownProfile?.id)
            .length +
        selectedSentByMe(
                openRequests: views,
                selectedDates: _selectedDays,
                myProfileId: _ownProfile?.id)
            .length +
        revertable;
  }

  Future<void> _openResolveSheet() async {
    final summary = await showResolveSheet(
      context: context,
      selectedDays: Set.of(_selectedDays),
      openRequests: _frozenByIso.values.toList(),
      daysByIso: _daysByIso,
      today: _today,
      ownProfileId: _ownProfile?.id,
      myProfile: _ownProfile,
      allProfiles: _members,
      dataSource: widget.dataSource,
    );
    if (summary != null) {
      // Mirror of RunBulkWorkflowAsync's close: selection clears, month
      // reloads, the summary is the toast.
      setState(() => _selectedDays.clear());
      _load(silent: true);
      if (mounted) showAppSnack(context, summary);
    }
  }

  Future<void> _openWizard() async {
    final generated = await showWizardSheet(
      context: context,
      activeMembers: _assignableMembers,
      today: _today,
      dataSource: widget.dataSource,
      // F-39: the wizard clamps to the same horizon as the paging.
      maxScheduleDate: _horizonDate,
      isFreeTier: !_isPremiumForPaging,
      analytics: widget.analytics,
    );
    if (generated == true) _load(silent: true);
  }

  Future<void> _openDay(DateTime date) async {
    HapticFeedback.selectionClick();
    final iso = CareSchedule.isoDate(date);
    final previousIso =
        CareSchedule.isoDate(date.subtract(const Duration(days: 1)));
    final outcome = await showDaySheet(
      context: context,
      date: date,
      day: _daysByIso[iso],
      previousDay: _daysByIso[previousIso],
      members: _assignableMembers,
      memberViews: _memberViews,
      today: _today,
      dataSource: widget.dataSource,
      adminBypass: _adminBypass,
      ownProfileId: _ownProfile?.id,
      // F-40 proactive gate wants the REAL entitlement (fail-closed mirror);
      // when the read failed it gets null and the gate steps aside — the
      // trigger's own refusal propagates instead of a wrongful client block.
      isPremium: _entitlementFailed
          ? null
          : Family.isPremiumFamily(_family, DateTime.now().toUtc()),
      settings: _settings,
      frozenDates: [for (final r in _frozenByIso.values) r.scheduleDate],
      myProfile: _ownProfile,
      allProfiles: _members,
    );
    if (outcome != null) {
      _load(silent: true);
      if (mounted) {
        showAppSnack(
            context,
            AppL10n.of(context).l[switch (outcome) {
              DaySheetOutcome.saved => K.toastSaved,
              DaySheetOutcome.cleared => K.toastDayCleared,
              DaySheetOutcome.swapRequested => K.toastSwapRequested,
              DaySheetOutcome.revertRequested => K.toastRevertRequested,
            }]);
      }
    }
  }

  /// Web: GoToToday — no-op when already on the current month (the card is
  /// not tappable then anyway).
  void _goToToday() {
    final now = _today;
    final delta = (now.year * 12 + now.month) -
        (_anchorMonth.year * 12 + _anchorMonth.month);
    _pageController.animateToPage(_basePage + delta,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// The Today card inputs, all from state the load already holds. The card
  /// itself is dumb — the rules live in core (today_rules).
  Widget _todayCard(BuildContext context) {
    final todayIso = CareSchedule.isoDate(_today);
    CareSchedule? todayRow;
    for (final d in _upcoming) {
      if (CareSchedule.isoDate(d.scheduleDate) == todayIso) {
        todayRow = d;
        break;
      }
    }
    final glance = todayGlance(
      userProfileId: _ownProfile?.id,
      scheduledParentId: todayRow?.scheduledParentId,
      actualParentId: todayRow?.actualParentId,
      handoffTime: todayRow?.handoffTime,
      members: _memberViews,
    );
    // Web: a no-schedule day nulls the handoff (the scan needs a "current"
    // parent to differ from).
    DateTime? nextHandoff;
    if (todayRow != null) {
      nextHandoff = nextHandoffDate(todayRow.effectiveParentId, [
        for (final d in _upcoming)
          if (CareSchedule.isoDate(d.scheduleDate) != todayIso)
            (
              date: d.scheduleDate,
              scheduledParentId: d.scheduledParentId,
              actualParentId: d.actualParentId,
            ),
      ]);
    }
    return TodayCard(
      glance: glance,
      userFullName: _ownProfile?.fullName ?? '',
      today: _today,
      nextHandoffDate: nextHandoff,
      viewingCurrentMonth: isCurrentMonth(_visibleMonth, _today),
      showInviteNudge: showInviteNudge(
        isLoading: _loading,
        isAdmin: _ownProfile?.isAdmin ?? false,
        // F-56: a pending member counts — the nudge is "reach out", and a
        // caregiver already on the calendar was reached.
        activeMemberCount: _assignableMembers.length,
      ),
      responsibleRole: _roleLabelFor(
          todayRow?.effectiveParentId, AppL10n.of(context).l.current),
      onGoToToday: _goToToday,
      onInvite: () => context.go('/family'),
    );
  }

  /// A heading starts with a capital; the date formatters lowercase because
  /// their output usually sits inside a sentence.
  String _capitalize(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  /// U-18 parity (QA round): the swap key appears only on a month that has a
  /// swapped day. The web hides it for exactly this reason — on a month with no
  /// swap it is a legend entry explaining something that is not on screen, and
  /// it costs the grid the width of its own label.
  bool get _visibleMonthHasSwap => _daysByIso.values.any((d) =>
      d.actualParentId != null && d.actualParentId != d.scheduledParentId);

  /// U-28 — how a member's role reads for this reader, or null when the family
  /// never set one. Built-ins translate, custom roles pass through — the
  /// composition lives in [Role.displayLabel], same as the family screen's.
  String? _roleLabelFor(int? memberId, AppLanguage language) {
    if (memberId == null) return null;
    for (final m in _members) {
      if (m.id != memberId) continue;
      for (final r in _roles) {
        if (r.id == m.roleId) {
          final label = r.displayLabel(language);
          return label.isEmpty ? null : label;
        }
      }
    }
    return null;
  }

  /// U-28 — the month, its two arrows and the calendar's own actions, sitting
  /// directly above the grid they act on.
  ///
  /// Two things were wrong before. The month name lived in the app bar, four
  /// icon buttons away from the calendar it names, and truncated to
  /// "agosto de…" whenever the admin shield made a fifth. And month navigation
  /// was swipe-ONLY — an improvement the owner asked for (18/08/2026), but one
  /// that silently removed the web's explicit `<` `>`, leaving no visible way
  /// to change month at all. The swipe stays; the arrows come back.
  Widget _monthBar(BuildContext context, Localization l) {
    // U-28 QA: `visualDensity.compact` on the arrows. A default IconButton is
    // 48 dp tall around a 24 dp glyph, and this row exists to name the month.
    //
    // The "today" chip sits INSIDE the centred group, never next to an arrow:
    // a chip that lands a thumb's width from "next month" is a mis-tap waiting
    // to happen, and the two do opposite things.
    final visible = _visibleMonth.year * 12 + _visibleMonth.month;
    final current = _today.year * 12 + _today.month;
    return Row(
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l[K.calPrevMonth],
          icon: const Icon(Icons.chevron_left),
          onPressed: () => _stepMonth(-1),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Viewing the FUTURE: today is behind the reader, so the chip
              // stands to the left of the month and its arrow points back.
              _todayChip(context, l,
                  visible: visible > current, forward: false),
              Flexible(
                child: Text(
                  // U-28 QA: "Agosto de 2026". The formatter lowercases because
                  // a month reads that way INSIDE a sentence; this is a heading.
                  _capitalize(l.formatMonthYear(
                      _visibleMonth.year, _visibleMonth.month)),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              // Viewing the PAST: today is ahead, so the chip stands to the
              // right and its arrow points forward.
              _todayChip(context, l,
                  visible: visible < current, forward: true),
            ],
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          tooltip: l[K.calNextMonth],
          icon: const Icon(Icons.chevron_right),
          onPressed: () => _stepMonth(1),
        ),
      ],
    );
  }

  /// U-28 QA — the way back to today, as a chip that says which WAY it goes.
  ///
  /// It used to be a line of link text under the greeting, where it read as an
  /// orphan sentence in the middle of a coloured band. Going back to today is
  /// navigation, so it belongs in the row that navigates — and the arrow points
  /// the direction the calendar will actually travel, from the reader's own
  /// position: forward when they are looking at the past, back when they are
  /// looking at the future.
  ///
  /// Both sides are always built and collapse to nothing when they do not
  /// apply, so the month name never jumps sideways as the chip swaps ends.
  Widget _todayChip(BuildContext context, Localization l,
      {required bool visible, required bool forward}) {
    final tokens = context.tokens;
    return AnimatedSize(
      duration: Motion.micro,
      curve: Motion.microCurve,
      child: !visible
          ? const SizedBox(height: 32)
          : Padding(
              padding: EdgeInsets.only(
                left: forward ? Spacing.sm : 0,
                right: forward ? 0 : Spacing.sm,
              ),
              child: ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: Icon(
                    forward ? Icons.arrow_forward : Icons.arrow_back,
                    size: TypeScale.subtitle,
                    color: tokens.accent.onContainer),
                label: Text(l[K.calToday]),
                labelStyle: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tokens.accent.onContainer),
                backgroundColor: tokens.accent.container,
                side: BorderSide(color: tokens.accent.border),
                onPressed: _goToToday,
              ),
            ),
    );
  }

  /// The calendar's OWN actions. They live in the app bar and not in the month
  /// bar: sharing that row with the month name is what truncated it to
  /// "agosto de 20…", and the app bar has room now that language and sign-out
  /// moved into the account menu.
  List<Widget> _calendarActions(BuildContext context, Localization l) => [
        // U-11: the accessible entry point to bulk selection (mirrors the
        // long-press). Once armed, tapping a day toggles its selection.
        if (!_isSelectionMode)
          IconButton(
            tooltip: l[K.calSelectDays],
            icon: const Icon(Icons.check_box_outlined),
            onPressed: () => setState(() => _selectionArmed = true),
          ),
        IconButton(
          key: widget.tourKeys?.keyFor(TourTarget.wizardButton),
          tooltip: l[K.calWizard],
          icon: const Icon(Icons.event_repeat),
          onPressed: _openWizard,
        ),
        // F-14: the explicit admin-mode toggle — mirror of the web's NavMenu
        // button. Only a real admin sees it; the shell shows the persistent
        // banner while it is on. It stays with the calendar and not in the
        // account menu because what it unlocks is a day on THIS grid.
        if (_ownProfile?.isAdmin == true)
          IconButton(
            tooltip:
                l[widget.adminMode.isActive ? K.navAdminExit : K.navAdminEnter],
            icon: Icon(
              widget.adminMode.isActive ? Icons.shield : Icons.shield_outlined,
              color:
                  widget.adminMode.isActive ? context.tokens.dangerBar : null,
            ),
            onPressed: widget.adminMode.toggle,
          ),
      ];

  /// One month forward or back, on the same controller the swipe drives — so
  /// the arrows and the gesture cannot disagree about where the calendar is.
  void _stepMonth(int delta) {
    final page = (_pageController.page ?? _basePage.toDouble()).round() + delta;
    _pageController.animateToPage(page,
        duration: Motion.sheet, curve: Motion.sheetCurve);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppL10n.of(context);
    final l = app.l;
    final views = _memberViews;
    return Scaffold(
      // U-28: the app bar names the TAB, like the other three do. The month
      // moved down to sit against the grid it labels — up here, competing with
      // five icon buttons, it truncated to "agosto de…" for any admin.
      appBar: AppBar(
        // U-28 QA: 48 instead of 56, and the title one step down the scale. The
        // calendar is the one screen whose content is a fixed grid — every
        // point spent on chrome is a point the month does not get, and the grid
        // was scrolling.
        toolbarHeight: 48,
        title: Text(l[K.navCalendar],
            style: Theme.of(context).textTheme.titleMedium),
        actions: [
          ..._calendarActions(context, l),
          const AppAccountButton(),
        ],
      ),
      body: Column(
        children: [
          if (_showChecklist)
            OnboardingLauncher(
              signals: _effectiveSignals!,
              onOpen: _openChecklist,
              onDismiss: _dismissChecklist,
            ),
          // U-28: the skeleton covers the WHOLE screen it stands in for. Before,
          // only the grid had one — the today card and the legend simply did
          // not exist until data arrived, so the calendar loaded as a bare grid
          // and then shoved itself down by two blocks when the load returned.
          if (_ownProfile == null && _loading)
            const _TodayCardSkeleton()
          else if (_ownProfile != null)
            KeyedSubtree(
                key: widget.tourKeys?.keyFor(TourTarget.todayCard),
                child: _todayCard(context)),
          _monthBar(context, l),
          if (_members.isEmpty && _loading)
            const _LegendSkeleton()
          else
            KeyedSubtree(
              key: widget.tourKeys?.keyFor(TourTarget.calendarLegend),
              child: _Legend(
                members: _members,
                views: views,
                roleOf: (id) => _roleLabelFor(id, l.current),
                showSwapKey: _visibleMonthHasSwap,
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, page) {
                final month = _monthForPage(page);
                final isVisible = month.year == _visibleMonth.year &&
                    month.month == _visibleMonth.month;
                return LayoutBuilder(builder: (context, box) {
                  return RefreshIndicator(
                  onRefresh: _load,
                  // U-29: the load error as the same danger banner the reports
                  // tabs use, WITH a visible way to retry — pull-to-refresh
                  // still works, but it is not a discoverable recovery.
                  child: _loadError != null && isVisible
                      ? ListView(children: [
                          Padding(
                            padding: const EdgeInsets.all(Spacing.lg),
                            child: Column(children: [
                              AppBanner(
                                  tone: context.tokens.danger,
                                  leading: '⚠️',
                                  message: _loadError!),
                              const SizedBox(height: Spacing.sm),
                              OutlinedButton(
                                  onPressed: _load,
                                  child: Text(l[K.layoutErrorReload])),
                            ]),
                          )
                        ])
                      : _MonthGrid(
                          month: month,
                          daysByIso: isVisible ? _daysByIso : const {},
                          frozenByIso: isVisible ? _frozenByIso : const {},
                          ownProfileId: _ownProfile?.id,
                          views: views,
                          today: _today,
                          loading: _loading && isVisible,
                          selectedIso: {
                            for (final d in _selectedDays)
                              CareSchedule.isoDate(d)
                          },
                          onDayTap: _onDayTap,
                          onDayLongPress: _onDayLongPress,
                          // U-28 QA: the height the grid may actually spend.
                          availableHeight: box.maxHeight,
                        ),
                );
                });
              },
            ),
          ),
          if (_isSelectionMode)
            Material(
              elevation: 8,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _selectedDays.isEmpty
                              ? null
                              : _openBulkSheet,
                          child: Text(l.format(
                              K.selectionEdit, [_selectedDays.length])),
                        ),
                      ),
                      // 🔔 Resolver — only when the selection carries open
                      // requests / revertable days (WorkflowActionableCount).
                      if (_workflowActionableCount > 0) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _openResolveSheet,
                            child: Text(l.format(K.selectionResolve,
                                [_workflowActionableCount])),
                          ),
                        ),
                      ],
                      IconButton(
                        tooltip: l[K.selectionCancel],
                        icon: const Icon(Icons.close),
                        onPressed: _cancelSelection,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The today card's outline while it loads — the same card, the same two
/// bands, the same heights, so nothing moves when the real one arrives.
class _TodayCardSkeleton extends StatelessWidget {
  const _TodayCardSkeleton();

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSkeleton(width: 180, height: 18),
              const SizedBox(height: Spacing.xs),
              const AppSkeleton(width: 130, height: 12),
              const Divider(height: Spacing.lg),
              Row(
                children: [
                  const AppSkeleton.circle(size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        AppSkeleton(width: 90, height: 10),
                        SizedBox(height: Spacing.xs),
                        AppSkeleton(width: 150, height: 16),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  const AppSkeleton(width: 70, height: 32),
                ],
              ),
            ],
          ),
        ),
      );
}

/// The legend's outline: one line of pills, the height the real one keeps.
class _LegendSkeleton extends StatelessWidget {
  const _LegendSkeleton();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: _Legend.rowHeight + Spacing.xs,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm, vertical: Spacing.xs),
          children: const [
            AppSkeleton(width: 88, height: 14, radius: Radii.sm),
            SizedBox(width: Spacing.md),
            AppSkeleton(width: 100, height: 14, radius: Radii.sm),
          ],
        ),
      );
}

/// U-28 — the legend: compact pill keys that WRAP when the family grows.
///
/// (U-29 doc fix: this comment used to carry the two superseded versions —
/// "scrolls sideways" and "one line only" — alongside the shipped one; the
/// build method below is the authority and this now says what it does.)
///
/// The QA rounds settled three things. Every carer's key carries the NAME AND
/// ROLE in the carer's own colour (the port had reduced it to unexplained
/// swatches); no `Chip` chrome — a bordered 32 dp chip row cost the grid
/// height it did not have, so the key is a bare `labelSmall` pill; and the
/// "Trocado" key appears only on a month that actually contains a swapped day
/// (the web's **U-18**). A four-carer family wraps onto a second row — the
/// rows appear only when the family has grown enough to need them, and a
/// horizontal scroll would hide the fourth carer behind a gesture nobody
/// knows is there.
class _Legend extends StatelessWidget {
  final List<Member> members;
  final List<MemberView> views;

  /// Resolves a member's role for the current reader; null keeps the bare name.
  final String? Function(int memberId) roleOf;

  /// U-18 parity: whether the month on screen has any swapped day at all.
  final bool showSwapKey;

  const _Legend({
    required this.members,
    required this.views,
    required this.roleOf,
    required this.showSwapKey,
  });

  /// One row of keys. A four-carer family plus the swap key needs two.
  static const rowHeight = 22.0;

  @override
  Widget build(BuildContext context) {
    // F-27/S-11: colors are per member still IN the family (persistent
    // color_slot). F-56: a pending member has a colour and a place in the key,
    // marked so the legend does not claim someone who has not joined.
    final active = members.where((m) => !m.hasLeft).toList()
      ..sort((a, b) => (a.colorSlot ?? 9).compareTo(b.colorSlot ?? 9));
    // U-28 QA: it WRAPS, it does not scroll.
    //
    // The arithmetic does not leave a choice. "Fernanda (Mãe)" is about 100 dp
    // with its swatch; four of those plus "Trocado" is roughly 490 dp against a
    // 360 dp phone. One line was never going to hold a four-carer family, and a
    // horizontal scroll hides the fourth carer behind a gesture nobody knows is
    // there. Two rows show everyone, and the rows only appear when the family
    // has grown enough to need them — a two-carer family still gets one.
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 0, Spacing.sm, Spacing.xs),
      child: Wrap(
        spacing: Spacing.md,
        runSpacing: Spacing.xs,
        children: [
          for (final m in active)
            Builder(builder: (context) {
              final slot = context.tokens.slot(profileSlotIndex(m.id, views));
              final role = roleOf(m.id);
              final first = m.fullName.split(' ').first;
              final base = role == null ? first : '$first ($role)';
              final label = m.isPendingMember
                  ? '$base ${AppL10n.of(context).l[KApp.calMemberPending]}'
                  : base;
              return _key(context, slot: slot, label: label);
            }),
          if (showSwapKey)
            _key(context,
                slot: context.tokens.swapped,
                label: AppL10n.of(context).l[K.calSwapped],
                dashed: true),
        ],
      ),
    );
  }

  /// One key, as the web draws it: a pill in the carer's own colour with their
  /// name in it.
  ///
  /// U-28 QA replaced a swatch-plus-label pair with this. The pill IS the
  /// colour, so carrying a separate swatch beside it said the same thing twice
  /// and spent width the legend cannot spare. The swapped key keeps its dashed
  /// outline — that border is the signal, not the fill.
  Widget _key(BuildContext context,
      {required SlotColors slot,
      required String label,
      bool dashed = false}) {
    // No `alignment:` here, and that is the whole fix: a Container WITH an
    // alignment expands to fill whatever space it is offered, so each key took
    // a full row of the Wrap and the legend became a stack of banners. Without
    // it the Container shrink-wraps its text, which is what a pill is.
    final pill = Container(
      height: rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      decoration: BoxDecoration(
        color: slot.tone.container,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: dashed ? null : Border.all(color: slot.tone.border),
      ),
      child: Center(
        widthFactor: 1,
        child: Text(label,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: slot.tone.onContainer)),
      ),
    );
    if (!dashed) return pill;
    return CustomPaint(
      foregroundPainter:
          DashedBorderPainter(color: slot.tone.border, radius: Radii.lg),
      child: pill,
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final Map<String, CareSchedule> daysByIso;
  final Map<String, SwapRequest> frozenByIso;
  final int? ownProfileId;
  final List<MemberView> views;
  final DateTime today;
  final bool loading;
  final Set<String> selectedIso;
  final void Function(DateTime) onDayTap;
  final void Function(DateTime) onDayLongPress;

  /// What the PageView's box gives this month, in logical pixels. The cell
  /// height is derived from it and the number of weeks the month really has.
  final double availableHeight;

  const _MonthGrid({
    required this.month,
    required this.daysByIso,
    required this.frozenByIso,
    required this.ownProfileId,
    required this.views,
    required this.today,
    required this.loading,
    required this.selectedIso,
    required this.onDayTap,
    required this.onDayLongPress,
    required this.availableHeight,
  });

  /// The F-12 cell badge — mirror of Home.razor's day-frozen markup: 🔔 when
  /// the request awaits MY response (overdue gets the red variant), ⏳ when it
  /// awaits someone else; the semantics label carries the web's title text.
  _FrozenMark? _markFor(SwapRequest? frozen, Localization l) {
    if (frozen == null) return null;
    final awaitingMe = frozen.targetProfileId == ownProfileId;
    final overdue =
        frozen.toView().priorityTag(DateTime.now()) == SwapPriorityTag.overdue;
    if (awaitingMe) {
      return _FrozenMark(
        badge: '🔔',
        overdue: overdue,
        label: l[overdue ? K.calOverdueAwaitingYou : K.calAwaitingYou],
      );
    }
    String? targetName;
    for (final v in views) {
      if (v.id == frozen.targetProfileId) {
        targetName = v.fullName;
        break;
      }
    }
    return _FrozenMark(
      badge: '⏳',
      overdue: false,
      label: l
          .format(K.calAwaitingFrom, [targetName ?? l[K.calOtherCaregiver]]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Sunday-first: DateTime.weekday has Mon=1..Sun=7, so %7 puts Sunday at 0
    // — same blank count as the web's (int)firstDayOfMonth.DayOfWeek.
    final blanksBefore = DateTime(month.year, month.month, 1).weekday % 7;
    final todayIso = CareSchedule.isoDate(today);
    // Sunday-first initials per language — the catalog carries the row
    // (K.calWeekdayInitials: "D,S,T,Q,Q,S,S" · "S,M,T,W,T,F,S").
    final weekdayInitials =
        AppL10n.of(context).l[K.calWeekdayInitials].split(',');

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: [
        Row(
          children: [
            for (final w in weekdayInitials)
              Expanded(
                child: Center(
                  child: Text(w,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 2),
        // U-28: the cell is sized by its CONTENT, not by the accident of being
        // square. `GridView.count` defaults to `childAspectRatio: 1`, which on a
        // phone gives a ~43 dp cell for the ~50 dp the day number, the avatar
        // and the handoff mark need — every assigned day rendered
        // `BOTTOM OVERFLOWED`. The height is fixed and the ratio derives from
        // the real width, so the same cell holds on any screen.
        LayoutBuilder(builder: (context, constraints) {
          final cellWidth = (constraints.maxWidth - 6 * 4) / 7;
          // Weeks this month actually needs — a February that starts on Sunday
          // is four rows, most months are five, and only a 31-day month
          // starting on Saturday is six.
          final rows = ((blanksBefore + daysInMonth) / 7).ceil();
          // What is left after the weekday initials, the list's bottom padding
          // and the gaps between rows.
          const chrome = 20.0 + 2 + 8;
          final free = availableHeight - chrome - (rows - 1) * _daySpacing;
          final cellHeight = (free / rows)
              .clamp(_dayCellMinHeight, _dayCellMaxHeight);
          final ratio = cellWidth / cellHeight;
          return loading
              // U-27: the grid's own shape, at its own aspect ratio — the month
              // does not jump into place when the days land.
              ? AppSkeletonCalendar(childAspectRatio: ratio)
              : _grid(context, ratio, daysInMonth, blanksBefore, todayIso);
        }),
      ],
    );
  }

  Widget _grid(BuildContext context, double ratio, int daysInMonth,
          int blanksBefore, String todayIso) =>
      GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            // 3 dp, not 4: five gaps in a six-week month, and the month has to
            // clear the admin strip on a 700 dp phone.
            mainAxisSpacing: _daySpacing,
            crossAxisSpacing: 4,
            childAspectRatio: ratio,
            children: [
              for (var i = 0; i < blanksBefore; i++) const SizedBox.shrink(),
              for (var day = 1; day <= daysInMonth; day++)
                _DayCell(
                  date: DateTime(month.year, month.month, day),
                  day: daysByIso[CareSchedule.isoDate(
                      DateTime(month.year, month.month, day))],
                  frozenMark: _markFor(
                      frozenByIso[CareSchedule.isoDate(
                          DateTime(month.year, month.month, day))],
                      AppL10n.of(context).l),
                  views: views,
                  isToday: CareSchedule.isoDate(
                          DateTime(month.year, month.month, day)) ==
                      todayIso,
                  isSelected: selectedIso.contains(CareSchedule.isoDate(
                      DateTime(month.year, month.month, day))),
                  onTap: onDayTap,
                  onLongPress: onDayLongPress,
                ),
            ],
          );
}

/// What a frozen day paints on its cell (computed in [_MonthGrid._markFor]).
class _FrozenMark {
  final String badge; // 🔔 (mine) · ⏳ (theirs)
  final bool overdue;
  final String label; // semantics — the web's badge title
  const _FrozenMark(
      {required this.badge, required this.overdue, required this.label});
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final CareSchedule? day;
  final _FrozenMark? frozenMark;
  final List<MemberView> views;
  final bool isToday;
  final bool isSelected;
  final void Function(DateTime) onTap;
  final void Function(DateTime) onLongPress;

  const _DayCell({
    required this.date,
    required this.day,
    required this.frozenMark,
    required this.views,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final assignment = day == null
        ? null
        : DayAssignment(
            scheduledParentId: day!.scheduledParentId,
            actualParentId: day!.actualParentId,
          );
    final paint = dayPaint(assignment, views);
    final slot = _slotOf(context, paint);
    final initial = parentInitial(assignment, views);
    final assigned = paint is! DayUnassigned;
    // The swap wears a dashed border instead of the slot's solid one — the
    // border IS the signal, so it cannot be drawn twice.
    final isSwapped = paint is DaySwapped;

    final primary = Theme.of(context).colorScheme.primary;
    final tokens = context.tokens;
    final l = AppL10n.of(context).l;

    // U-29 — the cell says to a screen reader what it paints for everyone
    // else. Colour was never the only vector VISUALLY (texture, initial), but
    // the grid was mute: a blind reader heard bare day numbers, and who is
    // responsible, the swap and the handoff time are the whole calendar.
    String? responsibleName;
    final effectiveId = assignment?.effectiveParentId;
    if (effectiveId != null) {
      for (final v in views) {
        if (v.id == effectiveId) {
          responsibleName = v.fullName;
          break;
        }
      }
    }
    final semanticsLabel = [
      '${date.day}',
      if (isToday) l[K.calToday],
      ?responsibleName,
      if (isSwapped) l[K.calSwapped],
      if (frozenMark != null)
        frozenMark!.label
      else if (day?.handoffTime != null)
        '${l[K.editorHandoffTime]} '
            '${l.formatTimeString(day!.handoffTime!)}',
    ].join(', ');

    return Semantics(
      button: true,
      selected: isSelected,
      label: semanticsLabel,
      // One node per cell: the inner texts (number, initial, time) would read
      // as loose fragments, and the composed label already carries them all.
      excludeSemantics: true,
      onTap: () => onTap(date),
      onLongPress: () => onLongPress(date),
      child: InkWell(
      onTap: () => onTap(date),
      // U-11: the mobile entry point to bulk selection (web: 500 ms press).
      onLongPress: () => onLongPress(date),
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.md),
              // U-28: "today" was a 2 px indigo hairline that vanished into a
              // tinted cell. It is the mark a reader looks for FIRST, so it
              // takes the text colour and real weight — the web's black ring.
              border: isSelected
                  ? Border.all(color: primary, width: 2)
                  : isToday
                      ? Border.all(color: tokens.text, width: 2.5)
                      : Border.all(
                          color: assigned && !isSwapped
                              ? slot.tone.border
                              : tokens.outline),
              color: isSelected
                  ? primary.withValues(alpha: 0.12)
                  : assigned
                      ? slot.tone.container
                      : null,
            ),
            child: CustomPaint(
              painter: assigned
                  ? SlotPatternPainter(slot.pattern, slot.tone.border)
                  : null,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${date.day}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          height: 1,
                          color: assigned ? slot.tone.onContainer : null)),
                  const SizedBox(height: 2),
                  CircleAvatar(
                    radius: 9,
                    backgroundColor:
                        assigned ? slot.tone.solid : Colors.transparent,
                    child: Text(initial,
                        style: TextStyle(
                            fontSize: 9,
                            height: 1,
                            color: assigned
                                ? slot.tone.onSolid
                                : Theme.of(context).hintColor)),
                  ),
                  // U-29 round 4 (owner): the same breath the date already
                  // gets above the avatar — without it the time sat glued to
                  // the initial. Gated, so a badge-less cell stays centred.
                  if (frozenMark != null || day?.handoffTime != null)
                    const SizedBox(height: 2),
                  // Web parity: the frozen badge REPLACES the handoff badge.
                  // (U-29: its label rides the CELL's semantics node now.)
                  if (frozenMark != null)
                    Container(
                      padding: frozenMark!.overdue
                          ? const EdgeInsets.symmetric(horizontal: 3)
                          : EdgeInsets.zero,
                      decoration: frozenMark!.overdue
                          ? BoxDecoration(
                              color: tokens.danger.container,
                              borderRadius: BorderRadius.circular(6),
                            )
                          : null,
                      child: Text(frozenMark!.badge,
                          style: const TextStyle(fontSize: 9)),
                    )
                  else if (day?.handoffTime != null)
                    // U-28: the TIME, not an anonymous swap arrow. The web
                    // prints "18:00" on every handoff day and the port replaced
                    // it with an icon that says a handoff exists but not when —
                    // which is the only thing a parent reads a handoff day for.
                    // (It is also what the square cell had no room for: the
                    // overflow the review caught was this line being clipped.)
                    Text(
                      AppL10n.of(context)
                          .l
                          .formatTimeString(day!.handoffTime!),
                      style: TextStyle(
                          fontSize: 9,
                          height: 1,
                          color: assigned
                              ? slot.tone.onContainer
                              : Theme.of(context).hintColor),
                    ),
                ],
              ),
            ),
          ),
          // Drawn over the fill so it survives the selected/today border,
          // which is the one thing allowed to outrank it.
          if (isSwapped && !isSelected && !isToday)
            CustomPaint(
              painter: DashedBorderPainter(
                  color: slot.tone.border, radius: Radii.md),
            ),
          // The web's corner mark on selected cells.
          if (isSelected)
            Positioned(
              top: 2,
              right: 2,
              child: Text('✓',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: primary)),
            ),
        ],
      ),
      ),
    );
  }
}
