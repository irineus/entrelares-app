import 'dart:js_interop';
// `.has(…)` and `.getProperty(…)`: the object whose shape is being read is the
// BROWSER's. Feature detection has no typed binding by construction — the whole
// question is whether the property is there at all.
import 'dart:js_interop_unsafe';

/// The property name this file feature-detects, spelled once.
const _api = 'getInstalledRelatedApps';

/// Web half: ask the browser whether [androidPackage] is installed here.
///
/// Every failure answers `false`, and each one is a real state rather than an
/// error worth surfacing:
///   * the browser does not implement the API (anything but Chrome on Android);
///   * the promise rejects — an insecure context or a cross-origin frame, where
///     the answer is refused rather than negative;
///   * the app is genuinely not installed.
///
/// The app never learns WHICH, on purpose: the only thing that depends on this
/// is whether to offer a shortcut, and all four answers mean "do not".
Future<bool> isStoreAppInstalled(String androidPackage) async {
  final navigator = globalContext.getProperty<JSObject?>('navigator'.toJS);
  if (navigator == null || !navigator.has(_api)) return false;
  try {
    final apps =
        await navigator.callMethod<JSPromise<JSArray<JSObject>>>(_api.toJS).toDart;
    return apps.toDart.any((app) =>
        app.getProperty<JSString?>('id'.toJS)?.toDart == androidPackage);
  } catch (_) {
    return false;
  }
}
