import '../activity.dart';
import '../activity_provider.dart';

/// Base for providers that are designed but not built yet. They report
/// themselves unavailable and return no data, so wiring one in by mistake
/// shows an empty history rather than crashing or inventing numbers.
///
/// Building one for real means overriding every method with platform
/// reads, stamping each record `source: device` with [platform] and the
/// platform's record id, and passing results through
/// [genuineDeviceRecords]. A provider must never fill gaps with estimates
/// or sample data: no reading means no record. That work waits until the internal Activity Engine is stable;
/// only files in `lib/shared/activity/providers/` may import a health
/// platform package (enforced by `test/device_data_architecture_test.dart`).
abstract class PlannedActivityProvider implements ActivityProvider {
  const PlannedActivityProvider();

  /// The platform every record from this provider names.
  DevicePlatform get platform;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> requestAccess() async => false;

  @override
  Future<List<Activity>> getActivities({
    required DateTime from,
    required DateTime to,
    String userId = '',
  }) async => const [];

  @override
  Future<List<DailyValue>> getDailySteps({
    required DateTime from,
    required DateTime to,
    String userId = '',
  }) async => const [];

  @override
  Future<double> getDistance({
    required DateTime from,
    required DateTime to,
    String userId = '',
  }) async => 0;

  @override
  Future<int> getActiveMinutes({
    required DateTime from,
    required DateTime to,
    String userId = '',
  }) async => 0;

  @override
  Future<List<Activity>> getWorkouts({
    required DateTime from,
    required DateTime to,
    String userId = '',
  }) async => const [];
}
