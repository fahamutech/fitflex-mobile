import 'activity.dart';
import 'activity_summary.dart';

/// Where a provider's data comes from.
enum ActivityProviderKind {
  /// Generated demo history; never shown as real tracking.
  sample,

  /// Activities stored on the FitFlex backend (logged in the app, by a
  /// trainer or gym, or synced from a device earlier).
  fitflex,

  /// Apple Health (HealthKit) on iOS.
  appleHealth,

  /// Health Connect on Android.
  healthConnect,

  /// A wearable vendor's own API (Garmin, Fitbit, …).
  wearable,
}

/// The kinds of reading a provider can supply.
enum ActivityDataType { steps, distance, activeMinutes, workouts }

/// Steps (or another count) on one local calendar day.
typedef DailyValue = ({DateTime day, int value});

/// A source of activity data for the Activity & Progress Engine.
///
/// Screens and the progress engine never see a health platform: they read
/// `List<Activity>` that came through this interface, chosen once in
/// `ActivityBackend` (`activity_config.dart`). A real provider
/// (`AppleHealthProvider`, `HealthConnectProvider`, `WearableProvider`) can
/// replace `MockActivityProvider` without touching any screen.
///
/// Every read covers `[from, to)` in local time. [userId] stamps the
/// returned activities; providers that read the device ignore it for
/// filtering because the device only holds the signed-in member's data.
abstract interface class ActivityProvider {
  /// Stable identifier, e.g. `mock`, `fitflex_api`, `apple_health`.
  String get id;

  ActivityProviderKind get kind;

  /// What this provider can read. The UI hides a metric no connected
  /// provider supplies rather than showing a misleading zero.
  Set<ActivityDataType> get supports;

  /// Whether this provider can run on the current device/platform at all.
  Future<bool> isAvailable();

  /// Asks the member for permission to read their activity data. Returns
  /// `true` when access is granted (or no permission is needed).
  Future<bool> requestAccess();

  /// All activity sessions, newest first.
  Future<List<Activity>> getActivities({
    required DateTime from,
    required DateTime to,
    String userId = '',
  });

  /// Steps per local day, oldest first, including days with zero.
  Future<List<DailyValue>> getDailySteps({
    required DateTime from,
    required DateTime to,
    String userId = '',
  });

  /// Total distance in kilometres.
  Future<double> getDistance({
    required DateTime from,
    required DateTime to,
    String userId = '',
  });

  /// Total active minutes.
  Future<int> getActiveMinutes({
    required DateTime from,
    required DateTime to,
    String userId = '',
  });

  /// Deliberate sessions only (not background walking), newest first.
  Future<List<Activity>> getWorkouts({
    required DateTime from,
    required DateTime to,
    String userId = '',
  });
}

/// Totals derived from [getActivities], using the same rules as the
/// progress engine. For providers whose source only stores sessions (the
/// FitFlex API, sample data). A health-platform provider should override
/// [getDailySteps] and friends with the platform's own aggregates, which
/// include steps recorded outside any session.
mixin ActivityTotalsFromSessions implements ActivityProvider {
  @override
  Future<List<DailyValue>> getDailySteps({
    required DateTime from,
    required DateTime to,
    String userId = '',
  }) async {
    final acts = await getActivities(from: from, to: to, userId: userId);
    final out = <DailyValue>[];
    for (var d = dayOf(from); d.isBefore(to); d = _nextDay(d)) {
      out.add((day: d, value: summarizeDay(acts, d).steps));
    }
    return out;
  }

  @override
  Future<double> getDistance({
    required DateTime from,
    required DateTime to,
    String userId = '',
  }) async {
    final acts = await getActivities(from: from, to: to, userId: userId);
    return acts.fold<double>(0, (km, a) => km + (a.distanceKm ?? 0));
  }

  @override
  Future<int> getActiveMinutes({
    required DateTime from,
    required DateTime to,
    String userId = '',
  }) async {
    final acts = await getActivities(from: from, to: to, userId: userId);
    // Same rule as [summarizeDay].
    return acts.fold<int>(
      0,
      (m, a) => m + (a.activeMinutes ?? a.durationMinutes ?? 0),
    );
  }

  @override
  Future<List<Activity>> getWorkouts({
    required DateTime from,
    required DateTime to,
    String userId = '',
  }) async {
    final acts = await getActivities(from: from, to: to, userId: userId);
    return acts.where((a) => a.isWorkout).toList();
  }
}

DateTime _nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);
