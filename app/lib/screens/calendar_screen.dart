import 'dart:async';
import 'dart:math' as math;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import 'package:entrelares_db_contracts/models/care_schedule.dart';
import 'package:entrelares_db_contracts/models/child.dart';
import 'package:entrelares_db_contracts/models/child_event.dart';
import 'package:entrelares_db_contracts/models/day_notice.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import '../services/admin_mode.dart';
import '../services/analytics_service.dart';
import '../services/connectivity_status.dart';
import '../services/custody_data_source.dart';
import '../services/offline_cache.dart';
import '../theme/slot_pattern.dart';
import '../theme/tokens.dart';
import '../widgets/account_button.dart';
import '../widgets/admin_mode_offer.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/day_agenda.dart';
import '../widgets/slot_pill.dart';
import '../widgets/today_card.dart';
import 'bulk_sheet.dart';
import 'notice_sheet.dart';
import 'day_sheet.dart';
import 'handoff_range_sheet.dart';
import 'frozen_day_sheet.dart';
import 'quick_swap_sheet.dart';
import 'resolve_sheet.dart';
import '../services/handoff_nudge_prefs.dart';
import '../services/onboarding_service.dart';
import '../services/push_service.dart';
import '../services/push_today_prefs.dart';
import '../widgets/invitee_welcome_sheet.dart';
import '../widgets/onboarding.dart';
import '../widgets/person_chip.dart';
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
/// The floor is measurement, not taste: the content is 12 + 2 + 18 + 2 + 11 =
/// 45 dp with every line's height pinned, inside a 2.5 dp "today" ring — 50 dp
/// exactly ([DayCellType.compact.needs] at 1.0×, which `calendar_fits_u28_test`
/// holds to the floor). A six-week month with the admin strip on and a
/// four-carer legend has to fit a 700 dp phone, and the same test fails if
/// either side of that stops being true.
///
/// The ceiling exists so a five-week month on a tall phone does not turn each
/// day into a letterbox: past about 76 dp the cell is mostly empty and the grid
/// stops reading as a month. U-39: what a 76 dp cell IS allowed to spend the
/// room on is bigger type — [DayCellType.comfortable], resolved once per
/// month from the cell this range produced ([DayCellType.resolve]).
const double _dayCellMinHeight = 50;
const double _dayCellMaxHeight = 76;

/// The vertical gap between two week rows.
const double _daySpacing = 3;

