import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:entrelares_db_contracts/models/chat_message.dart';
import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import '../services/custody_data_source.dart';
import '../theme/tokens.dart';
import 'app_l10n.dart';
import 'app_snack.dart';
import 'ui/ui.dart';

/// F-35 — the family's Conversa: one conversation per family, permanent.
///
/// The server keeps the texts immutable and refuses what it must (flag off, a
/// viewer writing, no Premium, too long, too many per hour). This widget adds
/// what the owner locked for v1: the fixed notice on top, reply by quoting,
/// "lida por" under every text, citing a calendar day (a tap opens that day),
/// search, and each member's own push silencing. No moderation and no tone
/// meter, on purpose.
///
/// Live (owner's validation, 25/09/2026): a text or a read mark written on
/// another device arrives through the chat Realtime channel — with the
/// T-83 poll as the net while the socket is down — and what arrives while the
/// Conversa is ON SCREEN is marked read at once. On screen = the shell branch
/// is active (go_router's `TickerMode`) and the app is in the foreground.
class ChatView extends StatefulWidget {
  final CustodyDataSource dataSource;

  /// Opens `/family/plan` — the Premium gate's CTA (U-35).
  final VoidCallback? onOpenPlan;

  /// Opens the calendar on a cited day.
  final ValueChanged<DateTime>? onOpenDay;

  /// Called after the reader's marks were written, so the bell recounts.
  final VoidCallback? onRead;

  final DateTime Function() now;

  const ChatView({
    super.key,
    required this.dataSource,
    this.onOpenPlan,
    this.onOpenDay,
    this.onRead,
    this.now = DateTime.now,
  });

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> with WidgetsBindingObserver {
  bool _loading = true;
  bool _loadFailed = false;
  PublicSettings _settings = PublicSettings.unloaded;
  Member? _me;
  Family? _family;
  List<Member> _members = const [];
  List<ChatMessage> _messages = const [];
  List<ChatRead> _reads = const [];
  bool _muted = false;

  String? _query;
  final _search = TextEditingController();
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  ChatMessage? _quote;
  DateTime? _day;
  bool _sending = false;
  String? _sendError;

  void Function()? _unwatch;
  bool _socketConnected = false;
  Timer? _changeDebounce;
  Timer? _pollTimer;
  ValueListenable<TickerModeData>? _activeBranch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _watch();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = TickerMode.getValuesNotifier(context);
    if (!identical(active, _activeBranch)) {
      _activeBranch?.removeListener(_onVisibilityChanged);
      _activeBranch = active..addListener(_onVisibilityChanged);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _onVisibilityChanged();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeBranch?.removeListener(_onVisibilityChanged);
    _unwatch?.call();
    _changeDebounce?.cancel();
    _pollTimer?.cancel();
    _search.dispose();
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Whether a text arriving now is a text the reader sees.
  bool get _onScreen {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return (_activeBranch?.value.enabled ?? true) &&
        (lifecycle == null || lifecycle == AppLifecycleState.resumed);
  }

  void _onVisibilityChanged() {
    if (!mounted) return;
    // Back on the Conversa: what arrived meanwhile, then mark it read.
    if (_onScreen) unawaited(_refresh());
    _schedulePoll();
  }

  Future<void> _watch() async {
    try {
      final unwatch = await widget.dataSource.watchChatChanges(
        () {
          // A mark_chat_read writes one row per text — a burst on the channel.
          _changeDebounce?.cancel();
          _changeDebounce = Timer(const Duration(milliseconds: 300), () {
            if (mounted) unawaited(_refresh());
          });
        },
        onStatus: (connected) {
          if (!mounted || connected == _socketConnected) return;
          _socketConnected = connected;
          // The socket coming back may have missed texts while it was down.
          if (connected) unawaited(_refresh());
          _schedulePoll();
        },
      );
      if (!mounted) {
        unwatch();
        return;
      }
      _unwatch = unwatch;
    } catch (_) {/* the poll below is the net */}
    _schedulePoll();
  }

  /// T-83's cadence, only while the Conversa is on screen.
  void _schedulePoll() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!mounted || !_onScreen || !_settings.chatEnabled) return;
    final ms = pollIntervalMs(
        socketConnected: _socketConnected, settings: _settings);
    if (ms == null) return;
    _pollTimer = Timer(Duration(milliseconds: ms), () async {
      if (!mounted) return;
      await _refresh();
      _schedulePoll();
    });
  }

  bool get _atEnd =>
      !_scroll.hasClients || _scroll.position.extentAfter < 96;

