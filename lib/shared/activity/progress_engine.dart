/// Activity & Progress Engine — goal progress, period totals, milestones and
/// personal records, all derived from activity history. Pure functions; no
/// Flutter or network dependencies.
library;

import 'activity.dart';
import 'activity_summary.dart';
import 'goal.dart';

/// A half-open time range `[start, end)`.
class PeriodWindow {
  final DateTime start;
  final DateTime end;

  const PeriodWindow(this.start, this.end);

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);
}

/// Weeks run Monday–Sunday.
DateTime weekStart(DateTime t) {
  final d = dayOf(t);
  return DateTime(d.year, d.month, d.day - (d.weekday - DateTime.monday));
}

DateTime monthStart(DateTime t) => DateTime(t.year, t.month);

PeriodWindow dayWindow(DateTime t) {
  final d = dayOf(t);
  return PeriodWindow(d, DateTime(d.year, d.month, d.day + 1));
}

PeriodWindow weekWindow(DateTime t) {
  final s = weekStart(t);
  return PeriodWindow(s, DateTime(s.year, s.month, s.day + 7));
}

PeriodWindow monthWindow(DateTime t) {
  final s = monthStart(t);
  return PeriodWindow(s, DateTime(s.year, s.month + 1));
}

/// The period of [goal] that contains [now]. Recurring goals count the whole
/// current period (a weekly goal set on Wednesday still counts Monday's
/// run); custom goals run from their start date to their end date inclusive.
PeriodWindow goalWindow(Goal goal, DateTime now) => switch (goal.period) {
  GoalPeriod.day => dayWindow(now),
  GoalPeriod.week => weekWindow(now),
  GoalPeriod.month => monthWindow(now),
  GoalPeriod.custom => PeriodWindow(
    dayOf(goal.startDate),
    dayOf(goal.endDate ?? goal.startDate).add(const Duration(days: 1)),
  ),
};

/// A goal's progress in [w]: measured from activity, or for a coaching
/// goal the times the member marked it done (same rule as the server).
num measureGoal(Goal goal, Iterable<Activity> activities, PeriodWindow w) {
  if (goal.type == GoalType.custom) {
    return goal.completions.where((c) => w.contains(c.toLocal())).length;
  }
  num total = 0;
  for (final a in activities) {
    if (!w.contains(a.startedAt.toLocal())) continue;
    total += switch (goal.type) {
      GoalType.steps => a.steps ?? 0,
      GoalType.workouts => a.isWorkout ? 1 : 0,
      GoalType.activeMinutes => a.activeMinutes ?? a.durationMinutes ?? 0,
      GoalType.distanceKm => a.distanceKm ?? 0,
      GoalType.custom => 0,
    };
  }
  return total;
}

class GoalProgress {
  final Goal goal;
  final PeriodWindow window;
  final num current;
  final DateTime now;

  const GoalProgress({
    required this.goal,
    required this.window,
    required this.current,
    required this.now,
  });

  /// Share of the target reached; may exceed 1.
  double get fraction => goal.target <= 0 ? 0 : current / goal.target;

  bool get completed => current >= goal.target;

  /// Custom goals only: the date range is over.
  bool get ended =>
      goal.period == GoalPeriod.custom && !now.isBefore(window.end);

  /// Custom goals only: the date range hasn't begun.
  bool get upcoming =>
      goal.period == GoalPeriod.custom && now.isBefore(window.start);
}

GoalProgress evaluateGoal(
  Goal goal,
  Iterable<Activity> activities,
  DateTime now,
) {
  final w = goalWindow(goal, now);
  final value = measureGoal(goal, activities, w);
  return GoalProgress(
    goal: goal.withProgress(value),
    window: w,
    current: value,
    now: now,
  );
}

/// The member's active daily step goal, which drives the "today's goal"
/// bar on Home and Overview. Null when they have none.
Goal? dailyStepGoal(Iterable<Goal> goals) {
  for (final g in goals) {
    if (g.type == GoalType.steps &&
        g.period == GoalPeriod.day &&
        g.status == GoalStatus.active) {
      return g;
    }
  }
  return null;
}

/// Totals over a window.
class PeriodTotals {
  final PeriodWindow window;
  final int steps;
  final int activeMinutes;
  final int workouts;
  final double distanceKm;

  /// Days in the window that count toward the activity streak.
  final int activeDays;

  const PeriodTotals({
    required this.window,
    this.steps = 0,
    this.activeMinutes = 0,
    this.workouts = 0,
    this.distanceKm = 0,
    this.activeDays = 0,
  });
}

PeriodTotals totalsFor(Iterable<Activity> activities, PeriodWindow w) {
  final byDay = groupByDay(
    activities.where((a) => w.contains(a.startedAt.toLocal())),
  );
  var steps = 0, minutes = 0, workouts = 0, activeDays = 0;
  var km = 0.0;
  for (final s in byDay.values) {
    steps += s.steps;
    minutes += s.activeMinutes;
    workouts += s.workoutCount;
    km += s.distanceKm;
    if (s.countsForStreak) activeDays++;
  }
  return PeriodTotals(
    window: w,
    steps: steps,
    activeMinutes: minutes,
    workouts: workouts,
    distanceKm: km,
    activeDays: activeDays,
  );
}

