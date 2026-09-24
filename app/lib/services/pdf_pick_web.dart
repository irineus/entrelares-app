import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Web: a hidden `<input type=file>` and a `FileReader` — read in the page,
/// never sent anywhere.
const bool canPickPdf = true;

Future<Uint8List?> _read(web.File file) {
  final done = Completer<Uint8List?>();
  final reader = web.FileReader();
  reader.onload = ((web.Event _) {
    final result = reader.result;
    done.complete(result == null
        ? null
        : (result as JSArrayBuffer).toDart.asUint8List());
  }).toJS;
  reader.onerror = ((web.Event _) => done.complete(null)).toJS;
  reader.readAsArrayBuffer(file);
  return done.future;
}

Future<Uint8List?> pickPdfBytes() {
  final done = Completer<Uint8List?>();
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = 'application/pdf,.pdf';
  input.onchange = ((web.Event _) {
    final file = input.files?.item(0);
    if (file == null) {
      done.complete(null);
    } else {
      _read(file).then(done.complete);
    }
  }).toJS;
  input.click();
  return done.future;
}

/// A PDF dropped anywhere on the page. Returns the way to stop listening.
void Function() listenForDroppedPdf(void Function(Uint8List bytes) onBytes) {
  final over = ((web.DragEvent e) => e.preventDefault()).toJS;
  final drop = ((web.DragEvent e) {
    e.preventDefault();
    final file = e.dataTransfer?.files.item(0);
    if (file != null) {
      _read(file).then((bytes) {
        if (bytes != null) onBytes(bytes);
      });
    }
  }).toJS;
  web.document.addEventListener('dragover', over);
  web.document.addEventListener('drop', drop);
  return () {
    web.document.removeEventListener('dragover', over);
    web.document.removeEventListener('drop', drop);
  };
}
