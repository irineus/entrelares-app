import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web delivery: a Blob and an `<a download>` — the same thing the Blazor app
/// did, and the same thing the F-33 PDF already does on this channel through
/// the `printing` package (which is why the PDF worked while the export did
/// not). The share sheet is deliberately NOT attempted: `navigator.share` is
/// absent on most desktop browsers and refuses files on several others, so
/// trying it first would only turn a working download into a failure snack.
Future<void> deliverTextFile(
  String fileName,
  String contents, {
  required String mimeType,
}) async {
  final blob = web.Blob(
    <JSUint8Array>[Uint8List.fromList(utf8.encode(contents)).toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  anchor.click();
  // Revoking immediately can cancel the download in some browsers; the delay
  // costs nothing and the URL dies with the tab anyway.
  Future<void>.delayed(const Duration(seconds: 30))
      .then((_) => web.URL.revokeObjectURL(url));
}
