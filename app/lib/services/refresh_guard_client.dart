import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:http/http.dart' as http;

/// T-93 — the token-refresh guard, on the transport every Supabase call shares.
///
/// gotrue refreshes whenever the DEVICE's clock says the token expired, before
/// every request and on every 10-second tick; a clock an hour ahead makes that
/// a loop (169 refreshes in four minutes from one Play pre-launch device,
/// 30/08/2026). And gotrue reads a 429 on a refresh as a refusal and signs the
/// reader out. This client stands between gotrue and the network for the
/// refresh grant ONLY ([isRefreshGrant]; the rules are core's
/// `refresh_guard_rules.dart`):
///
/// - the same refresh token asked again inside [refreshFloor] gets the last
///   successful answer back, without the network — the token in it is less
///   than a minute old and the server accepts it for the rest of its hour;
/// - a 429 becomes a retryable failure (a synthetic 503, which gotrue reports
///   as `AuthRetryableFetchException` and answers by KEEPING the session), and
///   opens a pause in which no refresh leaves the device.
///
/// It never signs anyone out and never touches any other request. It sits
/// OUTSIDE [ConnectivityHttpClient]: a replayed or paused answer did not come
/// from the server, so it must not tell the connectivity state that it did.
///
/// Time is read from a monotonic [Stopwatch] (or [elapsed] in tests), never
/// from `DateTime.now()` — the device's wall clock is what is wrong here.
class RefreshGuardHttpClient extends http.BaseClient {
  final http.Client _inner;
  final RefreshGuard _guard = RefreshGuard();
  final Duration Function() _elapsed;

  List<int>? _lastBody;
  Map<String, String> _lastHeaders = const {};

  RefreshGuardHttpClient(this._inner, {Duration Function()? elapsed})
      : _elapsed = elapsed ?? _monotonic();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (!isRefreshGrant(request.url)) return _inner.send(request);

    final token = request is http.Request ? refreshTokenIn(request.body) : null;
    final last = _lastBody;
    switch (_guard.decide(now: _elapsed(), token: token)) {
      case RefreshDecision.coolDown:
        return _paused(request);
      case RefreshDecision.replay when last != null:
        return _answer(request, last, _lastHeaders);
      case RefreshDecision.replay:
      case RefreshDecision.send:
        break;
    }

    final response = await _inner.send(request);
    if (response.statusCode == 429) {
      await response.stream.drain<void>();
      _guard.rateLimited(
          now: _elapsed(), retryAfter: response.headers['retry-after']);
      return _paused(request);
    }
    if (response.statusCode != 200) return response;

    final body = await response.stream.toBytes();
    _guard.succeeded(
        now: _elapsed(),
        issuedToken: refreshTokenIn(utf8.decode(body, allowMalformed: true)));
    _lastBody = body;
    _lastHeaders = response.headers;
    return _answer(request, body, response.headers);
  }

  http.StreamedResponse _answer(
          http.BaseRequest request, List<int> body, Map<String, String> headers) =>
      http.StreamedResponse(Stream.value(body), 200,
          contentLength: body.length, headers: headers, request: request);

  /// A 5xx is what gotrue retries and keeps the session through; the body
  /// says why, for whoever reads the exception in a log.
  http.StreamedResponse _paused(http.BaseRequest request) {
    final body = utf8.encode(jsonEncode({
      'code': 503,
      'error_code': 'refresh_paused',
      'msg': 'Token refresh paused after a rate limit (T-93).',
    }));
    return http.StreamedResponse(Stream.value(body), 503,
        contentLength: body.length,
        headers: const {'content-type': 'application/json; charset=utf-8'},
        request: request);
  }

  @override
  void close() => _inner.close();
}

Duration Function() _monotonic() {
  final watch = Stopwatch()..start();
  return () => watch.elapsed;
}
