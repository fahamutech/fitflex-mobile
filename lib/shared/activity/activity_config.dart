import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../api_client.dart';
import 'activity_provider.dart';
import 'api_activity_provider.dart';
import 'goal_repository.dart';
import 'mock/mock_activity_provider.dart';

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

ActivityProvider sampleActivityProvider() =>
    MockActivityProvider(days: activityHistoryDays);

ActivityProvider createActivityProvider(
  ApiClient api, {
  required bool sample,
}) => sample ? sampleActivityProvider() : ApiActivityProvider(api);

GoalRepository createGoalRepository(ApiClient api, {required bool sample}) =>
    sample ? LocalGoalRepository() : ApiGoalRepository(api);
