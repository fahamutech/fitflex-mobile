/// Workout engine — structured workouts made of exercises and sets.
///
/// The plan (names, targets, instructions) is fixed once a workout exists.
/// What the member logs during a session — reps, weight, duration,
/// completed, notes — is mutable, so the session screen can edit it in
/// place and save it as a whole.
library;

import 'activity.dart';

enum WorkoutStatus {
  planned('planned'),
  inProgress('in_progress'),
  completed('completed'),
  skipped('skipped');

  const WorkoutStatus(this.wire);

  final String wire;

  static WorkoutStatus fromWire(String? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => WorkoutStatus.planned,
  );

  bool get isOpen =>
      this == WorkoutStatus.planned || this == WorkoutStatus.inProgress;
}

class WorkoutSet {
  final String id;
  final String exerciseId;
  final int setNumber;

  /// Targets from the plan, kept to show "3 × 10" and pre-fill inputs.
  final int? targetReps;
  final int? targetDuration;

  int? reps;

  /// Kilograms. Only recorded when the exercise tracks weight.
  double? weight;

  /// Seconds.
  int? duration;
  bool completed;

  WorkoutSet({
    required this.id,
    required this.exerciseId,
    required this.setNumber,
    this.targetReps,
    this.targetDuration,
    this.reps,
    this.weight,
    this.duration,
    this.completed = false,
  });

  factory WorkoutSet.fromJson(
    Map<String, dynamic> json, {
    int? targetReps,
    int? targetDuration,
  }) => WorkoutSet(
    id: json['id'] as String? ?? '',
    exerciseId: json['exerciseId'] as String? ?? '',
    setNumber: (json['setNumber'] as num?)?.toInt() ?? 1,
    targetReps: targetReps,
    targetDuration: targetDuration,
    reps: (json['reps'] as num?)?.toInt(),
    weight: (json['weight'] as num?)?.toDouble(),
    duration: (json['duration'] as num?)?.toInt(),
    completed: json['completed'] == true,
  );

  /// The member-editable fields, as the backend's progress patch expects.
  Map<String, dynamic> toLogJson({required bool tracksWeight}) => {
    'id': id,
    'reps': reps,
    if (tracksWeight) 'weight': weight,
    'duration': duration,
    'completed': completed,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'exerciseId': exerciseId,
    'setNumber': setNumber,
    'reps': reps,
    'weight': weight,
    'duration': duration,
    'completed': completed,
  };
}

class WorkoutExercise {
  final String id;
  final String workoutId;
  final String exerciseName;
  final String? muscleGroup;

  /// Planned number of sets.
  final int sets;

  /// Target reps per set, for rep-based exercises.
  final int? reps;

  /// Target seconds per set, for timed exercises.
  final int? duration;
  final String? instructions;
  final bool tracksWeight;
  final List<WorkoutSet> workoutSets;
  String? notes;

  WorkoutExercise({
    required this.id,
    required this.workoutId,
    required this.exerciseName,
    this.muscleGroup,
    required this.sets,
    this.reps,
    this.duration,
    this.instructions,
    this.tracksWeight = false,
    required this.workoutSets,
    this.notes,
  });

  bool get isTimed => reps == null && duration != null;

  bool get isComplete =>
      workoutSets.isNotEmpty && workoutSets.every((s) => s.completed);

