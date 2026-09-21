import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';

import 'analytics_service.dart';

/// Session-scoped state for the explicit "admin mode" (F-14) — mirror of the
/// web's `AdminModeService`. Admin actions are deliberately separated from the
/// normal parental flow: an admin must switch the mode on (persistent banner
/// shown by the shell) before the UI relaxes the day-protection guards. This
/// is a UI convenience only — the real enforcement (and the admin bypass)
/// lives in the database triggers (V008/F-40).
class AdminMode extends ChangeNotifier {
  bool _active = false;

  bool get isActive => _active;

  void toggle() {
    _active = !_active;
    notifyListeners();
  }

  /// F-67: the answer to the offer — idempotent, unlike [toggle], so a sheet
  /// that asked while something else already switched the mode on can never
  /// switch it back off.
  void activate() {
    if (_active) return;
    _active = true;
    notifyListeners();
  }

  void deactivate() {
    if (!_active) return;
    _active = false;
    notifyListeners();
  }
}

/// F-67 Part B: what a sheet needs to offer the mode at the spot where an
/// admin reached for it. The calendar hands one to its sheets ONLY when the
/// reader is an admin — a null offerer is the "never see the question" rule
/// for everyone else, with no flag to forget.
class AdminModeOfferer {
  final AdminMode adminMode;
  final AnalyticsService? analytics;

  /// Opens `/family/plan` for the free-tier gate (U-49: every Premium gate
  /// CTA navigates there). Null leaves the gate as a sentence.
  final VoidCallback? onOpenPlan;

  const AdminModeOfferer(
      {required this.adminMode, this.analytics, this.onOpenPlan});

  bool get isActive => adminMode.isActive;

  /// The admin said yes: the mode goes on — the shell's banner appears and is
  /// still the way out — and the caller carries its action through.
  void accept(AdminModeAction action) {
    adminMode.activate();
    _track(action, 'accepted');
  }

  void decline(AdminModeAction action) => _track(action, 'declined');

  /// The gate CTA: the same funnel family as the other gates (T-37), told
  /// apart by `gate`.
  void openPlan() {
    unawaited(analytics?.trackEvent('premium-gate-click',
        props: {'gate': 'admin-retro'}));
    onOpenPlan?.call();
  }

  void _track(AdminModeAction action, String result) =>
      unawaited(analytics?.trackEvent('admin-mode-offer',
          props: {'action': action.wireName, 'result': result}));
}
