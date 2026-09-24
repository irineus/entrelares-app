import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';

import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_db_contracts/models/day_notice.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import '../services/analytics_service.dart';
import '../services/connectivity_status.dart';
import '../services/custody_data_source.dart';
import '../services/notification_badge.dart';
import '../services/push_service.dart';
import '../widgets/account_button.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';
import '../widgets/install_hint_sheet.dart';
import 'notice_sheet.dart';
import 'frozen_day_sheet.dart';

/// The Notifications page — port of `Notifications.razor`: three tabs
/// ("Para você" = open requests where I am the approver, "Enviadas" = my
/// newest 100 requests, "Todas" = my newest 100 notification rows,
/// rebuilt in the READER's language by the NotificationRenderer). Opening the
/// page marks everything read (web parity — one bulk PATCH); the F-45 diff
/// list arrives with the audit mirror in lote 6 (decision 19/08/2026).
///
/// U-42: the first two tabs are LISTS, not forms. Each request is one compact
/// row and tapping it opens [showFrozenDaySheet] — the same sheet the calendar
/// opens for a frozen day, which already knows the three roles (target
/// approves/rejects with the F-44 note, requester cancels, observer reads).
/// Approve/reject/cancel therefore exist in ONE place; this screen renders no
/// action button of its own. Before U-42 every incoming card carried a text
/// field and two buttons, so four open requests were four fields and eight
/// buttons on one screen, and the two copies of the action had already
/// drifted apart.
class NotificationsScreen extends StatefulWidget {
  final CustodyDataSource dataSource;
  final NotificationBadge badge;

  /// F-09. Null on a build with no push transport at all — the screen then says
  /// so (U-43: a line after the list) rather than staying silent, because
  /// "where are my alerts?" is a question a blank space answers badly.
  final PushService? push;

  /// F-09: which tab a TAPPED notification asked for ([PushRouting]).
  final NotificationLanding? landing;

  /// The tapped notification's id. It exists only to make the landing apply
  /// AGAIN: this screen lives in a shell branch, so its State survives a second
  /// navigation, and comparing the landing alone would silently ignore a second
  /// tap that wants the same tab the person has since navigated away from.
  final String? landingNonce;

  /// T-18: offline, a request opens without its answer buttons (see
  /// `showFrozenDaySheet`). Null in tests that do not exercise it.
  final ConnectivityStatus? connectivity;

  /// U-54: what the browser said about itself (U-51's seam), or null in the
  /// native app. With the push state it picks the ONE next step this device
  /// can take ([PushNudgeRules]).
  final BrowserInstallFacts? installFacts;

  /// U-54: the nudge's impressions and taps, and the enable result.
  final AnalyticsService? analytics;

  /// F-70: a plan-end row's "Planejar os próximos meses" — the host takes the
  /// reader to the calendar with the wizard open on this day. Null hides the
  /// action (tests, hosts without a calendar).
  final ValueChanged<DateTime>? onPlanFrom;

  /// F-34: an expense or settle-up row's "Abrir Despesas". Null hides it.
  final VoidCallback? onOpenExpenses;

  /// The notification types whose row opens Despesas.
  static const Set<String> expenseTypes = {
    'expense_changed',
    'settlement_requested',
    'settlement_answered',
  };

  static Key expenseActionKey(int id) => Key('notif-expense-$id');

  const NotificationsScreen(
      {super.key,
      required this.dataSource,
      required this.badge,
      this.connectivity,
      this.push,
      this.installFacts,
      this.analytics,
      this.onPlanFrom,
      this.onOpenExpenses,
      this.landing,
      this.landingNonce});

  /// U-43 — the three shapes of the push control, so a test finds each without
  /// a localized finder: the app-bar icon (on), the sheet's way out, and the
  /// line after the list (blocked / unsupported).
  static const pushStatusKey = Key('push-status');
  static const pushDisableKey = Key('push-disable');
  static const pushFooterKey = Key('push-footer');

  /// U-54: the iPhone-in-Safari step, above the list.
  static const pushInstallKey = Key('push-install');

