// T-48 — the store rail on screen: Play Billing behind its own master switch.
//
// The rule this suite exists to protect is the one Play enforces and the one
// the client can most easily break: **the app never grants Premium**. A
// purchase is a claim; the entitlement arrives only after the SERVER verified
// the token. So the interesting assertions are about what happens between the
// two — what is shown, what is acknowledged, and what is NOT.
import 'dart:async';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_db_contracts/models/member.dart';
import 'package:entrelares_db_contracts/models/role.dart';
import 'package:entrelares_db_contracts/models/subscription.dart';
import 'package:entrelares_app/screens/family_screen.dart';
import 'package:entrelares_app/services/admin_mode.dart';
import 'package:entrelares_app/services/custody_data_source.dart';
import 'package:entrelares_app/services/store_billing.dart';
import 'package:entrelares_app/services/sudo_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

const _admin = Member(
  id: 1,
  fullName: 'Ana Souza',
  colorSlot: 1,
  userId: 'u1',
  isAdmin: true,
  roleId: 1,
  email: 'ana@example.com',
);

const _storeOn = {
  'billing.enabled': 'true',
  'billing.store_enabled': 'true',
  'billing.price_monthly_cents': '549',
  'billing.price_annual_cents': '5490',
};

class _FakeStore implements StoreBilling {
  bool available = true;
  List<StoreProduct> products = const [
    StoreProduct(id: storeProductMonthly, price: 'R\$ 6,90', cycle: 'monthly'),
    StoreProduct(id: storeProductAnnual, price: 'R\$ 69,00', cycle: 'annual'),
  ];
  Object? throwOnLoad;
  final List<String> bought = [];
  final List<StorePurchase> completed = [];
  int restores = 0;

  final _controller = StreamController<StorePurchase>.broadcast();

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<List<StoreProduct>> loadProducts() async {
    if (throwOnLoad != null) throw throwOnLoad!;
    return products;
  }

  @override
  Future<void> buy(StoreProduct product) async => bought.add(product.id);

  @override
  Future<void> restore() async => restores++;

  @override
  Stream<StorePurchase> get purchases => _controller.stream;

  @override
  Future<void> complete(StorePurchase purchase) async =>
      completed.add(purchase);

  void emit(StorePurchase purchase) => _controller.add(purchase);

  @override
  void dispose() => _controller.close();
}

FakeCustodyDataSource _source({
  String plan = 'free',
  Subscription? subscription,
  Map<String, String> settings = _storeOn,
}) =>
    FakeCustodyDataSource(members: const [_admin], days: [])
      ..family = Family(id: 7, name: 'Souza', plan: plan)
      ..roles = const [Role(id: 1, roleName: 'mother')]
      ..publicSettings = settings
      ..subscription = subscription;

