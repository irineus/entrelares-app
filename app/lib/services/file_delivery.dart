/// F-17 (T-53 stage 4) — handing a generated file to the user, on whichever
/// platform this build runs.
///
/// The two channels do NOT agree on what "deliver a file" means, and pretending
/// they do is what broke the LGPD export on the web: the native half writes to
/// a temporary directory and opens the system share sheet, which needs
/// `dart:io` and `path_provider` — neither of which exists in a browser, so
/// every export ended in the generic failure snack. The web half is what the
/// Blazor app always did: an `<a download>`.
///
/// The choice is made at COMPILE time by the conditional export below, so
/// neither implementation's imports ever reach the other platform.
library;

export 'file_delivery_io.dart'
    if (dart.library.js_interop) 'file_delivery_web.dart';