/// U-40: what the empty-month strip costs the grid, so the cells shrink
/// (down to their floor) before the list has to scroll. One line of muted
/// text beside a compact text button, plus its top gap.
const double _emptyStripHeight = 48;

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

  /// T-18 — the app's connectivity state. The calendar dates what it shows
  /// here (the strip names that moment) and reloads the moment the server
  /// answers again. Null in tests that do not exercise it.
  final ConnectivityStatus? connectivity;

  /// T-18 — the device's copy of the current month. Written after every good
  /// load of it, read when the network fails with nothing on screen. Null in
  /// tests that do not exercise it (and disabled inside on the web).
  final OfflineCache? offlineCache;

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

  /// F-67 Part B: the free-tier gate on a past day beyond the 7-day reach
  /// sends the admin to `/family/plan` (U-49). Null leaves it a sentence.
  final VoidCallback? onOpenPlan;

  /// F-55: the agenda's "add the child" door (`/family/children`).
  final VoidCallback? onOpenChildren;

  /// F-95: Relatórios → Histórico, from a swapped day's story line.
  final VoidCallback? onOpenHistory;

  /// Owner's QA of 3.1.10: the Conversa, from the day sheet's read-only time.
  final VoidCallback? onOpenChat;

  /// F-07 (owner's QA, 29/09/2026): a carer's legend chip leads to the
  /// person — my profile, anyone's for an admin, the Família otherwise.
  final void Function(MemberLinkTarget target, int memberId)? onOpenMember;

  /// U-55: where the "Definir horário" strip's dismissal is kept on this
  /// device. Null (tests, hosts without storage) keeps it for the session.
  final HandoffNudgePrefs? handoffNudgePrefs;

  /// F-70: the plan-end notification's "Planejar os próximos meses" lands
  /// here with the day the wizard should open on. A notifier and not a route
  /// argument: this screen's State outlives the navigation inside the shell
  /// branch (go_router caches the page), so only a listenable reaches it (T-65).
  /// The screen consumes the value — it sets it back to null when it opens.
  final ValueNotifier<DateTime?>? planRequest;

  /// F-35: a day a Conversa text cited — the calendar goes to its month and
  /// opens that day's sheet once the month has loaded.
  final ValueNotifier<DateTime?>? dayRequest;

  /// F-59: this device's push, read for the *Ativar notificações* strip under
  /// the Hoje card. Null (tests, a host without push) shows no strip.
  final PushService? push;

  /// F-59: the U-51 browser facts (null in the native app), so the strip
  /// offers what THIS device can do — the same step Notificações shows.
  final BrowserInstallFacts? installFacts;

  /// F-59: where the strip's dismissals are kept on this device. Null keeps
  /// them for the session.
  final PushTodayPrefs? pushTodayPrefs;

  /// Owner's QA of 3.1.10: true while this screen shows one of its system
  /// strips ([_SystemStrip]) — the shell then holds back its own offers
  /// ("Abrir no app", the install invitation), so the calendar never carries
  /// more than one.
  final ValueNotifier<bool>? systemStripShowing;

  /// F-70: the plan-end strip, for tests.
  static const planEndStripKey = Key('plan-end-strip');

  /// F-59: the *Ativar notificações* strip, for tests.
  static const pushTodayKey = Key('push-today');

  /// F-07: the lane chips.
  static const laneChipsKey = Key('lane-chips');

  /// U-60: the ⋮ "Pedir troca de um dia" and the Hoje card's strip of the
  /// requests waiting for the reader's answer.
  static const askSwapMenuKey = Key('ask-swap-menu');
  static const requestStripKey = Key('request-strip');

  /// F-94: today's request, still unanswered, on the Hoje card.
  static const pendingTodayStripKey = Key('pending-today-strip');

  /// F-98: the Hoje card's own "Avisar" for whoever may send one today.
  static const noticeQuickActionKey = Key('notice-quick-action');

  const CalendarScreen(
      {super.key,
      required this.dataSource,
      required this.adminMode,
      this.connectivity,
      this.offlineCache,
      this.onboarding,
      this.tourKeys,
      this.analytics,
      this.onOpenFamily,
      this.onOpenNotifications,
      this.onOpenPlan,
      this.onOpenChildren,
      this.onOpenHistory,
      this.onOpenChat,
      this.onOpenMember,
      this.handoffNudgePrefs,
      this.push,
      this.installFacts,
      this.pushTodayPrefs,
      this.systemStripShowing,
      this.planRequest,
      this.dayRequest});

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

  /// T-76 — whether this family already has an invitation waiting to be
  /// accepted. Read inside the load, and only when the F-31 precondition
  /// holds, so the card paints its final answer on the first frame instead of
  /// flashing the nudge at somebody who already invited the other caregiver.
  bool _openInvitation = false;
  bool _tourShown = false;

  /// U-58 — the welcome sheet is up; the tour waits for it.
  bool _welcomeOpen = false;

  /// U-55: the strip was sent away in THIS session (the prefs keep it for
  /// good; this covers a host without them and the frame before the write).
  bool _handoffNudgeDismissed = false;

  /// F-59: what the server said about this account's push, and the strip's
  /// dismissal in THIS session (the prefs keep the rhythm across openings).
  ({bool accountHasPush, DateTime? newestUnreadAt})? _pushReach;
  DateTime? _pushTodayDismissedAt;
  // Today + the next-handoff window ([today, today + 91] — the web scans
  // [tomorrow, tomorrow + 90]; one query serves the card's row and the scan).
  List<CareSchedule> _upcoming = const [];

  /// F-52: every aviso about today, open or closed, newest first. The strip
  /// under the Hoje card reads the OPEN ones; the closed ones are kept so a
  /// cancellation stops showing the instant the load returns.
  List<DayNotice> _todayNotices = const [];

  /// U-60: every open request waiting for MY answer, any date — the Hoje
  /// card names them (it was only a badge on the Comunicação tab).
  List<SwapRequest> _pendingForMe = const [];

  /// F-52: yesterday's row, for the "who handed over today" end of the sender
  /// rule. Fetched on its own because `_upcoming` starts at today.
  CareSchedule? _yesterdayRow;
  // F-12: the visible month's OPEN swap requests — the frozen-day source
  // (paint, guards, panel). Keyed alongside _daysByIso on every load.
  Map<String, SwapRequest> _frozenByIso = const {};

  // ── F-07: the plan per child ──
  /// Every row of the visible month, EVERY lane — [_daysByIso] and
  /// [_frozenByIso] are the view of them the screen shows ([_applyLaneView]).
  List<CareSchedule> _monthRows = const [];
  List<SwapRequest> _monthFrozen = const [];
  List<CareSchedule> _upcomingRows = const [];

  /// The family's children, in their order — read only for a per-child plan.
  List<Child> _children = const [];

  /// F-07 (PR 5c): yesterday in every lane — the aviso's second end, per
  /// child. Read only for a per-child plan ([_yesterdayRow] is the family's).
  List<CareSchedule> _yesterdayRows = const [];

  /// The lane on screen in a per-child family: a child, or null for *Todas*.
  int? _lane;

  /// *Todas*: the dates whose children are with different carers, each with
  /// every lane's row — the cell paints the split, a tap asks which child.
  Map<String, List<CareSchedule>> _divergentByIso = const {};

  bool get _perChild => (_family?.isPerChild ?? false) && _children.isNotEmpty;

  String? _childName(int? id) =>
      _children.where((c) => c.id == id).firstOrNull?.firstName;

  /// Derives what the grid, the sheets and the today card read from the
  /// month's rows and the lane on screen. A single-plan family gets exactly
  /// what it always had: its rows are all in the family lane.
  void _applyLaneView() {
    final lane = _perChild ? _lane : null;
    final order = [for (final c in _children) c.id];
    final days = LaneViewRules.view<CareSchedule>(
      rows: _monthRows,
      isoOf: (d) => CareSchedule.isoDate(d.scheduleDate),
      childOf: (d) => d.childId,
      effectiveOf: (d) => d.effectiveParentId,
      lane: lane,
      childOrder: order,
    );
    // Web parity (Home's frozenRequests.First per day): one request per date
    // and lane — the DB's one-pending-per-date-per-lane index guarantees it.
    final frozen = LaneViewRules.view<SwapRequest>(
      rows: _monthFrozen,
      isoOf: (r) => CareSchedule.isoDate(r.scheduleDate),
      childOf: (r) => r.childId,
      effectiveOf: (r) => r.proposedActualParentId,
      lane: lane,
      childOrder: order,
    );
    final upcoming = LaneViewRules.view<CareSchedule>(
      rows: _upcomingRows,
      isoOf: (d) => CareSchedule.isoDate(d.scheduleDate),
      childOf: (d) => d.childId,
      effectiveOf: (d) => d.effectiveParentId,
      lane: lane,
      childOrder: order,
    );
    _daysByIso = days.byIso;
    _divergentByIso = _perChild && lane == null ? days.divergent : const {};
    // F-07 (owner's QA, 29/09/2026): a child's lane marks only that child's
    // items and the family's notes; Todas marks them all.
    _agendaByIso = _groupAgenda([
      for (final e in _monthEvents)
        if (lane == null || e.childId == null || e.childId == lane) e,
    ]);
    _frozenByIso = frozen.byIso;
    _upcoming = upcoming.byIso.values.toList()
      ..sort((a, b) => a.scheduleDate.compareTo(b.scheduleDate));
  }

  bool _loading = true;

  /// F-51: the Realtime burst of a range operation folds into one reload.
  Timer? _changeDebounce;
  static const _changeDebounceWindow = Duration(milliseconds: 300);
  String? _loadError;

  /// T-18: the month [_daysByIso] and [_frozenByIso] were last read for.
  /// Offline, a failed reload of THAT month keeps what is on screen — the strip
  /// dates it — while any other month has nothing to show and says so.
  DateTime? _loadedMonth;
  bool _wasOffline = false;
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

  /// F-67 Part B: handed to the sheets ONLY for a real admin — a sheet with
  /// no offerer never asks, which is the whole "a non-admin never sees the
  /// question" rule.
  AdminModeOfferer? get _adminOfferer => _ownProfile?.isAdmin == true
      ? AdminModeOfferer(
          adminMode: widget.adminMode,
          analytics: widget.analytics,
          onOpenPlan: widget.onOpenPlan)
      : null;

  /// The F-40 entitlement the day sheet's gate reads: null when the read
  /// failed, so no client-side limit is guessed.
  bool? get _isPremiumForGate => _entitlementFailed
      ? null
      : Family.isPremiumFamily(_family, DateTime.now().toUtc());

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
    // F-59: the strip follows the push state — enabling it on Notificações
    // (the State lives on in the tab stack) takes it away here too.
    widget.push?.addListener(_onPushChanged);
    _wasOffline = widget.connectivity?.offline ?? false;
    widget.connectivity?.addListener(_onConnectivityChanged);
    // T-18: a boot that already knows there is no network paints the device's
    // copy at once, instead of a skeleton for the ~7 s postgrest spends
    // retrying. The load runs alongside and wins the moment the server answers.
    if (_wasOffline) unawaited(_adoptCopyOf(_visibleMonth));
    _load();
    _loadHorizonInputs();
    _watch();
    _schedulePoll();
    widget.planRequest?.addListener(_onPlanRequest);
    // The branch may be built by the very navigation that carries the request.
    if (widget.planRequest?.value != null) _onPlanRequest();
    widget.dayRequest?.addListener(_onDayRequest);
    if (widget.dayRequest?.value != null) _onDayRequest();
  }

  /// F-35: the day a cited Conversa text asked for, held until a load that
  /// STARTED after the request has put its month on screen.
  DateTime? _pendingDay;

  /// Every [_load] takes the next number. A cited day opens only on a load
  /// numbered above [_pendingDayAfter]: the swap it names is usually minutes
  /// old, and a month read before it (or an older poll finishing late, for
  /// the previous month) would open the day as if nothing were pending —
  /// editable on the first tap, the owner's validation of 25/09/2026.
  int _loadSeq = 0;
  int _pendingDayAfter = 0;

  /// U-60: the queued day opens with the swap request armed (the ⋮ entry).
  bool _pendingAskSwap = false;

  void _onDayRequest() {
    final day = widget.dayRequest?.value;
    if (day == null) return;
    widget.dayRequest!.value = null;
    _queueDay(day);
  }

  /// Puts [day]'s month on screen and opens the day once a load that started
  /// after this call has read it — the cited day's path (F-35), and since
  /// U-60 the ⋮ "Pedir troca de um dia".
  void _queueDay(DateTime day, {bool askSwap = false}) {
    _pendingDay = DateTime(day.year, day.month, day.day);
    _pendingAskSwap = askSwap;
    _pendingDayAfter = _loadSeq;
    final month = DateTime(day.year, day.month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if ((month.year != _visibleMonth.year ||
              month.month != _visibleMonth.month) &&
          _pageController.hasClients) {
        // The page change loads the cited month itself.
        _pageController.jumpToPage(_pageForMonth(month));
      } else {
        _load(silent: true);
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _openPendingDay(int completedLoad) {
    final day = _pendingDay;
    if (day == null || !mounted || completedLoad <= _pendingDayAfter) return;
    if (!_isOnScreen(DateTime(day.year, day.month))) return;
    _pendingDay = null;
    final askSwap = _pendingAskSwap;
    _pendingAskSwap = false;
    // The same action a tap on the cell takes: a day with a pending request
    // opens the approval panel, anything else the day sheet.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openDayAsTapped(day, askSwap: askSwap);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// F-70: the family's last planned day, read with every load (best-effort).
  DateTime? _lastPlannedDay;

  /// F-55 on the grid (owner's validation, 25/09/2026): each day's live
  /// agenda items, in the day sheet's order, for the month on screen.
  Map<String, List<ChildEvent>> _agendaByIso = const {};

  /// F-07: the month's agenda items, every child — [_agendaByIso] is the
  /// lane's view of them ([_applyLaneView]).
  List<ChildEvent> _monthEvents = const [];
  void Function()? _unwatchAgenda;

  /// F-70: the day a plan-end notification asked the wizard to open on, held
  /// until the month has loaded — the wizard needs the members to offer.
  DateTime? _pendingPlanStart;

  void _onPlanRequest() {
    final start = widget.planRequest?.value;
    if (start == null) return;
    widget.planRequest!.value = null;
    _pendingPlanStart = start;
    _openPendingPlan();
  }

  void _openPendingPlan() {
    final start = _pendingPlanStart;
    if (start == null || _loading || !mounted) return;
    if (_iAmViewer) {
      _pendingPlanStart = null;
      return;
    }
    _pendingPlanStart = null;
    // A notifier write schedules no frame by itself, so ask for one — or the
    // callback waits for the next unrelated repaint.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openWizard(start: start);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  /// Whether the screen is visible and wants fresh data — separate from
  /// [_pollTimer], which is null ALSO when the healthy poll is off (T-83): a
  /// socket that drops must still bring the degraded poll back.
  bool _polling = false;

  void _schedulePoll() {
    _polling = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    final ms = pollIntervalMs(
        socketConnected: _socketConnected, settings: _settings);
    if (ms == null) return; // T-83: healthy socket, poll turned off
    _pollTimer = Timer(Duration(milliseconds: ms), () {
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
      _loadHorizonInputs();
      _schedulePoll();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _polling = false;
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _onAdminModeChanged() {
    if (mounted) setState(() {});
  }

  bool get _offline => widget.connectivity?.offline ?? false;

  bool _isOnScreen(DateTime month) =>
      _loadedMonth != null &&
      _loadedMonth!.year == month.year &&
      _loadedMonth!.month == month.month;

  /// T-18 — fills whatever is still empty from the device's copy. Only the
  /// month the copy is FOR fills the grid, and only while nothing real holds
  /// it: the read is async, and a copy arriving after the server answered
  /// must lose. The members, the profile and the upcoming window fill the
  /// legend and the today card whatever month is on screen — at the turn of
  /// the month the card is the whole point.
  ///
  /// Returns whether [month] is on screen afterwards.
  Future<bool> _adoptCopyOf(DateTime month) async {
    final snap = await widget.offlineCache?.read();
    if (!mounted) return false;
    if (snap == null || _isOnScreen(month)) return _isOnScreen(month);
    final fillsGrid = snap.isFor(month) && month == _visibleMonth;
    setState(() {
      if (_members.isEmpty) _members = snap.members;
      if (_roles.isEmpty) _roles = snap.roles;
      _ownProfile ??= snap.ownProfile;
      if (_upcomingRows.isEmpty) _upcomingRows = snap.upcoming;
      if (fillsGrid) {
        _monthRows = snap.days;
        _monthFrozen = snap.frozen;
        _loadedMonth = month;
        _loading = false;
        _loadError = null;
      }
      _applyLaneView();
    });
    // U-28: the account button in every tab's app bar wears the profile — from
    // the copy too, or an offline boot shows a "?" where the reader's initial
    // belongs (T-18 device measurement, 14/09/2026).
    final own = _ownProfile;
    if (own != null) {
      AccountScope.identityOf(context)
          ?.adopt(fullName: own.fullName, colorSlot: own.colorSlot);
    }
    // The strip dates what is on screen: the copy, unless a newer real read is
    // already there.
    if (widget.connectivity?.value.dataAsOf == null || fillsGrid) {
      widget.connectivity?.loadedData(snap.savedAt);
    }
    return fillsGrid;
  }

  /// T-18 — refresh on reconnect. Any response from the server (another tab's
  /// read, the badge, a push registration) ends the offline state, and the plan
  /// on screen is the first thing that should stop being old.
  void _onConnectivityChanged() {
    final offline = widget.connectivity!.offline;
    final reconnected = _wasOffline && !offline;
    _wasOffline = offline;
    if (reconnected && mounted) _load(silent: true);
  }

  /// Whether [_settings] holds a real read. The seeded fallbacks keep every
  /// `feature.*` flag OFF, so a read that failed at start-up — the first one
  /// of a cold start races the session refresh — hid the agenda for the whole
  /// session: this used to run once, from initState (validation, 25/09/2026).
  bool _settingsRead = false;
  bool _horizonInFlight = false;

  /// A read asked for while one was in flight — it runs when that one ends.
  bool _horizonAgain = false;

  /// The retry of a failed settings read, on its own clock. Owner's second
  /// validation round, 25/09/2026: retrying only from [_load] was not enough —
  /// with a healthy socket and the healthy poll off (T-83) the next load may
  /// never come, and a retry asked for while the first read still hung was
  /// dropped. The agenda stayed off until the app restarted, again.
  Timer? _settingsRetry;
  int _settingsAttempt = 0;
  static const List<int> _settingsBackoffSeconds = [2, 5, 10, 30, 60];

  void _scheduleSettingsRetry() {
    if (_settingsRead || _settingsRetry != null || !mounted) return;
    final i = _settingsAttempt < _settingsBackoffSeconds.length
        ? _settingsAttempt
        : _settingsBackoffSeconds.length - 1;
    _settingsAttempt++;
    _settingsRetry = Timer(Duration(seconds: _settingsBackoffSeconds[i]), () {
      _settingsRetry = null;
      if (mounted && !_settingsRead) _loadHorizonInputs();
    });
  }

  /// Defensive like the web: neither read may break the calendar — entitlement
  /// falls to premium, settings to the seeded fallbacks (no wrongful block).
  /// A failed settings read retries by itself (2, 5, 10, 30 s, then every
  /// minute) until it lands; every [_load] and every resume read again too (an
  /// operator's kill switch reaches an open app).
  Future<void> _loadHorizonInputs() async {
    if (_horizonInFlight) {
      _horizonAgain = true;
      return;
    }
    _horizonInFlight = true;
    try {
      Family? family;
      var failed = false;
      try {
        family = await widget.dataSource.fetchOwnFamily();
      } catch (_) {
        failed = true;
      }
      PublicSettings? settings;
      try {
        final values = await widget.dataSource.fetchPublicSettings();
        // An empty answer is RLS saying "no session yet", not a table with
        // no rows — it is a failed read, and it keeps the last good one.
        if (values.isNotEmpty) settings = PublicSettings(values);
      } catch (_) {/* seeded fallbacks, retried by the next load */}
      if (!mounted) return;
      // The month's agenda marks wait on this flag: a first read that lands
      // after the first load reloads once, so the marks do not wait a poll.
      final agendaTurnedOn = settings != null &&
          settings.childAgendaEnabled &&
          !_settings.childAgendaEnabled;
      // F-07: a switch of the plan's mode (here or on another device) needs
      // the children and the lanes — the next load reads them.
      final modeChanged = !failed &&
          (family?.isPerChild ?? false) != (_family?.isPerChild ?? false);
      setState(() {
        if (!failed || _family == null) {
          _family = family;
          _entitlementFailed = failed;
        }
        if (settings != null) {
          _settings = settings;
          _settingsRead = true;
        }
      });
      if ((agendaTurnedOn || modeChanged) && _loadedMonth != null) {
        _load(silent: true);
      }
    } finally {
      _horizonInFlight = false;
      if (mounted) {
        if (_settingsRead) {
          _settingsAttempt = 0;
          _settingsRetry?.cancel();
          _settingsRetry = null;
        }
        if (_horizonAgain) {
          _horizonAgain = false;
          unawaited(_loadHorizonInputs());
        } else {
          _scheduleSettingsRetry();
        }
      }
    }
  }

  /// The month's live items per day, in the day sheet's order — the first
  /// one is the one the cell draws.
  static Map<String, List<ChildEvent>> _groupAgenda(List<ChildEvent> events) {
    final byIso = <String, List<ChildEvent>>{};
    for (final e in events) {
      if (e.isDeleted) continue;
      (byIso[CareSchedule.isoDate(e.eventDate)] ??= []).add(e);
    }
    return {
      for (final entry in byIso.entries)
        entry.key: AgendaRules.timeline(
          entry.value,
          (e) => AgendaEntry(
            id: e.id,
            kind: AgendaKind.parse(e.kind) ?? AgendaKind.other,
            start: e.startTime,
            end: e.endTime,
            createdAt: e.createdAt,
          ),
        ),
    };
  }

  Future<void> _watch() async {
    // Native Realtime — the whole reason F-29's JS bridge retires. Any change
    // another member saves shows up here without polling. The socket's health
    // drives the F-23 poll cadence.
    _unwatch = await widget.dataSource.watchChanges(
      () {
        // F-51: a range operation is ONE statement on the server but N
        // Realtime events on every device — one per row, in a burst, and
        // `_load` has no in-flight guard. The bulk paths already produced
        // such bursts (one event per day saved); a year's re-plan makes it
        // ~730. Coalesce the burst into one reload after it goes quiet.
        _changeDebounce?.cancel();
        _changeDebounce = Timer(_changeDebounceWindow, () {
          if (mounted) _load(silent: true);
        });
      },
      onStatus: (connected) {
        if (!mounted) return;
        // T-18: the socket coming back while the app is offline is the first
        // sign of the network — try the plan now instead of at the next poll.
        if (connected && (widget.connectivity?.offline ?? false)) {
          _load(silent: true);
        }
        if (connected != _socketConnected) {
          _socketConnected = connected;
          if (_polling) _schedulePoll();
        }
      },
    );
    // F-55: an agenda item written on another device marks its day here.
    try {
      _unwatchAgenda = await widget.dataSource.watchAgendaChanges(() {
        _changeDebounce?.cancel();
        _changeDebounce = Timer(_changeDebounceWindow, () {
          if (mounted) _load(silent: true);
        });
      });
    } catch (_) {/* the poll and the next load still read it */}
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
    widget.push?.removeListener(_onPushChanged);
    widget.connectivity?.removeListener(_onConnectivityChanged);
    widget.planRequest?.removeListener(_onPlanRequest);
    widget.dayRequest?.removeListener(_onDayRequest);
    _unwatch?.call();
    _unwatchWorkflow?.call();
    _unwatchAgenda?.call();
    _pollTimer?.cancel();
    _changeDebounce?.cancel();
    _settingsRetry?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) =>
      DateTime(_anchorMonth.year, _anchorMonth.month + (page - _basePage), 1);

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final seq = ++_loadSeq;
    // Captured once: a swipe during the load must not date one month's rows
    // as another's.
    final month = _visibleMonth;
    if (!_settingsRead) unawaited(_loadHorizonInputs());
    try {
      final members = await widget.dataSource.fetchMembers();
      // Best-effort: a family whose roles fail to load still gets its
      // calendar, just without the "(Mãe)" suffix.
      List<Role> roles = _roles;
      try {
        roles = await widget.dataSource.fetchRoles();
      } catch (_) {/* keep whatever we had */}
      final days = await widget.dataSource.fetchMonth(month.year, month.month);
      final frozen = await widget.dataSource
          .fetchFrozenRequestsForMonth(month.year, month.month);
      final ownProfile = await widget.dataSource.fetchOwnProfile();
      final upcoming = await widget.dataSource
          .fetchUpcoming(_today, nextHandoffWindowDays + 1);
      // T-76: the nudge's own fact, asked only when the nudge could show at
      // all — a family whose second seat is filled never pays for the read.
      // It rides INSIDE the load for the same reason the rule refuses to run
      // while loading: an answer that arrives after the frame is a prompt
      // that blinks.
      final nudgeApplies = inviteNudgeApplies(
        isLoading: false,
        isAdmin: ownProfile?.isAdmin ?? false,
        activeMemberCount: members.where((m) => !m.hasLeft).length,
      );
      var openInvitation = false;
      if (nudgeApplies) {
        try {
          openInvitation = await widget.dataSource.hasOpenInvitation();
        } catch (_) {
          // Best-effort, and it fails towards SHOWING: the growth loop's only
          // prompt must not disappear because one bounded read did. The worst
          // case is an admin told to invite somebody they already invited.
        }
      }
      // F-52: today's avisos, and yesterday's row — the second end of a
      // handover happening today. `_upcoming` starts at today, so yesterday is
      // in `_daysByIso` on most days and MISSING on the 1st of a month; a
      // carer whose eligibility depends on it would silently lose the action
      // once a month, which is exactly the kind of defect nobody reports.
      // Both reads are best-effort: a calendar must not fail to draw because
      // an aviso could not be counted.
      // F-70: the plan-end strip's one fact. Best-effort like the avisos: a
      // calendar must not fail to draw because the strip could not decide.
      var lastPlannedDay = _lastPlannedDay;
      try {
        lastPlannedDay = await widget.dataSource.fetchLastPlannedDay();
      } catch (_) {/* keep whatever we had */}
      // F-55: the month's agenda marks. Best-effort like the avisos, and
      // asked only while the module is on for this family.
      var monthEvents = _monthEvents;
      if (_settings.childAgendaEnabled) {
        try {
          monthEvents = await widget.dataSource.fetchChildEvents(
              DateTime(month.year, month.month, 1),
              DateTime(month.year, month.month + 1, 0));
        } catch (_) {/* keep whatever we had */}
      } else {
        monthEvents = const [];
      }
      // F-07: the children name the lanes; read only for a per-child plan.
      var children = _children;
      var yesterdayRows = _yesterdayRows;
      if (_family?.isPerChild ?? false) {
        try {
          children = await widget.dataSource.fetchChildren();
          yesterdayRows = await widget.dataSource.fetchUpcoming(
              DateTime(_today.year, _today.month, _today.day - 1), 0);
        } catch (_) {/* keep whatever we had */}
      } else {
        children = const [];
        yesterdayRows = const [];
      }
      // U-60: best-effort like the avisos — the strip may wait for the next
      // load, the calendar may not.
      var pendingForMe = _pendingForMe;
      if (ownProfile != null && !ownProfile.isViewer) {
        try {
          pendingForMe = await widget.dataSource.fetchPendingForMe(ownProfile.id);
        } catch (_) {/* keep whatever we had */}
      } else {
        pendingForMe = const [];
      }
      var todayNotices = _todayNotices;
      var yesterdayRow = _yesterdayRow;
      try {
        todayNotices = await widget.dataSource.fetchDayNotices(_today);
        yesterdayRow = await widget.dataSource
            .fetchDay(DateTime(_today.year, _today.month, _today.day - 1));
      } catch (_) {/* keep whatever we had */}
      if (!mounted) return;
      setState(() {
        _members = members;
        _roles = roles;
        _monthRows = days;
        _monthFrozen = frozen;
        _children = children;
        _yesterdayRows = yesterdayRows;
        if (_lane != null && !children.any((c) => c.id == _lane)) _lane = null;
        _ownProfile = ownProfile;
        _upcomingRows = upcoming;
        _applyLaneView();
        _todayNotices = todayNotices;
        _pendingForMe = [
          for (final r in pendingForMe)
            if (!dateOnly(r.scheduleDate).isBefore(dateOnly(_today))) r
        ]..sort((a, b) => a.scheduleDate.compareTo(b.scheduleDate));
        _yesterdayRow = yesterdayRow;
        _lastPlannedDay = lastPlannedDay;
        _monthEvents = monthEvents;
        _applyLaneView();
        _loadedMonth = month;
        _openInvitation = openInvitation;
        _loading = false;
        _loadError = null;
      });
      _openPendingPlan();
      _openPendingDay(seq);
      final readAt = DateTime.now();
      widget.connectivity?.loadedData(readAt);
      // T-18: only the CURRENT month is worth a device copy — the door-of-the-
      // school moment is today and this week, and one month keeps the copy
      // small and its purpose obvious.
      if (isCurrentMonth(month, _today)) {
        unawaited(widget.offlineCache?.save(OfflineCalendarSnapshot(
          savedAt: readAt,
          month: month,
          members: members,
          roles: roles,
          days: days,
          frozen: frozen,
          ownProfile: ownProfile,
          upcoming: upcoming,
        )));
      }
      // U-28: the account button in every tab's app bar wears this.
      AccountScope.identityOf(context)?.adopt(
          fullName: ownProfile?.fullName, colorSlot: ownProfile?.colorSlot);
      unawaited(_refreshOnboarding(ownProfile, members));
      if (ownProfile != null) unawaited(_loadPushReach(ownProfile.id));
      // T-76 — the impression the Flutter port lost: `invite_nudge_shown` fed
      // Umami until the 23/08/2026 cutover and then simply stopped, leaving
      // the one loop that brings a new adult into the product unmeasured.
      // Fired where the answer is KNOWN (never from `build`) and once per app
      // session, the scope the pre-cutover series was counted in.
      if (nudgeApplies && !openInvitation) {
        final analytics = widget.analytics;
        if (analytics != null) {
          unawaited(analytics.trackEventOnce(AnalyticsEvents.inviteNudgeShown,
              props: analyticsFunnelProps(channel: analytics.channel)));
        }
      }
    } catch (e) {
      if (!mounted) return;
      final l = AppL10n.of(context).l;
      final raw = e.toString();
      final offline = isNetworkFailure(raw);
      var monthOnScreen = _isOnScreen(month);
      if (offline && !monthOnScreen) {
        monthOnScreen = await _adoptCopyOf(month);
        if (!mounted) return;
      }
      setState(() {
        _loading = false;
        // T-18: before, the F-23 poll's first failure with no signal replaced
        // a perfectly good month with an error banner — the calendar went
        // blank at the exact moment the reader needed it. What was read stays;
        // the shell's strip says how old it is.
        if (offline && monthOnScreen) {
          _loadError = null;
          return;
        }
        _loadError = isSessionExpired(raw)
            ? sessionExpiredMessage(l)
            : offline
                ? l[KApp.offlineMonthNotLoaded]
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

  /// Owner's QA of 3.1.10 (06/10/2026) — ONE system strip at a time over the
  /// calendar. On a first opening the notifications offer, the checklist, the
  /// handoff nudge and the shell's "Abrir no app" all stood above the grid
  /// and left it a single week. The order is the owner's: notifications, then
  /// the first steps, then the rest; the next one shows once the one before
  /// is answered or sent away. The day's own strips (a request, an aviso) are
  /// not in this queue — they are about today.
  _SystemStrip? get _systemStrip {
    if (_showPushToday) return _SystemStrip.pushToday;
    if (_showChecklist) return _SystemStrip.checklist;
    if (_showHandoffNudge) return _SystemStrip.handoffNudge;
    return null;
  }

  /// Tells the shell, after the frame, whether a system strip is on screen.
  void _reportSystemStrip(bool showing) {
    final notifier = widget.systemStripShowing;
    if (notifier == null || notifier.value == showing) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) notifier.value = showing;
    });
  }

  bool get _showChecklist {
    final signals = _effectiveSignals;
    if (signals == null || _loading || _iAmViewer) return false;
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

    // U-58: the invitee's welcome comes FIRST, only in the session where the
    // invitation was claimed (taken once), and the tour follows it. While it
    // is open a poll's refresh must not start the tour over it.
    final welcome = onboarding.takeInviteeWelcome();
    if (welcome != null) {
      _welcomeOpen = true;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final analytics = widget.analytics;
      if (analytics != null) {
        unawaited(analytics.trackEventOnce(AnalyticsEvents.inviteeWelcomeView,
            props: {
              'channel': analytics.channel,
              'member': InviteeWelcomeRules.memberProp(viewer: me.isViewer),
            }));
      }
      await showInviteeWelcomeSheet(context,
          welcome: welcome, viewer: me.isViewer);
      _welcomeOpen = false;
      if (!mounted) return;
    }

    // The tour runs ONCE, on the first authenticated session, and hands over
    // to the checklist when it ends — the web's FinishTour does the same.
    // (Explicit replays arrive through [_onTourReplayRequested] now.)
    if (!_tourShown &&
        !_welcomeOpen &&
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
      showAppSnack(context, _horizonSentence(AppL10n.of(context).l));
      _bounceBack();
      return;
    }
    // F-100: a selection SURVIVES the month change — a school vacation runs
    // from December into January. The month being left is remembered, so
    // the sheets still know its days.
    if (_isSelectionMode) {
      _selectionDays.addAll(_daysByIso);
      _selectionFrozen.addAll(_frozenByIso);
    }
    setState(() => _visibleMonth = month);
    _load();
  }

  /// The F-39 tier message — the paging bounce's snack, and the sentence the
  /// U-40 strip prints when the month on screen fell beyond the horizon.
  String _horizonSentence(Localization l) => _isPremiumForPaging
      ? l.format(K.horizonPremium, [_settings.calendarMonthsPremium])
      : l.format(K.horizonFree, [
          _settings.calendarMonthsFree,
          _settings.calendarMonthsPremium,
        ]);

  /// U-40: what the visible month says under its grid. Decided in core;
  /// the load error branch never reaches the grid, so it is not an input.
  EmptyMonthPrompt get _emptyPrompt => emptyMonthPrompt(
        visibleMonth: _visibleMonth,
        today: _today,
        horizonDate: _horizonDate,
        hasPlannedDays: _daysByIso.isNotEmpty,
        loading: _loading,
      );

  List<MemberView> get _memberViews =>
      _members.map((m) => m.toView()).toList(growable: false);

  /// F-56: who a day can be planned for — active members AND pending ones
  /// (invited, not yet joined). Only the S-11 tombstone is left out. The
  /// swap workflow is a different question, answered per day by the sheet.
  List<Member> get _assignableMembers =>
      _members.where((m) => !m.hasLeft && !m.isViewer).toList();

  /// F-50: I am a Visualizador — the calendar reads, and offers nothing to
  /// write (the server refuses it anyway).
  bool get _iAmViewer => _ownProfile?.isViewer == true;

  void _toggleDaySelection(DateTime date) {
    final d = dateOnly(date);
    setState(() {
      // F-100: the first tap after the long press closes the range.
      final anchor = _rangeAnchor;
      _rangeAnchor = null;
      if (anchor != null && d != anchor && !_selectedDays.contains(d)) {
        _selectedDays.addAll(selectionRange(anchor, d, horizon: _horizonDate));
        return;
      }
      if (!_selectedDays.remove(d)) _selectedDays.add(d);
      if (_selectedDays.isEmpty) _forgetSelectionMonths();
    });
  }

  /// F-100: the day a long press started a range from (cleared by the tap
  /// that closes it, or by any other tap).
  DateTime? _rangeAnchor;

  /// F-100: the days and open requests of the months the selection already
  /// crossed — the sheets read a selection that spans months from these plus
  /// the month on screen.
  final Map<String, CareSchedule> _selectionDays = {};
  final Map<String, SwapRequest> _selectionFrozen = {};

  Map<String, CareSchedule> get _selDaysByIso =>
      {..._selectionDays, ..._daysByIso};
  Map<String, SwapRequest> get _selFrozenByIso =>
      {..._selectionFrozen, ..._frozenByIso};

  void _forgetSelectionMonths() {
    _rangeAnchor = null;
    _selectionDays.clear();
    _selectionFrozen.clear();
  }

  /// F-07 (owner's QA, 29/09/2026) — *Todas* reads, a child's lane writes.
  /// A write started in *Todas* says to pick the child above, and returns
  /// true when it did (the caller stops).
  bool _refuseWriteInTodas() {
    if (!_perChild || _lane != null) return false;
    showAppSnack(context, AppL10n.of(context).l[KApp.calLanePickFirst]);
    return true;
  }

  void _selectLane(int? lane) {
    if (lane == _lane) return;
    setState(() {
      _lane = lane;
      // A selection belongs to the lane it was made in.
      _selectedDays.clear();
      _forgetSelectionMonths();
      _applyLaneView();
    });
  }

  /// Mirror of LongPressDay: entering selection always ADDS the day.
  Future<void> _onDayLongPress(DateTime date) async {
    if (_iAmViewer) return;
    if (_refuseWriteInTodas()) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedDays.add(dateOnly(date));
      // F-100: the range's first day — the next tap is its last.
      _rangeAnchor = dateOnly(date);
    });
  }

  void _onDayTap(DateTime date) {
    if (_isSelectionMode) {
      HapticFeedback.selectionClick();
      _toggleDaySelection(date);
      return;
    }
    _openDayAsTapped(date);
  }

  /// What a tap on [date]'s cell opens — also a day cited in the Conversa.
  Future<void> _openDayAsTapped(DateTime date, {bool askSwap = false}) async {
    // F-07: in *Todas* the day is every child's — read it whole.
    if (_perChild && _lane == null) {
      await _openAllChildrenDay(date);
      return;
    }
    // Web parity (HandleDayClick): a day with a pending request opens the
    // frozen panel instead of the editor — for everyone, admins included.
    final frozen = _frozenByIso[CareSchedule.isoDate(date)];
    if (frozen != null) {
      _openFrozenDay(frozen);
      return;
    }
    _openDay(date, askSwap: askSwap);
  }

  /// U-60: "Pedir troca de um dia" — which day, then that day's sheet with
  /// the request armed: the SAME sheet and field a tap on the cell opens.
  Future<void> _askSwapFromMenu() async {
    if (_refuseWriteOffline() || _refuseWriteInTodas()) return;
    final l = AppL10n.of(context).l;
    final today = dateOnly(_today);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: DateTime(today.year + 2, 12, 31),
      helpText: l[KApp.calAskSwapPick],
    );
    if (picked == null || !mounted) return;
    _queueDay(picked, askSwap: true);
  }

  Future<void> _openFrozenDay(SwapRequest request) async {
    HapticFeedback.selectionClick();
    final iso = CareSchedule.isoDate(request.scheduleDate);
    final outcome = await showFrozenDaySheet(
      context: context,
      request: request,
      allProfiles: _members,
      ownProfileId: _ownProfile?.id,
      dataSource: widget.dataSource,
      offline: _offline,
      // F-95: the frozen day's own content, read-only (the sheet knows the
      // day is frozen and offers no plan write; a past day keeps its relato).
      // Only for a day this screen holds (a request from another month,
      // reached from the Hoje strip, would open an empty day).
      onViewDay: _daysByIso.containsKey(iso)
          ? () => _openDay(request.scheduleDate)
          : null,
      childName: _perChild ? _childName(request.childId) : null,
      // F-07 (PR 4b): the other children's requests of this day, from the
      // same requester to the same approver — approved together.
      siblings: _perChild
          ? [
              for (final r in _monthFrozen)
                if (r.id != request.id &&
                    r.status == request.status &&
                    r.requestingProfileId == request.requestingProfileId &&
                    r.targetProfileId == request.targetProfileId &&
                    CareSchedule.isoDate(r.scheduleDate) == iso)
                  r,
            ]
          : const [],
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
      _forgetSelectionMonths();
    });
  }

  /// T-18 — the writes that start from the calendar itself do not start
  /// offline. The day and frozen sheets still OPEN (reading a day is the whole
  /// point of this item) and lose their actions instead; these three have
  /// nothing to show but a form, so they say why and stay shut.
  bool _refuseWriteOffline() {
    if (!_offline) return false;
    showAppSnack(context, AppL10n.of(context).l[KApp.offlineWriteBlocked]);
    return true;
  }

  Future<void> _openBulkSheet() async {
    if (_refuseWriteOffline()) return;
    final summary = await showBulkSheet(
      context: context,
      selectedDays: Set.of(_selectedDays),
      daysByIso: _selDaysByIso,
      activeMembers: _assignableMembers,
      today: _today,
      dataSource: widget.dataSource,
      adminBypass: _adminBypass,
      adminOffer: _adminOfferer,
      isPremium: _isPremiumForGate,
      settings: _settings,
      frozenDates: [for (final r in _selFrozenByIso.values) r.scheduleDate],
      myProfile: _ownProfile,
      allProfiles: _members,
      childId: _lane,
    );
    if (summary != null) {
      // Mirror of FinishBulkSave: the selection clears (armed state stays),
      // the month reloads and the summary is the toast.
      setState(() {
        _selectedDays.clear();
        _forgetSelectionMonths();
      });
      _load(silent: true);
      if (mounted) showAppSnack(context, summary);
    }
  }

  /// Mirror of `WorkflowActionableCount`: how many selected days carry an
  /// action for the resolve sheet (awaiting me + sent by me + revertable).
  int get _workflowActionableCount {
    final views = [for (final r in _selFrozenByIso.values) r.toView()];
    final frozenDates = [for (final r in _selFrozenByIso.values) r.scheduleDate];
    var revertable = 0;
    for (final d in _selectedDays) {
      final row = _selDaysByIso[CareSchedule.isoDate(d)];
      if (row != null &&
          isRevertCandidate(
            scheduleDate: row.scheduleDate,
            scheduledParentId: row.scheduledParentId,
            actualParentId: row.actualParentId,
            today: _today,
            frozenDates: frozenDates,
            requesterId: _ownProfile?.id,
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

  /// F-65: the quick swap the current selection allows, or null when the
  /// bar must not offer it (core decides — two planned parents, equal counts,
  /// every day clean, the requester one of the two). Never non-null together
  /// with [_workflowActionableCount] > 0: that count needs a frozen or an
  /// already-swapped day, and either hides the plan.
  QuickSwapPlan? get _quickSwapPlan => quickSwapPlan(
        selected: [
          for (final d in _selectedDays)
            () {
              final row = _selDaysByIso[CareSchedule.isoDate(d)];
              return QuickSwapDay(
                date: d,
                scheduledParentId: row?.scheduledParentId ?? 0,
                actualParentId: row?.actualParentId,
              );
            }(),
        ],
        requesterId: _ownProfile?.id,
        today: _today,
        frozenDates: [for (final r in _selFrozenByIso.values) r.scheduleDate],
        members: _memberViews,
      );

  Future<void> _openQuickSwap(QuickSwapPlan plan) async {
    if (_refuseWriteOffline()) return;
    final my = _ownProfile;
    if (my == null) return;
    final summary = await showQuickSwapSheet(
      context: context,
      plan: plan,
      daysByIso: _selDaysByIso,
      dataSource: widget.dataSource,
      myProfile: my,
      allProfiles: _members,
      childId: _lane,
    );
    if (summary != null) {
      // Same exit as the bulk sheet: selection clears, month reloads, the
      // summary is the toast.
      setState(() {
        _selectedDays.clear();
        _forgetSelectionMonths();
      });
      _load(silent: true);
      if (mounted) showAppSnack(context, summary);
    }
  }

  Future<void> _openResolveSheet() async {
    if (_refuseWriteOffline()) return;
    final summary = await showResolveSheet(
      context: context,
      selectedDays: Set.of(_selectedDays),
      openRequests: _selFrozenByIso.values.toList(),
      daysByIso: _selDaysByIso,
      today: _today,
      ownProfileId: _ownProfile?.id,
      myProfile: _ownProfile,
      allProfiles: _members,
      dataSource: widget.dataSource,
    );
    if (summary != null) {
      // Mirror of RunBulkWorkflowAsync's close: selection clears, month
      // reloads, the summary is the toast.
      setState(() {
        _selectedDays.clear();
        _forgetSelectionMonths();
      });
      _load(silent: true);
      if (mounted) showAppSnack(context, summary);
    }
  }

  /// [start] is the U-40 strip's: the first day the empty month can still be
  /// planned for. The ⋮ menu and the checklist pass nothing (today).
  // ── U-55: a plan born without a handoff time ────────────────────────────

  /// The strip's rule (`showHandoffNudge`, core) over the window the load
  /// already holds — `[today, today + 91]` plus yesterday — so it costs no
  /// query of its own.
  bool get _showHandoffNudge {
    final me = _ownProfile;
    final familyId = me?.familyId;
    if (me == null || familyId == null || _loading) return false;
    HandoffNudgeDay view(CareSchedule d) => HandoffNudgeDay(
        date: d.scheduleDate,
        effectiveParentId: d.actualParentId ?? d.scheduledParentId,
        hasTime: d.handoffTime != null);
    final yesterday = _yesterdayRow;
    return showHandoffNudge(
      isAdmin: me.isAdmin,
      dismissed: _handoffNudgeDismissed ||
          (widget.handoffNudgePrefs?.isDismissed(familyId) ?? false),
      upcoming: [for (final d in _upcoming) view(d)],
      yesterday: yesterday == null ? null : view(yesterday),
    );
  }

  void _dismissHandoffNudge() {
    final familyId = _ownProfile?.familyId;
    setState(() => _handoffNudgeDismissed = true);
    if (familyId != null) {
      unawaited(widget.handoffNudgePrefs?.dismiss(familyId));
    }
  }

  /// Admin-only by DB rule and by the strip's own rule, and — owner, U-55 —
  /// WITHOUT the admin mode: a handoff time is not a protected field.
  Future<void> _openHandoffRange() async {
    if (_refuseWriteOffline()) return;
    if (_refuseWriteInTodas()) return;
    final summary = await showHandoffRangeSheet(
      context: context,
      dataSource: widget.dataSource,
      today: _today,
      childId: _perChild ? _lane : null,
    );
    if (summary == null || !mounted) return;
    showAppSnack(context, summary);
    _load(silent: true);
  }

  // ── F-59: a device without push, now that most notices left e-mail ────────

  PushNudgeStep get _pushStep => PushNudgeRules.step(
      state: widget.push?.state ?? PushState.unsupported,
      facts: widget.installFacts);

  void _onPushChanged() {
    if (mounted) setState(() {});
  }

  /// Fire-and-forget, and only when the strip could show at all: a device
  /// whose push is on, or that cannot have it, costs no query.
  Future<void> _loadPushReach(int profileId) async {
    if (!_pushStep.isActionable) return;
    try {
      final reach = await widget.dataSource.fetchPushReach(profileId);
      if (mounted) setState(() => _pushReach = reach);
    } catch (_) {/* no answer: the rhythm alone decides */}
  }

  bool get _showPushToday {
    if (_loading || _ownProfile == null) return false;
    final now = DateTime.now();
    var dismissals =
        widget.pushTodayPrefs?.read() ?? InstallHintDismissals.none;
    // This session's dismissal, until the prefs have it (or with no prefs at
    // all). The stored time is in milliseconds, hence the tolerance.
    final session = _pushTodayDismissedAt;
    final stored = dismissals.last;
    if (session != null &&
        (stored == null ||
            session.difference(stored) > const Duration(seconds: 1))) {
      dismissals = dismissals.next(session);
    }
    return PushTodayRules.show(
      step: _pushStep,
      dismissals: dismissals,
      now: now,
      // Unknown reads as "has push": a failed read never chases the reader.
      accountHasPush: _pushReach?.accountHasPush ?? true,
      newestUnreadAt: _pushReach?.newestUnreadAt,
    );
  }

  void _dismissPushToday() {
    final now = DateTime.now();
    setState(() => _pushTodayDismissedAt = now);
    unawaited(widget.pushTodayPrefs?.dismiss(now));
  }

  /// A STATE line like F-70's, not an alert (03/10/2026): as an AppBanner it
  /// took 146 dp between the Hoje card and the month on a Pixel 6 — the
  /// month kept 228 dp of 729, and with the editor's keyboard up the column
  /// overflowed (the Android E2E lane, run 37124944050). One tinted row: the
  /// mark, a short sentence, a one-word action and the ✕ at its full 48 dp
  /// target, which is also the row's height.
  Widget _pushToday(Localization l) {
    final tone = context.tokens.info;
    return Padding(
      key: CalendarScreen.pushTodayKey,
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.xs, Spacing.md, Spacing.xs),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsetsDirectional.only(start: Spacing.sm),
        decoration: BoxDecoration(
          color: tone.container,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_outlined,
                size: 18, color: tone.onContainer),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                l[KApp.pushTodayMessage],
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tone.onContainer),
              ),
            ),
            // F-09: Notificações is the ONE door to the OS dialog; this strip
            // only points to it.
            if (widget.onOpenNotifications != null)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: tone.onContainer,
                  padding:
                      const EdgeInsets.symmetric(horizontal: Spacing.sm),
                ),
                onPressed: widget.onOpenNotifications,
                child: Text(l[KApp.pushTodayAction]),
              ),
            IconButton(
              onPressed: _dismissPushToday,
              tooltip: l[KApp.pushTodayDismiss],
              color: tone.onContainer,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  // ── F-70: the plan is running out ─────────────────────────────────────────

  /// `ending` / `ended` / null (`PlanEndRules.stripKind`). Every member sees
  /// it — any member may plan an empty day — and it has no close: it is the
  /// calendar's STATE, and it goes away the moment the family plans further.
  /// It is also where a reader lands after the login an e-mail link passes
  /// through (T-64 keeps no destination), so the action has to live here too.
  String? get _planEndKind =>
      _loading ? null : PlanEndRules.stripKind(_lastPlannedDay, _today);

  Widget _planEndStrip(Localization l, String kind) {
    final last = _lastPlannedDay!;
    final tone = context.tokens.info;
    // Owner (29/09/2026): the AppBanner took ~90 dp between the Hoje card
    // and the month and pushed the grid down on a small phone. It is a
    // STATE line, not an alert: one tinted row — the mark, the date, a
    // one-word action at the end — no taller than the action's 48 dp.
    return Padding(
      key: CalendarScreen.planEndStripKey,
      padding: const EdgeInsets.fromLTRB(
          Spacing.md, Spacing.xs, Spacing.md, Spacing.xs),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsetsDirectional.only(start: Spacing.sm),
        decoration: BoxDecoration(
          color: tone.container,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        child: Row(
          children: [
            Icon(Icons.event_note_outlined, size: 18, color: tone.onContainer),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(
                l.format(kind == 'ended' ? K.calPlanEnded : K.calPlanEnding,
                    [l.formatDate(last)]),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tone.onContainer),
              ),
            ),
            if (!_iAmViewer)
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: tone.onContainer,
                  padding:
                      const EdgeInsets.symmetric(horizontal: Spacing.sm),
                ),
                onPressed: () =>
                    _openWizard(start: PlanEndRules.startAfter(last, _today)),
                child: Text(l[KApp.calPlanEndAction]),
              )
            else
              const SizedBox(width: Spacing.sm),
          ],
        ),
      ),
    );
  }

  Widget _handoffNudge(Localization l) => Padding(
        key: const Key('handoff-nudge'),
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.xs, Spacing.md, Spacing.xs),
        child: AppBanner(
          tone: context.tokens.info,
          icon: Icons.schedule_outlined,
          message: l[K.handoffNudgeMessage],
          actionLabel: l[K.handoffNudgeAction],
          onAction: _openHandoffRange,
          onClose: _dismissHandoffNudge,
          closeTooltip: l[K.handoffNudgeDismiss],
        ),
      );

  Future<void> _openWizard({DateTime? start}) async {
    if (_refuseWriteOffline()) return;
    // F-07: a plan is one child's in a per-child family.
    if (_refuseWriteInTodas()) return;
    final generated = await showWizardSheet(
      context: context,
      activeMembers: _assignableMembers,
      today: _today,
      dataSource: widget.dataSource,
      initialStart: start,
      // F-39: the wizard clamps to the same horizon as the paging.
      maxScheduleDate: _horizonDate,
      isFreeTier: !_isPremiumForPaging,
      // F-51: the "substituir" checkbox is an admin-mode power, like every
      // other clear of a planned day.
      adminBypass: _adminBypass,
      adminOffer: _adminOfferer,
      analytics: widget.analytics,
      childId: _lane,
    );
    if (generated == true) _load(silent: true);
  }

  /// F-51 "Limpar mês": ONE server-side statement over today → the end of
  /// the displayed month (`monthClearRange`), never the past. The
  /// confirmation spells the exact count and the exact range — the count is
  /// the displayed month's own rows, which is exact because the range never
  /// leaves that month — and says what is kept; the toast is the SERVER's
  /// count, by reason, because only the server saw which rows the trigger's
  /// rules spared. U-27: the confirming action first, the way out after it.
  Future<void> _clearMonth() async {
    if (_refuseWriteOffline()) return;
    if (_refuseWriteInTodas()) return;
    // F-67 Part B: offered to an admin with the mode off. Yes turns it on
    // and carries on into the month's own "apagar N dias?" — activating the
    // mode never deletes anything by itself.
    final offerer = _adminOfferer;
    if (!_adminBypass) {
      if (offerer == null) return;
      final yes =
          await showAdminModeOfferDialog(context, AdminModeAction.clearMonth);
      if (!yes) {
        offerer.decline(AdminModeAction.clearMonth);
        return;
      }
      offerer.accept(AdminModeAction.clearMonth);
      if (!mounted) return;
    }
    final l = AppL10n.of(context).l;
    final range = monthClearRange(visibleMonth: _visibleMonth, today: _today);
    if (range == null) return;
    final fromText = l.formatDate(range.from);
    final toText = l.formatDate(range.to);
    // Only what the server will actually delete: a frozen day (pending
    // request) and a day holding an approved swap are kept by the RPC's
    // WHERE, so they must not be counted as "serão apagados" here either.
    // F-07: the lane on screen — or, in *Todas*, every lane (one row each).
    final lane = _perChild ? _lane : null;
    bool frozenRow(CareSchedule d) => _monthFrozen.any((r) =>
        r.childId == d.childId &&
        CareSchedule.isoDate(r.scheduleDate) ==
            CareSchedule.isoDate(d.scheduleDate));
    final count = [
      for (final d in _monthRows)
        if ((lane == null || d.childId == lane) &&
            !frozenRow(d) &&
            (d.actualParentId == null ||
                d.actualParentId == d.scheduledParentId) &&
            !d.scheduleDate.isBefore(range.from) &&
            !d.scheduleDate.isAfter(range.to))
          d,
    ].length;
    if (count == 0) {
      showAppSnack(
          context, l.format(K.calClearMonthNothing, [fromText, toText]));
      return;
    }
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l[K.calClearMonthTitle]),
        content: Text(l.format(
            count == 1 ? K.calClearMonthBodyOne : K.calClearMonthBodyMany,
            [count, fromText, toText])),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                  foregroundColor: context.tokens.danger.onContainer),
              child: Text(l[K.bulkYesDelete])),
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l[K.commonCancel])),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    try {
      final result =
          await widget.dataSource
              .clearScheduleRange(range.from, range.to, childId: lane);
      if (!mounted) return;
      _load(silent: true);
      showAppSnack(context, clearRangeSummary(l, result));
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      showAppSnack(
          context,
          isSessionExpired(raw)
              ? sessionExpiredMessage(l)
              : translateSaveError(raw, l[K.errSaveFailed], l));
    }
  }

  /// F-07 (PR 4b) — the other children whose [date] is in the SAME state as
  /// the lane on screen (same planned carer, same real carer, nothing
  /// pending): a swap asked for this child can be asked for them too.
  List<DaySheetSibling> _daySiblings(DateTime date) {
    if (!_perChild || _lane == null) return const [];
    final iso = CareSchedule.isoDate(date);
    final mine = _daysByIso[iso];
    if (mine == null) return const [];
    return [
      for (final c in _children)
        if (c.id != _lane)
          for (final d in _monthRows)
            if (d.childId == c.id &&
                CareSchedule.isoDate(d.scheduleDate) == iso &&
                d.scheduledParentId == mine.scheduledParentId &&
                d.actualParentId == mine.actualParentId &&
                !_monthFrozen.any((r) =>
                    r.childId == c.id &&
                    CareSchedule.isoDate(r.scheduleDate) == iso))
              DaySheetSibling(childId: c.id, childName: c.firstName, day: d),
    ];
  }

  /// F-07 (owner's QA, 29/09/2026) — *Todas*: the whole day, read-only. One
  /// block per child (who has them, the swap, the time, a pending request),
  /// every child's agenda and the day's relatos; "Editar o dia de `criança`"
  /// moves the calendar to that child and opens the day there.
  Future<void> _openAllChildrenDay(DateTime date) async {
    HapticFeedback.selectionClick();
    final iso = CareSchedule.isoDate(date);
    final lanes = [
      for (final c in _children)
        DaySheetLane(
          childId: c.id,
          childName: c.firstName,
          initials: _childInitials[c.id] ?? '',
          day: _monthRows
              .where((d) =>
                  d.childId == c.id &&
                  CareSchedule.isoDate(d.scheduleDate) == iso)
              .firstOrNull,
          frozen: _monthFrozen.any((r) =>
              r.childId == c.id && CareSchedule.isoDate(r.scheduleDate) == iso),
        ),
    ];
    await showDaySheet(
      context: context,
      date: date,
      day: _daysByIso[iso],
      previousDay: null,
      members: _assignableMembers,
      memberViews: _memberViews,
      today: _today,
      dataSource: widget.dataSource,
      ownProfileId: _ownProfile?.id,
      isPremium: _isPremiumForGate,
      settings: _settings,
      myProfile: _ownProfile,
      allProfiles: _members,
      offline: _offline,
      childName: AppL10n.of(context).l[KApp.calLaneAll],
      allLanes: lanes,
      onEditLane: _iAmViewer
          ? null
          : (childId) {
              _selectLane(childId);
              _openDayAsTapped(date);
            },
    );
  }

  Future<void> _openDay(DateTime date, {bool askSwap = false}) async {
    HapticFeedback.selectionClick();
    final iso = CareSchedule.isoDate(date);
    final previousIso =
        CareSchedule.isoDate(date.subtract(const Duration(days: 1)));
    final nextIso = CareSchedule.isoDate(
        DateTime(date.year, date.month, date.day + 1));
    final outcome = await showDaySheet(
      context: context,
      date: date,
      day: _daysByIso[iso],
      previousDay: _daysByIso[previousIso],
      nextDay: _daysByIso[nextIso],
      canonicalRoleOf: _canonicalRoleOf,
      daysInMonth: _carerDayCounts(),
      members: _assignableMembers,
      memberViews: _memberViews,
      today: _today,
      dataSource: widget.dataSource,
      adminBypass: _adminBypass,
      adminOffer: _adminOfferer,
      ownProfileId: _ownProfile?.id,
      // F-40 proactive gate wants the REAL entitlement (fail-closed mirror);
      // when the read failed it gets null and the gate steps aside — the
      // trigger's own refusal propagates instead of a wrongful client block.
      isPremium: _isPremiumForGate,
      settings: _settings,
      frozenDates: [for (final r in _frozenByIso.values) r.scheduleDate],
      myProfile: _ownProfile,
      allProfiles: _members,
      offline: _offline,
      onOpenPlan: widget.onOpenPlan,
      onOpenChildren: widget.onOpenChildren,
      childId: _perChild ? _lane : null,
      childName: _perChild ? _childName(_lane) : null,
      siblings: _daySiblings(date),
      askSwap: askSwap,
      onOpenHistory: widget.onOpenHistory,
      onCalendarStale: () => _load(silent: true),
      onSendNotice:
          dateOnly(date) == dateOnly(_today) && _canOfferNotice
              ? _openNoticeFromMenu
              : null,
      onOpenChat: widget.onOpenChat,
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

  /// F-07 (PR 4b) — *Todas*, today, children with different carers: who has
  /// whom, in the family's order. Null everywhere else.
  String? _todayLaneSummary(Localization l) {
    if (!_perChild || _lane != null) return null;
    final todayIso = CareSchedule.isoDate(_today);
    final rows = [
      for (final c in _children)
        for (final d in _upcomingRows)
          if (d.childId == c.id && CareSchedule.isoDate(d.scheduleDate) == todayIso)
            d,
    ];
    if ({for (final r in rows) r.effectiveParentId}.length < 2) return null;
    return [
      for (final r in rows)
        l.format(KApp.calLaneWith, [
          _childName(r.childId) ?? '',
          _members
                  .where((m) => m.id == r.effectiveParentId)
                  .firstOrNull
                  ?.fullName ??
              '',
        ]),
    ].join('; ');
  }

  /// F-07 — whose plan is on screen: *Todas* or one child. The same chip as
  /// the carers' legend above (owner, 29/09/2026), each child with the
  /// neutral avatar the split day draws — this row is the children's key.
  Widget _laneChips(Localization l) {
    final tokens = context.tokens;
    final scheme = Theme.of(context).colorScheme;
    final initials = _childInitials;
    // Round 3 (owner, 29/09/2026): the carers' short-name rule — the first
    // word, "Ana C." on a clash — so "Filho Pródigo" does not spend the
    // width that would let every name show.
    final short =
        legendNames({for (final c in _children) c.id: c.firstName});
    final allLabel = l[KApp.calLaneAllShort];
    PersonChip chip(
            {required Key key,
            required String? label,
            required String spoken,
            required bool selected,
            required VoidCallback onTap,
            required Widget avatar}) =>
        PersonChip(
          key: key,
          label: label,
          semanticsLabel: spoken,
          selected: selected,
          onTap: onTap,
          background: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.surface,
          border: selected ? scheme.primary : tokens.outline,
          ink: tokens.text,
          avatar: avatar,
        );
    return Padding(
      key: CalendarScreen.laneChipsKey,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm),
      child: LayoutBuilder(builder: (context, box) {
        // F-07 (owner's QA, 29/09/2026, round 3): every name while the row
        // fits one line. Past that, "Todas" is its icon and only the
        // SELECTED child keeps a name — the others are their avatars (the
        // name in the tooltip and the screen reader), so no name is ever
        // cut. Measured with every name, so a tap never flips the mode.
        final named = [
          PersonChip.widthOf(context, allLabel),
          for (final c in _children)
            PersonChip.widthOf(context, short[c.id] ?? c.firstName),
        ];
        final compact = named.fold<double>(0, (a, w) => a + w) +
                Spacing.sm * (named.length - 1) >
            box.maxWidth;
        final gap = compact
            ? Spacing.sm - (PersonChip.target - PersonChip.visual)
            : Spacing.sm;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: box.maxWidth),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                chip(
                  key: const ValueKey('lane-all'),
                  label: compact ? null : allLabel,
                  spoken: allLabel,
                  selected: _lane == null,
                  onTap: () => _selectLane(null),
                  avatar: Icon(Icons.groups_outlined,
                      size: PersonChip.avatarSize, color: tokens.textMuted),
                ),
                for (final c in _children) ...[
                  SizedBox(width: gap),
                  Padding(
                    // The named chip among compact ones gets the 4 dp each
                    // side their 40 dp targets already carry.
                    padding: EdgeInsets.symmetric(
                        horizontal: compact && _lane == c.id
                            ? (PersonChip.target - PersonChip.visual) / 2
                            : 0),
                    child: chip(
                      key: ValueKey('lane-${c.id}'),
                      label: compact && _lane != c.id
                          ? null
                          : short[c.id] ?? c.firstName,
                      spoken: c.firstName,
                      selected: _lane == c.id,
                      onTap: () => _selectLane(c.id),
                      avatar: _childAvatar(
                          initials[c.id] ?? '?', PersonChip.avatarSize),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }),
    );
  }

  /// F-07: the children's letters (`childInitials`, core).
  Map<int, String> get _childInitials =>
      childInitials({for (final c in _children) c.id: c.firstName});

  /// A child's NEUTRAL avatar — surface, ring, text ink.
  Widget _childAvatar(String letters, double diameter) {
    final tokens = context.tokens;
    return MiniAvatar(
      diameter: diameter,
      letters: letters,
      fill: Theme.of(context).colorScheme.surface,
      ink: tokens.text,
      ring: tokens.textMuted,
      letterScale: SplitCellFit.childLetter,
    );
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
        // T-76: so was somebody with an invitation still in their inbox.
        hasOpenInvitation: _openInvitation,
      ),
      responsibleRole: _roleLabelFor(
          todayRow?.effectiveParentId, AppL10n.of(context).l.current),
      onGoToToday: _goToToday,
      onInvite: _onInviteNudgeTap,
      noticeStrip: _noticeStrip(context, todayRow, nextHandoff),
      requestStrip: _requestStrips(context),
      onSendNotice: _canOfferNotice ? _openNoticeFromMenu : null,
      sendNoticeKey: CalendarScreen.noticeQuickActionKey,
      laneSummary: _todayLaneSummary(AppL10n.of(context).l),
    );
  }

  /// F-94: today's request that I asked or must answer, still open — the
  /// day itself is here and nobody has said yes or no.
  SwapRequest? get _pendingToday {
    final me = _ownProfile?.id;
    if (me == null || !isCurrentMonth(_visibleMonth, _today)) return null;
    final todayIso = CareSchedule.isoDate(_today);
    for (final r in _monthFrozen) {
      if (CareSchedule.isoDate(r.scheduleDate) == todayIso &&
          (r.requestingProfileId == me || r.targetProfileId == me)) {
        return r;
      }
    }
    return null;
  }

  /// The Hoje card's request strip — ONE line (owner's QA of 3.1.10): today's
  /// open request when there is one (F-94), with the others waiting for my
  /// answer as a "+N" under it; otherwise the waiting ones (U-60).
  Widget? _requestStrips(BuildContext context) {
    final waiting = _waitingForMe;
    return _pendingTodayStrip(context, others: waiting.length) ??
        _requestStrip(context);
  }

  /// The requests waiting for MY answer, today's own request left out (it has
  /// its own line).
  List<SwapRequest> get _waitingForMe {
    final today = _pendingToday;
    return [
      for (final r in _pendingForMe)
        if (today == null || r.id != today.id) r
    ];
  }

  /// F-94 (owner, 05/10/2026): on the day, while the request waits, both
  /// parties read who stays responsible until the answer — the target gets
  /// "Responder", the requester "Cancelar pedido" (the same panel, which
  /// holds both). No push on the morning of the day: the eve reminder was it.
  Widget? _pendingTodayStrip(BuildContext context, {int others = 0}) {
    final req = _pendingToday;
    final me = _ownProfile?.id;
    if (_loading || req == null || me == null) return null;
    final l = AppL10n.of(context).l;
    final todayIso = CareSchedule.isoDate(_today);
    final row = _monthRows
        .where((d) =>
            CareSchedule.isoDate(d.scheduleDate) == todayIso &&
            d.childId == req.childId)
        .firstOrNull;
    final carer = row?.effectiveParentId ??
        req.previousActualParentId ??
        req.targetProfileId;
    String first(int id) =>
        _members
            .where((m) => m.id == id)
            .firstOrNull
            ?.fullName
            .trim()
            .split(' ')
            .first ??
        '—';
    final iAnswer = req.targetProfileId == me;
    return AppStripLine(
      key: CalendarScreen.pendingTodayStripKey,
      tone: context.tokens.warning,
      icon: Icons.hourglass_top,
      message: l.format(KApp.cardPendingTodayLine, [
        pendingTodaySentence(
          l: l,
          me: me,
          carerId: carer,
          targetId: req.targetProfileId,
          firstName: first,
        ),
      ]),
      actionLabel:
          l[iAnswer ? KApp.cardRequestsAnswer : KApp.cardPendingTodayCancel],
      onAction: () => _openFrozenDay(req),
      extraLabel: others == 0
          ? null
          : l.format(
              others == 1 ? KApp.cardRequestsMoreOne : KApp.cardRequestsMore,
              [others]),
      onExtra: others == 0 ? null : widget.onOpenNotifications ?? () {},
    );
  }

  /// U-60: the requests waiting for MY answer, on the card about today —
  /// the soonest said in words, "Responder" opening its approval panel.
  /// Today's own request is the F-94 strip's, not this one's.
  Widget? _requestStrip(BuildContext context) {
    final waiting = _waitingForMe;
    if (_loading || waiting.isEmpty || _ownProfile == null) return null;
    final l = AppL10n.of(context).l;
    final first = waiting.first;
    final requester = _members
            .where((m) => m.id == first.requestingProfileId)
            .firstOrNull
            ?.fullName
            .trim()
            .split(' ')
            .first ??
        '—';
    final count = waiting.length;
    // Owner's QA of 3.1.10: one line. One request says itself and answers in
    // place; several say how many and open the list.
    return AppStripLine(
      key: CalendarScreen.requestStripKey,
      tone: context.tokens.info,
      icon: Icons.swap_horiz,
      message: count == 1
          ? swapRequestSentence(
              l: l,
              requesterName: requester,
              date: first.scheduleDate,
              isRevert: first.isRevertPending,
              requesterIsProposed:
                  first.proposedActualParentId == first.requestingProfileId,
            )
          : l.format(KApp.cardRequestsMany, [count]),
      actionLabel:
          l[count == 1 ? KApp.cardRequestsAnswer : KApp.cardRequestsSee],
      onAction: count == 1
          ? () => _openFrozenDay(first)
          : (widget.onOpenNotifications ?? () => _openFrozenDay(first)),
    );
  }

  // ── F-52 aviso de imprevisto ───────────────────────────────────────────────

  List<DayNotice> get _openNotices =>
      [for (final n in _todayNotices) if (n.isOpen) n];

  /// My own open aviso, or null. At most one matters: the strip offers to
  /// withdraw the one I am waiting on, and the cap keeps the number small.
  DayNotice? get _myOpenNotice {
    final me = _ownProfile?.id;
    if (me == null) return null;
    for (final n in _openNotices) {
      if (n.senderProfileId == me) return n;
    }
    return null;
  }

  /// Whether I am one of the day's two ends (`noticeSenderIds`). The server
  /// decides for real; this only chooses whether to OFFER the action, because
  /// an action that always ends in a refusal is worse than no action at all.
  bool _canSendNotice(CareSchedule? todayRow) {
    final me = _ownProfile?.id;
    if (me == null) return false;
    // F-07 (PR 5c): per child, the ends of the day in ANY lane — the server's
    // own rule since PR 5a.
    if (_perChild) return _laneNoticeSenders().contains(me);
    return noticeSenderIds(
      dayParentId: todayRow?.effectiveParentId,
      previousParentId: _yesterdayRow?.effectiveParentId,
    ).contains(me);
  }

  /// F-07 (PR 5c) — `noticeSenderIds` for every child's lane, united.
  Set<int> _laneNoticeSenders() {
    final todayIso = CareSchedule.isoDate(_today);
    final senders = <int>{};
    for (final c in _children) {
      final lane = [
        for (final d in _upcomingRows)
          if (d.childId == c.id) d,
      ]..sort((a, b) => a.scheduleDate.compareTo(b.scheduleDate));
      final today = lane
          .where((d) => CareSchedule.isoDate(d.scheduleDate) == todayIso)
          .firstOrNull;
      final yesterday =
          _yesterdayRows.where((d) => d.childId == c.id).firstOrNull;
      senders.addAll(noticeSenderIds(
        dayParentId: today?.effectiveParentId,
        previousParentId: yesterday?.effectiveParentId,
      ));
    }
    return senders;
  }

  /// The sentence a reader sees for an open aviso — the SAME one the
  /// notification carries, composed once in core. Two copies of it is how the
  /// strip says "30 min" while the notification says "sem previsão", both
  /// well-formed.
  String _noticeSentence(DayNotice notice, Localization l, {bool mine = false}) {
    final reason = NoticeReason.fromWire(notice.reason);
    final request = NoticeRequest.fromWire(notice.request);
    // A row we cannot read is a FUTURE writer's; saying nothing about it beats
    // inventing a reason it never gave.
    if (reason == null || request == null) return '';
    var senderName = l[K.notifRenderFbOtherCap];
    for (final m in _members) {
      if (m.id == notice.senderProfileId) {
        senderName = m.fullName;
        break;
      }
    }
    return noticeSentence(
      l: l,
      senderName: senderName,
      reason: reason,
      etaMinutes: notice.etaMinutes,
      request: request,
      note: notice.note,
      mine: mine,
    );
  }

  Widget? _noticeStrip(
      BuildContext context, CareSchedule? todayRow, DateTime? nextHandoff) {
    if (_loading || _ownProfile == null) return null;
    final l = AppL10n.of(context).l;
    final me = _ownProfile!.id;

    // F-98 (owner, 05/10/2026): the others' open avisos are shown WITH mine —
    // my own open "Só avisando" used to hide the other parent's "alguém pode
    // buscar?" all day — and the ones that ask for an answer come first. When
    // an aviso closes is still F-52's rule.
    final theirs = [
      for (final n in _openNotices)
        if (n.senderProfileId != me) n
    ];
    bool answerable(DayNotice n) =>
        NoticeRequest.fromWire(n.request) != null &&
        NoticeRequest.fromWire(n.request) != NoticeRequest.info &&
        !_iAmViewer;
    final ordered = [
      ...theirs.where(answerable),
      ...theirs.where((n) => !answerable(n)),
    ];
    final mine = _myOpenNotice;
    final strips = <Widget>[
      for (final n in ordered)
        // "Só avisando" asks for nothing, so its banner offers nothing: an
        // action on a notice that made no request is an invitation to answer
        // a question nobody asked.
        // Owner's QA of 3.1.10: one line each, like every strip on the card.
        AppStripLine(
          key: ValueKey('notice-strip-${n.id}'),
          tone: context.tokens.warning,
          icon: Icons.campaign_outlined,
          message: _noticeSentence(n, l),
          actionLabel: answerable(n) ? l[KApp.noticeAnswerTitle] : null,
          onAction: answerable(n) ? () => _answerNotice(n) : null,
        ),
      if (mine != null)
        AppStripLine(
          key: ValueKey('notice-strip-${mine.id}'),
          tone: context.tokens.warning,
          icon: Icons.campaign_outlined,
          // F-98: the author reads herself in the second person — which is
          // also what says it is hers, so the strip needs no title.
          message: _noticeSentence(mine, l, mine: true),
          actionLabel: l[KApp.noticeCancel],
          onAction: () => _confirmCancelNotice(mine),
        ),
    ];
    // Owner's QA of 3.1.10: "Avisar" is an icon in the card's header now
    // ([TodayCard.onSendNotice]) — a line of its own pushed the calendar down
    // for the one action of the day most people never need.
    if (strips.isEmpty) return null;
    if (strips.length == 1) return strips.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, w) in strips.indexed) ...[
          if (i > 0) const SizedBox(height: Spacing.sm),
          w,
        ],
      ],
    );
  }

  Future<void> _openNoticeSheet(int? dayParentId, int sentToday) async {
    if (_refuseWriteOffline()) return;
    final id = await showNoticeSheet(
      context: context,
      dataSource: widget.dataSource,
      myProfileId: _ownProfile!.id,
      dayParentId: dayParentId,
      sentToday: sentToday,
      dailyCap: _settings.dayNoticeDailyCap,
    );
    if (id == null || !mounted) return;
    _load(silent: true);
    showAppSnack(context, AppL10n.of(context).l[KApp.noticeSent]);
  }

  /// F-52 PR 2 — answering. The sheet pops the outcome that actually landed,
  /// because the two are not the same news: somebody who just took the day is
  /// told THAT, not "resposta enviada".
  Future<void> _answerNotice(DayNotice notice) async {
    if (_refuseWriteOffline()) return;
    final l = AppL10n.of(context).l;
    final outcome = await showAnswerNoticeSheet(
      context: context,
      dataSource: widget.dataSource,
      notice: notice,
      sentence: _noticeSentence(notice, l),
    );
    if (outcome == null || !mounted) return;
    _load(silent: true);
    showAppSnack(
        context,
        AppL10n.of(context).l[outcome == NoticeOutcome.keeping
            ? KApp.noticeAnsweredKeeping
            : KApp.noticeAnsweredHelping]);
  }

  /// U-38: the question a tap raised is answered where the finger is — the
  /// sheet's `confirmation:` IS the question, in the action row's own place.
  Future<void> _confirmCancelNotice(DayNotice notice) async {
    if (_refuseWriteOffline()) return;
    final l = AppL10n.of(context).l;
    final done = await showAppSheet<bool>(
      context: context,
      builder: (context) => CancelNoticeSheet(
        dataSource: widget.dataSource,
        notice: notice,
        sentence: _noticeSentence(notice, l),
      ),
    );
    if (done != true || !mounted) return;
    _load(silent: true);
    showAppSnack(context, AppL10n.of(context).l[KApp.noticeCancelled]);
  }

  /// T-76 — the other half of the F-31 measurement, under the name the Blazor
  /// client used (`invite_nudge_click`), so the series that stopped at the
  /// cutover continues instead of starting over. Fired before the navigation:
  /// the tap is the fact, and `/family` is what it leads to.
  void _onInviteNudgeTap() {
    final analytics = widget.analytics;
    if (analytics != null) {
      unawaited(analytics.trackEvent(AnalyticsEvents.inviteNudgeClick,
          props: analyticsFunnelProps(channel: analytics.channel)));
    }
    context.go('/family');
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

  /// Owner's QA of 3.1.10 — how many days of the visible month each carer
  /// has (the swap entry's tie-break).
  Map<int, int> _carerDayCounts() {
    final counts = <int, int>{};
    for (final d in _daysByIso.values) {
      counts[d.effectiveParentId] = (counts[d.effectiveParentId] ?? 0) + 1;
    }
    return counts;
  }

  /// Owner's QA of 3.1.10 — a member's BUILT-IN role by its canonical name
  /// (`father`, `mother`, …), or null for none or a custom role.
  String? _canonicalRoleOf(int profileId) {
    final roleId =
        _members.where((m) => m.id == profileId).firstOrNull?.roleId;
    final role = _roles.where((r) => r.id == roleId).firstOrNull;
    return role == null ? null : RoleCatalog.find(role.roleName)?.canonicalName;
  }

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
    // U-48: with the month bar focused (either arrow, the today chip), ← and
    // → step the month — the keys a reader expects on the row that names it.
    // Scoped to the bar on purpose: over the grid the arrows keep Flutter's
    // own meaning, moving focus from cell to cell.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _stepMonth(-1),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _stepMonth(1),
      },
      child: Row(
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
      ),
    );
  }

  /// F-52 — whether "Enviar um aviso" belongs in the ⋮ menu right now.
  ///
  /// **Why the menu and not the Hoje card.** The card is the one surface whose
  /// height the month grid pays for: an idle strip in it took the cells from
  /// 76 dp to 67.8 at 360x740, measured — U-28 already paid for that lesson,
  /// and U-48's rule is that an addition must not change what the majority
  /// sees at 1.0×. The month bar was the next candidate and is worse: its
  /// arrows are 40 dp and pass the U-32 gate only because they touch the
  /// screen edge, so a fourth button there un-exempts "Próximo mês" and turns
  /// the gate red on a defect this item did not cause. The ⋮ is free, and it
  /// is where U-47 puts everything that is not a card's one primary action.
  /// The Hoje card keeps the half the strip is FOR: an aviso that is open.
  bool get _canOfferNotice {
    if (_loading || _ownProfile == null) return false;
    if (!isCurrentMonth(_visibleMonth, _today)) return false;
    // An aviso already open is withdrawn on the card's strip, not sent twice.
    if (_myOpenNotice != null) return false;
    final todayRow = _rowForToday();
    return _canSendNotice(todayRow);
  }

  void _openNoticeFromMenu() {
    final todayRow = _rowForToday();
    final me = _ownProfile!.id;
    final sentToday = [
      for (final n in _todayNotices)
        if (n.senderProfileId == me) n
    ].length;
    // F-07 (PR 5c): per child, I may offer the day when I hold it in ANY
    // lane — taking it moves every lane that is mine (server, PR 5a).
    final todayIso = CareSchedule.isoDate(_today);
    final holdsAnyLane = _perChild &&
        _upcomingRows.any((d) =>
            d.childId != null &&
            CareSchedule.isoDate(d.scheduleDate) == todayIso &&
            d.effectiveParentId == me);
    unawaited(_openNoticeSheet(
        holdsAnyLane ? me : todayRow?.effectiveParentId, sentToday));
  }

  /// Today's row out of [_upcoming], which the load fetches starting today.
  CareSchedule? _rowForToday() {
    final todayIso = CareSchedule.isoDate(_today);
    for (final d in _upcoming) {
      if (CareSchedule.isoDate(d.scheduleDate) == todayIso) return d;
    }
    return null;
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
  ///
  /// U-36: two of them — the wizard and "select several days" — used to be
  /// unlabelled icons (`event_repeat` says "wizard" to nobody, and a tooltip
  /// on Android is a long-press nobody performs). They are items of ONE ⋮
  /// menu now, each with its text, which is also where F-51's "Limpar mês"
  /// enters without pushing a fifth icon into the bar. The admin shield stays
  /// an icon: it is a MODE, its state is the glyph, and the shell banner names
  /// it. Order: shield, then the menu, then the account button the caller adds.
  List<Widget> _calendarActions(BuildContext context, Localization l) => [
        // F-14: the explicit admin-mode toggle — mirror of the web's NavMenu
        // button. Only a real admin sees it; the shell shows the persistent
        // banner while it is on. It stays with the calendar and not in the
        // account menu because what it unlocks is a day on THIS grid — and it
        // stays through selection mode (owner, 15/09/2026): an admin who
        // selected past days and needs the mode to edit them would otherwise
        // have to cancel the whole selection to reach it.
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
        if (!_isSelectionMode)
          PopupMenuButton<_CalendarAction>(
            // The tour's third stop spotlights this button and its copy names
            // the item to pick, so the spotlight still has something to point
            // at now that the wizard has no icon of its own.
            key: widget.tourKeys?.keyFor(TourTarget.actionsMenu),
            tooltip: l[K.calActionsMenu],
            icon: const Icon(Icons.more_vert),
            onSelected: (action) => switch (action) {
              _CalendarAction.wizard => _openWizard(),
              // The accessible entry point to bulk selection (mirrors the
              // long-press). Once armed, tapping a day toggles its selection.
              _CalendarAction.selectDays =>
                setState(() => _selectionArmed = true),
              _CalendarAction.askSwap => _askSwapFromMenu(),
              _CalendarAction.notice => _openNoticeFromMenu(),
              _CalendarAction.clearMonth => _clearMonth(),
              _CalendarAction.adminMode => widget.adminMode.toggle(),
            },
            itemBuilder: (context) => [
              // F-50: a viewer plans nothing and selects nothing.
              if (!_iAmViewer)
              PopupMenuItem(
                value: _CalendarAction.wizard,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_repeat),
                  title: Text(l[K.calWizard]),
                ),
              ),
              if (!_iAmViewer)
              PopupMenuItem(
                value: _CalendarAction.selectDays,
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_box_outlined),
                  title: Text(l[K.calSelectDays]),
                ),
              ),
              // U-60: the explicit way to ask — it lands on the day sheet's
              // own request, never around it.
              if (!_iAmViewer && _assignableMembers.length > 1)
                PopupMenuItem(
                  key: CalendarScreen.askSwapMenuKey,
                  value: _CalendarAction.askSwap,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.swap_horiz),
                    title: Text(l[KApp.calAskSwap]),
                  ),
                ),
              // F-52: offered only to one of the day's three ends, and only
              // on the month today is in — an action about today offered from
              // December reads as a bug.
              if (_canOfferNotice)
                PopupMenuItem(
                  value: _CalendarAction.notice,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.campaign_outlined),
                    title: Text(l[KApp.noticeAction]),
                  ),
                ),
              // F-51 "Limpar mês": the third item, after a divider —
              // destructive, so last and set apart, in the danger tone. Only
              // under the admin bypass (clearing a planned day is an admin
              // power, and the shield is this product's override gesture —
              // the same gate as "Limpar dia" and "Apagar dias"), and only
              // while the displayed month still has days ahead: the past is
              // never offered, not even to an admin.
              // F-67 Part B (owner, 21/09/2026): the shield's own words. The
              // icon stays — it is a mode and its glyph is the state — but a
              // tooltip is a long-press nobody performs (U-36), so the menu
              // carries the same toggle with its text.
              if (_ownProfile?.isAdmin == true)
                PopupMenuItem(
                  value: _CalendarAction.adminMode,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(widget.adminMode.isActive
                        ? Icons.shield
                        : Icons.shield_outlined),
                    title: Text(l[widget.adminMode.isActive
                        ? K.navAdminExit
                        : K.navAdminEnter]),
                  ),
                ),
              // F-67 Part B: an admin with the mode off sees it too, and is
              // asked to turn the mode on when picking it.
              if (_ownProfile?.isAdmin == true &&
                  monthClearRange(
                          visibleMonth: _visibleMonth, today: _today) !=
                      null) ...[
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _CalendarAction.clearMonth,
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.delete_sweep_outlined,
                        color: context.tokens.danger.onContainer),
                    title: Text(l[K.calClearMonth],
                        style: TextStyle(
                            color: context.tokens.danger.onContainer)),
                  ),
                ),
              ],
            ],
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
    final quickSwap = _isSelectionMode ? _quickSwapPlan : null;
    final strip = _systemStrip;
    _reportSystemStrip(strip != null);
    return Scaffold(
      // U-28: the app bar names the TAB, like the other three do. The month
      // moved down to sit against the grid it labels — up here, competing with
      // five icon buttons, it truncated to "agosto de…" for any admin.
      // U-36: while days are being selected the app bar is CONTEXTUAL —
      // Material's contextual action bar: ✕ on the left, the count as the
      // title, the mode's own actions on the right. Before, entering selection
      // changed only the strip at the bottom while the top kept saying
      // "Calendário", so the state of the screen was announced at the far end
      // from where the eye is. The two labelled actions stay in the bottom
      // strip (owner, 15/09/2026): at 360 dp the count and both labels do not
      // fit one bar, and turning them into icons would undo this very item.
      appBar: _isSelectionMode
          ? AppBar(
              toolbarHeight: 48,
              leading: IconButton(
                tooltip: l[K.selectionCancel],
                icon: const Icon(Icons.close),
                onPressed: _cancelSelection,
              ),
              // Armed with nothing picked yet, the title says what to do; the
              // same two keys the month-paging guard uses, so the count reads
              // the same sentence in both places.
              title: Text(
                  switch (_selectedDays.length) {
                    0 => l[K.calSelectDays],
                    1 => l.format(K.navGuardSelectedOne, [1]),
                    final n => l.format(K.navGuardSelectedMany, [n]),
                  },
                  style: Theme.of(context).textTheme.titleMedium),
              actions: _calendarActions(context, l),
            )
          : AppBar(
              // U-28 QA: 48 instead of 56, and the title one step down the
              // scale. The calendar is the one screen whose content is a fixed
              // grid — every point spent on chrome is a point the month does
              // not get, and the grid was scrolling.
              toolbarHeight: 48,
              title: Text(l[K.navCalendar],
                  style: Theme.of(context).textTheme.titleMedium),
              actions: [
                ..._calendarActions(context, l),
                const AppAccountButton(),
              ],
            ),
      // U-48: PageUp / PageDown change the month from ANYWHERE on the
      // calendar, and the screen takes keyboard focus as it mounts so the
      // keys work before the reader tabs to anything (the node is skipped by
      // Tab, so it never costs a stop). Above the body, not inside a cell:
      // key events bubble UP from the focused node, so the shortcuts have to
      // be an ancestor of whatever holds focus.
      body: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.pageUp): () =>
              _stepMonth(-1),
          const SingleActivator(LogicalKeyboardKey.pageDown): () =>
              _stepMonth(1),
        },
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          child: Column(
        children: [
          if (strip == _SystemStrip.checklist)
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
          if (strip == _SystemStrip.pushToday) _pushToday(l),
          if (strip == _SystemStrip.handoffNudge) _handoffNudge(l),
          if (_iAmViewer)
            Padding(
              key: const ValueKey('viewer-read-only'),
              padding: const EdgeInsets.fromLTRB(
                  Spacing.md, Spacing.xs, Spacing.md, Spacing.xs),
              child: AppBanner(
                tone: context.tokens.info,
                icon: Icons.visibility_outlined,
                message: l[KApp.viewerReadOnly],
              ),
            ),
          if (_planEndKind case final kind?) _planEndStrip(l, kind),
          _monthBar(context, l),
          if (_members.isEmpty && _loading)
            const _LegendSkeleton()
          else
            KeyedSubtree(
              key: widget.tourKeys?.keyFor(TourTarget.calendarLegend),
              child: _Legend(
                members: _members,
                views: views,
                showSwapKey: _visibleMonthHasSwap,
                onOpen: widget.onOpenMember == null || _ownProfile == null
                    ? null
                    : (m) => widget.onOpenMember!(
                        memberLinkTarget(
                            isOwn: m.id == _ownProfile!.id,
                            iAmAdmin: _ownProfile!.isAdmin),
                        m.id),
              ),
            ),
          const Divider(height: 1),
          if (_perChild) _laneChips(l),
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
                                  icon: Icons.error_outline,
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
                          divergentByIso:
                              isVisible ? _divergentByIso : const {},
                          laneNames: {
                            for (final c in _children) c.id: c.firstName
                          },
                          laneInitials: _childInitials,
                          frozenByIso: isVisible ? _frozenByIso : const {},
                          agendaByIso: isVisible ? _agendaByIso : const {},
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
                          // U-40: only the month whose rows are in hand can
                          // say it is empty — a neighbour page gets nothing.
                          emptyPrompt: isVisible && !_iAmViewer
                              ? _emptyPrompt
                              : EmptyMonthPrompt.none,
                          horizonNote: _horizonSentence(l),
                          onPlanMonth: () => _openWizard(
                              start: emptyMonthPlanStart(
                                  visibleMonth: month, today: _today)),
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
                        child: FilledButton.icon(
                          onPressed: _selectedDays.isEmpty
                              ? null
                              : _openBulkSheet,
                          icon: const Icon(Icons.edit_outlined),
                          label: Text(l.format(
                              K.selectionEdit, [_selectedDays.length])),
                        ),
                      ),
                      // Resolver — only when the selection carries open
                      // requests / revertable days (WorkflowActionableCount).
                      if (_workflowActionableCount > 0) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _openResolveSheet,
                            icon: const Icon(Icons.pending_actions),
                            label: Text(l.format(K.selectionResolve,
                                [_workflowActionableCount])),
                          ),
                        ),
                      ],
                      // F-65: Trocar — only when the selection is a pair
                      // of planned parents with equal days, all clean. It
                      // and Resolver never show together (see the getter),
                      // so the bar holds at most two labelled actions.
                      if (quickSwap != null) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _openQuickSwap(quickSwap),
                            icon: const Icon(Icons.swap_horiz),
                            label: Text(l.format(
                                K.selectionSwap, [quickSwap.dayCount])),
                          ),
                        ),
                      ],
                      // U-36: the ✕ moved to the contextual app bar — one
                      // place to leave the mode, where Material puts it.
                    ],
                  ),
                ),
              ),
            ),
        ],
          ),
        ),
      ),
    );
  }
}

