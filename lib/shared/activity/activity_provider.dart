import 'activity.dart';

/// A source of activity history for the Activity & Progress Engine.
///
/// The rest of the app depends only on this interface, so a real provider
/// (e.g. `AppleHealthProvider`, `HealthConnectProvider`, `WearableProvider`,
/// or one backed by the FitFlex API) can replace `MockActivityProvider`
/// without touching any screen.
abstract class ActivityProvider {
  /// Stable identifier, e.g. `mock`, `apple_health`, `health_connect`.
  String get id;

  /// Whether this provider can run on the current device/platform at all.
  Future<bool> isAvailable();

  /// Asks the member for permission to read their activity data. Returns
  /// `true` when access is granted (or no permission is needed).
  Future<bool> requestAccess();

  /// Activities for [userId] that started within `[from, to)`, newest first.
  Future<List<Activity>> activitiesBetween({
    required String userId,
    required DateTime from,
    required DateTime to,
  });
}
