import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  const package = 'com.entrelares.app';

  Uri handoff(String location) =>
      ChannelHandoffRules.handoffUri(androidPackage: package, location: location);

  group('the address the handoff uses', () {
    test('it is the app\'s own scheme, never an https URL', () {
      // The whole point of the item: no https address changes owner, so a
      // plain visit to web.entrelares.app still belongs to the web channel.
      final uri = handoff('/');
      expect(uri.scheme, package);
      expect(uri.host, ChannelHandoffRules.host);
      expect(uri.toString(), startsWith('com.entrelares.app://open/'));
    });

    test('the scheme is the FLAVOR\'s applicationId', () {
      // A device carrying both flavors must never see a chooser, and the dev
      // web build must never wake the production app.
      final dev = ChannelHandoffRules.handoffUri(
          androidPackage: 'com.entrelares.flutter', location: '/');
      expect(dev.scheme, 'com.entrelares.flutter');
    });
  });

  group('the location travels in the path', () {
    test('path, query and fragment all survive', () {
      // Android's embedding builds the initial route from getPath() + query +
      // fragment, so this shape arrives at go_router as the location itself.
      final uri = handoff('/notifications?tab=incoming&n=1');
      expect(uri.path, '/notifications');
      expect(uri.query, 'tab=incoming&n=1');
      expect(uri.toString(),
          'com.entrelares.app://open/notifications?tab=incoming&n=1');
    });

    test('a nested location keeps every segment', () {
      expect(handoff('/family/profile').path, '/family/profile');
    });

    test('the home location still has a non-empty path', () {
      // An EMPTY path makes the embedding return null, which is the app's
      // initialLocation — the same destination, but only by luck. Keep the
      // path honest so the URI says where it goes.
      expect(handoff('/').path, '/');
    });
  });

  group('what never crosses channels', () {
    test('a recovery location is refused, fragment and all', () {
      // /update-password carries the recovery token in its fragment. Handing
      // it to a second channel would be a credential travelling in a URL.
      final uri = handoff('/update-password#access_token=abc&type=recovery');
      expect(uri.path, '/');
      expect(uri.fragment, isEmpty);
      expect(uri.toString(), isNot(contains('access_token')));
    });

    test('an invitation location is refused, token and all', () {
      final uri = handoff('/register?invite=tok_123');
      expect(uri.path, '/');
      expect(uri.toString(), isNot(contains('tok_123')));
    });

    test('every anonymous-only and public route falls back to home', () {
      for (final route in {
        ...RouteRules.anonymousOnlyRoutes,
        ...RouteRules.publicRoutes,
      }) {
        expect(ChannelHandoffRules.targetFor(route), RouteRules.home,
            reason: '$route is not a place to hand a reader over to');
      }
    });

    test('a location that is not an in-app path falls back to home', () {
      expect(ChannelHandoffRules.targetFor('https://evil.example/steal'),
          RouteRules.home);
      expect(ChannelHandoffRules.targetFor('notifications'), RouteRules.home);
      expect(ChannelHandoffRules.targetFor(''), RouteRules.home);
    });
  });

  group('an authenticated location is handed over untouched', () {
    test('the four shell branches all travel', () {
      for (final location in ['/', '/family', '/notifications', '/reports']) {
        expect(ChannelHandoffRules.targetFor(location), location);
      }
    });
  });
}