/// U-36 — the items of the calendar's ⋮ menu. F-51 adds `clearMonth` here.
enum _CalendarAction {
  wizard,
  selectDays,
  askSwap,
  notice,
  adminMode,
  clearMonth,
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

  /// U-18 parity: whether the month on screen has any swapped day at all.
  final bool showSwapKey;

  /// F-07 (owner's QA, 29/09/2026): a carer's chip leads to the person.
  final void Function(Member member)? onOpen;

  const _Legend({
    required this.members,
    required this.views,
    required this.showSwapKey,
    this.onOpen,
  });

  /// One row of keys (the skeleton's height).
  static const rowHeight = PersonChip.target;

  @override
  Widget build(BuildContext context) {
    // F-27/S-11: colors are per member still IN the family (persistent
    // color_slot). F-56: a pending member has a colour and a place in the key,
    // marked so the legend does not claim someone who has not joined.
    // F-50: a viewer has no colour and is never on a day — no key for it.
    final active = members.where((m) => !m.hasLeft && !m.isViewer).toList()
      ..sort((a, b) => (a.colorSlot ?? 9).compareTo(b.colorSlot ?? 9));
    // U-28 QA: it WRAPS, it does not scroll.
    //
    // The arithmetic does not leave a choice. "Fernanda (Mãe)" is about 100 dp
    // with its swatch; four of those plus "Trocado" is roughly 490 dp against a
    // 360 dp phone. One line was never going to hold a four-carer family, and a
    // horizontal scroll hides the fourth carer behind a gesture nobody knows is
    // there. Two rows show everyone, and the rows only appear when the family
    // has grown enough to need them — a two-carer family still gets one.
    // F-07 (owner's QA, 29/09/2026): an avatar and the short name — the role
    // left the key, the chip leads to the person instead, and the children's
    // lane chips wear the same shape.
    final names = legendNames({for (final m in active) m.id: m.fullName});
    final l = AppL10n.of(context).l;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Spacing.sm, 0, Spacing.sm, 0),
      child: LayoutBuilder(builder: (context, box) {
        // F-07 (owner's QA, 29/09/2026, round 3): the names while the whole
        // key fits ONE line; past that, every carer is the avatar alone (the
        // name goes to the screen reader and a long-press tooltip) — four
        // carers and "Trocado" on an iPhone SE, where two rows of names took
        // the grid's height.
        final swapLabel = l[K.calSwapped];
        final named = [
          for (final m in active) PersonChip.widthOf(context, names[m.id]),
          if (showSwapKey) _swapKeyWidth(context, swapLabel),
        ];
        final compact = named.fold<double>(0, (a, w) => a + w) +
                Spacing.sm * (named.length - 1) >
            box.maxWidth;
        return Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          // The compact chip's 40 dp target already holds 8 dp around its
          // 32 dp circle: no extra gap, or the key spreads.
          spacing: compact
              ? Spacing.sm - (PersonChip.target - PersonChip.visual)
              : Spacing.sm,
          children: [
            for (final m in active)
              Builder(builder: (context) {
                final slot =
                    context.tokens.slot(profileSlotIndex(m.id, views));
                final base = names[m.id] ?? m.fullName;
                // The pending mark is the hollow avatar, never "(pendente)"
                // on the chip — the words stay for the screen reader.
                final pending = m.isPendingMember;
                return PersonChip(
                  key: ValueKey('legend-member-${m.id}'),
                  label: compact ? null : base,
                  semanticsLabel:
                      pending ? '$base ${l[KApp.calMemberPending]}' : base,
                  background: slot.tone.container,
                  border: slot.tone.border,
                  ink: slot.tone.onContainer,
                  onTap: onOpen == null ? null : () => onOpen!(m),
                  avatar: MiniAvatar(
                    key: ValueKey('legend-avatar-${m.id}'),
                    diameter: PersonChip.avatarSize,
                    letters: displayInitials(m.id, views),
                    fill: pending
                        ? Theme.of(context).colorScheme.surface
                        : slot.tone.solid,
                    ink: pending ? slot.tone.onContainer : slot.tone.onSolid,
                    dashedRing: pending ? slot.tone.onContainer : null,
                  ),
                );
              }),
            if (showSwapKey)
              _key(context,
                  slot: context.tokens.swapped, label: swapLabel, dashed: true),
          ],
        );
      }),
    );
  }

  /// The swap key's width — the [SlotPill] with [Spacing.sm] each side.
  static double _swapKeyWidth(BuildContext context, String label) {
    final painter = TextPainter(
      text: TextSpan(
          text: label, style: Theme.of(context).textTheme.labelSmall),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width + 2 * Spacing.sm + 2;
    painter.dispose();
    return width.ceilToDouble();
  }

  /// One key, as the web draws it: a pill in the carer's own colour with their
  /// name in it.
  ///
  /// U-28 QA replaced a swatch-plus-label pair with this. The pill IS the
  /// colour, so carrying a separate swatch beside it said the same thing twice
  /// and spent width the legend cannot spare. The swapped key keeps its dashed
  /// outline — that border is the signal, not the fill. U-25 moved the pill to
  /// [SlotPill], so the day sheet's chips are the same shape.
  Widget _key(BuildContext context,
          {required SlotColors slot,
          required String label,
          bool dashed = false}) =>
      SlotPill(slot: slot, label: label, height: 22, dashed: dashed);
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final Map<String, CareSchedule> daysByIso;

  /// F-07: *Todas* — the dates whose children are with different carers.
  final Map<String, List<CareSchedule>> divergentByIso;

  /// F-07: child id → first name, for the split cell's spoken label.
  final Map<int, String> laneNames;

  /// F-07: child id → avatar letters (`childInitials`).
  final Map<int, String> laneInitials;
  final Map<String, SwapRequest> frozenByIso;
  final Map<String, List<ChildEvent>> agendaByIso;
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

  /// U-40: the sentence under an empty month (`emptyMonthPrompt`, core), the
  /// F-39 sentence for the beyond-horizon case, and the wizard door.
  final EmptyMonthPrompt emptyPrompt;
  final String horizonNote;
  final VoidCallback onPlanMonth;

  const _MonthGrid({
    required this.month,
    required this.daysByIso,
    this.divergentByIso = const {},
    this.laneNames = const {},
    this.laneInitials = const {},
    required this.frozenByIso,
    this.agendaByIso = const {},
    required this.ownProfileId,
    required this.views,
    required this.today,
    required this.loading,
    required this.selectedIso,
    required this.onDayTap,
    required this.onDayLongPress,
    required this.availableHeight,
    required this.emptyPrompt,
    required this.horizonNote,
    required this.onPlanMonth,
  });

  /// The F-12 cell badge — mirror of Home.razor's day-frozen markup: a bell
  /// when the request awaits MY response (overdue gets the red variant), an
  /// hourglass when it awaits someone else; the semantics label carries the web's title text.
  _FrozenMark? _markFor(SwapRequest? frozen, Localization l) {
    if (frozen == null) return null;
    final awaitingMe = frozen.targetProfileId == ownProfileId;
    final overdue =
        frozen.toView().priorityTag(DateTime.now()) == SwapPriorityTag.overdue;
    if (awaitingMe) {
      return _FrozenMark(
        badge: Icons.notifications_active,
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
      badge: Icons.hourglass_top,
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
          // U-40: the strip is part of what has to fit under the initials.
          final strip =
              emptyPrompt == EmptyMonthPrompt.none ? 0.0 : _emptyStripHeight;
          final free =
              availableHeight - chrome - strip - (rows - 1) * _daySpacing;
          final cellHeight = (free / rows)
              .clamp(_dayCellMinHeight, _dayCellMaxHeight);
          final ratio = cellWidth / cellHeight;
          if (loading) {
            // U-27: the grid's own shape, at its own aspect ratio — the month
            // does not jump into place when the days land.
            return AppSkeletonCalendar(childAspectRatio: ratio);
          }
          // U-39: one typographic step for the whole month, chosen from the
          // cell this range produced, at the READER's scale (the factor at
          // the cell's own type size — exact for the number, within a hair
          // for the 9–11 px lines), and with the time's width MEASURED in
          // the reader's language rather than counted.
          final scale = MediaQuery.textScalerOf(context).scale(TypeScale.label) /
              TypeScale.label;
          final type = DayCellType.resolve(
              width: cellWidth,
              height: cellHeight,
              scale: scale,
              timeWidth: (fontSize) => _widestTime(context, fontSize));
          return _grid(
              context, ratio, type, daysInMonth, blanksBefore, todayIso);
        }),
        // U-40: thirty grey dots look like a plan; the sentence says there is
        // none, and what to do — under the grid it describes, in the list, so
        // it travels with the month.
        if (emptyPrompt != EmptyMonthPrompt.none)
          EmptyMonthStrip(
            month: month,
            prompt: emptyPrompt,
            horizonNote: horizonNote,
            onPlan: onPlanMonth,
          ),
      ],
    );
  }

  /// The width of the widest handoff time the reader's language prints, at
  /// [fontSize] (already scaled), in the style the cell paints it with. Two
  /// probes cover both catalogs: "10:00" / "10:00 AM" and "12:00" /
  /// "12:00 PM" — the 12-hour clock adds a period, and the digits differ.
  double _widestTime(BuildContext context, double fontSize) {
    final l = AppL10n.of(context).l;
    final style =
        DefaultTextStyle.of(context).style.copyWith(fontSize: fontSize, height: 1);
    var widest = 0.0;
    for (final probe in const ['10:00', '12:00']) {
      final painter = TextPainter(
        text: TextSpan(text: l.formatTimeString(probe), style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      widest = math.max(widest, painter.width);
      painter.dispose();
    }
    return widest;
  }

  Widget _grid(BuildContext context, double ratio, DayCellType type,
          int daysInMonth, int blanksBefore, String todayIso) =>
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
                  lanes: divergentByIso[CareSchedule.isoDate(
                          DateTime(month.year, month.month, day))] ??
                      const [],
                  laneNames: laneNames,
                  laneInitials: laneInitials,
                  frozenMark: _markFor(
                      frozenByIso[CareSchedule.isoDate(
                          DateTime(month.year, month.month, day))],
                      AppL10n.of(context).l),
                  views: views,
                  agenda: agendaByIso[CareSchedule.isoDate(
                          DateTime(month.year, month.month, day))] ??
                      const [],
                  isToday: CareSchedule.isoDate(
                          DateTime(month.year, month.month, day)) ==
                      todayIso,
                  isSelected: selectedIso.contains(CareSchedule.isoDate(
                      DateTime(month.year, month.month, day))),
                  type: type,
                  onTap: onDayTap,
                  onLongPress: onDayLongPress,
                ),
            ],
          );
}

