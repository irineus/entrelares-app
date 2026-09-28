/// T-93 — the token-refresh guard: a floor between refreshes, and a 429 that
/// is a pause, never a verdict.
///
/// gotrue decides a session has expired by comparing the access token's `exp`
/// — written by the SERVER's clock — with the DEVICE's clock
/// (`Session.isExpired`), and it refreshes an expired session before EVERY
/// request (`getSession`) and on every 10-second auto-refresh tick. A device
/// whose clock runs an hour or more ahead therefore sees every fresh token as
/// already expired and refreshes in a loop. Measured in production (read-only
/// SQL on `auth.refresh_tokens`, 27/09/2026): 169 refreshes in four minutes on
/// 30/08/2026 and 126 on 01/09/2026, each from ONE session of the Play
/// pre-launch account on a Google test device, median 0.25 s apart (a screen's
/// requests) and never more than 10.2 s (one tick). Real families refresh about
/// once every few hours.
///
/// Two things made that loop worth guarding. Behind the gateway the refresh
/// budget may be shared by every user (Fulcrum 03.2.4); and gotrue reads a 429
/// on a refresh as a REFUSAL — `AuthApiException`, the session removed,
/// `signedOut` — so one looping device could sign strangers out. T-18's rule is
/// that only a refusal of the TOKEN signs out; a rate limit refuses nothing.
///
/// Pure on purpose: the app owns the transport (`RefreshGuardHttpClient`) and a
/// monotonic clock — the device's wall clock is the very thing that is wrong
/// here, so no instant below is read from it.
library;

import 'dart:convert';

/// The shortest interval between two refreshes that reach the network, per
/// process (owner, 27/09/2026). A healthy session refreshes about once an hour;
/// a device whose clock makes every token look expired drops from ~170
/// refreshes per five minutes to five. A refresh asked for inside the floor
/// gets the previous answer back — its token was issued less than a minute
/// ago, and the server accepts it for the rest of its hour.
const refreshFloor = Duration(seconds: 60);

/// How long refreshes stay on the device after the server answered 429 and did
/// not say for how long (`Retry-After`).
const refreshCooldownDefault = Duration(seconds: 60);

/// The longest pause a `Retry-After` may ask for; beyond it the header is read
/// as a mistake, not an instruction to leave a session unrefreshed for hours.
const refreshCooldownMax = Duration(minutes: 10);

/// True when [url] is GoTrue's refresh grant — the one call the guard watches.
/// Sign-in, sign-up and every other grant pass untouched.
bool isRefreshGrant(Uri url) =>
    url.path.endsWith('/auth/v1/token') &&
    url.queryParameters['grant_type'] == 'refresh_token';

/// The `refresh_token` field of a JSON body — the request gotrue sends and the
/// session the server answers carry it under the same name. Null when [body]
/// is not a JSON object or has no such string.
String? refreshTokenIn(String body) {
  try {
    final json = jsonDecode(body);
    if (json is! Map) return null;
    final token = json['refresh_token'];
    return token is String && token.isNotEmpty ? token : null;
  } on FormatException {
    return null;
  }
}

/// The pause a 429 opens: the `Retry-After` seconds when the server sent a
/// sane number, [refreshCooldownDefault] otherwise. The HTTP-date form is not
/// parsed — it would be read against the device clock, which is exactly the
/// clock this guard cannot trust.
Duration refreshCooldownFor(String? retryAfter) {
  final seconds = int.tryParse(retryAfter?.trim() ?? '');
  if (seconds == null || seconds <= 0) return refreshCooldownDefault;
  final asked = Duration(seconds: seconds);
  return asked > refreshCooldownMax ? refreshCooldownMax : asked;
}

/// What to do with one refresh request.
enum RefreshDecision {
  /// Let it reach the server.
  send,

  /// Answer it with the last successful response, without the network: the
  /// same refresh token asked again inside [refreshFloor].
  replay,

  /// Answer it with a retryable failure, without the network: a 429 opened a
  /// pause that has not ended. gotrue keeps the session and tries again later.
  coolDown,
}

/// The guard's memory, one per process. Every instant is an elapsed time on a
/// monotonic clock, never a wall-clock reading.
class RefreshGuard {
  Duration? _lastSuccessAt;
  String? _issuedToken;
  Duration? _coolUntil;

  /// Decides a refresh asked at [now] for [token] (the refresh token the
  /// request carries).
  ///
  /// A replay needs the SAME token the last answer issued: a different one is a
  /// new session — a sign-in, another user in the E2E harness — and handing it
  /// the previous session would sign the wrong person in.
  RefreshDecision decide({required Duration now, required String? token}) {
    final until = _coolUntil;
    if (until != null && now < until) return RefreshDecision.coolDown;
    final last = _lastSuccessAt;
    if (last != null &&
        token != null &&
        token == _issuedToken &&
        now - last < refreshFloor) {
      return RefreshDecision.replay;
    }
    return RefreshDecision.send;
  }

  /// The server answered a refresh at [now] and issued [issuedToken]. An
  /// answer whose token cannot be read is never replayed.
  void succeeded({required Duration now, required String? issuedToken}) {
    _coolUntil = null;
    if (issuedToken == null) {
      _lastSuccessAt = null;
      _issuedToken = null;
      return;
    }
    _lastSuccessAt = now;
    _issuedToken = issuedToken;
  }

  /// The server answered 429 at [now]; [retryAfter] is its header, if any.
  void rateLimited({required Duration now, String? retryAfter}) {
    _coolUntil = now + refreshCooldownFor(retryAfter);
  }
}
