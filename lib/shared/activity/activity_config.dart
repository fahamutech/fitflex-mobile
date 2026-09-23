import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../api_client.dart';
import 'activity_provider.dart';
import 'api_activity_provider.dart';
import 'goal_repository.dart';
import 'mock/mock_activity_provider.dart';
import 'sample_activity_log.dart';
import 'workout_repository.dart';

/// Whether the member Activity screens run on generated sample data instead
/// of the FitFlex API. Set `ACTIVITY_SAMPLE_DATA=true|false` in `.env`;
/// without it, debug and profile builds use samples and release builds use
/// real data.
bool activitySampleDataEnabled() {
  String? value;
  try {
    value = dotenv.maybeGet('ACTIVITY_SAMPLE_DATA');
  } catch (_) {
    // dotenv not initialised (tests) — fall through to the build default.
  }
  if (value != null) return value.trim().toLowerCase() == 'true';
  return !kReleaseMode;
}

/// History the progress screens look back over (13 full weeks).
const activityHistoryDays = 91;

/// Everything the Activity screens read and write, from one source. In
/// sample mode the pieces share a [SampleActivityLog], so a finished sample
/// workout appears in the sample activity history.
class ActivityBackend {
  final ActivityProvider activity;
  final GoalRepository goals;
  final WorkoutRepository workouts;

  const ActivityBackend({
    required this.activity,
    required this.goals,
    required this.workouts,
  });

  factory ActivityBackend.sample() {
    final log = SampleActivityLog();
    return ActivityBackend(
      activity: MockActivityProvider(days: activityHistoryDays, log: log),
      goals: LocalGoalRepository(),
      workouts: LocalWorkoutRepository(log: log),
    );
  }

  factory ActivityBackend.api(ApiClient api) => ActivityBackend(
    activity: ApiActivityProvider(api),
    goals: ApiGoalRepository(api),
    workouts: ApiWorkoutRepository(api),
  );

  factory ActivityBackend.create(ApiClient api, {required bool sample}) =>
      sample ? ActivityBackend.sample() : ActivityBackend.api(api);
}
