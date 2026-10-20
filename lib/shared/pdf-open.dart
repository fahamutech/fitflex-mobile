// ignore_for_file: file_names
// Opens PDF bytes in a new browser tab (Flutter web, S5 "Open PDF"). On
// other platforms it answers false: the app shares the file instead.
export 'pdf-open-native.dart' if (dart.library.js_interop) 'pdf-open-web.dart';
