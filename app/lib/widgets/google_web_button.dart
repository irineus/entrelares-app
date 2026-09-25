/// F-71 — the GIS button, on the web only.
///
/// GIS hands an ID token to its OWN button and to nothing else, so on the web
/// the Google door is Google's widget (`renderButton`), accepted by the owner
/// on 24/09/2026 with only what GIS itself lets us choose: the theme that
/// matches ours, the width of the form, and "Continuar com o Google". Same
/// compile-time split as `services/install_hint.dart`: the native half never
/// imports the web plugin.
library;

export 'google_web_button_io.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart';