/// U-40 — the sentence under an empty month. Two shapes, both decided in
/// core (`emptyMonthPrompt`): the month named plus *Gerar plano*, or the F-39
/// sentence alone when the wizard could not write a single day of this month.
/// Discreet on purpose — muted body text and a text button, never a banner:
/// an empty future month is a normal state, not a warning. Public so the
/// tests can find its door by key.
class EmptyMonthStrip extends StatelessWidget {
  final DateTime month;
  final EmptyMonthPrompt prompt;
  final String horizonNote;
  final VoidCallback onPlan;

  /// The *Gerar plano* button.
  static const Key planKey = Key('empty-month-plan');

  const EmptyMonthStrip({
    super.key,
    required this.month,
    required this.prompt,
    required this.horizonNote,
    required this.onPlan,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    final style = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: context.tokens.textMuted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, Spacing.sm, 4, 0),
      child: prompt == EmptyMonthPrompt.beyondHorizon
          ? Text(horizonNote, style: style, textAlign: TextAlign.center)
          : Row(
              children: [
                Expanded(
                  child: Text(
                    l.format(K.calEmptyMonth, [l.monthName(month.month)]),
                    style: style,
                  ),
                ),
                TextButton(
                  key: planKey,
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                  onPressed: onPlan,
                  child: Text(l[K.calEmptyMonthPlan]),
                ),
              ],
            ),
    );
  }
}

