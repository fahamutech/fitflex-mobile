import 'package:flutter/services.dart';

/// Root shells must leave the Flutter activity instead of popping the final
/// route, which exposes an empty/black Navigator surface on Android.
void handleRootBack({required bool didPop}) {
  if (!didPop) SystemNavigator.pop();
}
