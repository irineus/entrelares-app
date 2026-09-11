import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// T-48 — the store rail's client half, behind an interface.
///
/// Play Billing is the only way a native app may sell a digital subscription
/// inside the app, and its flow is nothing like the web's: there is no URL to
/// open, the system sheet does the charging, and the answer arrives on a
/// STREAM that can also deliver purchases made on another device or before a
/// reinstall. Wrapping it here keeps two promises:
///
/// * the Premium section is testable without a store (widget tests drive a
///   fake), and
/// * **nothing here grants Premium.** A purchase is a claim; the entitlement
///   comes from the server verifying the token with the Play Developer API and
///   writing through the same `set_family_plan` the Asaas webhook uses.
abstract class StoreBilling {
  /// Whether this device can sell at all (no Play Services, a sideloaded APK
  /// outside the store, an emulator without the store — all answer false).
  Future<bool> isAvailable();

  /// The subscription products, with the price PLAY reports for this user's
  /// country. Ids the client does not recognise are dropped.
  Future<List<StoreProduct>> loadProducts();

  /// Opens the system purchase sheet. The outcome arrives on [purchases].
  Future<void> buy(StoreProduct product);

  /// Asks the store to re-deliver what this account already owns — the way
  /// back after a reinstall or a device swap.
  Future<void> restore();

  /// Purchase updates: new ones, restored ones, failures and cancellations.
  Stream<StorePurchase> get purchases;

  /// Tells the store the purchase was handled. MUST be called after the server
  /// verified it, or Play refunds the charge after three days.
  Future<void> complete(StorePurchase purchase);

  void dispose();
}

/// One sellable subscription, with Play's own localized price string.
class StoreProduct {
  final String id;

  /// Formatted by the store for the buyer's country — displayed verbatim.
  /// This is why the store rail has no price arithmetic: the number is Play's.
  final String price;

  /// `monthly` / `annual`, derived from the id by the core mirror.
  final String cycle;

  const StoreProduct({
    required this.id,
    required this.price,
    required this.cycle,
  });
}

/// How a purchase update arrived.
enum StorePurchaseStatus { pending, purchased, restored, failed, canceled }

/// A purchase update. [verificationToken] is what the SERVER checks against
/// the Play Developer API — the client never inspects it.
class StorePurchase {
  final String productId;
  final StorePurchaseStatus status;
  final String? verificationToken;

  /// The store's own message when it failed, preferred over a guess.
  final String? errorMessage;

  const StorePurchase({
    required this.productId,
    required this.status,
    this.verificationToken,
    this.errorMessage,
  });

  bool get isOwned =>
      status == StorePurchaseStatus.purchased ||
      status == StorePurchaseStatus.restored;
}

/// The real implementation, on `in_app_purchase`.
class PlayStoreBilling implements StoreBilling {
  final InAppPurchase _iap;
  final _controller = StreamController<StorePurchase>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  /// The plugin's details for a product id, kept so [buy] can hand the plugin
  /// back its own object (it will not accept ours).
  final Map<String, ProductDetails> _details = {};

  PlayStoreBilling({InAppPurchase? iap}) : _iap = iap ?? InAppPurchase.instance {
    _subscription = _iap.purchaseStream.listen(
      (updates) => updates.map(_map).forEach(_controller.add),
      onError: (_) {/* a dead stream is not a failed payment */},
    );
  }

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<List<StoreProduct>> loadProducts() async {
    final response = await _iap
        .queryProductDetails({storeProductMonthly, storeProductAnnual});
    final products = <StoreProduct>[];
    for (final detail in response.productDetails) {
      _details[detail.id] = detail;
      final cycle = cycleForStoreProduct(detail.id);
      // An id we do not recognise is never shown: the store answering with
      // something unexpected must not become a button that charges.
      if (cycle == null) continue;
      products
          .add(StoreProduct(id: detail.id, price: detail.price, cycle: cycle));
    }
    return products;
  }

  @override
  Future<void> buy(StoreProduct product) async {
    final detail = _details[product.id];
    if (detail == null) return;
    await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: detail));
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Stream<StorePurchase> get purchases => _controller.stream;

  @override
  Future<void> complete(StorePurchase purchase) async {
    final pending = _pending.remove(purchase.productId);
    if (pending != null && pending.pendingCompletePurchase) {
      await _iap.completePurchase(pending);
    }
  }

  /// The plugin objects awaiting completion, by product — [complete] needs the
  /// original to acknowledge, and Play refunds an unacknowledged purchase
  /// after three days.
  final Map<String, PurchaseDetails> _pending = {};

  StorePurchase _map(PurchaseDetails details) {
    _pending[details.productID] = details;
    return StorePurchase(
      productId: details.productID,
      status: switch (details.status) {
        PurchaseStatus.pending => StorePurchaseStatus.pending,
        PurchaseStatus.purchased => StorePurchaseStatus.purchased,
        PurchaseStatus.restored => StorePurchaseStatus.restored,
        PurchaseStatus.canceled => StorePurchaseStatus.canceled,
        PurchaseStatus.error => StorePurchaseStatus.failed,
      },
      verificationToken: details.verificationData.serverVerificationData,
      errorMessage: details.error?.message,
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
