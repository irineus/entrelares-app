// T-93 — the refresh guard's rules. The loop itself is reproduced through the
// real gotrue in the app suite (refresh_guard_t93_test.dart); here are the
// decisions, one instant at a time.
import 'package:entrelares_core/entrelares_core.dart';
import 'package:test/test.dart';

Duration _s(int seconds) => Duration(seconds: seconds);

void main() {
  group('isRefreshGrant', () {
    test('matches only the refresh grant, on the gateway or the project', () {
      expect(
          isRefreshGrant(Uri.parse(
              'https://api.entrelares.app/auth/v1/token?grant_type=refresh_token')),
          isTrue);
      expect(
          isRefreshGrant(Uri.parse(
              'https://x.supabase.co/auth/v1/token?grant_type=refresh_token')),
          isTrue);
    });

    test('sign-in grants and other auth paths pass untouched', () {
      for (final url in [
        'https://api.entrelares.app/auth/v1/token?grant_type=password',
        'https://api.entrelares.app/auth/v1/token?grant_type=id_token',
        'https://api.entrelares.app/auth/v1/token',
        'https://api.entrelares.app/auth/v1/user',
        'https://api.entrelares.app/rest/v1/token?grant_type=refresh_token',
      ]) {
        expect(isRefreshGrant(Uri.parse(url)), isFalse, reason: url);
      }
    });
  });

  group('refreshTokenIn', () {
    test('reads the field from a request or a session body', () {
      expect(refreshTokenIn('{"refresh_token":"rt-1"}'), 'rt-1');
      expect(
          refreshTokenIn(
              '{"access_token":"a","refresh_token":"rt-2","expires_in":3600}'),
          'rt-2');
    });

    test('anything else is null, never a throw', () {
      expect(refreshTokenIn(''), isNull);
      expect(refreshTokenIn('not json'), isNull);
      expect(refreshTokenIn('[1,2]'), isNull);
      expect(refreshTokenIn('{"refresh_token":""}'), isNull);
      expect(refreshTokenIn('{"refresh_token":42}'), isNull);
    });
  });

  group('refreshCooldownFor', () {
    test('a sane Retry-After in seconds is obeyed', () {
      expect(refreshCooldownFor('30'), _s(30));
      expect(refreshCooldownFor(' 120 '), _s(120));
    });

    test('no header, a date or nonsense falls back to the default', () {
      expect(refreshCooldownFor(null), refreshCooldownDefault);
      expect(refreshCooldownFor(''), refreshCooldownDefault);
      expect(refreshCooldownFor('0'), refreshCooldownDefault);
      expect(refreshCooldownFor('-5'), refreshCooldownDefault);
      expect(refreshCooldownFor('Wed, 21 Oct 2026 07:28:00 GMT'),
          refreshCooldownDefault);
    });

    test('an absurd pause is capped', () {
      expect(refreshCooldownFor('86400'), refreshCooldownMax);
    });
  });

  group('RefreshGuard', () {
    test('the first refresh is always sent', () {
      expect(RefreshGuard().decide(now: Duration.zero, token: 'rt-1'),
          RefreshDecision.send);
    });

    test('the SAME token inside the floor is replayed; at the floor it is sent',
        () {
      final guard = RefreshGuard()
        ..succeeded(now: _s(100), issuedToken: 'rt-2');

      expect(guard.decide(now: _s(100), token: 'rt-2'), RefreshDecision.replay);
      expect(guard.decide(now: _s(159), token: 'rt-2'), RefreshDecision.replay);
      expect(guard.decide(now: _s(160), token: 'rt-2'), RefreshDecision.send);
    });

    test('the floor is 60 s (owner, 27/09/2026)', () {
      expect(refreshFloor, _s(60));
    });

    test('a different token is a new session and is never replayed', () {
      final guard = RefreshGuard()
        ..succeeded(now: Duration.zero, issuedToken: 'rt-2');

      expect(guard.decide(now: _s(1), token: 'rt-other'), RefreshDecision.send);
      expect(guard.decide(now: _s(1), token: null), RefreshDecision.send);
    });

    test('an answer whose token cannot be read is never replayed', () {
      final guard = RefreshGuard()
        ..succeeded(now: Duration.zero, issuedToken: 'rt-2')
        ..succeeded(now: _s(1), issuedToken: null);

      expect(guard.decide(now: _s(2), token: 'rt-2'), RefreshDecision.send);
    });

    test('a 429 opens a pause the replay cannot jump', () {
      final guard = RefreshGuard()
        ..succeeded(now: Duration.zero, issuedToken: 'rt-2')
        ..rateLimited(now: _s(10));

      expect(guard.decide(now: _s(10), token: 'rt-2'), RefreshDecision.coolDown);
      expect(guard.decide(now: _s(69), token: 'rt-other'),
          RefreshDecision.coolDown);
      expect(guard.decide(now: _s(70), token: 'rt-2'), RefreshDecision.send);
    });

    test('the pause follows Retry-After, and a success ends it', () {
      final guard = RefreshGuard()..rateLimited(now: Duration.zero, retryAfter: '5');

      expect(guard.decide(now: _s(4), token: 'rt-1'), RefreshDecision.coolDown);
      expect(guard.decide(now: _s(5), token: 'rt-1'), RefreshDecision.send);

      guard
        ..rateLimited(now: _s(10))
        ..succeeded(now: _s(11), issuedToken: 'rt-3');
      expect(guard.decide(now: _s(12), token: 'rt-3'), RefreshDecision.replay);
    });
  });
}
