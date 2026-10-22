// ignore_for_file: file_names
import 'dart:typed_data';

/// Not a browser: nothing opened (the caller shares the file).
Future<bool> openPdfInNewTab(Uint8List bytes, String filename) async => false;
