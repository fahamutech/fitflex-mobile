// Whether the device says it is online — on Flutter web, the browser's own
// state (navigator.onLine and its online / offline events); elsewhere there
// is no such signal and this stays true. Screens combine it with the
// "last request got no answer" signal they already have: either one means
// offline. Never a reason to queue money: it only greys actions out early.
import 'package:flutter/foundation.dart';

import 'browser_online_stub.dart'
    if (dart.library.js_interop) 'browser_online_web.dart'
    as platform;

class BrowserOnline extends ValueNotifier<bool> {
  BrowserOnline._() : super(platform.isOnline()) {
    platform.listen((online) => value = online);
  }

  static final BrowserOnline instance = BrowserOnline._();

  /// Tests: pretend the browser went offline (false) or online (true).
  @visibleForTesting
  static void debugSet(bool online) => instance.value = online;
}
