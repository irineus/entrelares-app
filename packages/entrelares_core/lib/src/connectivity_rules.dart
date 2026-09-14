/// T-18 — the ONE connectivity state the app derives, and the strip's words.
///
/// The state is never read from a bare reachability probe: a probe reports
/// the network interface, and a captive portal is an interface that is up.
/// It is derived from what the app already does — every HTTP exchange with
/// Supabase goes through one client, and each one either comes back from OUR
/// server or fails to. That is the only evidence that answers the question the
/// reader has: "is what I am looking at still the plan?"
///
/// Pure on purpose: the app owns the transport and the notifier, the rule of
/// what counts as "we heard the server" and "we could not reach it" lives here
/// with `dart test` coverage.
library;

import 'localization/date_formats.dart';
import 'localization/k_app.dart';
import 'localization/localization.dart';

/// True when [raw] — an error's `toString()` — is the transport failing, not
/// the server answering.
///
/// The shapes are what the stack actually throws, one per layer:
/// - `package:http` wraps the socket error on native (`ClientException: Failed
///   host lookup` / `Connection refused` / `Network is unreachable`) and the
///   browser's refusal on the web (`ClientException: XMLHttpRequest error.`);
/// - `SocketException` / `HandshakeException` when something reaches us
///   unwrapped;
/// - postgrest's own per-attempt timeout (`TimeoutException`);
/// - gotrue's `AuthRetryableFetchException`, which is how a token refresh says
///   "no network" as opposed to "that refresh token is dead".
///
/// Everything else — a `PostgrestException`, a 42501, a trigger's sentence — is
/// the server ANSWERING, so it is never offline, however it failed. Blaming the
/// reader's network for a rule the server explained is the defect
/// `save_errors.dart` already paid for once.
bool isNetworkFailure(String raw) {
  if (raw.contains('PostgrestException(')) return false;
  return raw.contains('ClientException') ||
      raw.contains('SocketException') ||
      raw.contains('HandshakeException') ||
      raw.contains('TimeoutException') ||
      raw.contains('AuthRetryableFetchException') ||
      raw.contains('Failed host lookup') ||
      raw.contains('XMLHttpRequest error') ||
      raw.contains('Network is unreachable') ||
      raw.contains('Connection refused') ||
      raw.contains('Connection closed');
}

/// True when an HTTP response proves we reached OUR server.
///
/// Every Supabase surface we call answers JSON or nothing (a 204 from a
/// minimal-return write, a HEAD count). An HTML page in its place is the
/// signature of something between us and the server answering instead — a
/// captive portal's login page, or an edge error page when the project itself
/// is unreachable — and neither means the reader's plan can be refreshed.
bool isServerResponse({String? contentType}) =>
    !(contentType ?? '').toLowerCase().contains('text/html');

/// The app's connectivity, as the strip and the calendar read it.
///
/// Two states and not three, by decision (T-18, 14/09/2026): a Realtime socket
/// that is down while reads still succeed is NOT shown — the F-23 poll already
/// covers it, and a strip that appears while everything on screen is current
/// teaches the reader to ignore the strip.
class ConnectivitySnapshot {
  /// True from the first transport failure until the next server response.
  final bool offline;

  /// When what the calendar shows was last read from the server — the moment
  /// the strip has to name. Null until the first successful load.
  final DateTime? dataAsOf;

  const ConnectivitySnapshot({this.offline = false, this.dataAsOf});

  static const ConnectivitySnapshot initial = ConnectivitySnapshot();

  /// Any response from our server: the network is back.
  ConnectivitySnapshot reachedServer() =>
      offline ? ConnectivitySnapshot(dataAsOf: dataAsOf) : this;

  /// A transport failure. [dataAsOf] survives: it is exactly what the strip
  /// needs now.
  ConnectivitySnapshot lostServer() =>
      offline ? this : ConnectivitySnapshot(offline: true, dataAsOf: dataAsOf);

  /// The calendar finished a load at [at].
  ConnectivitySnapshot loadedData(DateTime at) =>
      ConnectivitySnapshot(offline: offline, dataAsOf: at);

  /// Leaving the authenticated phase: nothing on a signed-out screen was read
  /// for anyone, so no age may carry over to the next person.
  ConnectivitySnapshot forgetData() => ConnectivitySnapshot(offline: offline);

  @override
  bool operator ==(Object other) =>
      other is ConnectivitySnapshot &&
      other.offline == offline &&
      other.dataAsOf == dataAsOf;

  @override
  int get hashCode => Object.hash(offline, dataAsOf);

  @override
  String toString() =>
      'ConnectivitySnapshot(offline: $offline, dataAsOf: $dataAsOf)';
}

/// The strip's sentence: how OLD what is on screen is, never just "offline".
///
/// A plan read today names the time alone ("dados de 08:12"); one read on an
/// earlier day names the day too, because "08:12" on a Monday morning about
/// data from Friday is precisely the mistake the strip exists to prevent. No
/// load yet names no time at all — there is nothing on screen to date.
/// [dataAsOf] and [now] are local times.
String offlineStripText(Localization l,
    {required DateTime? dataAsOf, required DateTime now}) {
  if (dataAsOf == null) return l[KApp.offlineStripNoData];
  final sameDay = dataAsOf.year == now.year &&
      dataAsOf.month == now.month &&
      dataAsOf.day == now.day;
  return l.format(KApp.offlineStrip, [
    sameDay ? l.formatTime(dataAsOf) : l.formatDateTimeShort(dataAsOf),
  ]);
}
