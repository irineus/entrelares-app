/// F-64 — reading a PDF the reader chooses (or drops) on the check page, to
/// hash it LOCALLY. Nothing is uploaded: the bytes never leave the device.
///
/// The web can pick and drop a file with no plugin (`package:web`); the
/// native build has no file picker in its dependencies, and the page says so
/// and shows the fingerprint to compare by other means. Chosen at COMPILE time,
/// like `file_delivery.dart`.
library;

export 'pdf_pick_io.dart' if (dart.library.js_interop) 'pdf_pick_web.dart';
