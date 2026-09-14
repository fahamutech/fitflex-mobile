// Native save dialog implementation.
// ignore_for_file: file_names

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uri?> saveTextExport({
  required String filename,
  required String content,
  String mimeType = 'text/plain',
}) => FilePicker.saveFile(
  fileName: filename,
  bytes: Uint8List.fromList(utf8.encode(content)),
  mimeType: mimeType,
);
