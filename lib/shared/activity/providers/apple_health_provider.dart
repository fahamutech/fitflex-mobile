import '../activity_provider.dart';
import 'planned_activity_provider.dart';

/// Apple Health (HealthKit) on iOS. Not built yet.
///
/// When built: read step count, walking/running distance, exercise minutes
/// and workouts; map each HealthKit workout to an [ActivityType] and stamp
/// `source: device`. Daily steps come from HealthKit's statistics query
/// (which de-duplicates iPhone and Watch), not from summing sessions.
class AppleHealthProvider extends PlannedActivityProvider {
  const AppleHealthProvider();

  @override
  String get id => 'apple_health';

  @override
  ActivityProviderKind get kind => ActivityProviderKind.appleHealth;

  @override
  Set<ActivityDataType> get supports => ActivityDataType.values.toSet();
}
