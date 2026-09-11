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
  void Function()? _unwatch;
  bool _disposed = false;

  NotificationBadge(this._dataSource);

  /// Entering the authenticated phase: first count + the Realtime trigger.
  Future<void> start() async {
    await refresh();
    if (_disposed || _unwatch != null) return;
    _unwatch = await _dataSource.watchWorkflowChanges(() => refresh());
    if (_disposed) stop();
  }

  /// Leaving the authenticated phase: no badge for anonymous shells.
  void stop() {
    _unwatch?.call();
    _unwatch = null;
    _set(0);
  }

  /// Best-effort: a failed read keeps the last known count (web parity — the
  /// badge is a hint, never a gate).
  Future<void> refresh() async {
    try {
      final me = await _dataSource.fetchOwnProfile();
      if (me == null) {
        _set(0);
        return;
      }
      final pending = await _dataSource.fetchPendingForMe(me.id);
      _set(pending.length);
    } catch (_) {/* keep the last count */}
  }

  void _set(int value) {
    if (_disposed || value == count) return;
    count = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _unwatch?.call();
    _unwatch = null;
    super.dispose();
  }
}
