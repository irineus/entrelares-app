import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart';

import 'analytics_service.dart';
import 'custody_data_source.dart';
import 'store_billing.dart';

/// What happened to a purchase update, for whoever is on screen.
enum StorePurchaseOutcomeKind { pending, verified, refused, failed, canceled }

class StorePurchaseOutcome {
  final StorePurchaseOutcomeKind kind;
  final StorePurchase purchase;

  /// The server's own sentence for a refusal, or the store's for a failure.
  final String? message;

  const StorePurchaseOutcome(this.kind, this.purchase, {this.message});
}

/// F-86 — the ONE listener to the store's purchase stream, for the whole
/// life of the app.
///
/// It used to live in the plan page's state: a purchase that settled later (a
/// slow payment method) while the parent was on the calendar reached no
/// listener, was never verified nor acknowledged — and Play refunds an
/// unacknowledged purchase after three days. She paid, never got Premium, and
/// got refunded. Now the purchase is verified and acknowledged wherever the
/// reader is; the plan page only listens to [outcomes] to say so.
///
/// Verification needs a signed-in session, so an owned purchase that arrives
/// before the authenticated phase is HELD and handled on [activate]. On the
/// first activation of the process, one [StoreBilling.restore] asks Play to
/// re-deliver what this account owns — the way an unacknowledged purchase
/// from an earlier opening is finally verified.
///
/// Nothing here grants Premium: the server verifies the token, and the
/// acknowledgement goes to Play only after it accepted (T-48).
class StorePurchaseCoordinator {
  final StoreBilling store;
  final CustodyDataSource dataSource;
  final AnalyticsService? analytics;

  /// A purchase is in flight (Play pending, or our server verifying).
  final ValueNotifier<bool> pending = ValueNotifier(false);

  final _outcomes = StreamController<StorePurchaseOutcome>.broadcast();
  StreamSubscription<StorePurchase>? _subscription;
  final List<StorePurchase> _held = [];
  bool _active = false;
  bool _restored = false;

  StorePurchaseCoordinator({
    required this.store,
    required this.dataSource,
    this.analytics,
  }) {
    _subscription = store.purchases.listen(_onPurchase);
  }

  Stream<StorePurchaseOutcome> get outcomes => _outcomes.stream;

  /// The session entered the authenticated phase: handle what was held, and
  /// — once per process, when [restore] — ask Play for what this account
  /// owns.
  Future<void> activate({bool restore = true}) async {
    _active = true;
    final held = [..._held];
    _held.clear();
    for (final purchase in held) {
      await _handle(purchase);
    }
    if (!restore || _restored) return;
    _restored = true;
    try {
      if (await store.isAvailable()) await store.restore();
    } catch (_) {/* no store on this device: nothing to re-deliver */}
  }

  /// Left the authenticated phase: owned purchases wait for the next session.
  void deactivate() => _active = false;

  Future<void> _onPurchase(StorePurchase purchase) async {
    if (!_active && purchase.isOwned) {
      _held.add(purchase);
      return;
    }
    await _handle(purchase);
  }

  Future<void> _handle(StorePurchase purchase) async {
    if (purchase.status == StorePurchaseStatus.pending) {
      pending.value = true;
      _emit(StorePurchaseOutcomeKind.pending, purchase);
      return;
    }
    if (!purchase.isOwned) {
      pending.value = false;
      _emit(
          purchase.status == StorePurchaseStatus.failed
              ? StorePurchaseOutcomeKind.failed
              : StorePurchaseOutcomeKind.canceled,
          purchase,
          message: purchase.errorMessage);
      return;
    }

    pending.value = true;
    try {
      await dataSource.verifyStorePurchase(
        productId: purchase.productId,
        purchaseToken: purchase.verificationToken ?? '',
      );
      // Acknowledge ONLY after the server accepted it — Play refunds an
      // unacknowledged purchase after three days, and acknowledging one the
      // server refused would strand the family without the entitlement.
      await store.complete(purchase);
      // A RESTORED purchase is something already bought: counting it as a
      // checkout outcome would inflate the funnel on every opening.
      if (purchase.status == StorePurchaseStatus.purchased) {
        analytics?.trackEvent(AnalyticsEvents.premiumCheckoutOutcome,
            props: analyticsFunnelProps(
                channel: analyticsChannel(isWeb: false),
                cycle: cycleForStoreProduct(purchase.productId),
                mode: 'store',
                outcome: 'confirmed'));
      }
      pending.value = false;
      _emit(StorePurchaseOutcomeKind.verified, purchase);
    } on BillingRefused catch (e) {
      pending.value = false;
      _emit(StorePurchaseOutcomeKind.refused, purchase,
          message: e.serverMessage);
    } catch (_) {
      pending.value = false;
      _emit(StorePurchaseOutcomeKind.failed, purchase);
    }
  }

  void _emit(StorePurchaseOutcomeKind kind, StorePurchase purchase,
      {String? message}) {
    if (!_outcomes.isClosed) {
      _outcomes.add(StorePurchaseOutcome(kind, purchase, message: message));
    }
  }

  void dispose() {
    _subscription?.cancel();
    _outcomes.close();
    pending.dispose();
  }
}
