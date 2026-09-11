import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import '../widgets/ui/ui.dart';
import '../theme/tokens.dart';

import 'package:entrelares_db_contracts/models/app_notification.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/swap_request.dart';
import '../services/custody_data_source.dart';
import '../services/notification_badge.dart';
import '../services/push_service.dart';
import '../widgets/account_button.dart';
import '../widgets/app_l10n.dart';
import '../widgets/app_snack.dart';

/// The Notifications page — port of `Notifications.razor`: three tabs
/// ("Para você" = open requests where I am the approver, "Enviadas" = my
/// newest 100 requests, "Histórico" = my newest 100 notification rows,
/// rebuilt in the READER's language by the NotificationRenderer). Opening the
/// page marks everything read (web parity — one bulk PATCH); the F-45 diff
/// list arrives with the audit mirror in lote 6 (decision 19/08/2026).
class NotificationsScreen extends StatefulWidget {
  final CustodyDataSource dataSource;
  final NotificationBadge badge;

  /// F-09. Null on a build with no push transport at all — the card then says
  /// so rather than disappearing, because "where are my alerts?" is a question
  /// a blank space answers badly.
  final PushService? push;

  /// F-09: which tab a TAPPED notification asked for ([PushRouting]).
  final NotificationLanding? landing;

  /// The tapped notification's id. It exists only to make the landing apply
  /// AGAIN: this screen lives in a shell branch, so its State survives a second
  /// navigation, and comparing the landing alone would silently ignore a second
  /// tap that wants the same tab the person has since navigated away from.
  final String? landingNonce;

  const NotificationsScreen(
      {super.key,
      required this.dataSource,
      required this.badge,
      this.push,
      this.landing,
      this.landingNonce});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

enum _Tab { incoming, sent, history }

/// Mirror of `GetNotifIcon`.
String notifIcon(String type) => switch (type) {
      'swap_requested' => '🔄',
      'swap_sent' => '📤',
      'swap_approved' => '✅',
      'swap_approved_self' => '✅',
      'swap_rejected' => '❌',
      'swap_cancelled' => '🚫',
      'swap_reverted' => '↩️',
      'revert_requested' => '↩️',
      'revert_sent' => '📤',
      'revert_approved' => '✅',
      'revert_approved_self' => '✅',
      'revert_rejected' => '❌',
      'revert_cancelled' => '🚫',
      'auto_reminder' => '⏰',
      'auto_approved' => '🤖',
      'swap_family_info' => '👪',
      'email_cap_80' => '⚠️',
      'email_cap_last' => '✉️',
      'email_cap_reached' => '✉️',
      'billing' => '💳',
      _ => '🔔',
    };

class _NotificationsScreenState extends State<NotificationsScreen> {
  _Tab _tab = _Tab.incoming;
  bool _loading = true;
  String? _loadError;
  List<Member> _allProfiles = const [];
  Member? _ownProfile;
  List<SwapRequest> _incoming = const [];
  List<SwapRequest> _sent = const [];
  List<AppNotification> _history = const [];

  /// F-44: one dual-purpose note per incoming card (approval note on approve,
  /// rejection reason on reject — same decision as the frozen panel).
  final Map<int, TextEditingController> _approverNotes = {};

  /// Which request is being acted on (disables its card's buttons) and the
  /// per-card error text.
  final Map<int, String> _actioning = {};
  final Map<int, String> _actionErrors = {};

  @override
  void initState() {
    super.initState();
    _applyLanding();
    _init();
  }

