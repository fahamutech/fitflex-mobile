import '../activity_provider.dart';
import 'planned_activity_provider.dart';

/// Health Connect on Android. Not built yet.
///
/// When built: read Steps, Distance, ExerciseSession and active-minute
/// records; map exercise types to [ActivityType] and stamp
/// `source: device`. Daily steps come from Health Connect's aggregate API,
/// which de-duplicates across apps, not from summing sessions.
class HealthConnectProvider extends PlannedActivityProvider {
  const HealthConnectProvider();

  @override
  String get id => 'health_connect';

  @override
  ActivityProviderKind get kind => ActivityProviderKind.healthConnect;

  @override
  Set<ActivityDataType> get supports => ActivityDataType.values.toSet();
}
