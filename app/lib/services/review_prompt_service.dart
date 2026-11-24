import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'connectivity_status.dart';
import 'custody_data_source.dart';

/// F-73 — Google's In-App Review behind a seam, so the suite drives it.
abstract class InAppReviewer {
  Future<bool> isAvailable();
  Future<void> requestReview();
}

/// T-60 — Play's review flow through the app's OWN Android channel
/// (`InAppReviewChannel.kt`, registered by `MainActivity`), in place of the
/// `in_app_review` plugin, which applied the Kotlin Gradle Plugin that future
/// Flutter versions refuse. Only the Android production store build ever gets
/// here (`ReviewPromptRules.isStoreBuild`).
class PlayInAppReviewer implements InAppReviewer {
  PlayInAppReviewer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  /// The channel `MainActivity` answers on. Spelled once on each side.
  static const String channelName = 'app.entrelares/in_app_review';
  static const String isAvailableMethod = 'isAvailable';
  static const String requestReviewMethod = 'requestReview';

  final MethodChannel _channel;

  /// False for anything but a clear yes: no channel (a platform without it),
  /// a missing Play Store, or any error.
  @override
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>(isAvailableMethod) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Throws when Play refused a flow — [ReviewPromptService] treats that as
  /// "no review this time" and never shows it to the reader.
  @override
  Future<void> requestReview() =>
      _channel.invokeMethod<void>(requestReviewMethod);
}

/// The last request on THIS device — the interval is per device, like
/// Play's own quota. Best-effort: a prefs failure never reaches the reader.
abstract class ReviewPromptPrefs {
  DateTime? get lastRequestedAt;
  Future<void> markRequested(DateTime at);
}

class SharedReviewPromptPrefs implements ReviewPromptPrefs {
  static const key = 'app.reviewPrompt.lastRequestedAt';
  final SharedPreferences _prefs;
  SharedReviewPromptPrefs(this._prefs);

  @override
  DateTime? get lastRequestedAt {
    try {
      final ms = _prefs.getInt(key);
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> markRequested(DateTime at) async {
    try {
      await _prefs.setInt(key, at.millisecondsSinceEpoch);
    } catch (_) {}
  }
}

/// F-73 — asks Play for the review sheet when the swap's requester SEES the
/// other side's approval (the Notificações list calls [approvalSeen]). Every
/// floor is [ReviewPromptRules]; this only gathers the facts, once per call,
/// and never throws — the review is a courtesy, never a step.
class ReviewPromptService {
  final CustodyDataSource _dataSource;
  final InAppReviewer reviewer;
  final ReviewPromptPrefs prefs;
  final ConnectivityStatus connectivity;

  /// `ReviewPromptRules.isStoreBuild(...)`, decided by `main.dart` from the
  /// build it is.
  final bool isStoreBuild;

  /// When the LOGIN was created (GoTrue's `created_at`) — never the profile
  /// row's, which for a claimed F-56 placeholder is the day the admin added
  /// the seat.
  final DateTime? Function() accountCreatedAt;
  final DateTime Function() now;

  bool _busy = false;

  ReviewPromptService(
    this._dataSource, {
    required this.reviewer,
    required this.prefs,
    required this.connectivity,
    required this.isStoreBuild,
    required this.accountCreatedAt,
    this.now = DateTime.now,
  });

  /// Returns whether the request was made (for the tests).
  Future<bool> approvalSeen() async {
    // Nothing is even read outside the store build.
    if (!isStoreBuild || _busy) return false;
    _busy = true;
    try {
      final me = await _dataSource.fetchOwnProfile();
      final settings = PublicSettings(await _dataSource.fetchPublicSettings());
      final at = now();
      final ask = ReviewPromptRules.shouldRequest(
        enabled: settings.reviewPromptEnabled,
        isStoreBuild: isStoreBuild,
        isViewer: me?.isViewer ?? true,
        offline: connectivity.offline,
        accountCreatedAt: accountCreatedAt(),
        lastRequestedAt: prefs.lastRequestedAt,
        now: at,
        minAccountDays: settings.reviewPromptMinAccountDays,
        intervalDays: settings.reviewPromptIntervalDays,
      );
      if (!ask || !await reviewer.isAvailable()) return false;
      // Marked BEFORE the call: a request Play swallowed still spent the
      // window, which is exactly Play's own reading of its quota.
      await prefs.markRequested(at);
      await reviewer.requestReview();
      await _dataSource.analytics
          ?.trackEvent(AnalyticsEvents.reviewPromptRequested);
      return true;
    } catch (_) {
      return false;
    } finally {
      _busy = false;
    }
  }
}
