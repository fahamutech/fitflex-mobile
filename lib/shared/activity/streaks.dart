/// Activity & Progress Engine — streaks.
///
/// Every streak is a run of consecutive qualifying periods (days or
/// Monday–Sunday weeks). Rules:
///
/// * **Activity** (days): a workout, or at least [streakMinActiveMinutes]
///   active minutes.
/// * **Workout** (weeks): at least [workoutStreakPerWeek] workouts. Weekly,
///   so rest days never cost anything.
/// * **Goal** (days): every active daily goal met. Unavailable when the
///   member has no daily goals.
/// * **Gym attendance** (weeks): at least one gym check-in.
/// * **Challenge**: unavailable until challenges exist.
///
/// The period in progress never breaks a streak — it only adds to it once
/// it qualifies. Missing a period ends the streak quietly; see
/// [StreakStatus.endedLength].
library;

import 'activity.dart';
import 'activity_summary.dart';
import 'goal.dart';
import 'progress_engine.dart';

const workoutStreakPerWeek = 2;

enum StreakKind { activity, workout, goal, challenge, gymAttendance }

enum StreakUnit { day, week }

class StreakStatus {
  final StreakKind kind;
  final StreakUnit unit;

  /// Consecutive qualifying periods up to now.
  final int current;

  /// Longest run within the history the app can see.
  final int best;

  /// When [current] is 0 because the last full period was missed, the
  /// length of the streak that just ended — so the app can say "Your 8-day
  /// streak has ended" once, rather than just showing a zero.
  final int? endedLength;

  const StreakStatus({
    required this.kind,
    required this.unit,
    required this.current,
    required this.best,
    this.endedLength,
  });

  bool get justEnded => current == 0 && (endedLength ?? 0) > 0;
}

/// Computes the streak of [kind], or null when the rule can't apply (no
/// daily goals for a goal streak; challenges don't exist yet).
StreakStatus? computeStreak(
  StreakKind kind, {
  required DateTime today,
  Iterable<Activity> activities = const [],
  Iterable<DateTime> checkIns = const [],
  Iterable<Goal> goals = const [],
  int historyDays = 91,
}) {
  final acts = activities.toList();
  final byDay = groupByDay(acts);
  final t = dayOf(today);
  final since = DateTime(t.year, t.month, t.day - historyDays + 1);

  switch (kind) {
    case StreakKind.activity:
      return _run(
        kind,
        StreakUnit.day,
        today: t,
        since: since,
        qualifies: (d) => byDay[d]?.countsForStreak ?? false,
      );
    case StreakKind.workout:
      final weekly = <DateTime, int>{};
      for (final e in byDay.entries) {
        final w = weekStart(e.key);
        weekly[w] = (weekly[w] ?? 0) + e.value.workoutCount;
      }
      return _run(
        kind,
        StreakUnit.week,
        today: t,
        since: since,
        qualifies: (w) => (weekly[w] ?? 0) >= workoutStreakPerWeek,
      );
    case StreakKind.goal:
      final daily = goals
          .where((g) => g.period == GoalPeriod.day)
          .where((g) => g.status == GoalStatus.active)
          .toList();
      if (daily.isEmpty) return null;
      return _run(
        kind,
        StreakUnit.day,
        today: t,
        since: since,
        qualifies: (d) {
          final live = daily.where((g) => !dayOf(g.startDate).isAfter(d));
          if (live.isEmpty) return false;
          final w = dayWindow(d);
          return live.every((g) => measureGoal(g.type, acts, w) >= g.target);
        },
      );
    case StreakKind.gymAttendance:
      final weeks = {for (final c in checkIns) weekStart(c.toLocal())};
      return _run(
        kind,
        StreakUnit.week,
        today: t,
        since: since,
        qualifies: weeks.contains,
      );
    case StreakKind.challenge:
      return null;
  }
}

StreakStatus _run(
  StreakKind kind,
  StreakUnit unit, {
  required DateTime today,
  required DateTime since,
  required bool Function(DateTime periodStart) qualifies,
}) {
  final first = unit == StreakUnit.day ? today : weekStart(today);
  final floor = unit == StreakUnit.day ? since : weekStart(since);
  DateTime back(int n) => unit == StreakUnit.day
      ? DateTime(first.year, first.month, first.day - n)
      : DateTime(first.year, first.month, first.day - 7 * n);

  int runFrom(int start) {
    var n = 0;
    while (!back(start + n).isBefore(floor) && qualifies(back(start + n))) {
      n++;
    }
    return n;
  }

  // The period in progress only ever adds to a streak.
  final current = qualifies(first) ? runFrom(0) : runFrom(1);

  int? ended;
  if (current == 0) {
    // Periods 0 (in progress) and 1 (just finished) both missed: report the
    // run that ended right before, once. Older gaps aren't brought up.
    final prior = runFrom(2);
    if (prior > 0) ended = prior;
  }

  var best = 0, run = 0;
  for (var n = 0; !back(n).isBefore(floor); n++) {
    run = qualifies(back(n)) ? run + 1 : 0;
    if (run > best) best = run;
  }

  return StreakStatus(
    kind: kind,
    unit: unit,
    current: current,
    best: best,
    endedLength: ended,
  );
}