  @override
  void didUpdateWidget(NotificationsScreen old) {
    super.didUpdateWidget(old);
    if (widget.landingNonce != old.landingNonce) _applyLanding();
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

  @override
  void dispose() {
    for (final c in _approverNotes.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _noteFor(int requestId) =>
      _approverNotes.putIfAbsent(requestId, TextEditingController.new);

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
      final history = me == null
          ? <AppNotification>[]
          : await widget.dataSource.fetchNotifications(me.id);
      if (!mounted) return;
      setState(() {
        _allProfiles = profiles;
        _ownProfile = me;
        _incoming = incoming;
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

  Future<void> _act(
    SwapRequest req,
    String action,
    String errorKey,
    String toastKey,
    Future<void> Function() run,
  ) async {
    final l = AppL10n.of(context).l;
    setState(() {
      _actioning[req.id] = action;
      _actionErrors.remove(req.id);
    });
    try {
      await run();
      await _loadAll();
      await widget.badge.refresh();
      if (mounted) showAppSnack(context, l[toastKey]);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _actionErrors[req.id] = isSessionExpired(e.toString())
            ? sessionExpiredMessage(l)
            : l.format(errorKey, [e.toString()]);
      });
    } finally {
      if (mounted) setState(() => _actioning.remove(req.id));
    }
  }

  String? _noteText(int requestId) {
    final text = _noteFor(requestId).text;
    return text.trim().isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    return Scaffold(
      appBar: AppBar(
          title: Text(l[K.notifPageTitle]),
          actions: const [AppAccountButton()]),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: AppSegmented<_Tab>(
              options: [
                (
                  value: _Tab.incoming,
                  label: _incoming.isEmpty
                      ? l[K.notifTabIncoming]
                      : '${l[K.notifTabIncoming]} (${_incoming.length})'
                ),
                (value: _Tab.sent, label: l[K.notifTabSent]),
                (value: _Tab.history, label: l[K.notifTabHistory]),
              ],
              selected: _tab,
              onChanged: (v) => setState(() => _tab = v),
            ),
          ),
          _pushCard(l),
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
                                  leading: '⚠️',
                                  message: _loadError!),
                              const SizedBox(height: Spacing.sm),
                              OutlinedButton(
                                  onPressed: _loadAll,
                                  child: Text(l[K.layoutErrorReload])),
                            ]),
                          )
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
  /// Every state renders something, including the two that offer no button.
  /// A blocked permission and a browser both look identical to a card that
  /// hides itself: alerts that never come, and no explanation anywhere.
  Widget _pushCard(Localization l) {
    final push = widget.push;
    final state = push?.state ?? PushState.unsupported;

    final (String hint, Widget? action) = switch (state) {
      PushState.on => (
          l[KApp.pushHintOn],
          TextButton(
              onPressed: () => _setPush(l, on: false),
              child: Text(l[KApp.pushDisable]))
        ),
      PushState.off => (
          l[KApp.pushHintOff],
          FilledButton(
              onPressed: () => _setPush(l, on: true),
              child: Text(l[KApp.pushEnable]))
        ),
      // No button on purpose: the OS will not show the dialog again, so a
      // button here would do nothing when pressed — the failure that makes an
      // app look broken while it behaves exactly as designed.
      PushState.blocked => (l[KApp.pushHintBlocked], null),
      PushState.unsupported => (l[KApp.pushHintUnsupported], null),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, Spacing.sm),
      child: AppCard(
        title: l[KApp.pushTitle],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hint, style: Theme.of(context).textTheme.bodySmall),
            if (action != null) ...[
              const SizedBox(height: Spacing.sm),
              Align(alignment: Alignment.centerLeft, child: action),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _setPush(Localization l, {required bool on}) async {
    final push = widget.push;
    if (push == null) return;

    if (on) {
      final result = await push.enable();
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
  Widget _empty(String icon, String textKey, Localization l) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: Spacing.md),
          AppEmptyState(icon: icon, title: l[textKey]),
        ],
      );

  Widget _infoRow(String label, String value) =>
      AppListRow(label: label, value: value);

  /// U-28 — a card's first line: the day on the left, its state pills on the
  /// right, and a SECOND LINE for the pills when they do not fit.
  ///
  /// It was a `Row` with the date in an `Expanded` beside a `Wrap` of up to
  /// three badges. `Row` lays the inflexible child out first, so the badges took
  /// the width they wanted and the `Expanded` got what was left — around ten
  /// pixels, which the date then filled ONE CHARACTER PER LINE while the badges
  /// still reported `RIGHT OVERFLOWED BY 85 PIXELS`. A `Wrap` cannot do that to
  /// itself: what does not fit moves down.
  Widget _cardHeader(String title, List<Widget> badges) => Wrap(
        spacing: Spacing.sm,
        runSpacing: Spacing.xs,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          Wrap(spacing: Spacing.xs, runSpacing: Spacing.xs, children: badges),
        ],
      );

