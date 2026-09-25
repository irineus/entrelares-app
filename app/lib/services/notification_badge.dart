import 'package:flutter/foundation.dart';

import 'custody_data_source.dart';

/// The bell badge state — ⚠️ mirror of `MainLayout.RefreshNotificationBadgeAsync`:
/// the count is the OPEN REQUESTS AWAITING ME (`fetchPendingForMe`), NOT the
/// unread notifications (the web's `UnreadCount` exists but nothing renders
/// it). Refreshes on the same triggers as the web: entering the authenticated
/// phase, tab navigation, workflow Realtime events and after page actions.
class NotificationBadge extends ChangeNotifier {
  final CustodyDataSource _dataSource;
  int count = 0;

  /// F-35: texts of others in the Conversa I have not read — counted only
  /// while [chatOn] (the module's flag, set by the app). The bar's bell shows
  /// [total]: pending requests plus unread texts.
  int chatUnread = 0;
  bool chatOn = false;

  int get total => count + chatUnread;
  void Function()? _unwatch;
  void Function()? _unwatchChat;
  bool _disposed = false;

  NotificationBadge(this._dataSource);

  /// Entering the authenticated phase: first count + the Realtime trigger.
  Future<void> start() async {
    await refresh();
    if (_disposed || _unwatch != null) return;
    _unwatch = await _dataSource.watchWorkflowChanges(() => refresh());
    // F-35: a text read on another device of mine drops the Conversa's
    // counter here too; a new text already arrives as a notification row.
    try {
      _unwatchChat = await _dataSource.watchChatChanges(() {
        if (chatOn) refresh();
      });
    } catch (_) {/* the workflow channel and the reads still count */}
    if (_disposed) stop();
  }

  /// Leaving the authenticated phase: no badge for anonymous shells.
  void stop() {
    _unwatch?.call();
    _unwatch = null;
    _unwatchChat?.call();
    _unwatchChat = null;
    _set(0, 0);
  }

  /// Best-effort: a failed read keeps the last known count (web parity — the
  /// badge is a hint, never a gate).
  Future<void> refresh() async {
    try {
      final me = await _dataSource.fetchOwnProfile();
      if (me == null) {
        _set(0, 0);
        return;
      }
      final pending = await _dataSource.fetchPendingForMe(me.id);
      var unread = 0;
      if (chatOn) {
        try {
          unread = await _dataSource.fetchChatUnreadCount(me.id);
        } catch (_) {/* the pending count still stands */}
      }
      _set(pending.length, unread);
    } catch (_) {/* keep the last count */}
  }

  void _set(int value, int unread) {
    if (_disposed || (value == count && unread == chatUnread)) return;
    count = value;
    chatUnread = unread;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _unwatch?.call();
    _unwatch = null;
    _unwatchChat?.call();
    _unwatchChat = null;
    super.dispose();
  }
}