  /// F-70: the plan-end row's action, per notification.
  static Key planActionKey(Object notificationId) =>
      ValueKey('plan-end-action-$notificationId');

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

enum _Tab { incoming, sent, history }

/// Mirror of `GetNotifIcon` — a vector icon per type since U-31, one family
/// of outlined Material glyphs so the rail reads as one voice.
IconData notifIcon(String type) => switch (type) {
      'swap_requested' => Icons.swap_horiz,
      'swap_sent' || 'revert_sent' => Icons.outbox_outlined,
      'swap_approved' ||
      'swap_approved_self' ||
      'revert_approved' ||
      'revert_approved_self' =>
        Icons.check_circle_outline,
      'swap_rejected' || 'revert_rejected' => Icons.highlight_off,
      'swap_cancelled' || 'revert_cancelled' => Icons.block,
      'swap_reverted' || 'revert_requested' => Icons.undo,
      'auto_reminder' => Icons.alarm,
      'auto_approved' => Icons.smart_toy_outlined,
      'swap_family_info' => Icons.groups_outlined,
      'email_cap_80' => Icons.warning_amber_rounded,
      'email_cap_last' || 'email_cap_reached' => Icons.mail_outline,
      'billing' => Icons.credit_card,
      'plan_ending' => Icons.event_note_outlined,
      _ => Icons.notifications_none,
    };

class _NotificationsScreenState extends State<NotificationsScreen> {
  _Tab _tab = _Tab.incoming;
  bool _loading = true;
  String? _loadError;
  List<Member> _allProfiles = const [];
  Member? _ownProfile;
  List<SwapRequest> _incoming = const [];

  /// F-52: the avisos about TODAY that are still open, are somebody else's and
  /// ASK for something. They sit in "Para você" because that is the tab a push
  /// of a PICKUP or KEEP opens — `PushRouting.landingFor` sends those two
  /// kinds here and every other one to "Todas". A notice that asks something,
  /// arrives on this phone and is not listed here is exactly the empty-tab
  /// defect that rule exists to prevent.
  List<DayNotice> _openNotices = const [];
  List<SwapRequest> _sent = const [];
  List<AppNotification> _history = const [];

  @override
  void initState() {
    super.initState();
    _applyLanding();
    widget.push?.addListener(_onPushChanged);
    _trackNudgeView();
    _init();
  }

  @override
  void didUpdateWidget(NotificationsScreen old) {
    super.didUpdateWidget(old);
    if (widget.landingNonce != old.landingNonce) _applyLanding();
    if (widget.push != old.push) {
      old.push?.removeListener(_onPushChanged);
      widget.push?.addListener(_onPushChanged);
    }
  }

  @override
  void dispose() {
    widget.push?.removeListener(_onPushChanged);
    super.dispose();
  }

  /// U-43: WHERE the push control sits now depends on its state, so a state
  /// that settles after this screen mounted (the service is still reading the
  /// permission) has to move it — not wait for the next unrelated rebuild.
  void _onPushChanged() {
    if (!mounted) return;
    setState(() {});
    _trackNudgeView();
  }

  /// U-54 — the next step toward push for THIS device, and only for the
  /// member holding it: nothing here is ever shown about another member.
  PushNudgeStep get _nudge =>
      PushNudgeRules.step(state: _pushState, facts: widget.installFacts);

  PushNudgePlatform get _platform =>
      PushNudgeRules.platform(widget.installFacts);

  /// One impression per app session (T-76), fired where the answer is KNOWN,
  /// never from `build`. The two "unsupported" steps are left out on purpose:
  /// `unsupported` is also the service's state BEFORE it settles, so counting
  /// them would count a phone that is about to say `off`. Every step counted
  /// here is one the service only reaches by settling — or, on an iPhone
  /// tab, one that cannot change.
  void _trackNudgeView() {
    final analytics = widget.analytics;
    final step = _nudge;
    if (analytics == null) return;
    if (step == PushNudgeStep.none ||
        step == PushNudgeStep.unsupportedHere ||
        step == PushNudgeStep.unsupportedBrowser) {
      return;
    }
    unawaited(analytics.trackEventOnce(AnalyticsEvents.pushNudgeView,
        props: analyticsFunnelProps(
            channel: analytics.channel, platform: _platform, step: step)));
  }