Future<void> _pump(
  WidgetTester tester,
  FakeCustodyDataSource ds,
  _FakeStore store, {
  List<String>? opened,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(store.dispose);
  await tester.pumpWidget(AppL10n(
    l: Localization(AppLanguage.ptBr),
    setLanguage: (_) async {},
    child: MaterialApp(
      home: FamilyScreen(
        dataSource: ds,
        adminMode: AdminMode(),
        sudo: SudoService(ds),
        isStoreChannel: true,
        storeBilling: store,
        openExternal: opened == null ? (_) async {} : (url) async => opened.add(url),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  final l = Localization(AppLanguage.ptBr);
  Finder text(String value) => find.text(stripRichText(value));

  group('the master switch', () {
    testWidgets('off keeps the T-38 neutral note and never asks the store',
        (tester) async {
      final store = _FakeStore();
      await _pump(
        tester,
        _source(settings: const {
          'billing.enabled': 'true',
          'billing.store_enabled': 'false',
        }),
        store,
      );

      expect(text(l[K.premStoreNote]), findsOne);
      expect(text(l.format(K.premSubscribeMonthly, ['R\$ 6,90'])), findsNothing);
    });

    testWidgets('on, with products, shows PLAY prices — not app_settings ones',
        (tester) async {
      // The store price carries Google's fee and is set in the Console per
      // country; showing the web rail's number here would be a lie about what
      // is charged.
      final store = _FakeStore();
      await _pump(tester, _source(), store);

      expect(text(l.format(K.premSubscribeMonthly, ['R\$ 6,90'])), findsOne);
      expect(text(l.format(K.premSubscribeAnnual, ['R\$ 69,00'])), findsOne);
      expect(text(l.format(K.premSubscribeMonthly, ['R\$ 5,49'])), findsNothing);
    });

    testWidgets('a store that cannot answer falls back to the neutral note',
        (tester) async {
      final store = _FakeStore()..available = false;
      await _pump(tester, _source(), store);

      expect(text(l[K.premStoreNote]), findsOne);
      expect(text(l[KApp.storeRestore]), findsNothing);
    });

    testWidgets('a query that throws falls back too — never a half offer',
        (tester) async {
      final store = _FakeStore()..throwOnLoad = Exception('billing unavailable');
      await _pump(tester, _source(), store);

      expect(text(l[K.premStoreNote]), findsOne);
    });
  });

  group('buying', () {
    testWidgets('the button opens the store sheet for that product',
        (tester) async {
      final store = _FakeStore();
      await _pump(tester, _source(), store);

      await tester.tap(text(l.format(K.premSubscribeAnnual, ['R\$ 69,00'])));
      await tester.pumpAndSettle();

      expect(store.bought, [storeProductAnnual]);
    });

    testWidgets('a pending purchase says it is being confirmed, grants nothing',
        (tester) async {
      final ds = _source();
      final store = _FakeStore();
      await _pump(tester, ds, store);

      store.emit(const StorePurchase(
          productId: storeProductMonthly,
          status: StorePurchaseStatus.pending));
      await tester.pumpAndSettle();

      expect(text(l[KApp.storePending]), findsOne);
      expect(ds.verifiedPurchases, isEmpty);
    });

    testWidgets('a purchase is verified by the SERVER before being acknowledged',
        (tester) async {
      final ds = _source();
      final store = _FakeStore();
      await _pump(tester, ds, store);

      store.emit(const StorePurchase(
        productId: storeProductMonthly,
        status: StorePurchaseStatus.purchased,
        verificationToken: 'token-abc',
      ));
      await tester.pumpAndSettle();

      expect(ds.verifiedPurchases,
          [(productId: storeProductMonthly, token: 'token-abc')]);
      // Acknowledge only AFTER the server accepted: Play refunds an
      // unacknowledged purchase after three days, and acknowledging one the
      // server refused would strand the family without the entitlement.
      expect(store.completed, hasLength(1));
      expect(text(l[KApp.storeToastActive]), findsOne);
    });

    testWidgets('a server refusal is NOT acknowledged and says why',
        (tester) async {
      final ds = _source()
        ..throwOnVerify = const BillingRefused('Compra já usada por outra família.');
      final store = _FakeStore();
      await _pump(tester, ds, store);

      store.emit(const StorePurchase(
        productId: storeProductMonthly,
        status: StorePurchaseStatus.purchased,
        verificationToken: 'token-abc',
      ));
      await tester.pumpAndSettle();

      expect(store.completed, isEmpty);
      expect(find.text('Compra já usada por outra família.'), findsOne);
    });

    testWidgets('a failed purchase shows the store message, verifies nothing',
        (tester) async {
      final ds = _source();
      final store = _FakeStore();
      await _pump(tester, ds, store);

      store.emit(const StorePurchase(
        productId: storeProductMonthly,
        status: StorePurchaseStatus.failed,
        errorMessage: 'Pagamento recusado pelo Google.',
      ));
      await tester.pumpAndSettle();

      expect(find.text('Pagamento recusado pelo Google.'), findsOne);
      expect(ds.verifiedPurchases, isEmpty);
    });

    testWidgets('a cancelled purchase says nothing at all', (tester) async {
      // Backing out is not an error — the family chose it.
      final ds = _source();
      final store = _FakeStore();
      await _pump(tester, ds, store);

      store.emit(const StorePurchase(
          productId: storeProductMonthly,
          status: StorePurchaseStatus.canceled));
      await tester.pumpAndSettle();

      expect(text(l[KApp.storeErrPurchase]), findsNothing);
      expect(ds.verifiedPurchases, isEmpty);
    });

    testWidgets('a restored purchase takes the same verification path',
        (tester) async {
      final ds = _source();
      final store = _FakeStore();
      await _pump(tester, ds, store);

      await tester.tap(text(l[KApp.storeRestore]));
      await tester.pumpAndSettle();
      expect(store.restores, 1);

      store.emit(const StorePurchase(
        productId: storeProductAnnual,
        status: StorePurchaseStatus.restored,
        verificationToken: 'token-restored',
      ));
      await tester.pumpAndSettle();

      expect(ds.verifiedPurchases,
          [(productId: storeProductAnnual, token: 'token-restored')]);
    });
  });

  group('an existing store subscriber', () {
    testWidgets('is not sold to again, and manages on Play', (tester) async {
      final opened = <String>[];
      final store = _FakeStore();
      await _pump(
        tester,
        _source(
          plan: 'premium',
          subscription: Subscription(
            id: 1,
            familyId: 7,
            gateway: 'play',
            status: 'canceled',
            cycle: 'annual',
            currentPeriodEnd:
                DateTime.now().toUtc().add(const Duration(days: 30)),
          ),
        ),
        store,
        opened: opened,
      );

      expect(text(l.format(K.premSubscribeAnnual, ['R\$ 69,00'])), findsNothing);

      await tester.tap(text(l[KApp.storeManage]));
      await tester.pumpAndSettle();
      // Play owns that subscription — cancelling it is done there, and this is
      // the honest route rather than a button we cannot honor.
      expect(opened.single, contains('play.google.com/store/account/subscriptions'));
      expect(opened.single, contains('sku=premium_annual'));
    });
  });
}
