/// T-66 — the handoff between the two things that watch for a broken web page.
///
/// The inline script in `web/index.html` is armed from the first byte of the
/// document, which is the ONLY way to see a failure that happens before Dart
/// runs at all: `main.dart.js` that 404s after a bad deploy, a chunk the
/// browser refuses, a CanvasKit fetch the CSP blocks. Once Dart IS running, its
/// two hooks are strictly better — they see Dart exceptions with Dart stacks —
/// so the boot script must stand down, or the same failure travels twice under
/// two different shapes.
///
/// [markAppBooted] is that stand-down. It runs once, right after the hooks are
/// installed, and on every non-web build it is a no-op: there is no document to
/// tell.
///
/// The choice is made at COMPILE time by the conditional export below, so
/// neither implementation's imports ever reach the other platform — the same
/// split `file_delivery.dart` uses.
library;

export 'boot_handoff_io.dart'
    if (dart.library.js_interop) 'boot_handoff_web.dart';
