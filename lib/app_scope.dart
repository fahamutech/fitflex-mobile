import 'package:flutter/material.dart';
import 'shared/activity/activity_provider.dart';
import 'shared/activity/mock/mock_activity_provider.dart';
import 'shared/api_client.dart';
import 'shared/auth_state.dart';

/// Simple DI: an InheritedWidget exposing the singleton API client + auth state.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.api,
    required this.auth,
    this.activityProvider,
    required super.child,
  });

  final ApiClient api;
  final AuthState auth;

  /// Activity data source. Only the mock exists today; pass a real provider
  /// here once device or API integration lands.
  final ActivityProvider? activityProvider;

  static final ActivityProvider _mockActivity = MockActivityProvider();

  ActivityProvider get activity => activityProvider ?? _mockActivity;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      api != oldWidget.api ||
      auth != oldWidget.auth ||
      activityProvider != oldWidget.activityProvider;
}
