import 'dart:convert';

import 'package:entrelares_db_gate/entrelares_db_gate.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

import '_helpers.dart';

/// T-81 — the public feed of the parameters the landing may show.
///
/// The landing has no credential and must not get one (T-44), so the only
/// thing standing between `app_settings` and the internet is the
/// `landing_visible` column and the function that answers it. These tests pin
/// both halves: the column can never mark a server-only row (the CHECK), the
/// whitelist is exactly what we chose (adding a key to the internet is a
/// deliberate diff HERE), and the function says nothing beyond it.
///
/// This suite needs NO family — it touches nothing the fixture owns.
void publicSettingsTests(GateFixture fx) {
  /// What entrelares.app is allowed to read. A new key here is a new value
  /// published to anyone, in the same delivery as its migration.
  const whitelist = {
    'billing.price_monthly_cents',
    'billing.price_annual_cents',
    'calendar_months_free',
    'calendar_months_premium',
    'free_caregivers',
    'landing.launch_free_badge',
    'landing.promo_price_label',
    'landing.play_badge',
  };

  final url = Uri.parse('${TestEnv.supabaseUrl.replaceAll(RegExp(r'/+$'), '')}'
      '/functions/v1/public-settings');

  /// CI redeploys every function minutes before the gate: a 503 is the runtime
  /// still booting, never the function's answer (see edge_function_auth).
  Future<http.Response> send(Future<http.Response> Function() request) async {
    var response = await request();
    for (var attempt = 1; attempt <= 4 && response.statusCode == 503; attempt++) {
      await Future<void>.delayed(Duration(seconds: 2 * attempt));
      response = await request();
    }
    return response;
  }

  group('PublicSettingsTests', () {
    test('a landing value must also be an app value (CHECK)', () async {
      const probeKey = 'e2e.landing_probe';
      await fx.service.from('app_settings').delete().eq('key', probeKey);
      try {
        await expectRejected(
          () => fx.service.from('app_settings').insert({
            'key': probeKey,
            'value': '1',
            'value_type': 'int',
            'category': 'e2e',
            'is_public': false,
            'landing_visible': true,
          }),
          contains: 'app_settings_landing_is_public',
        );
      } finally {
        await fx.service.from('app_settings').delete().eq('key', probeKey);
      }
    });

    test('the whitelist is exactly the chosen set', () async {
      final rows = await fx.service
          .from('app_settings')
          .select('key, is_public')
          .eq('landing_visible', true);
      final keys = {
        for (final row in rows)
          if (!(row['key'] as String).startsWith('e2e.')) row['key'] as String
      };
      expect(keys, whitelist);
      expect(rows.every((r) => r['is_public'] == true), isTrue);
    });

    test('anyone may read the feed, and it says only the whitelist', () async {
      // No apikey, no Authorization: the Worker of L-34 calls exactly like this.
      final response = await send(() => http.get(url));
      expect(response.statusCode, 200, reason: response.body);
      expect(response.headers['cache-control'], contains('max-age=60'));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final values = (body['values'] as Map).cast<String, dynamic>();
      expect(values.keys.toSet(), whitelist);
      // The e-mail caps are server-only: the CHECK keeps them out, and this is
      // the end-to-end proof.
      expect(values.containsKey('email_cap_free'), isFalse);
      expect(values.containsKey('policy.current_version'), isFalse);
      expect(body['updated_at'], isA<String>());

      // The feed carries the table's own value, byte for byte.
      final price = (await fx.service
              .from('app_settings')
              .select('value')
              .eq('key', 'billing.price_monthly_cents'))
          .single['value'];
      expect(values['billing.price_monthly_cents'], price);
    });

    test('a matching If-None-Match answers 304 with no body', () async {
      final first = await send(() => http.get(url));
      final etag = first.headers['etag'];
      expect(etag, isNotNull, reason: first.body);

      final second =
          await send(() => http.get(url, headers: {'If-None-Match': etag!}));
      expect(second.statusCode, 304);
      expect(second.body, isEmpty);
    });

    test('anything but GET is refused', () async {
      final response = await send(() => http.post(url, body: '{}'));
      expect(response.statusCode, 405, reason: response.body);
    });
  });
}
