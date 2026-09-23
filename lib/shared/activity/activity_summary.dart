import 'activity.dart';

/// Step target for [DaySummary.goalProgress] when none is given; the
/// member's own daily step goal takes precedence wherever one exists.
const defaultDailyStepGoal = 8000;

/// A day counts toward the streak when it has a workout or at least this
/// many active minutes.
const streakMinActiveMinutes = 30;

extension ActivityKind on Activity {
  /// Everything except passive, device-counted walking — that is background
  /// movement, not a session the member chose to do.
  bool get isWorkout =>
      !(type == ActivityType.walking && source == ActivitySource.device);
}

/// Totals for one calendar day (local time).
class DaySummary {
  final DateTime day;
  final int steps;
  final double distanceKm;
  final int activeMinutes;

  /// Null when no activity that day reported calories.
  final int? calories;
  final int activityCount;
  final int workoutCount;

  const DaySummary({
    required this.day,
    this.steps = 0,
    this.distanceKm = 0,
    this.activeMinutes = 0,
    this.calories,
    this.activityCount = 0,
    this.workoutCount = 0,
  });

  bool get countsForStreak =>
      workoutCount > 0 || activeMinutes >= streakMinActiveMinutes;

  /// Share of [stepGoal] reached; may exceed 1.
  double goalProgress([int stepGoal = defaultDailyStepGoal]) =>
      stepGoal <= 0 ? 0 : steps / stepGoal;
}

DateTime dayOf(DateTime t) => DateTime(t.year, t.month, t.day);

DaySummary summarizeDay(Iterable<Activity> activities, DateTime day) {
  final d = dayOf(day);
  var steps = 0, active = 0, count = 0, workouts = 0;
  var distance = 0.0;
  int? calories;
  for (final a in activities) {
    if (dayOf(a.startedAt.toLocal()) != d) continue;
    count++;
    if (a.isWorkout) workouts++;
    steps += a.steps ?? 0;
    distance += a.distanceKm ?? 0;
    active += a.activeMinutes ?? a.durationMinutes ?? 0;
    if (a.calories != null) calories = (calories ?? 0) + a.calories!;
  }
  return DaySummary(
    day: d,
    steps: steps,
    distanceKm: distance,
    activeMinutes: active,
    calories: calories,
    activityCount: count,
    workoutCount: workouts,
  );
}
