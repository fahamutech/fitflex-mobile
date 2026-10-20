import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The browser asks to save data: `navigator.connection.saveData` (Chrome,
/// Android browsers) or the `prefers-reduced-data` media query. Browsers
/// without either answer false.
bool browserSavesData() {
  try {
    if (web.window.matchMedia('(prefers-reduced-data: reduce)').matches) {
      return true;
    }
  } catch (_) {}
  try {
    final nav = web.window.navigator as JSObject;
    if (!nav.has('connection')) return false;
    final conn = nav['connection'];
    if (conn == null || conn.isUndefinedOrNull) return false;
    return (conn as JSObject)['saveData']?.dartify() == true;
  } catch (_) {
    return false;
  }
}
