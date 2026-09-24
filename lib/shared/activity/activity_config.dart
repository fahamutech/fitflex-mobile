import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api_client.dart';
import 'activity_provider.dart';
import 'api_activity_provider.dart';
import 'goal_repository.dart';
import 'manual_activity_log.dart';
import 'mock/mock_activity_provider.dart';
import 'phone_steps.dart';
import 'providers/phone_step_counter.dart';
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

  /// Where hand-logged activity is saved.
  final ManualActivityLog manualLog;

  const ActivityBackend({
    required this.activity,
    required this.goals,
    required this.workouts,
    required this.manualLog,
  });

  factory ActivityBackend.sample() {
    final log = SampleActivityLog();
    return ActivityBackend(
      activity: MockActivityProvider(days: activityHistoryDays, log: log),
      goals: LocalGoalRepository(),
      workouts: LocalWorkoutRepository(log: log),
      manualLog: LocalManualActivityLog(sampleLog: log),
    );
  }

  factory ActivityBackend.api(ApiClient api) => ActivityBackend(
    activity: ApiActivityProvider(api),
    goals: ApiGoalRepository(api),
    workouts: ApiWorkoutRepository(api),
    manualLog: ApiManualActivityLog(api),
  );

  factory ActivityBackend.create(ApiClient api, {required bool sample}) =>
      sample ? ActivityBackend.sample() : ActivityBackend.api(api);
}

// ── Counting steps with this phone ─────────────────────────────────────────

/// Whether this platform can count steps with the phone (Android for now).
bool phoneStepsSupported() => const SensorPhoneStepCounter().isSupported;

PhoneSteps createPhoneSteps() =>
    PhoneSteps(counter: const SensorPhoneStepCounter());

/// Starts the background task runner. Call once from `main()` on Android.
Future<void> initPhoneStepsBackground() async {
  try {
    await Workmanager().initialize(phoneStepsCallbackDispatcher);
  } catch (e) {
    debugPrint('[PhoneSteps] background runner unavailable: $e');
  }
}

/// Runs in a background isolate about every 15 minutes while counting is on.
@pragma('vm:entry-point')
void phoneStepsCallbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {
      // Defaults apply.
    }
    final token = (await SharedPreferences.getInstance()).getString('token');
    // Signed out: nothing to count for (sign-out also turns counting off).
    if (token == null) return true;
    try {
      await PhoneSteps.syncOnce(
        counter: const SensorPhoneStepCounter(),
        store: PrefsStepStore(),
        api: ApiClient()..setToken(token),
        now: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[PhoneSteps] background pass failed: $e');
    }
    return true;
  });
}
