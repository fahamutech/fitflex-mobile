import '../activity.dart';
import '../activity_provider.dart';
import 'planned_activity_provider.dart';

/// A wearable vendor's cloud API (e.g. Garmin, Fitbit). Not built yet.
///
/// Most watches already write to Apple Health or Health Connect, so this is
/// only for devices that don't. [vendor] names the integration; what it can
/// read varies by vendor.
class WearableProvider extends PlannedActivityProvider {
  const WearableProvider({
    required this.vendor,
    this.platform = DevicePlatform.other,
    this.supports = const {ActivityDataType.steps, ActivityDataType.workouts},
  });

  final String vendor;

  @override
  final DevicePlatform platform;

  @override
  final Set<ActivityDataType> supports;

  @override
  String get id => 'wearable_$vendor';

  @override
  ActivityProviderKind get kind => ActivityProviderKind.wearable;
}