/// The carer's disc in a day cell — a circle that takes its new radius on
/// the SAME frame the cell does.
///
/// It was a `CircleAvatar`, which is an `AnimatedContainer` inside: when the
/// U-39 step drops from comfortable to compact (the selection bar appearing
/// takes the cell from 61 dp to its 50 dp floor), the avatar kept animating
/// from radius 12 to 9 for 200 ms while the cell had already shrunk, and for
/// those frames 14 + 2 + 24 + 2 + 11 = 51 dp of content sat in a 46 dp
/// column — `RenderFlex overflowed by 5 pixels`, found by U-40's strip, which
/// is what first pushed a month with marks to the floor in a test. A cell's
/// geometry is decided once per layout; nothing inside it may tween.
class DayCellAvatar extends StatelessWidget {
  final double radius;
  final Color color;
  final Widget child;

  const DayCellAvatar({
    super.key,
    required this.radius,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          child: Center(child: child),
        ),
      );
}

/// What a frozen day paints on its cell (computed in [_MonthGrid._markFor]).
class _FrozenMark {
  final IconData badge; // bell (mine) · hourglass (theirs)
  final bool overdue;
  final String label; // semantics — the web's badge title
  const _FrozenMark(
      {required this.badge, required this.overdue, required this.label});
}

class _DayCell extends StatelessWidget {
  final DateTime date;
  final CareSchedule? day;