  factory WorkoutExercise.fromJson(Map<String, dynamic> json) {
    final reps = (json['reps'] as num?)?.toInt();
    final duration = (json['duration'] as num?)?.toInt();
    final sets = (json['workoutSets'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (s) => WorkoutSet.fromJson(
            Map<String, dynamic>.from(s),
            targetReps: reps,
            targetDuration: duration,
          ),
        )
        .toList();
    return WorkoutExercise(
      id: json['id'] as String? ?? '',
      workoutId: json['workoutId'] as String? ?? '',
      exerciseName: json['exerciseName'] as String? ?? '',
      muscleGroup: json['muscleGroup'] as String?,
      sets: (json['sets'] as num?)?.toInt() ?? sets.length,
      reps: reps,
      duration: duration,
      instructions: json['instructions'] as String?,
      tracksWeight: json['tracksWeight'] == true,
      workoutSets: sets,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toLogJson() => {
    'id': id,
    'notes': notes,
    'workoutSets': [
      for (final s in workoutSets) s.toLogJson(tracksWeight: tracksWeight),
    ],
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'workoutId': workoutId,
    'exerciseName': exerciseName,
    'muscleGroup': muscleGroup,
    'sets': sets,
    'reps': reps,
    'duration': duration,
    'instructions': instructions,
    'tracksWeight': tracksWeight,
    'notes': notes,
    'workoutSets': [for (final s in workoutSets) s.toJson()],
  };
}

class Workout {
  final String id;
  final String userId;
  final String? trainerId;
  final String? gymId;
  final String? templateId;

  /// `template`, `member` or `trainer`.
  final String? source;
  final String name;
  final String? description;

  /// What the completed workout is recorded as.
  final ActivityType activityType;

  /// Local calendar date.
  final DateTime scheduledDate;

  /// Minutes.
  final int? estimatedDuration;
  final WorkoutStatus status;
  final List<WorkoutExercise> exercises;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final String? activityId;
  String? notes;

  Workout({
    required this.id,
    required this.userId,
    this.trainerId,
    this.gymId,
    this.templateId,
    this.source,
    required this.name,
    this.description,
    required this.activityType,
    required this.scheduledDate,
    this.estimatedDuration,
    this.status = WorkoutStatus.planned,
    required this.exercises,
    this.startedAt,
    this.completedAt,
    this.activityId,
    this.notes,
  });

  /// Assigned by a connected trainer.
  bool get fromTrainer => trainerId != null;

  int get setsTotal => exercises.fold(0, (n, e) => n + e.workoutSets.length);
  int get setsCompleted => exercises.fold(
    0,
    (n, e) => n + e.workoutSets.where((s) => s.completed).length,
  );
  int get exercisesCompleted => exercises.where((e) => e.isComplete).length;

  factory Workout.fromJson(Map<String, dynamic> json) {
    final scheduled = DateTime.tryParse(
      (json['scheduledDate'] as String? ?? '').padRight(10).substring(0, 10),
    );
    if (scheduled == null) {
      throw FormatException('Workout is missing scheduledDate', json);
    }
    return Workout(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      trainerId: json['trainerId'] as String?,
      gymId: json['gymId'] as String?,
      templateId: json['templateId'] as String?,
      source: json['source'] as String?,
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      activityType: ActivityType.fromWire(json['activityType'] as String?),
      scheduledDate: DateTime(scheduled.year, scheduled.month, scheduled.day),
      estimatedDuration: (json['estimatedDuration'] as num?)?.toInt(),
      status: WorkoutStatus.fromWire(json['status'] as String?),
      exercises: (json['exercises'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => WorkoutExercise.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? ''),
      completedAt: DateTime.tryParse(json['completedAt'] as String? ?? ''),
      activityId: json['activityId'] as String?,
      notes: json['notes'] as String?,
    );
  }

  /// Deep copy, so a session can be edited without touching shared state.
  Workout copy({
    WorkoutStatus? status,
    DateTime? startedAt,
    DateTime? completedAt,
    String? activityId,
  }) {
    final json = toJson();
    if (status != null) json['status'] = status.wire;
    if (startedAt != null) json['startedAt'] = startedAt.toIso8601String();
    if (completedAt != null) {
      json['completedAt'] = completedAt.toIso8601String();
    }
    if (activityId != null) json['activityId'] = activityId;
    return Workout.fromJson(json);
  }

  /// The member-editable log, as the backend's progress patch expects.
  Map<String, dynamic> toLogJson() => {
    'notes': notes,
    'exercises': [for (final e in exercises) e.toLogJson()],
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'trainerId': trainerId,
    'gymId': gymId,
    'templateId': templateId,
    'source': source,
    'name': name,
    'description': description,
    'activityType': activityType.wire,
    'scheduledDate':
        '${scheduledDate.year.toString().padLeft(4, '0')}-'
        '${scheduledDate.month.toString().padLeft(2, '0')}-'
        '${scheduledDate.day.toString().padLeft(2, '0')}',
    'estimatedDuration': estimatedDuration,
    'status': status.wire,
    'exercises': [for (final e in exercises) e.toJson()],
    'startedAt': startedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'activityId': activityId,
    'notes': notes,
  };
}

/// A plan a member can schedule. Exercises carry targets only.
class WorkoutTemplate {
  final String id;
  final String name;
  final String? description;
  final ActivityType activityType;
  final int? estimatedDuration;
  final List<Map<String, dynamic>> exercises;

  const WorkoutTemplate({
    required this.id,
    required this.name,
    this.description,
    required this.activityType,
    this.estimatedDuration,
    required this.exercises,
  });

  factory WorkoutTemplate.fromJson(Map<String, dynamic> json) =>
      WorkoutTemplate(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        description: json['description'] as String?,
        activityType: ActivityType.fromWire(json['activityType'] as String?),
        estimatedDuration: (json['estimatedDuration'] as num?)?.toInt(),
        exercises: (json['exercises'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
}

String formatWorkoutDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
