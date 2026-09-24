import 'dart:typed_data';

/// Native: no picker in the build — the page shows the fingerprint instead.
const bool canPickPdf = false;

Future<Uint8List?> pickPdfBytes() async => null;

/// Nothing to listen to off the web.
void Function() listenForDroppedPdf(void Function(Uint8List bytes) onBytes) =>
    () {};