  /// F-07: on a divergent date of *Todas*, every child's row — the fill is
  /// split between their carers' tones and the cell says who has whom.
  final List<CareSchedule> lanes;
  final Map<int, String> laneNames;
  final Map<int, String> laneInitials;
  final _FrozenMark? frozenMark;
  final List<MemberView> views;

  /// F-55: the day's live agenda items, first one first.
  final List<ChildEvent> agenda;
  final bool isToday;
  final bool isSelected;

  /// U-39 — the typographic step [_MonthGrid] resolved for this month,
  /// text-scale cap included (see [DayCellType.resolve]).
  final DayCellType type;
  final void Function(DateTime) onTap;
  final void Function(DateTime) onLongPress;

  const _DayCell({
    required this.date,
    required this.day,
    this.lanes = const [],
    this.laneNames = const {},
    this.laneInitials = const {},
    required this.frozenMark,
    required this.views,
    this.agenda = const [],
    required this.isToday,
    required this.isSelected,
    required this.type,
    required this.onTap,
    required this.onLongPress,
  });

  /// "Agenda: Escola 10:30" / "Agenda: Escola 10:30 e mais 2".
  String _agendaAloud(Localization l) {
    final first = agenda.first;
    final kind = AgendaKind.parse(first.kind) ?? AgendaKind.other;
    final what = [
      l[kind.labelKey],
      if (first.startTime != null) l.formatTimeString(first.startTime!),
    ].join(' ');
    return agenda.length == 1
        ? l.format(KApp.agendaCellAria, [what])
        : l.format(KApp.agendaCellAriaMore, [what, agenda.length - 1]);
  }

