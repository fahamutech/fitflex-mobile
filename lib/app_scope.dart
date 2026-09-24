import 'package:flutter/material.dart';
import 'shared/activity/activity_config.dart';
import 'shared/activity/activity_provider.dart';
import 'shared/activity/goal_repository.dart';
import 'shared/activity/manual_activity_log.dart';
import 'shared/activity/workout_repository.dart';
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
    this.workoutRepository,
    this.manualActivityLog,
    required super.child,
  });

  final ApiClient api;
  final AuthState auth;

  /// Activity and goal sources (see `activity_config.dart`). When omitted —
  /// as in widget tests — sample data is used.
  final ActivityProvider? activityProvider;
  final GoalRepository? goalRepository;
  final WorkoutRepository? workoutRepository;
  final ManualActivityLog? manualActivityLog;

  static final ActivityBackend _sample = ActivityBackend.sample();

  ActivityProvider get activity => activityProvider ?? _sample.activity;
  GoalRepository get goals => goalRepository ?? _sample.goals;
  WorkoutRepository get workouts => workoutRepository ?? _sample.workouts;
  ManualActivityLog get manualLog => manualActivityLog ?? _sample.manualLog;

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
      goalRepository != oldWidget.goalRepository ||
      workoutRepository != oldWidget.workoutRepository ||
      manualActivityLog != oldWidget.manualActivityLog;
}