  void _trackNudgeClick(PushNudgeStep step) {
    final analytics = widget.analytics;
    if (analytics == null) return;
    unawaited(analytics.trackEvent(AnalyticsEvents.pushNudgeClick,
        props: analyticsFunnelProps(
            channel: analytics.channel, platform: _platform, step: step)));
  }

  /// F-09 — a tapped notification chooses the tab.
  ///
  /// Without this the tap lands on "Para você", which lists OPEN requests, and
  /// a notice saying a swap was APPROVED is about a request that is now closed
  /// — so the person taps the notification and arrives at "nada pendente para
  /// você", which reads as the app having lost what it just told them.
  void _applyLanding() {
    final landing = widget.landing;
    if (landing == null) return;
    _tab = switch (landing) {
      NotificationLanding.incoming => _Tab.incoming,
      NotificationLanding.history => _Tab.history,
    };
  }

  Future<void> _init() async {
    await _loadAll();
    // Web parity (OnInitializedAsync): refresh the badge, then mark
    // everything read — best-effort, never blocks the page.
    await widget.badge.refresh();
    try {
      final me = _ownProfile;
      if (me != null) {
        await widget.dataSource.markAllNotificationsRead(me.id);
      }
    } catch (_) {/* best-effort */}
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final profiles = await widget.dataSource.fetchMembers();
      final me = await widget.dataSource.fetchOwnProfile();
      final incoming =
          me == null ? <SwapRequest>[] : await widget.dataSource.fetchPendingForMe(me.id);
      final sent =
          me == null ? <SwapRequest>[] : await widget.dataSource.fetchSentRequests(me.id);
      // Best-effort: the notifications page must not fail to open because an
      // aviso could not be counted.
      var notices = <DayNotice>[];
      if (me != null) {
        try {
          notices = [
            for (final n in await widget.dataSource
                .fetchDayNotices(DateTime.now()))
              if (n.isOpen &&
                  n.senderProfileId != me.id &&
                  NoticeRequest.fromWire(n.request) != null &&
                  NoticeRequest.fromWire(n.request) != NoticeRequest.info)
                n
          ];
        } catch (_) {/* keep the page */}
      }
      final history = me == null
          ? <AppNotification>[]
          : await widget.dataSource.fetchNotifications(me.id);
      if (!mounted) return;
      setState(() {
        _allProfiles = profiles;
        _ownProfile = me;
        _incoming = incoming;
        _openNotices = notices;
        _sent = sent;
        _history = history;
        _loading = false;
        _loadError = null;
      });
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

  String? _nameOf(int? id) {
    for (final p in _allProfiles) {
      if (p.id == id) return p.fullName;
    }
    return null;
  }

  /// The one way to act on a request from this screen (U-42). The sheet does
  /// the work and reports the outcome; this screen reloads, refreshes the bell
  /// and shows the SAME toast the calendar shows for the same outcome.
  Future<void> _openRequest(SwapRequest req) async {
    _trackListOpen(req.isRevertPending ? 'revert_request' : 'swap_request');
    final outcome = await showFrozenDaySheet(
      context: context,
      request: req,
      allProfiles: _allProfiles,
      ownProfileId: _ownProfile?.id,
      dataSource: widget.dataSource,
      offline: widget.connectivity?.offline ?? false,
    );
    if (outcome == null || !mounted) return;
    await _loadAll();
    await widget.badge.refresh();
    if (mounted) {
      showAppSnack(
          context, AppL10n.of(context).l[frozenOutcomeToastKey(outcome)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      appBar: AppBar(
          title: Text(l[K.notifPageTitle]),
          actions: [
            // U-43: with push ON the control is this icon, not a card — the
            // first fold belongs to the list.
            if (_pushState == PushState.on)
              IconButton(
                key: NotificationsScreen.pushStatusKey,
                icon: const Icon(Icons.notifications_active_outlined),
                tooltip: l[KApp.pushStatusOnTooltip],
                onPressed: () => _openPushSheet(l),
              ),
            const AppAccountButton(),
          ]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: AppSegmented<_Tab>(
              options: [
                (
                  value: _Tab.incoming,
                  // F-52: an aviso waiting on an answer counts here too — the
                  // number on the tab is "things asking something of you", and
                  // leaving it out would put a row in a tab that claims to be
                  // empty.
                  label: _incoming.isEmpty && _openNotices.isEmpty
                      ? l[K.notifTabIncoming]
                      : '${l[K.notifTabIncoming]} '
                          '(${_incoming.length + _openNotices.length})'
                ),
                (value: _Tab.sent, label: l[K.notifTabSent]),
                (value: _Tab.history, label: l[K.notifTabHistory]),
              ],
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
          ),
          if (_nudge == PushNudgeStep.enable) _pushCard(l),
          if (_nudge == PushNudgeStep.install) _installCard(l),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await _loadAll();
                await widget.badge.refresh();
              },
              child: _loading
                  ? AppSkeletonList(rows: 3, semanticsLabel: l[K.famLoading])
                  // U-29: same recovery shape as the calendar and the reports
                  // tabs — a danger banner plus a visible retry.
                  : _loadError != null
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
                                  onPressed: _loadAll,
                                  child: Text(l[K.layoutErrorReload])),
                            ]),
                          ),
                          ..._pushFooter(l),
                        ])
                      : switch (_tab) {
                          _Tab.incoming => _incomingTab(l),
                          _Tab.sent => _sentTab(l),
                          _Tab.history => _historyTab(l),
                        },
            ),
          ),
        ],
      ),
    );
  }

  /// F-09 — the push control, and the reason it lives on THIS screen.
  ///
  /// The permission dialog is a one-shot resource on Android 13+: it appears
  /// once per install and a refusal is only undone in Settings. Asking on app
  /// load spends it on someone who has no idea yet what the product does. Here,
  /// the person is looking at the list of things they would have been told
  /// about — the one moment where "get these on your phone" answers a question
  /// they already have.
  ///
  /// U-43 — the control keeps this home and changes SHAPE with its state. Only
  /// OFF is a card above the list: it is a nudge, and it sits over exactly the
  /// list it promises. ON is an icon in the app bar ([_openPushSheet]); blocked
  /// and unsupported are a quiet line after the list ([_pushFooter]). Before,
  /// all four were this card, on every visit — a settings row holding the first
  /// fold of a screen whose purpose is the list.
  ///
  /// Every state still renders something. A blocked permission and a browser
  /// both look identical to a control that hides itself: alerts that never
  /// come, and no explanation anywhere.
  PushState get _pushState => widget.push?.state ?? PushState.unsupported;

  Widget _pushCard(Localization l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, Spacing.sm),
      child: AppCard(
        title: l[KApp.pushTitle],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l[KApp.pushHintOff],
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Spacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                  onPressed: () => _setPush(l, on: true),
                  child: Text(l[KApp.pushEnable])),
            ),
          ],
        ),
      ),
    );
  }

  /// U-54 — Safari on an iPhone or iPad, still in a tab. It has a button, so
  /// it sits where the U-43 card sits: over the list it promises. It opens the
  /// U-51 sheet, whatever became of the shell strip.
  ///
  /// The sentence states Apple's CONDITION, never that our delivery works on
  /// an iPhone — T-75 measures that on a real device (owner, 21/09/2026).
  Widget _installCard(Localization l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, Spacing.sm),
      child: AppBanner(
        key: NotificationsScreen.pushInstallKey,
        tone: context.tokens.info,
        icon: Icons.add_to_home_screen,
        message: l[KApp.pushHintInstallIos],
        actionLabel: l[KApp.pushInstallHow],
        onAction: () {
          _trackNudgeClick(PushNudgeStep.install);
          showInstallHintSheet(context);
        },
      ),
    );
  }

  /// U-43 — push is ON: the state and the way out, two taps from any tab.
  Future<void> _openPushSheet(Localization l) async {
    final disable = await showAppSheet<bool>(
      context: context,
      builder: (sheetContext) => AppSheetFrame(
        title: l[KApp.pushTitle],
        onClose: () => Navigator.of(sheetContext).pop(),
        closeLabel: l[K.commonClose],
        extraAction: OutlinedButton.icon(
          key: NotificationsScreen.pushDisableKey,
          onPressed: () => Navigator.of(sheetContext).pop(true),
          icon: const Icon(Icons.notifications_off_outlined),
          label: Text(l[KApp.pushDisable]),
        ),
        children: [Text(l[KApp.pushHintOn])],
      ),
    );
    if (disable == true && mounted) await _setPush(l, on: false);
  }

  /// U-43 — blocked / unsupported: the explanation, as the LAST item of
  /// whatever the tab shows (the empty state and the load error included).
  ///
  /// No button on purpose: the OS will not show the dialog again, so a button
  /// here would do nothing when pressed — the failure that makes an app look
  /// broken while it behaves exactly as designed.
  ///
  /// U-54: the line now says WHERE to go on this device — the Android
  /// Settings path, the iPhone's Ajustes path or the site permission beside
  /// the address — each read from the vendor's own guide (see the catalog).
  List<Widget> _pushFooter(Localization l) {
    final hint = switch (_nudge) {
      PushNudgeStep.needsSafari => l[KApp.pushHintNeedsSafari],
      PushNudgeStep.reallowApp => l[KApp.pushHintReallowApp],
      PushNudgeStep.reallowIos => l[KApp.pushHintReallowIos],
      PushNudgeStep.reallowBrowser => l[KApp.pushHintReallowBrowser],
      PushNudgeStep.unsupportedHere => l[KApp.pushHintUnsupportedHere],
      PushNudgeStep.unsupportedBrowser => l[KApp.pushHintUnsupported],
      PushNudgeStep.none ||
      PushNudgeStep.enable ||
      PushNudgeStep.install =>
        null,
    };
    if (hint == null) return const [];
    final muted = context.tokens.textMuted;
    return [
      Padding(
        key: NotificationsScreen.pushFooterKey,
        padding: const EdgeInsets.fromLTRB(
            Spacing.md, Spacing.sm, Spacing.md, Spacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
                child: Icon(Icons.notifications_off_outlined,
                    size: 18, color: muted)),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Text(hint,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: muted)),
            ),
          ],
        ),
      ),
    ];
  }

  Future<void> _setPush(Localization l, {required bool on}) async {
    final push = widget.push;
    if (push == null) return;

    if (on) {
      _trackNudgeClick(PushNudgeStep.enable);
      final result = await push.enable();
      final analytics = widget.analytics;
      if (analytics != null) {
        unawaited(analytics.trackEvent(AnalyticsEvents.pushEnableResult,
            props: analyticsFunnelProps(
                channel: analytics.channel,
                platform: _platform,
                outcome: PushNudgeRules.enableOutcome(result))));
      }
      if (!mounted) return;
      setState(() {});
      // The message reads off the RESULTING state, never off the fact that a
      // button was pressed: a dialog the person dismissed leaves the state
      // exactly where it was, and "alerts are on" would be a lie they discover
      // the next time a swap goes unanswered.
      showAppSnack(context,
          result == PushState.on ? l[KApp.pushToastOn] : l[KApp.pushErrEnable],
          type: result == PushState.on
              ? AppSnackType.success
              : AppSnackType.error);
      return;
    }

    await push.disable();
    if (!mounted) return;
    setState(() {});
    showAppSnack(context, l[KApp.pushToastOff]);
  }

  // Still a ListView: the empty tab has to stay pull-to-refreshable, which is
  // the one thing the shared component cannot know about.
  Widget _empty(IconData icon, String textKey, Localization l) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: Spacing.md),
          AppEmptyState(icon: icon, title: l[textKey]),
          ..._pushFooter(l),
        ],
      );

  /// U-28 — a row's first line: the day on the left, its state pills on the
  /// right, and a SECOND LINE for the pills when they do not fit.
  ///
  /// It was a `Row` with the date in an `Expanded` beside a `Wrap` of up to
  /// three badges. `Row` lays the inflexible child out first, so the badges took
  /// the width they wanted and the `Expanded` got what was left — around ten
  /// pixels, which the date then filled ONE CHARACTER PER LINE while the badges
  /// still reported `RIGHT OVERFLOWED BY 85 PIXELS`. A `Wrap` cannot do that to
  /// itself: what does not fit moves down.
  Widget _rowHeader(String title, List<Widget> badges) => Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.xs,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.event_outlined,
                  size: 18, color: context.tokens.textMuted),
              const SizedBox(width: Spacing.xs),
              Text(title, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          Wrap(spacing: Spacing.xs, runSpacing: Spacing.xs, children: badges),
        ],
      );

  Widget _statusBadge(String text, {ToneColors? tone, String? semantics}) =>
      AppBadge(
        text: text,
        tone: tone ?? context.tokens.neutral,
        semantics: semantics,
      );

  /// F-20 urgency as a pill. The banner it replaces took a full line per card;
  /// on a row the state is a badge beside the date, and the sheet still says
  /// the whole sentence.
  Widget _tagBadge(SwapPriorityTag tag, Localization l) => _statusBadge(
        l[tag == SwapPriorityTag.overdue
            ? K.notifTagOverdueShort
            : K.notifTagUrgentShort],
        tone: tag == SwapPriorityTag.overdue
            ? context.tokens.danger
            : context.tokens.warning,
      );

  /// One request, one compact row (U-42): the date and its pills, one line of
  /// facts, and a chevron when tapping it leads somewhere. [onTap] null is a
  /// resolved request in "Enviadas" — there is nothing left to do on it, so it
  /// is read-only here rather than opening a sheet whose only content would be
  /// an action the database is about to refuse.
  ///
  /// The key names the request so the E2E lane can find THIS row without
  /// depending on how the date or a name is rendered.
  Widget _requestRow({
    required SwapRequest req,
    required String title,
    required List<Widget> badges,
    required List<String> lines,
    required VoidCallback? onTap,
  }) {
    final theme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm + Spacing.xs, vertical: Spacing.sm - 2),
      child: AppCard(
        key: ValueKey('swap-request-${req.id}'),
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm + Spacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _rowHeader(title, badges),
                  const SizedBox(height: Spacing.xs),
                  for (final line in lines)
                    Text(line, style: theme.bodySmall),
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: Spacing.xs),
              Icon(Icons.chevron_right,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ],
          ],
        ),
      ),
    );
  }

  // ── "Para você" ────────────────────────────────────────────────────────────

  Widget _incomingTab(Localization l) {
    if (_incoming.isEmpty && _openNotices.isEmpty) {
      return _empty(Icons.task_alt, K.notifEmptyIncoming, l);
    }
    final now = DateTime.now();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        // F-52 first, and not by accident: an aviso is about RIGHT NOW, and a
        // swap request has 48 h. Sorting by urgency here means sorting by
        // what the reader can still do something about.
        for (final notice in _openNotices) _noticeRow(notice, l),
        for (final req in _incoming) _incomingRow(req, now, l),
        const SizedBox(height: 12),
        ..._pushFooter(l),
      ],
    );
  }

  /// F-52 — an open aviso, in the tab its push opens. The sentence is the one
  /// `noticeSentence` composes, the same the card's strip and the notification
  /// show; a second copy of it here is how "30 min" on one screen and "sem
  /// previsão" on another both end up well-formed and disagreeing.
  Widget _noticeRow(DayNotice notice, Localization l) {
    final reason = NoticeReason.fromWire(notice.reason);
    final request = NoticeRequest.fromWire(notice.request);
    if (reason == null || request == null) return const SizedBox.shrink();
    final theme = Theme.of(context).textTheme;
    final sentence = noticeSentence(
      l: l,
      senderName: _nameOf(notice.senderProfileId) ??
          l[K.notifRenderFbOtherCap],
      reason: reason,
      etaMinutes: notice.etaMinutes,
      request: request,
      note: notice.note,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.sm + Spacing.xs, vertical: Spacing.sm - 2),
      child: AppCard(
        key: ValueKey('day-notice-${notice.id}'),
        // F-50: a Visualizador reads the aviso and answers nothing.
        onTap: _ownProfile?.isViewer == true
            ? null
            : () => _answerNotice(notice, sentence),
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.md, vertical: Spacing.sm + Spacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _rowHeader(l[K.notifRenderTitleDayNotice], [
                    _statusBadge(l[KApp.noticeAnswerTitle],
                        tone: context.tokens.warning),
                  ]),
                  const SizedBox(height: Spacing.xs),
                  Text(sentence, style: theme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: Spacing.xs),
            Icon(Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  /// T-78: a row of *Para você* opened — the push twin fires in main.dart.
  void _trackListOpen(String type) => unawaited(widget.analytics?.trackEvent(
          AnalyticsEvents.notificationOpen,
          props: {'source': 'list', 'type': type}) ??
      Future<void>.value());

  Future<void> _answerNotice(DayNotice notice, String sentence) async {
    _trackListOpen('day_notice');
    final outcome = await showAnswerNoticeSheet(
      context: context,
      dataSource: widget.dataSource,
      notice: notice,
      sentence: sentence,
    );
    if (outcome == null || !mounted) return;
    await _loadAll();
    if (!mounted) return;
    showAppSnack(
        context,
        AppL10n.of(context).l[outcome == NoticeOutcome.keeping
            ? KApp.noticeAnsweredKeeping
            : KApp.noticeAnsweredHelping]);
  }

  Widget _incomingRow(SwapRequest req, DateTime now, Localization l) {
    final isRevert = req.isRevertPending;
    final tag = req.toView().priorityTag(now); // F-20: pending → clock
    return _requestRow(
      req: req,
      title: l.formatDate(req.scheduleDate),
      badges: [
        _statusBadge(
          l[isRevert ? K.notifRevertPendingBadge : K.notifPendingBadge],
          tone: isRevert ? context.tokens.accent : context.tokens.warning,
        ),
        if (tag != SwapPriorityTag.none) _tagBadge(tag, l),
      ],
      lines: [
        '${l[K.notifLabelRequester]}: '
            '${_nameOf(req.requestingProfileId) ?? '—'} · '
            '${l[isRevert ? K.notifLabelRevertTo : K.notifLabelProposed]}: '
            '${_nameOf(req.proposedActualParentId) ?? '—'}',
        // F-60: a request waiting on YOU says when it stops waiting.
        '${l[K.frozenAutoApproval]}: '
            '${l.formatDateTime(autoApprovalDeadline(req.scheduleDate, req.proposedHandoffTime))}',
      ],
      onTap: () => _openRequest(req),
    );
  }

  // ── "Enviadas" ─────────────────────────────────────────────────────────────

  Widget _sentTab(Localization l) {
    if (_sent.isEmpty) return _empty(Icons.outbox_outlined, K.notifEmptySent, l);
    final now = DateTime.now();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (final req in _sent) _sentRow(req, now, l),
        const SizedBox(height: 12),
        ..._pushFooter(l),
      ],
    );
  }

  Widget _sentRow(SwapRequest req, DateTime now, Localization l) {
    final isPending = req.status == 'pending' || req.status == 'revert_pending';
    // F-20: pending → live tag; resolved → frozen at resolved_at.
    final tag = req.toView().priorityTag(now);
    final statusKey = swapStatusLabelKey(req.status);

    return _requestRow(
      req: req,
      title: l.formatDate(req.scheduleDate),
      badges: [
        // The state the request had AT RESOLUTION, kept forever (F-20).
        if (!isPending && tag != SwapPriorityTag.none)
          _statusBadge(
            l[tag == SwapPriorityTag.overdue
                ? K.notifTagOverdueShort
                : K.notifTagUrgentShort],
            tone: tag == SwapPriorityTag.overdue
                ? context.tokens.danger
                : context.tokens.warning,
            semantics: l[K.notifResolvedStateTitle],
          ),
        _statusBadge(statusKey == null ? req.status : l[statusKey]),
        if (isPending && tag != SwapPriorityTag.none) _tagBadge(tag, l),
        // F-24: resolved by the 48h server cron.
        if (req.isAutoResolved)
          _statusBadge(l[K.notifAutoBadge],
              tone: context.tokens.info,
              semantics: l[K.notifAutoBadgeTitle]),
      ],
      lines: [
        '${l[K.notifLabelTo]}: ${_nameOf(req.targetProfileId) ?? '—'} · '
            '${l[K.notifLabelProposed]}: '
            '${_nameOf(req.proposedActualParentId) ?? '—'}',
        // F-60: the same deadline the approver sees, so neither side has to
        // do arithmetic on a window that was never measured from here.
        if (isPending)
          '${l[K.frozenAutoApproval]}: '
              '${l.formatDateTime(autoApprovalDeadline(req.scheduleDate, req.proposedHandoffTime))}',
        // F-44 on a RESOLVED request: the sheet never opens for it again, so
        // the two messages live on the row — the sender's own and the
        // approver's note or rejection reason. A pending one shows them in
        // the sheet, where the cancel action is.
        if (!isPending) ...[
          if ((req.requestMessage ?? '').isNotEmpty)
            '${l[K.notifLabelYourMessage]}: ${req.requestMessage}',
          if ((req.approvalNote ?? '').isNotEmpty)
            '${l[K.notifLabelApproverMessage]}: ${req.approvalNote}',
          if ((req.rejectionReason ?? '').isNotEmpty)
            '${l[K.notifLabelApproverMessage]}: ${req.rejectionReason}',
        ],
      ],
      onTap: isPending ? () => _openRequest(req) : null,
    );
  }

  // ── "Todas" ────────────────────────────────────────────────────────────

  Widget _historyTab(Localization l) {
    if (_history.isEmpty) return _empty(Icons.notifications_none, K.notifEmptyHistory, l);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (final notif in _history) _historyItem(notif, l),
        const SizedBox(height: 12),
        ..._pushFooter(l),
      ],
    );
  }

  Widget _historyItem(AppNotification notif, Localization l) {
    final createdLocal = notif.createdAt == null
        ? null
        : DateTime.tryParse(notif.createdAt!)?.toLocal();
    // U-28: an entry on a rail, not a free-floating stack of three greys.
    //
    // Title, body and timestamp all had nearly the same weight and colour, and
    // nothing connected one entry to the next — the tab read as a wall of text
    // where the web reads as a sequence. [AppTimelineEntry] restores the rail
    // and gives the timestamp its own (quieter, right-aligned) place.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
      child: AppTimelineEntry(
        tone: notif.isRead ? context.tokens.neutral : context.tokens.accent,
        marker: notifIcon(notif.type),
        isLast: identical(notif, _history.last),
        // U-13: the row was written in the LANGUAGE OF WHOEVER ACTED, so the
        // stored sentence is only correct by accident. Rebuild from type +
        // params in THIS reader's language; rows written before the item carry
        // no params and render as stored.
        title: Text(
          NotificationRenderer.title(
              notif.type, notif.paramsJson, notif.title, l),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight:
                  notif.isRead ? FontWeight.w600 : FontWeight.w700),
        ),
        body: Text(
          NotificationRenderer.message(
              notif.type, notif.paramsJson, notif.message, l),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        timestamp:
            createdLocal == null ? '' : l.formatDateTime(createdLocal),
        detail: _planAction(notif, l) ?? _expenseAction(notif, l),
      ),
    );
  }

  /// F-34: an expense or settle-up row opens Despesas, where the balance and
  /// the "Recebi / Não recebi" answer live.
  Widget? _expenseAction(AppNotification notif, Localization l) {
    final open = widget.onOpenExpenses;
    if (open == null ||
        _ownProfile?.isViewer == true ||
        !NotificationsScreen.expenseTypes.contains(notif.type)) {
      return null;
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: NotificationsScreen.expenseActionKey(notif.id),
        icon: const Icon(Icons.receipt_long_outlined),
        label: Text(l[KApp.expenseOpen]),
        onPressed: open,
      ),
    );
  }

  /// F-70: the one thing a plan-end row asks for, on the row itself. A row
  /// whose params the rule cannot read offers nothing and still renders.
  Widget? _planAction(AppNotification notif, Localization l) {
    final onPlanFrom = widget.onPlanFrom;
    if (onPlanFrom == null || _ownProfile?.isViewer == true) return null;
    final start =
        PlanEndRules.actionStart(notif.type, notif.paramsJson, DateTime.now());
    if (start == null) return null;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        key: NotificationsScreen.planActionKey(notif.id),
        icon: const Icon(Icons.edit_calendar_outlined),
        label: Text(l[K.notifPlanAction]),
        onPressed: () {
          _trackListOpen(PlanEndRules.type);
          onPlanFrom(start);
        },
      ),
    );
  }
}
