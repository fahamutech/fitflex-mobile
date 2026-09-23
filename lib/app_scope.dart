import 'package:flutter/material.dart';
import 'shared/activity/activity_config.dart';
import 'shared/activity/activity_provider.dart';
import 'shared/activity/goal_repository.dart';
import 'shared/api_client.dart';
import 'shared/auth_state.dart';

/// Simple DI: an InheritedWidget exposing the singleton API client + auth state.
class AppScope extends InheritedWidget {
  const AppScope({
    super.key,
    required this.api,
    required this.auth,
    this.activityProvider,
    this.goalRepository,
    required super.child,
  });

  final ApiClient api;
  final AuthState auth;

  /// Activity and goal sources (see `activity_config.dart`). When omitted —
  /// as in widget tests — sample data is used.
  final ActivityProvider? activityProvider;
  final GoalRepository? goalRepository;

  static final ActivityProvider _sampleActivity = sampleActivityProvider();
  static final GoalRepository _sampleGoals = LocalGoalRepository();

  ActivityProvider get activity => activityProvider ?? _sampleActivity;
  GoalRepository get goals => goalRepository ?? _sampleGoals;

  static AppScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing in widget tree');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) =>
      api != oldWidget.api ||
      auth != oldWidget.auth ||
      activityProvider != oldWidget.activityProvider ||
      goalRepository != oldWidget.goalRepository;
}
