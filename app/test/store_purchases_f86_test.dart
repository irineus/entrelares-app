// F-86 — the purchase listener lives with the app, not with the plan page.
//
// The only listener used to be the plan page's: a purchase that settled while
// the parent was on the calendar reached nobody, was never verified nor
// acknowledged, and Play refunds an unacknowledged purchase after three days.
import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/services/store_billing.dart';
import 'package:entrelares_app/services/store_purchases.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

class _Store implements StoreBilling {
  final _controller = StreamController<StorePurchase>.broadcast();
  final List<StorePurchase> completed = [];
  int restores = 0;
  bool available = true;

  void emit(StorePurchase p) => _controller.add(p);

  @override
  Future<bool> isAvailable() async => available;
  @override
  Future<List<StoreProduct>> loadProducts() async => const [];
  @override
  Future<void> buy(StoreProduct product) async {}
  @override
  Future<void> restore() async => restores++;
  @override
  Stream<StorePurchase> get purchases => _controller.stream;
  @override
  Future<void> complete(StorePurchase purchase) async => completed.add(purchase);
  @override
  void dispose() => _controller.close();
}

const _bought = StorePurchase(
  productId: storeProductMonthly,
  status: StorePurchaseStatus.purchased,
  verificationToken: 'token-late',
);

void main() {
  test('a purchase that settles with no plan page open is verified and '
      'acknowledged', () async {
    final store = _Store();
    final ds = FakeCustodyDataSource(members: const [], days: const []);
    final purchases = StorePurchaseCoordinator(store: store, dataSource: ds);
    await purchases.activate(restore: false);

    store.emit(const StorePurchase(
        productId: storeProductMonthly, status: StorePurchaseStatus.pending));
    await pumpEventQueue();
    expect(purchases.pending.value, isTrue);

    // The slow payment method settles while the reader is on the calendar.
    store.emit(_bought);
    await pumpEventQueue();

    expect(ds.verifiedPurchases,
        [(productId: storeProductMonthly, token: 'token-late')]);
    expect(store.completed, [_bought]);
    expect(purchases.pending.value, isFalse);
    purchases.dispose();
  });

  test('a purchase delivered before sign-in is held, then verified; one '
      'restore per process', () async {
    final store = _Store();
    final ds = FakeCustodyDataSource(members: const [], days: const []);
    final purchases = StorePurchaseCoordinator(store: store, dataSource: ds);

    store.emit(_bought);
    await pumpEventQueue();
    expect(ds.verifiedPurchases, isEmpty, reason: 'no session to verify with');

    await purchases.activate();
    await pumpEventQueue();
    expect(ds.verifiedPurchases, hasLength(1));
    expect(store.restores, 1);

    purchases.deactivate();
    await purchases.activate();
    expect(store.restores, 1, reason: 'once per process');
    purchases.dispose();
  });

  test('a purchase the server refused is never acknowledged', () async {
    final store = _Store();
    final ds = FakeCustodyDataSource(members: const [], days: const [])
      ..throwOnVerify = const BillingRefused('Compra não reconhecida.');
    final purchases = StorePurchaseCoordinator(store: store, dataSource: ds);
    final outcomes = <StorePurchaseOutcome>[];
    purchases.outcomes.listen(outcomes.add);
    await purchases.activate(restore: false);

    store.emit(_bought);
    await pumpEventQueue();

    expect(store.completed, isEmpty);
    expect(outcomes.single.kind, StorePurchaseOutcomeKind.refused);
    expect(outcomes.single.message, 'Compra não reconhecida.');
    purchases.dispose();
  });
}