  /// The day number — and, on a day with agenda items, the first item's icon
  /// beside it, with a small "+" on its shoulder when more follow (owner's
  /// validation, 25/09/2026). The first line, because the third is the
  /// handoff time or the frozen mark and was already the tightest (U-39).
  ///
  /// The icon holds the step's size while the number follows the reader's
  /// scale: at 1.3× a scaled icon plus a "+" beside it overflowed the 360 dp
  /// cell by 8 px (the worst-case test). The "+" sits inside a box reserved
  /// for it, never beside the icon; the rare line that still does not fit
  /// shrinks as a whole, never below the product's floor (U-48).
  Widget _numberLine(BuildContext context, AppTokens tokens, Color? ink) {
    final number = Text('${date.day}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: type.number, height: 1, color: ink));
    if (agenda.isEmpty) return number;
    final size = type.number;
    final color = ink ?? tokens.textMuted;
    final kind = AgendaKind.parse(agenda.first.kind) ?? AgendaKind.other;
    final icon = Icon(agendaKindIcon(kind), size: size, color: color);
    return AppShrinkToFit(
      alignment: Alignment.center,
      child: Row(
        key: ValueKey('cell-agenda-${date.day}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          number,
          SizedBox(width: size * 0.15),
          if (agenda.length == 1)
            icon
          else
            SizedBox(
              width: size * 1.4,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PositionedDirectional(start: 0, top: 0, child: icon),
                  PositionedDirectional(
                    end: 0,
                    top: -size * 0.2,
                    child: Icon(Icons.add,
                        key: ValueKey('cell-agenda-more-${date.day}'),
                        size: size * 0.6,
                        color: color),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

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
    final split = lanes.length > 1;
    // F-07 (owner's QA, 29/09/2026): one COLUMN per distinct carer, in the
    // children's order — the carer's avatar on top, the children's (neutral)
    // below, so who has whom reads without a tap. `fitSplitCell` (core)
    // sizes it all. Round 3: each column stands on its carer's light tone
    // (a white cell read as "not planned"), under a neutral border.
    final carers = <int, List<int?>>{};
    for (final r in lanes) {
      (carers[r.effectiveParentId] ??= []).add(r.childId);
    }
    LinearGradient? bands;
    if (split) {
      final tones = [
        for (final id in carers.keys)
          context.tokens.slot(profileSlotIndex(id, views)).tone.container,
      ];
      final n = tones.length;
      // Hard stops: flat bands, not a blend.
      bands = LinearGradient(
        colors: [for (final t in tones) ...[t, t]],
        stops: [
          for (var i = 0; i < n; i++) ...[i / n, (i + 1) / n],
        ],
      );
    }
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
    if (split) {
      // F-07: "Lia com Ana; Theo com Bruno" — the split said aloud.
      String nameOf(int id) =>
          views.where((v) => v.id == id).firstOrNull?.fullName ?? '';
      responsibleName = [
        for (final r in lanes)
          l.format(KApp.calLaneWith,
              [laneNames[r.childId] ?? '', nameOf(r.effectiveParentId)]),
      ].join('; ');
    } else if (effectiveId != null) {
      for (final v in views) {
        if (v.id == effectiveId) {
          responsibleName = v.fullName;
          break;
        }
      }
    }
    // U-32: a day with nobody says so — U-11's own phrase, idle in the
    // catalog since the port. Before, a blind reader heard bare numbers for
    // every unplanned day and could not tell "not loaded" from "nobody".
    final semanticsLabel = [
      '${date.day}',
      if (isToday) l[K.calToday],
      if (responsibleName != null)
        responsibleName
      else if (!assigned)
        l[K.calAriaNoResponsible],
      if (isSwapped) l[K.calSwapped],
      if (frozenMark != null)
        frozenMark!.label
      else if (day?.handoffTime != null)
        '${l[K.editorHandoffTime]} '
            '${l.formatTimeString(day!.handoffTime!)}',
      // The agenda mark is drawn for the eye; this is the same fact aloud.
      if (agenda.isNotEmpty) _agendaAloud(l),
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
      // U-32: the long press is the only way into bulk selection on Android
      // and nothing announced it — TalkBack reads these as "double-tap to
      // open the day; double-tap and hold to select several days".
      onTapHint: l[K.calAriaTapHint],
      onLongPressHint: l[K.calAriaLongPressHint],
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.md),
              color: isSelected
                  ? primary.withValues(alpha: 0.12)
                  : split
                      ? null
                      : assigned
                          ? slot.tone.container
                          : null,
              gradient: isSelected ? null : bands,
            ),
            // U-48: the border is a FOREGROUND decoration, so the ink below
            // fills the whole cell (a `decoration` border insets the child by
            // its width, and the U-28/U-39 suites measure the InkWell as the
            // cell) and the ring draws over hover and ripple, never under.
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.md),
              // U-28: "today" was a 2 px indigo hairline that vanished into a
              // tinted cell. It is the mark a reader looks for FIRST, so it
              // takes the text colour and real weight — the web's black ring.
              border: isSelected
                  ? Border.all(color: primary, width: 2)
                  : isToday
                      ? Border.all(color: tokens.text, width: 2.5)
                      : Border.all(
                          color: assigned && !isSwapped && !split
                              ? slot.tone.border
                              : tokens.outline),
            ),
            // U-48: the ink lives INSIDE the tinted box. An `InkWell` paints
            // its hover and ripple on the nearest `Material` — the
            // Scaffold's, UNDER this opaque container — so on the web a
            // pointer over an assigned day showed nothing (and a tap rippled
            // under the fill). A transparent `Material` between the fill and
            // the ink puts the state layer over the tint, at Material 3's
            // 8 % of the slot's own colour (the card's 4 % vanished on a
            // tinted container). The pointer cursor is the InkWell's own.
            child: Material(
              type: MaterialType.transparency,
              borderRadius: BorderRadius.circular(Radii.md),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onTap(date),
                // U-11: the mobile entry point to bulk selection (web:
                // 500 ms press).
                onLongPress: () => onLongPress(date),
                hoverColor: (assigned ? slot.tone.solid : tokens.text)
                    .withValues(alpha: _hoverAlpha),
                child: CustomPaint(
              painter: assigned && !split
                  ? SlotPatternPainter(slot.pattern, slot.tone.border)
                  : null,
              // U-39: one clamp over the cell's texts, a no-op wherever the
              // step fits at the reader's scale (DayCellType.textScaleCap).
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: type.textScaleCap,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _numberLine(context, tokens,
                        assigned ? slot.tone.onContainer : null),
                    const SizedBox(height: DayCellType.gap),
                    // F-07: the split day draws its columns in the avatar's
                    // place — number and columns centred as one group, as
                    // every other cell centres number and avatar (round 3).
                    if (split)
                      _SplitColumns(
                        key: ValueKey('cell-split-${date.day}'),
                        carers: carers,
                        views: views,
                        laneInitials: laneInitials,
                        avatarDiameter: type.avatarRadius * 2,
                      )
                    else
                      DayCellAvatar(
                        radius: type.avatarRadius,
                        color: assigned ? slot.tone.solid : Colors.transparent,
                        child: Text(initial,
                            style: TextStyle(
                                fontSize: type.initial,
                                height: 1,
                                color: assigned
                                    ? slot.tone.onSolid
                                    : Theme.of(context).hintColor)),
                      ),
                    // U-29 round 4 (owner): the same breath the date already
                    // gets above the avatar — without it the time sat glued to
                    // the initial. Gated, so a badge-less cell stays centred.
                    if (!split &&
                        (frozenMark != null || day?.handoffTime != null))
                      const SizedBox(height: DayCellType.gap),
                    // Web parity: the frozen badge REPLACES the handoff badge.
                    // (U-29: its label rides the CELL's semantics node now.)
                    // F-07: the split day has no room for a mark or a time
                    // (they may differ per child); the tap shows both.
                    if (split)
                      const SizedBox.shrink()
                    else if (frozenMark != null)
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
                        child: Icon(frozenMark!.badge,
                            size: type.mark,
                            color: frozenMark!.overdue
                                ? tokens.danger.onContainer
                                : frozenMark!.badge ==
                                        Icons.notifications_active
                                    ? tokens.warning.solid
                                    : tokens.textMuted),
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
                        // One line, always: the step and the cap were chosen
                        // so it fits; below the design size (which U-28
                        // measured to fit) a clip beats a second line that
                        // would push the avatar out of the cell.
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                            fontSize: type.time,
                            height: 1,
                            color: assigned
                                ? slot.tone.onContainer
                                : Theme.of(context).hintColor),
                      ),
                  ],
                ),
              ),
                ),
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
              child: Icon(Icons.check, size: 12, color: primary),
            ),
        ],
      ),
    );
  }

  /// Material 3's hover state layer: 8 % of the content colour.
  static const double _hoverAlpha = 0.08;
}