  Widget _statusBadge(String text, {ToneColors? tone, String? semantics}) =>
      AppBadge(
        text: text,
        tone: tone ?? context.tokens.neutral,
        semantics: semantics,
      );

  Widget _tagBanner(SwapPriorityTag tag, Localization l) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
        child: AppBanner(
          tone: tag == SwapPriorityTag.overdue
              ? context.tokens.danger
              : context.tokens.warning,
          bordered: false,
          message: l[
              tag == SwapPriorityTag.overdue ? K.frozenOverdue : K.frozenUrgent],
        ),
      );

  Widget _card({required List<Widget> children}) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.sm + Spacing.xs, vertical: Spacing.sm - 2),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );

  // ── "Para você" ────────────────────────────────────────────────────────────

  Widget _incomingTab(Localization l) {
    if (_incoming.isEmpty) return _empty('✅', K.notifEmptyIncoming, l);
    final now = DateTime.now();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (final req in _incoming) _incomingCard(req, now, l),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _incomingCard(SwapRequest req, DateTime now, Localization l) {
    final isRevert = req.isRevertPending;
    final tag = req.toView().priorityTag(now); // F-20: pending → clock
    final handoff = parseTimeOfDay(req.proposedHandoffTime);
    final createdLocal = req.createdAt == null
        ? null
        : DateTime.tryParse(req.createdAt!)?.toLocal();
    final acting = _actioning.containsKey(req.id);
    final error = _actionErrors[req.id];

    return _card(children: [
      _cardHeader('📅 ${l.formatDate(req.scheduleDate)}', [
        _statusBadge(
          l[isRevert ? K.notifRevertPendingBadge : K.notifPendingBadge],
          tone: isRevert ? context.tokens.accent : context.tokens.warning,
        ),
      ]),
      if (tag != SwapPriorityTag.none) _tagBanner(tag, l),
      _infoRow(l[K.notifLabelRequester],
          _nameOf(req.requestingProfileId) ?? '—'),
      // F-44: the requester's message, shown to the approver.
      if ((req.requestMessage ?? '').isNotEmpty)
        _infoRow(l[K.notifLabelRequesterMessage], req.requestMessage!),
      if (isRevert)
        _infoRow(
            l[K.notifLabelRevertTo], _nameOf(req.proposedActualParentId) ?? '—')
      else
        _infoRow(l[K.notifLabelProposes],
            '${_nameOf(req.proposedActualParentId) ?? '—'} ${l[K.notifProposesSuffix]}'),
      if (handoff != null)
        _infoRow(
            l[K.notifLabelTime],
            '${handoff.hour.toString().padLeft(2, '0')}:'
            '${handoff.minute.toString().padLeft(2, '0')}'),
      if (createdLocal != null)
        _infoRow(
            l[K.notifLabelRequestedAt], l.formatDateTimeShort(createdLocal)),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('⚠️ $error',
              style: TextStyle(
                  color: context.tokens.danger.onContainer,
                  fontSize: TypeScale.label)),
        ),
      const SizedBox(height: 8),
      // U-27: a placeholder-only field has no accessible name once it has
      // text in it — the label is permanent, the placeholder stays a hint.
      AppTextField(
        label: l[K.wfMessage],
        hint: l[K.notifNotePlaceholder],
        controller: _noteFor(req.id),
        maxLength: 200,
        enabled: !acting,
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          Expanded(
            child: FilledButton(
              onPressed: acting
                  ? null
                  : () => isRevert
                      ? _act(
                          req,
                          'approve',
                          K.errConfirmRevertFailed,
                          K.toastRevertConfirmed,
                          () => widget.dataSource.approveRevert(req.id,
                              approvalNote: _noteText(req.id),
                              allProfiles: _allProfiles))
                      : _act(
                          req,
                          'approve',
                          K.errApproveFailed,
                          K.toastSwapApproved,
                          () => widget.dataSource.approveSwap(req.id,
                              approvalNote: _noteText(req.id),
                              allProfiles: _allProfiles)),
              child: _actioning[req.id] == 'approve'
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l[
                      isRevert ? K.notifBtnConfirmRevert : K.notifBtnApprove]),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: acting
                  ? null
                  : () => isRevert
                      ? _act(
                          req,
                          'reject',
                          K.errRejectRevertFailed,
                          K.toastRevertRejected,
                          () => widget.dataSource.rejectRevert(req.id,
                              reason: _noteText(req.id),
                              allProfiles: _allProfiles))
                      : _act(
                          req,
                          'reject',
                          K.errRejectFailed,
                          K.toastSwapRejected,
                          () => widget.dataSource.rejectSwap(req.id,
                              reason: _noteText(req.id),
                              allProfiles: _allProfiles)),
              child: _actioning[req.id] == 'reject'
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(l[K.notifBtnReject]),
            ),
          ),
        ],
      ),
    ]);
  }

  // ── "Enviadas" ─────────────────────────────────────────────────────────────

  Widget _sentTab(Localization l) {
    if (_sent.isEmpty) return _empty('📤', K.notifEmptySent, l);
    final now = DateTime.now();
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (final req in _sent) _sentCard(req, now, l),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _sentCard(SwapRequest req, DateTime now, Localization l) {
    final isPending = req.status == 'pending' || req.status == 'revert_pending';
    // F-20: pending → live tag; resolved → frozen at resolved_at.
    final tag = req.toView().priorityTag(now);
    final createdLocal = req.createdAt == null
        ? null
        : DateTime.tryParse(req.createdAt!)?.toLocal();
    final acting = _actioning.containsKey(req.id);
    final error = _actionErrors[req.id];
    final statusKey = swapStatusLabelKey(req.status);

    return _card(children: [
      _cardHeader('📅 ${l.formatDate(req.scheduleDate)}', [
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
        // F-24: resolved by the 48h server cron.
        if (req.isAutoResolved)
          _statusBadge(l[K.notifAutoBadge],
              tone: context.tokens.info,
              semantics: l[K.notifAutoBadgeTitle]),
      ]),
      _infoRow(l[K.notifLabelTo], _nameOf(req.targetProfileId) ?? '—'),
      _infoRow(l[K.notifLabelProposed],
          _nameOf(req.proposedActualParentId) ?? '—'),
      if (isPending && tag != SwapPriorityTag.none) _tagBanner(tag, l),
      // F-44: the sender sees their own message and, once resolved, the
      // approver's note / rejection reason.
      if ((req.requestMessage ?? '').isNotEmpty)
        _infoRow(l[K.notifLabelYourMessage], req.requestMessage!),
      if ((req.approvalNote ?? '').isNotEmpty)
        _infoRow(l[K.notifLabelApproverMessage], req.approvalNote!),
      if ((req.rejectionReason ?? '').isNotEmpty)
        _infoRow(l[K.notifLabelApproverMessage], req.rejectionReason!),
      if (createdLocal != null)
        _infoRow(
            l[K.notifLabelRequestedAt], l.formatDateTimeShort(createdLocal)),
      if (isPending) ...[
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('⚠️ $error',
                style: TextStyle(
                    color: context.tokens.danger.onContainer,
                    fontSize: TypeScale.label)),
          ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: acting
              ? null
              : () => req.isRevertPending
                  ? _act(
                      req,
                      'cancel',
                      K.errCancelRevertFailed,
                      K.toastRevertCancelled,
                      () => widget.dataSource
                          .cancelRevert(req.id, allProfiles: _allProfiles))
                  : _act(
                      req,
                      'cancel',
                      K.errCancelFailed,
                      K.toastRequestCancelled,
                      () => widget.dataSource
                          .cancelSwap(req.id, allProfiles: _allProfiles)),
          style: OutlinedButton.styleFrom(
              foregroundColor: context.tokens.danger.onContainer),
          child: acting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(l[req.isRevertPending
                  ? K.notifBtnCancelRevert
                  : K.notifBtnCancelRequest]),
        ),
      ],
    ]);
  }

  // ── "Histórico" ────────────────────────────────────────────────────────────

  Widget _historyTab(Localization l) {
    if (_history.isEmpty) return _empty('🔔', K.notifEmptyHistory, l);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (final notif in _history) _historyItem(notif, l),
        const SizedBox(height: 12),
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
      ),
    );
  }
}
