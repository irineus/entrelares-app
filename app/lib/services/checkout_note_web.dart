import 'package:web/web.dart' as web;

const _key = 'entrelares.checkoutBaseline';

/// Web half: `localStorage`, best effort — a blocked storage (private mode,
/// cleared site data) only means the return page measures from its first
/// read instead.
String? readCheckoutNote() {
  try {
    return web.window.localStorage.getItem(_key);
  } catch (_) {
    return null;
  }
}

void writeCheckoutNote(String value) {
  try {
    web.window.localStorage.setItem(_key, value);
  } catch (_) {/* best effort */}
}

void clearCheckoutNote() {
  try {
    web.window.localStorage.removeItem(_key);
  } catch (_) {/* best effort */}
}
