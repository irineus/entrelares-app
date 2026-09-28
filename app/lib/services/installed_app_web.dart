import 'dart:js_interop';
// `.has(…)` and `.getProperty(…)`: the object whose shape is being read is the
// BROWSER's. Feature detection has no typed binding by construction — the whole
// question is whether the property is there at all.
import 'dart:js_interop_unsafe';

import 'package:entrelares_core/entrelares_core.dart';

/// The property name this file feature-detects, spelled once.
const _api = 'getInstalledRelatedApps';

/// Web half: ask the browser whether [androidPackage] is installed here.
///
/// Three answers, because F-72 needs the difference T-65 could ignore:
///   * [StoreAppPresence.unknown] — the browser does not implement the API
///     (anything but Chrome), or the promise rejects (an insecure context or a
///     cross-origin frame, where the answer is refused rather than negative);
///   * [StoreAppPresence.installed] — the package is in the list;
///   * [StoreAppPresence.notInstalled] — the API answered and the package is
///     not in the list. Which, as T-65 measured, is ALSO what a broken source
///     looks like — `PlayInstallRules` decides how far to trust it.
Future<StoreAppPresence> storeAppPresence(String androidPackage) async {
  final navigator = globalContext.getProperty<JSObject?>('navigator'.toJS);
  if (navigator == null || !navigator.has(_api)) {
    return StoreAppPresence.unknown;
  }
  try {
    final apps =
        await navigator.callMethod<JSPromise<JSArray<JSObject>>>(_api.toJS).toDart;
    return apps.toDart.any((app) =>
            app.getProperty<JSString?>('id'.toJS)?.toDart == androidPackage)
        ? StoreAppPresence.installed
        : StoreAppPresence.notInstalled;
  } catch (_) {
    return StoreAppPresence.unknown;
  }
}
