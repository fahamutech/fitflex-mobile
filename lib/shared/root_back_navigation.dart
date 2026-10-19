import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Something inside a root tab that wants the system Back first (for example
/// the shop's product list, which goes back to the Shop home). Returns true
/// when it handled Back.
typedef RootBackHandler = bool Function();

final List<RootBackHandler> _handlers = [];

/// Registers [handler]; the most recently added is asked first.
void addRootBackHandler(RootBackHandler handler) => _handlers.add(handler);

void removeRootBackHandler(RootBackHandler handler) =>
    _handlers.remove(handler);

@visibleForTesting
int get rootBackHandlerCount => _handlers.length;

/// Root shells must leave the Flutter activity instead of popping the final
/// route, which exposes an empty/black Navigator surface on Android. A
/// registered [RootBackHandler] that handles Back keeps the app open.
void handleRootBack({required bool didPop}) {
  if (didPop) return;
  for (final handler in _handlers.reversed.toList()) {
    if (handler()) return;
  }
  SystemNavigator.pop();
}
