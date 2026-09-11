// T-37 — the transport half of the analytics port. The no-PII rule itself is
// proven in `analytics_rules_test.dart` (core); what this suite pins is what
// the app can still get wrong: sending anything at all when the flavor has no
// website id, sending an UNsanitized URL, or letting a failed beacon reach the
// user.
import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:entrelares_app/env.dart';
import 'package:entrelares_app/services/analytics_service.dart';

void main() {
  late List<http.Request> sent;

  http.Client recording({int status = 200}) {
    sent = [];
    return MockClient((request) async {
      sent.add(request);
      return http.Response('', status);
    });
  }

  AnalyticsService service({String websiteId = 'site-1'}) => AnalyticsService(
        websiteId: websiteId,
        host: 'https://cloud.umami.is',
        hostname: 'app.entrelares.app',
        language: AppLanguage.ptBrCode,
        screen: '1080x2400',
        client: recording(),
      );

  Map<String, dynamic> payloadOf(http.Request request) =>
      (jsonDecode(request.body) as Map<String, dynamic>)['payload']
          as Map<String, dynamic>;

  group('disabled', () {
    test('an empty website id makes every call a no-op', () async {
      final analytics = service(websiteId: '');

      await analytics.trackPageView('/family');
      await analytics.trackEvent('signup_started');

      expect(analytics.isEnabled, isFalse);
      expect(sent, isEmpty);
    });

    test('the DEV flavor ships with analytics off', () {
      // QA traffic must never pollute production statistics — the same reason
      // the web app leaves the variable unset outside `master`.
      expect(Env.dev.umamiWebsiteId, isEmpty);
      expect(Env.prod.umamiWebsiteId, isNotEmpty);
    });
  });

  group('pageview', () {
    test('posts the Umami event shape to /api/send', () async {
      final analytics = service();
      await analytics.trackPageView('/notifications');

      final request = sent.single;
      expect(request.url.toString(), 'https://cloud.umami.is/api/send');
      // text/plain on purpose: it matches Umami's own tracker and avoids a
      // CORS preflight the collector may reject.
      expect(request.headers['Content-Type'], contains('text/plain'));

      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['type'], 'event');
      final payload = payloadOf(request);
      expect(payload['website'], 'site-1');
      expect(payload['hostname'], 'app.entrelares.app');
      expect(payload['language'], 'pt-BR');
      expect(payload['screen'], '1080x2400');
      expect(payload['url'], '/notifications');
      // A pageview has no name and no data.
      expect(payload.containsKey('name'), isFalse);
      expect(payload.containsKey('data'), isFalse);
    });

    test('the URL is sanitized before it leaves the device', () async {
      final analytics = service();
      await analytics
          .trackPageView('/register?invite=8f14e45f-ceea-467a-9a3e-1e1d1f6f9b1f');

      expect(payloadOf(sent.single)['url'], '/register');
      expect(sent.single.body, isNot(contains('invite')));
    });
  });

  group('events', () {
    test('carry a name, the props and the CURRENT screen', () async {
      final analytics = service();
      await analytics.trackPageView('/family/profile/42');
      await analytics.trackEvent('invite_sent', props: {'email': 'sent'});

      final payload = payloadOf(sent.last);
      expect(payload['name'], 'invite_sent');
      expect(payload['data'], {'email': 'sent'});
      // The profile id never travels, not even as the event's context.
      expect(payload['url'], '/family/profile/:id');
    });

    test('an event with no props sends no data key', () async {
      final analytics = service();
      await analytics.trackEvent('family_created');

      expect(payloadOf(sent.single).containsKey('data'), isFalse);
    });
  });

  group('best-effort', () {
    test('a failing collector never throws', () async {
      final analytics = AnalyticsService(
        websiteId: 'site-1',
        client: MockClient((_) async => throw const SocketishException()),
      );

      await expectLater(analytics.trackEvent('swap_requested'), completes);
    });

    test('a rejected beacon is equally silent', () async {
      final analytics = AnalyticsService(
        websiteId: 'site-1',
        client: recording(status: 500),
      );

      await expectLater(analytics.trackPageView('/'), completes);
    });
  });
}

/// A stand-in for whatever the platform throws when the network is gone.
class SocketishException implements Exception {
  const SocketishException();
}
