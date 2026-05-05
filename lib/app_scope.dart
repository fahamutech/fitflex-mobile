import 'package:flutter/material.dart';
import 'shared/api_client.dart';
import 'shared/auth_state.dart';

/// Simple DI: an InheritedWidget exposing the singleton API client + auth state.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.api,
    required this.auth,
    required super.child,
  });

  final ApiClient api;
  final AuthState auth;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      api != oldWidget.api || auth != oldWidget.auth;
}
