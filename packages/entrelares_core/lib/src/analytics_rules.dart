/// T-37 client mirror — the NO-PII contract of the product analytics, ported
/// from `entrelares-app` `Entrelares/Services/AnalyticsService.cs`.
///
/// Umami is cookieless by construction (the daily visitor id is derived
/// server-side from IP + User-Agent; nothing is stored on the device), so the
/// only way this client could leak an identity is through what it SENDS. That
/// is exactly what lives here, pure and tested: the path sanitizer and the
/// funnel props. The transport is the app's business; the promise is this
/// file's.
library;

import 'push_nudge_rules.dart';

/// GUID segments — the only dynamic route id (`/family/profile/{id}`) — are
/// masked so no pseudonymous identifier travels as part of a URL.
final _guidSegment = RegExp(
    r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}');

/// Numeric path ids — the app routes by profile id (`/family/profile/42`),
/// where the web routes by GUID. Same reasoning, one step further: an id that
/// identifies a person never reaches the collector.
final _numericSegment = RegExp(r'/\d+(?=/|$)');

/// Reduce any app URL to a privacy-safe path: keep only the path, drop the
/// query string and fragment ENTIRELY (never leak the invite token or the
/// recovery hash) and mask id segments.
///
/// Mirror of `AnalyticsService.SanitizePath`, including the order it does
/// things in — stripping the query FIRST is what guarantees `?invite=…` cannot
/// survive whatever the rest does.
String sanitizeAnalyticsPath(String uriOrPath) {
  if (uriOrPath.trim().isEmpty) return '/';

  final cut = uriOrPath.indexOf(RegExp(r'[?#]'));
  var path = cut >= 0 ? uriOrPath.substring(0, cut) : uriOrPath;

  // An absolute http(s) URL is reduced to its path component. (The C# avoids
  // Uri parsing here on purpose — on Linux a relative path parses as a file://
  // URI and gets mangled; string work has no such trap in either language.)
  final scheme = path.indexOf('://');
  if (scheme >= 0) {
    final afterScheme = path.substring(scheme + 3);
    final slash = afterScheme.indexOf('/');
    path = slash >= 0 ? afterScheme.substring(slash) : '/';
  }

  if (path.isEmpty) return '/';
  if (!path.startsWith('/')) path = '/$path';

  path = path.replaceAll(_guidSegment, ':id');
  path = path.replaceAllMapped(_numericSegment, (_) => '/:id');
  return path.isEmpty ? '/' : path;
}

/// The acquisition channel dimension (F-48). In the web this reads the T-38
/// store-shell flag; here the parity map's decision applies — the store shell
/// is DROPPED and the channel falls out of the build: the Flutter app IS the
/// store channel, and the web target is the web one.
String analyticsChannel({required bool isWeb}) => isWeb ? 'web' : 'store';

/// Props every funnel step carries. Central so no call site can slip a PII key
/// in: channel always, and cycle/outcome/mode only where the step knows them.
///
/// U-54: [platform] and [step] are ENUMS, not strings — the push nudge's two
/// dimensions are a closed set by type, so no call site can put a user agent
/// or a device id where the platform goes.
Map<String, Object> analyticsFunnelProps({
  required String channel,
  String? cycle,
  String? outcome,
  String? mode,
  PushNudgePlatform? platform,
  PushNudgeStep? step,
}) =>
    {
      'channel': channel,
      'cycle': ?cycle,
      'outcome': ?outcome,
      'mode': ?mode,
      'platform': ?platform?.analyticsValue,
      'step': ?step?.analyticsValue,
    };
