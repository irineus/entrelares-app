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
import 'chat_export_sheet.dart';
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
///
/// T-104: the texts arrive in PAGES — the newest [chatPageSize] first, older
/// ones as the reader scrolls up — and the read marks only for the texts on
/// hand. The whole table in one request was cut by PostgREST's `max_rows`
/// at the NEWEST end, so past ~1,000 texts new ones never showed, and past
/// ~1,000 marks every new text read "Ainda não lida" for everyone.
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

  /// T-104: the first text of the page loaded at opening. Older pages grow
  /// UPWARD from it (the sliver before the scroll view's center), so loading
  /// them never moves what the reader is looking at. Null while the Conversa
  /// opened empty: everything then sits after the center.
  int? _anchorId;
  bool _hasOlder = false;
  bool _loadingOlder = false;

  /// Quoted texts older than every loaded page, by id.
  Map<int, ChatMessage> _quoted = const {};
  final Key _center = UniqueKey();

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

  /// U-66: the text a jump landed on, tinted for a moment so the eye finds
  /// it among its neighbours.
  int? _highlightId;
  Timer? _highlightTimer;
  ValueListenable<TickerModeData>? _activeBranch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    _load();
    _watch();
  }

  /// Near the top with older texts on the server: fetch the previous page.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    // F-90: reaching the end is reading what arrived meanwhile.
    if (_atEnd && _hasNewForMe) unawaited(_markRead());
    if (!_hasOlder || _loadingOlder) return;
    if (_scroll.position.extentBefore < 300) unawaited(_loadOlder());
  }

  /// F-90: a text counts as READ only when the reader can see it — no search
  /// filtering the list, and the list at its end. "Lida por" is evidence in a
  /// separation and goes to the PDF: the mother looking for an old message,
  /// or scrolled far up, used to "read" the father's new text at 14:02.
  bool get _searching => (_query ?? '').trim().isNotEmpty;

  bool get _hasNewForMe {
    final me = _me;
    return me != null && ChatRules.unreadFor(me.id, _lines, _marks) > 0;
  }

  int get _newForMe {
    final me = _me;
    return me == null ? 0 : ChatRules.unreadFor(me.id, _lines, _marks);
  }

  List<int> _ids(Iterable<ChatMessage> messages) =>
      [for (final m in messages) m.id];

  /// T-104: the texts quoted by [page] that no loaded page carries — a reply
  /// to something said long ago still shows what it answers. Best effort:
  /// a failure costs the quote box, never the text.
  Future<Map<int, ChatMessage>> _quotesFor(
      Iterable<ChatMessage> page, Iterable<ChatMessage> loaded) async {
    final have = {..._ids(loaded), ..._quoted.keys};
    final missing = {
      for (final m in page)
        if (m.quoteId != null && !have.contains(m.quoteId)) m.quoteId!
    }.toList();
    if (missing.isEmpty) return _quoted;
    try {
      final got = await widget.dataSource.fetchChatMessagesByIds(missing);
      return {..._quoted, for (final m in got) m.id: m};
    } catch (_) {
      return _quoted;
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _messages.isEmpty) return;
    setState(() => _loadingOlder = true);
    try {
      final older =
          await widget.dataSource.fetchChatPage(beforeId: _messages.first.id);
      final reads = await widget.dataSource.fetchChatReads(_ids(older));
      final quoted = await _quotesFor(older, [...older, ..._messages]);
      if (!mounted) return;
      setState(() {
        _messages = [...older, ..._messages];
        _reads = [...reads, ..._reads];
        _quoted = quoted;
        _hasOlder = older.length >= chatPageSize;
        _loadingOlder = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOlder = false);
    }
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
    _scroll.removeListener(_onScroll);
    _unwatch?.call();
    _changeDebounce?.cancel();
    _pollTimer?.cancel();
    _highlightTimer?.cancel();
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
      final newest = ChatRules.newestId(_lines);
      final fresh = newest == null
          ? await widget.dataSource.fetchChatPage()
          : await widget.dataSource.fetchChatMessagesAfter(newest);
      final messages = [
        ..._messages,
        for (final m in fresh)
          if (newest == null || m.id > newest) m
      ];
      final reads = await widget.dataSource.fetchChatReads(_ids(messages));
      final quoted = await _quotesFor(fresh, messages);
      if (!mounted) return;
      final follow = toEnd || _atEnd;
      setState(() {
        if (_messages.isEmpty && messages.isNotEmpty) {
          _hasOlder = fresh.length >= chatPageSize;
        }
        _messages = messages;
        _reads = reads;
        _quoted = quoted;
      });
      if (follow) _scrollToEnd();
      if (_onScreen && follow && !_searching) await _markRead();
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
        widget.dataSource.fetchChatPage(),
        widget.dataSource
            .fetchChatPushMuted()
            .catchError((Object _) => false),
      ]);
      final page = rest[2] as List<ChatMessage>;
      final reads = await widget.dataSource.fetchChatReads(_ids(page));
      _quoted = const {};
      final quoted = await _quotesFor(page, page);
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _me = me;
        _members = rest[0] as List<Member>;
        _family = rest[1] as Family?;
        _messages = page;
        _anchorId = page.isEmpty ? null : page.first.id;
        _hasOlder = page.length >= chatPageSize;
        _quoted = quoted;
        _reads = reads;
        _muted = rest[3] as bool;
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
    if (!_onScreen || _searching) return;
    final me = _me;
    final newest = ChatRules.newestId(_lines);
    if (me == null || newest == null || _marking) return;
    if (ChatRules.unreadFor(me.id, _lines, _marks) == 0) return;
    _marking = true;
    try {
      await widget.dataSource.markChatRead(newest);
      final reads = await widget.dataSource.fetchChatReads(_ids(_messages));
      if (mounted) setState(() => _reads = reads);
      widget.onRead?.call();
    } catch (_) {
      /* the marks are a courtesy; the texts are already here */
    } finally {
      _marking = false;
    }
  }

  /// T-104: a lazy list only ESTIMATES its end until the last rows are laid
  /// out — with a page of 200 texts one jump lands short — so it jumps again
  /// until the end stops moving.
  void _scrollToEnd([int tries = 6]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final end = _scroll.position.maxScrollExtent;
      if (_scroll.position.pixels == end) return;
      _scroll.jumpTo(end);
      if (tries > 1) _scrollToEnd(tries - 1);
    });
  }

  /// U-66 (T-103 audit) — a lawyer asks what was said AFTER the school-fee
  /// text in March: search found it in isolation and a tap did nothing. A
  /// jump clears the filter, loads older pages until the text is in (bounded),
  /// and moves the thread's CENTER (T-104's anchor) to it, so it opens at the
  /// top of the viewport with what came after it below — without estimating
  /// the height of a lazy list. Then a brief tint.
  Future<void> _jumpTo(int id) async {
    var pages = 0;
    while (!_messages.any((m) => m.id == id) && _hasOlder && pages++ < 50) {
      await _loadOlder();
      if (!mounted) return;
    }
    if (!_messages.any((m) => m.id == id)) return;
    _highlightTimer?.cancel();
    setState(() {
      _query = null;
      _search.clear();
      _anchorId = id;
      _highlightId = id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final p = _scroll.position;
      _scroll.jumpTo(0.0.clamp(p.minScrollExtent, p.maxScrollExtent));
    });
    _highlightTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _highlightId = null);
    });
  }

  /// U-66 — "Ir para a data": the first text on or after the chosen day
  /// (older pages loaded as needed); past the last text, the last one.
  Future<void> _goToDate(Localization l) async {
    final now = widget.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(2020),
      lastDate: today,
      helpText: l[KApp.chatGoToDate],
    );
    if (picked == null || !mounted) return;
    var pages = 0;
    while (_hasOlder &&
        _messages.isNotEmpty &&
        !_messages.first.createdAt.toLocal().isBefore(picked) &&
        pages++ < 50) {
      await _loadOlder();
      if (!mounted) return;
    }
    if (_messages.isEmpty) return;
    final target = _messages.firstWhere(
        (m) => !m.createdAt.toLocal().isBefore(picked),
        orElse: () => _messages.last);
    await _jumpTo(target.id);
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
              if (_query != null)
                IconButton(
                  key: const ValueKey('chat-go-to-date'),
                  icon: const Icon(Icons.event_outlined),
                  tooltip: l[KApp.chatGoToDate],
                  onPressed: () => _goToDate(l),
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
                // F-90: an ACTION, like the other state's — the tooltip
                // used to read "Push da Conversa ligado." while it was off.
                tooltip: l[_muted ? KApp.chatUnmute : KApp.chatMute],
                onPressed: () => _toggleMute(l),
              ),
              // U-59: the door to the EXISTING PDF, pre-filled with the
              // Conversa. A viewer exports too (F-50); the sheet gates a
              // family without Premium.
              if (_me != null)
                IconButton(
                  key: const ValueKey('chat-export'),
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: l[KApp.chatExport],
                  onPressed: () => showChatExportSheet(
                    context,
                    dataSource: widget.dataSource,
                    premium: Family.isPremiumFamily(
                        _family, widget.now().toUtc()),
                    viewer: _me!.isViewer,
                    attestationEnabled: _settings.reportAttestationEnabled,
                    now: widget.now,
                    onOpenPlan: widget.onOpenPlan,
                  ),
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
                : _thread(shown, notice, l),
          ),
        ),
        // F-90: what arrived while the reader searched or read further up —
        // one tap goes to it, and only then is it read.
        if (_onScreen && _newForMe > 0 && (_searching || !_atEnd))
          Padding(
            padding: const EdgeInsets.only(bottom: Spacing.xs),
            child: ActionChip(
              key: const ValueKey('chat-new-below'),
              avatar: const Icon(Icons.arrow_downward, size: 18),
              label: Text(_newForMe == 1
                  ? l[KApp.chatNewOne]
                  : l.format(KApp.chatNewMany, [_newForMe])),
              onPressed: () {
                setState(() {
                  _query = null;
                  _search.clear();
                });
                _scrollToEnd();
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => unawaited(_markRead()));
              },
            ),
          ),
        _composerArea(l),
      ],
    );
  }

  /// T-104: the thread around a CENTER — the page loaded at opening (and
  /// everything newer) after it, older pages before it growing upward, so a
  /// page prepended while the reader is at the top lands above what they read
  /// instead of pushing it down. The notice and the "older" row close the top.
  Widget _thread(List<ChatMessage> shown, Widget notice, Localization l) {
    final anchor = _anchorId;
    final older = [
      for (final m in shown)
        if (anchor != null && m.id < anchor) m
    ];
    final newer = [
      for (final m in shown)
        if (anchor == null || m.id >= anchor) m
    ];
    return CustomScrollView(
      controller: _scroll,
      center: _center,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        // Laid out upward from the center: index 0 is the text right above it.
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final n = older.length;
                if (i < n) return _bubble(older[n - 1 - i], l);
                if (i == n) return _olderRow(l);
                return notice;
              },
              childCount: older.isEmpty ? 0 : older.length + 2,
            ),
          ),
        ),
        // Until an older page is loaded the top rows open the center sliver:
        // before it they would sit above the viewport even on a short thread.
        SliverPadding(
          key: _center,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                if (older.isNotEmpty) return _bubble(newer[i], l);
                if (i == 0) return notice;
                if (i == 1) return _olderRow(l);
                return _bubble(newer[i - 2], l);
              },
              childCount: newer.length + (older.isEmpty ? 2 : 0),
            ),
          ),
        ),
      ],
    );
  }

  /// The top of the loaded thread: a spinner while the previous page comes,
  /// a button when there is one (the scroll fetches it on its own; the button
  /// is for a thread too short to scroll), nothing at the very beginning.
  Widget _olderRow(Localization l) {
    if (_loadingOlder) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Spacing.sm),
        child: Center(
          child: SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (!_hasOlder) return const SizedBox.shrink();
    return Center(
      child: TextButton(
        key: const ValueKey('chat-load-older'),
        onPressed: _loadOlder,
        child: Text(l[KApp.chatLoadOlder]),
      ),
    );
  }

  Widget _bubble(ChatMessage m, Localization l) {
    final tokens = context.tokens;
    final textTheme = Theme.of(context).textTheme;
    final mine = m.authorProfileId == _me?.id;
    final quoted = m.quoteId == null
        ? null
        : _messages.where((q) => q.id == m.quoteId).firstOrNull ??
            _quoted[m.quoteId];
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
          color: m.id == _highlightId
              ? tokens.warning.container
              : mine
                  ? tokens.accent.container
                  : null,
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
                  // U-66: the quote is a way to the text it quotes.
                  Semantics(
                    button: true,
                    hint: l[KApp.chatOpenQuoted],
                    child: InkWell(
                      key: ValueKey('chat-quote-${m.id}'),
                      onTap: () => _jumpTo(quoted.id),
                      child: Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 48),
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
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  // U-66: still selectable (a parent copies what was said),
                  // but no longer a 20 dp unlabelled tap target — the U-32
                  // walk found SelectableText's own node the first time a
                  // scene carried texts.
                  child: SelectionArea(child: Text(m.body)),
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
                // U-66: a search result leads back into the thread, where
                // what was said around it is.
                if (_searching)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: ValueKey('chat-show-${m.id}'),
                      icon: const Icon(Icons.forum_outlined, size: 18),
                      label: Text(l[KApp.chatShowInThread]),
                      onPressed: () => _jumpTo(m.id),
                    ),
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
          onAction: widget.onOpenPlan == null
              ? null
              : () {
                  // F-79: this gate's door now counts its click, like the rest.
                  unawaited(widget.dataSource.analytics?.trackEvent(
                          AnalyticsEvents.premiumGateClick,
                          props: {'gate': 'chat'}) ??
                      Future<void>.value());
                  widget.onOpenPlan!();
                },
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
                    // U-66: the opening notice scrolls away once the thread
                    // has history; the permanence is said where one writes.
                    helper: l[KApp.chatComposerPermanent],
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
