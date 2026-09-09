/// The router's S-02 allow-list.
///
/// It used to be more than that: the rule also carried a `pendingLocation`, the
/// deep-link destination the app had to remember while the session gate parked
/// it on the splash. **T-64 deleted that half** (08/09/2026) — the app no
/// longer routes at all until the gate has answered, so the browser's URL is
/// still the URL when the first decision is made about it, and there is nothing
/// to remember. What is left is the question this file was always about: who
/// may see what.
library;

import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

void main() {
  const inviteLink = '/register?invite=11111111-2222-3333-4444-555555555555';

  group('gate phase — the router does not exist yet', () {
    test('nothing is redirected, because nothing is routed', () {
      for (final location in ['/', '/register', '/family', '/login']) {
        expect(
          RouteRules.redirect(phase: AuthPhase.gate, location: location),
          isNull,
          reason: 'the app shows the splash INSTEAD of routing while the gate '
              'decides — a redirect here would move the URL, which is the '
              'whole thing T-64 stopped doing',
        );
      }
    });
  });

  group('anonymous phase', () {
    test('the four public screens are reachable', () {
      for (final location in RouteRules.publicRoutes) {
        expect(RouteRules.redirect(phase: AuthPhase.anon, location: location),
            isNull);
      }
    });

    test('anything guarded goes to login', () {
      for (final location in ['/', '/family', '/notifications', '/reports']) {
        expect(RouteRules.redirect(phase: AuthPhase.anon, location: location),
            RouteRules.login);
      }
    });

    test('an invitation link opens where it points', () {
      // The case that used to need the remembered destination and now needs
      // nothing, because the URL is never taken away from the visitor. The
      // router asks with `matchedLocation`, so the token rides in the query
      // and only the PATH is judged — `route_gate_test` drives the real thing
      // with the token attached.
      expect(
          RouteRules.redirect(
              phase: AuthPhase.anon, location: Uri.parse(inviteLink).path),
          isNull);
    });
  });

  group('authenticated phase', () {
    test('a real screen is left alone — the URL is the reader\'s', () {
      for (final location in [
        '/',
        '/family',
        '/family/profile',
        '/notifications',
        '/reports',
        '/premium/retorno',
      ]) {
        expect(RouteRules.redirect(phase: AuthPhase.authed, location: location),
            isNull,
            reason: 'a cold entry, a paste, an F5 and a push tap all arrive '
                'here, and all of them must stay put');
      }
    });

    test('the anonymous-only screens fall back to the calendar', () {
      for (final location in RouteRules.anonymousOnlyRoutes) {
        expect(RouteRules.redirect(phase: AuthPhase.authed, location: location),
            RouteRules.home,
            reason: '$location is already answered for a signed-in reader');
      }
    });

    test('/update-password is NOT anonymous-only: the recovery flow lands '
        'there with a session', () {
      expect(
          RouteRules.redirect(
              phase: AuthPhase.authed, location: RouteRules.updatePassword),
          isNull);
    });
  });

  group('onboarding phase (F-57)', () {
    test('confines to /onboarding, wherever the visitor came from', () {
      for (final location in ['/', '/family', RouteRules.login, '/reports']) {
        expect(
          RouteRules.redirect(phase: AuthPhase.onboarding, location: location),
          RouteRules.onboarding,
          reason: 'a profile-less session has nothing to see at $location',
        );
      }
      expect(
          RouteRules.redirect(
              phase: AuthPhase.onboarding, location: RouteRules.onboarding),
          isNull);
    });

    test('an ONBOARDED visitor has no business on /onboarding', () {
      expect(
          RouteRules.redirect(
              phase: AuthPhase.authed, location: RouteRules.onboarding),
          RouteRules.home);
      expect(
          RouteRules.redirect(
              phase: AuthPhase.anon, location: RouteRules.onboarding),
          RouteRules.login,
          reason: 'not public: an anonymous visitor cannot onboard');
    });
  });

  group('the allow-list itself', () {
    test('isPublic is the four screens and nothing else', () {
      for (final location in RouteRules.publicRoutes) {
        expect(RouteRules.isPublic(location), isTrue);
      }
      for (final location in ['/', '/family', RouteRules.splash]) {
        expect(RouteRules.isPublic(location), isFalse);
      }
    });

    test('the splash is anonymous-only, never public', () {
      expect(RouteRules.anonymousOnlyRoutes, contains(RouteRules.splash));
      expect(RouteRules.isPublic(RouteRules.splash), isFalse);
    });
  });
}
