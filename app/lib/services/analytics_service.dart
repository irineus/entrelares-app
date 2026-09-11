import 'dart:convert';

import 'package:entrelares_core/entrelares_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../env.dart';

/// T-37 — cookieless, LGPD-safe product analytics (Umami Events API). Port of
/// `entrelares-app` `AnalyticsService.cs` + `wwwroot/js/analytics.js`.
///
/// The guarantees are the web's, unchanged:
/// * **No PII ever leaves the client.** An event carries a name, a SANITIZED
///   path (query and fragment stripped, id segments masked — the pure mirror
///   [sanitizeAnalyticsPath] owns that promise) and coarse props chosen at the
///   call site.
/// * **Cookieless**: the daily visitor id is derived server-side from IP +
///   User-Agent; nothing is stored on the device. This is why no consent
///   banner is required.
/// * **Disabled unless configured**: with an empty website id every method is
///   a no-op — which is exactly the dev flavor, so QA traffic never pollutes
///   production statistics.
/// * **Best-effort**: sending never throws and never blocks a screen.
///
/// A hand-written POST rather than a tracker script, for the same reasons the
/// web gives: `Content-Type: text/plain` matches Umami's own tracker and
/// avoids a CORS preflight the collector may reject (which matters again now
/// that the app also builds for the web).
class AnalyticsService {
  final String websiteId;
  final String host;

  /// What Umami reports as the site — the app declares its own so store
  /// traffic is separable from the web channel in the same dashboard. On the
  /// WEB build it is the hostname the browser is actually on, which since the
  /// T-53 cutover is the one the Blazor PWA reported before it: same site,
  /// unbroken series, and `channel` telling the two clients apart.
  final String hostname;

  /// The reader's language and the device screen: non-identifying device
  /// dimensions the web reads from `navigator`/`screen`. Set once at boot.
  String language;
  String? screen;

  final http.Client _client;

  AnalyticsService({
    String? websiteId,
    String? host,
    String? hostname,
    this.language = AppLanguage.ptBrCode,
    this.screen,
    http.Client? client,
  })  : websiteId = (websiteId ?? Env.current.umamiWebsiteId).trim(),
        host = (host ?? Env.current.umamiHost).trim(),
        hostname = hostname ??
            (kIsWeb
                ? Env.current.webHostname
                : Env.current.analyticsHostname),
        _client = client ?? http.Client();

  /// True when a website id is configured; false makes every call a no-op.
  bool get isEnabled => websiteId.isNotEmpty;

  /// The acquisition channel of this build (F-48 dimension).
  String get channel => analyticsChannel(isWeb: kIsWeb);

  /// Where the app currently is, already sanitized — kept here so an event
  /// fired from a screen does not have to know (or guess) its own URL.
  String _currentPath = '/';

  /// A pageview for [location] (any app URL — it is sanitized here).
  Future<void> trackPageView(String location) {
    _currentPath = sanitizeAnalyticsPath(location);
    return _send(null, _currentPath, null);
  }

  /// A custom funnel event on the current screen. [props] must carry only
  /// coarse, non-identifying values (a category, a bucket, an action).
  Future<void> trackEvent(String name, {Map<String, Object>? props}) =>
      _send(name, _currentPath, props);

  Future<void> _send(
      String? name, String location, Map<String, Object>? props) async {
    if (!isEnabled) return;
    try {
      final payload = <String, Object>{
        'website': websiteId,
        'hostname': hostname,
        'language': language,
        'screen': ?screen,
        'url': sanitizeAnalyticsPath(location),
        'name': ?name,
        if (name != null && props != null && props.isNotEmpty) 'data': props,
      };

      await _client.post(
        Uri.parse('$host/api/send'),
        headers: const {'Content-Type': 'text/plain'},
        body: jsonEncode({'type': 'event', 'payload': payload}),
      );
    } catch (_) {
      // Best-effort by contract: analytics can NEVER break the app, and a
      // failure is not worth a line of the user's attention.
    }
  }
}
