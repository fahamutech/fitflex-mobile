/// Workout engine — the "Workout complete" summary and per-exercise
/// personal records. Pure functions.
library;

import 'workout.dart';

enum WorkoutRecordKind {
  /// Heaviest completed set, for exercises that track weight.
  weight,

  /// Most reps in one completed set, for bodyweight rep exercises.
  reps,

  /// Longest completed set, for timed exercises.
  duration,
}

class WorkoutRecord {
  final String exerciseName;
  final WorkoutRecordKind kind;
  final num value;
  final num previous;

  const WorkoutRecord({
    required this.exerciseName,
    required this.kind,
    required this.value,
    required this.previous,
  });
}

class WorkoutSummary {
  final int durationMinutes;
  final int exercisesCompleted;
  final int exercisesTotal;
  final int setsCompleted;
  final int setsTotal;
  final List<WorkoutRecord> records;

  const WorkoutSummary({
    required this.durationMinutes,
    required this.exercisesCompleted,
    required this.exercisesTotal,
    required this.setsCompleted,
    required this.setsTotal,
    this.records = const [],
  });
}

WorkoutRecordKind _kindFor(WorkoutExercise e) => e.tracksWeight
    ? WorkoutRecordKind.weight
    : e.isTimed
    ? WorkoutRecordKind.duration
    : WorkoutRecordKind.reps;

num? _best(WorkoutExercise e, WorkoutRecordKind kind) {
  num? best;
  for (final s in e.workoutSets.where((s) => s.completed)) {
    final num? v = switch (kind) {
      WorkoutRecordKind.weight => s.weight,
      WorkoutRecordKind.reps => s.reps,
      WorkoutRecordKind.duration => s.duration,
    };
    if (v != null && v > 0 && (best == null || v > best)) best = v;
  }
  return best;
}

String _key(String name) => name.trim().toLowerCase();

/// Records in [workout] that beat every earlier completed workout in
/// [history] for the same exercise. An exercise done for the first time sets
/// no record — there is nothing to beat yet.
List<WorkoutRecord> workoutRecords(Workout workout, Iterable<Workout> history) {
  final previousBest = <String, num>{};
  for (final w in history) {
    if (w.id == workout.id || w.status != WorkoutStatus.completed) continue;
    for (final e in w.exercises) {
      final v = _best(e, _kindFor(e));
      if (v == null) continue;
      final k = '${_key(e.exerciseName)}|${_kindFor(e).name}';
      if (v > (previousBest[k] ?? 0)) previousBest[k] = v;
    }
  }
  final out = <WorkoutRecord>[];
  for (final e in workout.exercises) {
    final kind = _kindFor(e);
    final v = _best(e, kind);
    final prev = previousBest['${_key(e.exerciseName)}|${kind.name}'];
    if (v != null && prev != null && v > prev) {
      out.add(
        WorkoutRecord(
          exerciseName: e.exerciseName,
          kind: kind,
          value: v,
          previous: prev,
        ),
      );
    }
  }
  return out;
}

WorkoutSummary summarizeWorkout(
  Workout workout, {
  required int durationMinutes,
  Iterable<Workout> history = const [],
}) => WorkoutSummary(
  durationMinutes: durationMinutes,
  exercisesCompleted: workout.exercisesCompleted,
  exercisesTotal: workout.exercises.length,
  setsCompleted: workout.setsCompleted,
  setsTotal: workout.setsTotal,
  records: workoutRecords(workout, history),
);