/// One summary per local day that has any activity.
Map<DateTime, DaySummary> groupByDay(Iterable<Activity> activities) {
  final buckets = <DateTime, List<Activity>>{};
  for (final a in activities) {
    buckets.putIfAbsent(dayOf(a.startedAt.toLocal()), () => []).add(a);
  }
  return {for (final e in buckets.entries) e.key: summarizeDay(e.value, e.key)};
}

/// Totals for the [weeks] weeks ending with the current one, oldest first.
List<PeriodTotals> weeklyTotals(
  Iterable<Activity> activities, {
  required DateTime today,
  int weeks = 8,
}) {
  final list = activities.toList();
  final current = weekStart(today);
  return [
    for (var back = weeks - 1; back >= 0; back--)
      totalsFor(
        list,
        weekWindow(
          DateTime(current.year, current.month, current.day - 7 * back),
        ),
      ),
  ];
}

// ── Milestones ──────────────────────────────────────────────────────────────

enum MilestoneMetric { workouts, steps, distanceKm }

class Milestone {
  final String id;
  final MilestoneMetric metric;
  final num threshold;

  const Milestone(this.id, this.metric, this.threshold);
}

/// Fixed ladder, smallest first within each metric.
const milestoneLadder = [
  Milestone('workouts_1', MilestoneMetric.workouts, 1),
  Milestone('workouts_10', MilestoneMetric.workouts, 10),
  Milestone('workouts_25', MilestoneMetric.workouts, 25),
  Milestone('workouts_50', MilestoneMetric.workouts, 50),
  Milestone('steps_100k', MilestoneMetric.steps, 100000),
  Milestone('steps_250k', MilestoneMetric.steps, 250000),
  Milestone('steps_500k', MilestoneMetric.steps, 500000),
  Milestone('steps_1m', MilestoneMetric.steps, 1000000),
  Milestone('distance_50', MilestoneMetric.distanceKm, 50),
  Milestone('distance_100', MilestoneMetric.distanceKm, 100),
  Milestone('distance_250', MilestoneMetric.distanceKm, 250),
];

/// Milestones reached within [activities]. Only reached ones are returned:
/// the app sees a bounded history window, so "not yet reached" can't be
/// claimed reliably, but anything reached inside the window is certain.
List<Milestone> reachedMilestones(Iterable<Activity> activities) {
  var workouts = 0, steps = 0;
  var km = 0.0;
  for (final a in activities) {
    if (a.isWorkout) workouts++;
    steps += a.steps ?? 0;
    km += a.distanceKm ?? 0;
  }
  return [
    for (final m in milestoneLadder)
      if (switch (m.metric) {
            MilestoneMetric.workouts => workouts,
            MilestoneMetric.steps => steps,
            MilestoneMetric.distanceKm => km,
          } >=
          m.threshold)
        m,
  ];
}

/// The highest milestone reached for each metric — "25 workouts" says it
/// all; "1, 10 and 25 workouts" is noise.
List<Milestone> topMilestones(Iterable<Activity> activities) {
  final best = <MilestoneMetric, Milestone>{};
  for (final m in reachedMilestones(activities)) {
    best[m.metric] = m; // ladder is ascending within a metric
  }
  return [for (final metric in MilestoneMetric.values) ?best[metric]];
}

// ── Personal records ────────────────────────────────────────────────────────

class PersonalRecords {
  /// Longest single run or jog.
  final Activity? longestRun;

  /// Day with the most steps.
  final DaySummary? mostStepsDay;

  /// Longest single workout by duration.
  final Activity? longestWorkout;

  /// Week with the most active minutes.
  final PeriodTotals? bestWeek;

  const PersonalRecords({
    this.longestRun,
    this.mostStepsDay,
    this.longestWorkout,
    this.bestWeek,
  });

  bool get isEmpty =>
      longestRun == null &&
      mostStepsDay == null &&
      longestWorkout == null &&
      bestWeek == null;
}

PersonalRecords personalRecords(
  Iterable<Activity> activities, {
  required DateTime today,
  int weeks = 13,
}) {
  final list = activities.toList();
  Activity? run, workout;
  for (final a in list) {
    final isRun =
        a.type == ActivityType.running || a.type == ActivityType.jogging;
    if (isRun && (a.distanceKm ?? 0) > (run?.distanceKm ?? 0)) run = a;
    if (a.isWorkout &&
        (a.durationMinutes ?? 0) > (workout?.durationMinutes ?? 0)) {
      workout = a;
    }
  }
  DaySummary? stepsDay;
  for (final d in groupByDay(list).values) {
    if (d.steps > (stepsDay?.steps ?? 0)) stepsDay = d;
  }
  PeriodTotals? week;
  for (final w in weeklyTotals(list, today: today, weeks: weeks)) {
    if (w.activeMinutes > (week?.activeMinutes ?? 0)) week = w;
  }
  return PersonalRecords(
    longestRun: run,
    mostStepsDay: stepsDay,
    longestWorkout: workout,
    bestWeek: week,
  );
}
