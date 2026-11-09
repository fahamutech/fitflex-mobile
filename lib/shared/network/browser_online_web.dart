// Flutter web: navigator.onLine plus the window's online / offline events.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

bool isOnline() => web.window.navigator.onLine;

void listen(void Function(bool online) onChange) {
  web.window.addEventListener(
    'online',
    ((web.Event _) => onChange(true)).toJS,
  );
  web.window.addEventListener(
    'offline',
    ((web.Event _) => onChange(false)).toJS,
  );
}
