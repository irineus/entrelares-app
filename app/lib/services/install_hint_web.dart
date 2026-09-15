import 'dart:js_interop';
// `.has(…)`, `.getProperty(…)` and `.callMethod(…)`: the object whose shape is
// being read is the BROWSER's, and two of the four facts are feature
// detection by construction — `navigator.standalone` exists only in Safari,
// and the question is whether it is there at all.
import 'dart:js_interop_unsafe';

import 'package:entrelares_core/entrelares_core.dart';

/// The media query that says "already on the Home Screen" in every browser.
/// Safari's own `navigator.standalone` says the same in Safari's words; both
/// are read, because the app's `manifest.json` is `display: standalone` and
/// either spelling may be the one this Safari version honours.
const _standaloneQuery = '(display-mode: standalone)';

/// Web half: read what the browser says about itself, fail-closed.
///
/// Each fact is read on its own, so a browser that lacks ONE property still
/// answers the others truthfully — an old Safari without `matchMedia` is
/// still an iPhone. Anything that throws reads as that fact's "no".
BrowserInstallFacts? readBrowserInstallFacts() {
  final navigator = globalContext.getProperty<JSObject?>('navigator'.toJS);
  if (navigator == null) return null;
  return BrowserInstallFacts(
    userAgent: _string(navigator, 'userAgent') ?? '',
    maxTouchPoints: _int(navigator, 'maxTouchPoints') ?? 0,
    navigatorStandalone: _bool(navigator, 'standalone') ?? false,
    displayModeStandalone: _matchesStandalone(),
  );
}

String? _string(JSObject object, String property) {
  try {
    return object.getProperty<JSString?>(property.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}

int? _int(JSObject object, String property) {
  try {
    return object.getProperty<JSNumber?>(property.toJS)?.toDartInt;
  } catch (_) {
    return null;
  }
}

bool? _bool(JSObject object, String property) {
  try {
    if (!object.has(property)) return null;
    return object.getProperty<JSBoolean?>(property.toJS)?.toDart;
  } catch (_) {
    return null;
  }
}

bool _matchesStandalone() {
  try {
    if (!globalContext.has('matchMedia')) return false;
    final list = globalContext.callMethod<JSObject?>(
        'matchMedia'.toJS, _standaloneQuery.toJS);
    return list?.getProperty<JSBoolean?>('matches'.toJS)?.toDart ?? false;
  } catch (_) {
    return false;
  }
}
