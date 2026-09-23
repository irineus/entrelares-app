import 'package:entrelares_core/entrelares_core.dart';

/// T-78 — tells the server, at most once per local day, that the signed-in
/// member used the app on [channel] (`touch_activity`).
///
/// The shell calls [touch] generously — on entering the authenticated phase,
/// on every resume and on every pointer-down — and this class makes that
/// cheap: after the day's first SUCCESS, every other call is a string
/// comparison. A failed call (no signal, T-18) is dropped, not queued, and
/// leaves the day open so the next open or tap asks again. Nothing is ever
/// read back: the table is service-role only.
class ActivityTracker {
  ActivityTracker(this._send, {required this.channel, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  /// The RPC, injected so the class tests without a server.
  final Future<void> Function(String channel) _send;

  /// Resolved once per process (`ActivityRules.channel`).
  final ActivityChannel channel;

  final DateTime Function() _clock;

  String? _lastTouchedDay;
  bool _inFlight = false;

  /// Fire-and-forget by contract: never throws, never awaits anything the
  /// caller must wait for.
  Future<void> touch() async {
    final now = _clock();
    if (_inFlight) return;
    if (!ActivityRules.shouldTouch(lastTouchedDay: _lastTouchedDay, now: now)) {
      return;
    }
    _inFlight = true;
    try {
      await _send(channel.wire);
      _lastTouchedDay = ActivityRules.dayKey(now);
    } catch (_) {
      // Lost on purpose: activity is a count of days, not a queue of events.
    } finally {
      _inFlight = false;
    }
  }

  /// Leaving the authenticated phase: whoever signs in next on this device is
  /// another member, with a day of their own to record.
  void reset() => _lastTouchedDay = null;
}