/// F-07 (owner's QA, 29/09/2026) — the split day's columns: one per carer,
/// the carer's avatar on top and the children's below (a "+N" when they do
/// not fit). Sized by `fitSplitCell` (core), whose floors are exception D
/// of `no_tiny_text_test` — the letters here are under the U-48 floor on
/// purpose, by the owner's decision, and ONLY here.
class _SplitColumns extends StatelessWidget {
  final Map<int, List<int?>> carers;
  final List<MemberView> views;
  final Map<int, String> laneInitials;
  final double avatarDiameter;

  const _SplitColumns({
    super.key,
    required this.carers,
    required this.views,
    required this.laneInitials,
    required this.avatarDiameter,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final surface = Theme.of(context).colorScheme.surface;
    return LayoutBuilder(builder: (context, box) {
      final entries = carers.entries.toList();
      final width = box.maxWidth;
      final fit = fitSplitCell(
        width: width,
        avatarDiameter: avatarDiameter,
        childrenPerColumn: [for (final e in entries) e.value.length],
      );
      Widget child(String letters) => MiniAvatar(
            diameter: fit.childDiameter,
            letters: letters,
            fill: surface,
            ink: tokens.text,
            ring: tokens.textMuted,
            letterScale: SplitCellFit.childLetter,
          );
      // Each column is centred on its band. Round 3 (owner, iPhone SE with
      // four carers): the carers' floor (14 dp) is wider than a quarter of a
      // 46 dp cell, so they OVERLAP there, ringed in the surface colour so
      // each circle stays whole — instead of the fourth falling off the edge.
      final column = width / entries.length;
      final overlapping = fit.carerDiameter > column;
      final step = fit.childDiameter * (1 - SplitCellFit.overlap);
      double left(double centre, double size) =>
          (centre - size / 2).clamp(0.0, math.max(0.0, width - size));
      return SizedBox(
          width: width,
          height: fit.carerDiameter + 2 + fit.childDiameter,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (final (i, e) in entries.indexed) ...() {
                final centre = column * (i + 0.5);
                final slot = tokens.slot(profileSlotIndex(e.key, views));
                final count = fit.shown[i] + (fit.more[i] > 0 ? 1 : 0);
                final start = left(
                    centre, fit.childDiameter + (count - 1) * step);
                return [
                  Positioned(
                    left: left(centre, fit.carerDiameter),
                    top: 0,
                    child: MiniAvatar(
                      diameter: fit.carerDiameter,
                      letters: displayInitials(e.key, views),
                      fill: slot.tone.solid,
                      ink: slot.tone.onSolid,
                      ring: overlapping ? surface : null,
                      letterScale: SplitCellFit.carerLetter,
                    ),
                  ),
                  for (var k = 0; k < fit.shown[i]; k++)
                    Positioned(
                      left: start + k * step,
                      top: fit.carerDiameter + 2,
                      child: child(laneInitials[e.value[k]] ?? '?'),
                    ),
                  if (fit.more[i] > 0)
                    Positioned(
                      left: start + fit.shown[i] * step,
                      top: fit.carerDiameter + 2,
                      child: child('+${fit.more[i]}'),
                    ),
                ];
              }(),
            ],
          ),
      );
    });
  }
}

/// Owner's QA of 3.1.10 — the system strips the calendar queues, in order.
enum _SystemStrip { pushToday, checklist, handoffNudge }
