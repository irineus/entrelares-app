// `/premium/retorno` — where the payer lands after the hosted checkout.
//
// The screen's whole job is to be HONEST about an asynchronous confirmation:
// the webhook flips `families.plan`, not this client, so it may only say
// "ativo" when it has SEEN the flip. The two failure shapes it must survive
// are a slow settle (Pix) and a read that blows up mid-poll — neither is a
// failed payment, and neither may be announced as one.
import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:entrelares_db_contracts/models/family.dart';
import 'package:entrelares_app/screens/premium_return_screen.dart';
import 'package:entrelares_app/services/analytics_service.dart';
import 'package:entrelares_app/widgets/app_l10n.dart';

import 'calendar_slice_test.dart' show FakeCustodyDataSource;

/// A family whose plan flips to premium on the [flipsOnRead]-th read, the way
/// the webhook flips it while the payer waits on this screen.
class _FlippingSource extends FakeCustodyDataSource {
  final int flipsOnRead;
  int reads = 0;
  Object? throwOnce;

  _FlippingSource({this.flipsOnRead = 1})
      : super(members: const [], days: const []);

  @override
  Future<Family?> fetchOwnFamily() async {
    reads++;
    if (throwOnce != null && reads == 1) {
      final error = throwOnce!;
      throwOnce = null;
      throw error;
    }
    return Family(
        id: 7, name: 'Souza', plan: reads >= flipsOnRead ? 'premium' : 'free');
  }
}

void main() {
  final l = Localization(AppLanguage.ptBr);

  late List<Map<String, dynamic>> payloads;

  AnalyticsService analytics() {
    payloads = [];
    return AnalyticsService(
      websiteId: 'site-1',
      host: 'https://umami.example',
      hostname: 'app.entrelares.app',
      client: MockClient((request) async {
        payloads.add(
            (jsonDecode(request.body) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>);
        return http.Response('', 200);
      }),
    );
  }

  Map<String, dynamic>? dataOf(String name) {
    for (final payload in payloads) {
      if (payload['name'] == name) return payload['data'] as Map<String, dynamic>?;
    }
    return null;
  }

  Future<void> pump(
    WidgetTester tester,
    FakeCustodyDataSource ds, {
    AnalyticsService? tracker,
    int maxAttempts = 3,
  }) async {
    await tester.pumpWidget(AppL10n(
      l: l,
      setLanguage: (_) async {},
      child: MaterialApp(
        home: PremiumReturnScreen(
          dataSource: ds,
          analytics: tracker,
          maxAttempts: maxAttempts,
          pollDelay: const Duration(milliseconds: 10),
        ),
      ),
    ));
  }

  testWidgets('while nothing is confirmed it says it is confirming, no promise',
      (tester) async {
    await pump(tester, _FlippingSource(flipsOnRead: 99));
    await tester.pump();

    expect(find.text(l[K.payConfirmingTitle]), findsOne);
    expect(find.text(l[K.payActiveTitle]), findsNothing);

    await tester.pumpAndSettle();
  });

  testWidgets('the flip the webhook makes is what turns the screen green',
      (tester) async {
    final tracker = analytics();
    await pump(tester, _FlippingSource(flipsOnRead: 2), tracker: tracker);
    await tester.pumpAndSettle();

    expect(find.text(l[K.payActiveTitle]), findsOne);
    // F-48: the guarantee travels to the confirmation — the moment of payment
    // is when the promise matters most.
    expect(find.text(l[K.payGuarantee]), findsOne);
    expect(dataOf('premium-checkout-return'), {'channel': 'store'});
    expect(dataOf('premium-checkout-outcome'),
        {'channel': 'store', 'outcome': 'confirmed'});
  });

  testWidgets('a slow settle ends in "quase lá", never in a false success',
      (tester) async {
    final tracker = analytics();
    await pump(tester, _FlippingSource(flipsOnRead: 99), tracker: tracker);
    await tester.pumpAndSettle();

    expect(find.text(l[K.payAlmostTitle]), findsOne);
    expect(find.text(l[K.payAlmostHint]), findsOne);
    expect(find.text(l[K.payActiveTitle]), findsNothing);
    expect(dataOf('premium-checkout-outcome'),
        {'channel': 'store', 'outcome': 'timeout'});
  });

  testWidgets('a read that fails is not a failed payment — the poll goes on',
      (tester) async {
    final ds = _FlippingSource(flipsOnRead: 2)..throwOnce = Exception('offline');
    await pump(tester, ds);
    await tester.pumpAndSettle();

    // The first read threw; the second saw the flip.
    expect(find.text(l[K.payActiveTitle]), findsOne);
  });

  testWidgets('leaving the screen stops the poll', (tester) async {
    final ds = _FlippingSource(flipsOnRead: 99);
    await pump(tester, ds, maxAttempts: 50);
    await tester.pump();
    final readsWhileMounted = ds.reads;

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));

    expect(ds.reads, lessThanOrEqualTo(readsWhileMounted + 1));
  });
}