  /// The texts and the marks again — the cheap half of [_load], for a change
  /// on the channel, a poll or a send. Keeps the reader's place unless they
  /// were already at the end (or [toEnd], after their own send).
  Future<void> _refresh({bool toEnd = false}) async {
    if (_loading || _loadFailed || _me == null || !_settings.chatEnabled) {
      return;
    }
    try {
      final got = await Future.wait<Object?>([
        widget.dataSource.fetchChatMessages(),
        widget.dataSource.fetchChatReads(),
      ]);
      if (!mounted) return;
      final follow = toEnd || _atEnd;
      setState(() {
        _messages = got[0] as List<ChatMessage>;
        _reads = got[1] as List<ChatRead>;
      });
      if (follow) _scrollToEnd();
      if (_onScreen) await _markRead();
    } catch (_) {/* what is on screen stays; the next change or poll retries */}
  }

  Future<void> _load() async {
    setState(() {
      _loading = _messages.isEmpty;
      _loadFailed = false;
    });
    try {
      final first = await Future.wait<Object?>([
        widget.dataSource.fetchPublicSettings(),
        widget.dataSource.fetchOwnProfile(),
      ]);
      final settings = PublicSettings(first[0] as Map<String, String>);
      final me = first[1] as Member?;
      if (!settings.chatEnabled || me == null) {
        if (!mounted) return;
        setState(() {
          _settings = settings;
          _me = me;
          _loading = false;
        });
        return;
      }
      final rest = await Future.wait<Object?>([
        widget.dataSource.fetchMembers(),
        widget.dataSource.fetchOwnFamily(),
        widget.dataSource.fetchChatMessages(),
        widget.dataSource.fetchChatReads(),
        widget.dataSource
            .fetchChatPushMuted()
            .catchError((Object _) => false),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _me = me;
        _members = rest[0] as List<Member>;
        _family = rest[1] as Family?;
        _messages = rest[2] as List<ChatMessage>;
        _reads = rest[3] as List<ChatRead>;
        _muted = rest[4] as bool;
        _loading = false;
      });
      if (_onScreen) unawaited(_markRead());
      _scrollToEnd();
      _schedulePoll();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  List<ChatLine> get _lines => [
        for (final m in _messages)
          (id: m.id, author: m.authorProfileId, body: m.body)
      ];

  List<ChatMark> get _marks => [
        for (final r in _reads)
          (messageId: r.messageId, profileId: r.profileId, readAt: r.readAt)
      ];

  /// Marks what is on screen as read — only when something is actually new
  /// for me, so opening the tab does not write for nothing.
  bool _marking = false;

  Future<void> _markRead() async {
    final me = _me;
    final newest = ChatRules.newestId(_lines);
    if (me == null || newest == null || _marking) return;
    if (ChatRules.unreadFor(me.id, _lines, _marks) == 0) return;
    _marking = true;
    try {
      await widget.dataSource.markChatRead(newest);
      final reads = await widget.dataSource.fetchChatReads();
      if (mounted) setState(() => _reads = reads);
      widget.onRead?.call();
    } catch (_) {
      /* the marks are a courtesy; the texts are already here */
    } finally {
      _marking = false;
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  bool get _canWrite {
    final me = _me;
    if (me == null || me.isViewer || me.hasLeft) return false;
    if (!_settings.chatPremiumOnly) return true;
    return Family.isPremiumFamily(_family, widget.now().toUtc());
  }

  String _name(int profileId, Localization l) {
    if (profileId == _me?.id) return l[KApp.chatYou];
    for (final m in _members) {
      if (m.id == profileId) {
        final name = m.fullName.trim();
        return name.isEmpty ? l[KApp.chatFormerMember] : name;
      }
    }
    return l[KApp.chatFormerMember];
  }

  Future<void> _send(Localization l) async {
    if (_sending) return;
    final body = _composer.text.trim();
    if (body.isEmpty) return;
    final max = _settings.chatMessageMaxChars;
    if (body.length > max) {
      setState(() => _sendError = l.format(KApp.chatTooLong, [max]));
      return;
    }
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await widget.dataSource.sendChatMessage(
          body: body, quoteId: _quote?.id, quotedDay: _day);
      if (!mounted) return;
      _composer.clear();
      setState(() {
        _quote = null;
        _day = null;
        _sending = false;
      });
      await _refresh(toEnd: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sendError =
            translateSaveError(e.toString(), l[KApp.chatSendFailed], l);
      });
    }
  }

  Future<void> _toggleMute(Localization l) async {
    final next = !_muted;
    try {
      await widget.dataSource.setChatPushMuted(next);
      if (!mounted) return;
      setState(() => _muted = next);
      showAppSnack(
          context,
          next
              ? '${l[KApp.chatMuted]} ${l[KApp.chatMuteLead]}'
              : l[KApp.chatUnmuted]);
    } catch (e) {
      if (!mounted) return;
      showAppSnack(
          context, translateSaveError(e.toString(), l[K.errSaveFailed], l));
    }
  }

  Future<void> _pickDay(Localization l) async {
    final today = widget.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? DateTime(today.year, today.month, today.day),
      firstDate: DateTime(today.year - 5),
      lastDate: DateTime(today.year + 2, 12, 31),
    );
    if (picked != null && mounted) setState(() => _day = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppL10n.of(context).l;
    if (_loading) return AppSkeletonList(semanticsLabel: l[KApp.chatTabChat]);
    if (_loadFailed) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l[KApp.chatErrLoad]),
            const SizedBox(height: Spacing.sm + Spacing.xs),
            FilledButton(
                onPressed: _load, child: Text(l[K.layoutErrorReload])),
          ],
        ),
      );
    }
    if (!_settings.chatEnabled || _me == null) {
      return AppEmptyState(
        key: const ValueKey('chat-off'),
        icon: Icons.forum_outlined,
        title: l[KApp.chatOff],
      );
    }
    final tokens = context.tokens;
    final query = _query ?? '';
    final shown = [
      for (final m in _messages)
        if (ChatRules.matches(m.body, query)) m
    ];
    // The notice opens the conversation and scrolls away with it: pinned
    // above the list, it took most of what the keyboard leaves on a phone and
    // the column overflowed (owner's validation, 25/09/2026).
    final notice = Padding(
      padding: const EdgeInsets.only(top: Spacing.xs, bottom: Spacing.sm),
      child: AppBanner(
        key: const ValueKey('chat-notice'),
        tone: tokens.warning,
        icon: Icons.lock_clock_outlined,
        message: l[KApp.chatNotice],
      ),
    );
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: _query == null
                    ? const SizedBox(height: 48)
                    : AppTextField(
                        key: const ValueKey('chat-search-field'),
                        label: l[KApp.chatSearch],
                        controller: _search,
                        autofocus: true,
                        onChanged: (v) => setState(() => _query = v),
                      ),
              ),
              IconButton(
                key: const ValueKey('chat-search'),
                icon: Icon(_query == null ? Icons.search : Icons.close),
                tooltip:
                    l[_query == null ? KApp.chatSearch : KApp.chatSearchClose],
                onPressed: () => setState(() {
                  if (_query == null) {
                    _query = '';
                  } else {
                    _query = null;
                    _search.clear();
                  }
                }),
              ),
              IconButton(
                key: const ValueKey('chat-mute'),
                icon: Icon(_muted
                    ? Icons.notifications_off_outlined
                    : Icons.notifications_active_outlined),
                tooltip: l[_muted ? KApp.chatUnmuted : KApp.chatMute],
                onPressed: () => _toggleMute(l),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: shown.isEmpty
                ? ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                    notice,
                    AppEmptyState(
                      key: const ValueKey('chat-empty'),
                      icon: Icons.forum_outlined,
                      title: query.trim().isEmpty
                          ? l[KApp.chatEmpty]
                          : l.format(KApp.chatSearchEmpty, [query.trim()]),
                    ),
                  ])
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: shown.length + 1,
                    itemBuilder: (context, i) =>
                        i == 0 ? notice : _bubble(shown[i - 1], l),
                  ),
          ),
        ),
        _composerArea(l),
      ],
    );
  }

  Widget _bubble(ChatMessage m, Localization l) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final mine = m.authorProfileId == _me?.id;
    final quoted = m.quoteId == null
        ? null
        : _messages.where((q) => q.id == m.quoteId).firstOrNull;
    final readers =
        ChatRules.readersOf(m.id, m.authorProfileId, _marks);
    final readLine = readers.isEmpty
        ? l[KApp.chatNotRead]
        : l.format(KApp.chatReadBy, [
            readers
                .map((r) => l.format(KApp.chatReadEntry, [
                      _name(r.profileId, l),
                      l.formatDateTimeShort(r.readAt.toLocal()),
                    ]))
                .join(', ')
          ]);
    return Align(
      alignment:
          mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          key: ValueKey('chat-message-${m.id}'),
          color: mine ? tokens.accent.container : null,
          margin: const EdgeInsets.symmetric(vertical: Spacing.xs),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_name(m.authorProfileId, l)} · '
                        '${l.formatDateTimeShort(m.createdAt.toLocal())}',
                        style: textTheme.labelMedium,
                      ),
                    ),
                    if (_canWrite)
                      IconButton(
                        key: ValueKey('chat-reply-${m.id}'),
                        icon: const Icon(Icons.reply, size: 20),
                        tooltip: l[KApp.chatReply],
                        onPressed: () => setState(() => _quote = m),
                      ),
                  ],
                ),
                if (quoted != null)
                  Container(
                    key: ValueKey('chat-quote-${m.id}'),
                    width: double.infinity,
                    margin: const EdgeInsets.only(right: 8, bottom: 4),
                    padding: const EdgeInsets.all(Spacing.sm),
                    decoration: BoxDecoration(
                      border: BorderDirectional(
                          start: BorderSide(
                              color: tokens.outline, width: 3)),
                    ),
                    child: Text(
                      '${_name(quoted.authorProfileId, l)}: '
                      '${ChatRules.snippet(quoted.body)}',
                      style: textTheme.bodySmall,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: SelectableText(m.body),
                ),
                if (m.quotedDay != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.xs),
                    child: ActionChip(
                      key: ValueKey('chat-day-${m.id}'),
                      avatar: const Icon(Icons.event_outlined, size: 18),
                      label: Text(l.format(
                          KApp.chatCitedDay, [l.formatDate(m.quotedDay!)])),
                      onPressed: widget.onOpenDay == null
                          ? null
                          : () => widget.onOpenDay!(m.quotedDay!),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: Spacing.xs, right: 8),
                  child: Text(readLine,
                      key: ValueKey('chat-read-${m.id}'),
                      style: textTheme.bodySmall
                          ?.copyWith(color: tokens.textMuted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _composerArea(Localization l) {
    final tokens = context.tokens;
    final me = _me!;
    if (me.isViewer) {
      return Padding(
        padding: const EdgeInsets.all(Spacing.md),
        child: Text(l[KApp.chatReadOnly],
            key: const ValueKey('chat-read-only'),
            style: Theme.of(context).textTheme.bodySmall),
      );
    }
    if (!_canWrite) {
      return Padding(
        padding: const EdgeInsets.all(Spacing.sm),
        child: AppBanner(
          key: const ValueKey('chat-premium'),
          tone: tokens.info,
          icon: Icons.workspace_premium_outlined,
          message: l[KApp.chatPremium],
          actionLabel: widget.onOpenPlan == null ? null : l[K.famSeePremium],
          onAction: widget.onOpenPlan,
        ),
      );
    }
    final quote = _quote;
    final day = _day;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_sendError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Spacing.xs),
                child: AppBanner(
                    key: const ValueKey('chat-send-error'),
                    tone: tokens.danger,
                    icon: Icons.error_outline,
                    message: _sendError!),
              ),
            if (quote != null)
              InputChip(
                key: const ValueKey('chat-quoting'),
                label: Text(
                  l.format(KApp.chatQuoting, [
                    '${_name(quote.authorProfileId, l)}: '
                        '${ChatRules.snippet(quote.body, max: 40)}'
                  ]),
                  overflow: TextOverflow.ellipsis,
                ),
                deleteButtonTooltipMessage: l[KApp.chatCancelQuote],
                onDeleted: () => setState(() => _quote = null),
              ),
            if (day != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: InputChip(
                  key: const ValueKey('chat-cited-day'),
                  avatar: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                      l.format(KApp.chatCitedDay, [l.formatDate(day)])),
                  deleteButtonTooltipMessage: l[KApp.chatRemoveDay],
                  onDeleted: () => setState(() => _day = null),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const ValueKey('chat-cite-day'),
                  icon: const Icon(Icons.event_outlined),
                  tooltip: l[KApp.chatCiteDay],
                  onPressed: () => _pickDay(l),
                ),
                Expanded(
                  child: AppTextField(
                    key: const ValueKey('chat-composer'),
                    label: l[KApp.chatHint],
                    controller: _composer,
                    // One line that grows to five as the text wraps: fixed at
                    // five, the field alone filled a phone's space above the
                    // keyboard.
                    minLines: 1,
                    maxLines: 5,
                    maxLength: _settings.chatMessageMaxChars,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.newline,
                  ),
                ),
                IconButton(
                  key: const ValueKey('chat-send'),
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  tooltip: l[KApp.chatSend],
                  onPressed: _sending ? null : () => _send(l),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
