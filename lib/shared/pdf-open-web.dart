// ignore_for_file: file_names
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Opens [bytes] as a PDF in a new tab; when the browser blocks the tab, it
/// is downloaded as [filename] instead.
Future<bool> openPdfInNewTab(Uint8List bytes, String filename) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  final opened = web.window.open(url, '_blank');
  if (opened == null) {
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = filename;
    web.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
  }
  Timer(const Duration(minutes: 2), () => web.URL.revokeObjectURL(url));
  return true;
}
