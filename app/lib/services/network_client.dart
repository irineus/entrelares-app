/// T-18 — the transport under [ConnectivityHttpClient], one per platform.
///
/// Native gets a CONNECTION timeout, and the reason is the elevator, not the
/// school door. With no network at all the socket fails in milliseconds; with
/// a signal that comes and goes — a lift between floors, a Wi-Fi that joined
/// but routes nowhere — the connect simply hangs, and `dart:io` leaves that to
/// the operating system, which waits for minutes. Every read would then sit
/// under a skeleton with no failure to report, so the strip could never
/// appear. Only establishing the connection is bounded: a slow RESPONSE on a
/// working connection (a PDF export, a big month) is untouched.
///
/// The web has no such knob and no such hang — the browser gives up on its
/// own and says so as `XMLHttpRequest error`.
///
/// The choice is made at COMPILE time by the conditional export below, so
/// neither implementation's imports ever reach the other platform — the same
/// split `installed_app.dart` uses.
library;

export 'network_client_io.dart'
    if (dart.library.js_interop) 'network_client_web.dart';
