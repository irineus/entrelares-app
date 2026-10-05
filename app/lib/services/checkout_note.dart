/// F-86 — the checkout baseline, kept across the hosted checkout's redirect.
///
/// The web rail leaves the app for the payment page and comes back on
/// `/premium/retorno` — a fresh page load, in a new tab, with nothing in
/// memory. What the family had before leaving (plan, paid period) is written
/// here just before the redirect, so the return page can tell a payment from
/// a family that was already Premium. Two values and a timestamp, no family
/// data, and it is cleared once the return page has read it.
///
/// The web keeps it in `localStorage` (the checkout tab is opened without an
/// opener, so `sessionStorage` would not travel); every other build keeps it
/// in memory — the store channel never uses the hosted checkout. The choice is
/// made at COMPILE time, as in `boot_handoff.dart`.
library;

export 'checkout_note_io.dart'
    if (dart.library.js_interop) 'checkout_note_web.dart';
