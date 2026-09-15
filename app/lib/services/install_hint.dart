/// U-51 — "is this Safari on an iPhone or iPad, still living in a tab?", asked
/// of the browser.
///
/// The decision itself is the core rule (`InstallHintRules`); this seam only
/// READS the four facts the rule wants and hands them over, or answers null
/// when there is no browser to ask. Same compile-time split as
/// `installed_app.dart` and `boot_handoff.dart`: the web half touches
/// `navigator` and `matchMedia` through `dart:js_interop`, the native half
/// never imports them.
///
/// Fail-closed at every step: a property the browser lacks, or a call that
/// throws, reads as the fact's "no" value, and the rule turns every "no" into
/// silence. A hint the browser cannot justify is a set of steps that do not
/// match the screen in the reader's hand — worse than no hint.
library;

export 'install_hint_io.dart'
    if (dart.library.js_interop) 'install_hint_web.dart';
