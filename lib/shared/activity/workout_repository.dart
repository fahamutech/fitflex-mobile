import '../api_client.dart';
import 'activity.dart';
import 'mock/sample_workout_templates.dart';
import 'sample_activity_log.dart';
import 'workout.dart';

/// Result of finishing a workout: the stored workout and the Activity it
/// was recorded as (which is what goals, progress and streaks read).
class WorkoutCompletion {
  final Workout workout;
  final Activity activity;

  const WorkoutCompletion(this.workout, this.activity);
}

/// Where a member's workouts live. Screens depend only on this interface.
abstract class WorkoutRepository {
  Future<List<WorkoutTemplate>> templates();

  /// Workouts scheduled within `[from, to]` (calendar dates), newest first.
  Future<List<Workout>> list({required DateTime from, required DateTime to});

  Future<Workout> plan({required String templateId, required DateTime date});

  Future<Workout> start(String id);

  /// Saves the logged sets and notes mid-session.
  Future<Workout> save(Workout workout);

  Future<WorkoutCompletion> complete(Workout workout, {int? durationMinutes});

  Future<Workout> skip(String id);

  /// Exercises that could stand in for one in a workout. Empty when the
  /// exercise didn't come from the FitFlex library.
  Future<List<ExerciseAlternative>> alternatives(
    String workoutId,
    String exerciseId, {
    String? lang,
  });

  /// Says how a finished workout went: a [rating] for the session and/or
  /// what got in the way of [exerciseId] ([reason] null clears it).
  /// FitFlex shapes the next plan with it.
  Future<Workout> feedback(
    String workoutId, {
    String? rating,
    String? exerciseId,
    String? reason,
  });

  /// Swaps an exercise for one of its [alternatives]; returns the workout.
  Future<Workout> replaceExercise(
    String workoutId,
    String exerciseId,
    String libraryId,
  );
}

/// Workouts stored on the FitFlex backend.
class ApiWorkoutRepository implements WorkoutRepository {
  ApiWorkoutRepository(this.api);

  final ApiClient api;

  Workout _workout(Map<String, dynamic> res) =>
      Workout.fromJson(Map<String, dynamic>.from(res['workout'] as Map));

  @override
  Future<List<WorkoutTemplate>> templates() async => [
    for (final t in (await api.workoutTemplates()).whereType<Map>())
      WorkoutTemplate.fromJson(Map<String, dynamic>.from(t)),
  ];

  @override
  Future<List<Workout>> list({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await api.myWorkouts(
      from: formatWorkoutDate(from),
      to: formatWorkoutDate(to),
    );
    final out = <Workout>[];
    for (final r in rows.whereType<Map>()) {
      try {
        out.add(Workout.fromJson(Map<String, dynamic>.from(r)));
      } on FormatException {
        // Skip a malformed row rather than hiding the whole list.
      }
    }
    return out;
  }

  @override
  Future<Workout> plan({
    required String templateId,
    required DateTime date,
  }) async => _workout(
    await api.planWorkout({
      'templateId': templateId,
      'scheduledDate': formatWorkoutDate(date),
    }),
  );

  @override
  Future<Workout> start(String id) async =>
      _workout(await api.startWorkout(id));

  @override
  Future<Workout> save(Workout workout) async =>
      _workout(await api.saveWorkout(workout.id, workout.toLogJson()));

  @override
  Future<WorkoutCompletion> complete(
    Workout workout, {
    int? durationMinutes,
  }) async {
    final res = await api.completeWorkout(workout.id, {
      ...workout.toLogJson(),
      'durationMinutes': ?durationMinutes,
    });
    return WorkoutCompletion(
      _workout(res),
      Activity.fromJson(Map<String, dynamic>.from(res['activity'] as Map)),
    );
  }

  @override
  Future<Workout> skip(String id) async => _workout(await api.skipWorkout(id));

  @override
  Future<Workout> feedback(
    String workoutId, {
    String? rating,
    String? exerciseId,
    String? reason,
  }) async => _workout(
    await api.workoutFeedback(workoutId, {
      'rating': ?rating,
      if (exerciseId != null)
        'exercises': [
          {'id': exerciseId, 'reason': reason},
        ],
    }),
  );

  @override
  Future<List<ExerciseAlternative>> alternatives(
    String workoutId,
    String exerciseId, {
    String? lang,
  }) async => [
    for (final raw in await api.workoutExerciseAlternatives(
      workoutId,
      exerciseId,
      lang: lang,
    ))
      ?ExerciseAlternative.tryParse(raw),
  ];

  @override
  Future<Workout> replaceExercise(
    String workoutId,
    String exerciseId,
    String libraryId,
  ) async => _workout(
    await api.replaceWorkoutExercise(workoutId, exerciseId, libraryId),
  );
}

/// In-memory workouts for sample-data mode. Completing one adds its
/// Activity to [log], which the sample activity provider serves — so a
/// finished sample workout still shows up in goals, progress and streaks.
class LocalWorkoutRepository implements WorkoutRepository {
  LocalWorkoutRepository({required this.log, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final SampleActivityLog log;
  final DateTime Function() _clock;
  final List<Workout> _workouts = [];
  var _seq = 0;

  String _id(String prefix) => 'local_${prefix}_${_seq++}';

  int _index(String id) {
    final i = _workouts.indexWhere((w) => w.id == id);
    if (i < 0) throw StateError('Unknown workout $id');
    return i;
  }

  @override
  Future<List<WorkoutTemplate>> templates() async => sampleWorkoutTemplates;

  @override
  Future<List<Workout>> list({
    required DateTime from,
    required DateTime to,
  }) async {
    // Compare calendar dates, whatever time of day the bounds carry.
    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    return _workouts
        .where(
          (w) =>
              !w.scheduledDate.isBefore(start) && !w.scheduledDate.isAfter(end),
        )
        .map((w) => w.copy())
        .toList()
      ..sort((a, b) => b.scheduledDate.compareTo(a.scheduledDate));
  }

  @override
  Future<Workout> plan({
    required String templateId,
    required DateTime date,
  }) async {
    final t = sampleWorkoutTemplates.firstWhere((t) => t.id == templateId);
    final workoutId = _id('wkt');
    final w = Workout.fromJson({
      'id': workoutId,
      'userId': '',
      'templateId': t.id,
      'name': t.name,
      'description': t.description,
      'activityType': t.activityType.wire,
      'scheduledDate': formatWorkoutDate(date),
      'estimatedDuration': t.estimatedDuration,
      'status': 'planned',
      'exercises': [
        for (final e in t.exercises)
          () {
            final exId = _id('wex');
            final count = (e['sets'] as num?)?.toInt() ?? 1;
            return {
              ...e,
              'id': exId,
              'workoutId': workoutId,
              'workoutSets': [
                for (var i = 0; i < count; i++)
                  {
                    'id': _id('wst'),
                    'exerciseId': exId,
                    'setNumber': i + 1,
                    'reps': e['reps'],
                    'duration': e['duration'],
                    'completed': false,
                  },
              ],
            };
          }(),
      ],
    });
    _workouts.add(w);
    return w.copy();
  }

  @override
  Future<Workout> start(String id) async {
    final i = _index(id);
    if (_workouts[i].status == WorkoutStatus.planned) {
      _workouts[i] = _workouts[i].copy(
        status: WorkoutStatus.inProgress,
        startedAt: _clock(),
      );
    }
    return _workouts[i].copy();
  }

  @override
  Future<Workout> save(Workout workout) async {
    final i = _index(workout.id);
    _workouts[i] = workout.copy(status: _workouts[i].status);
    return _workouts[i].copy();
  }

  @override
  Future<WorkoutCompletion> complete(
    Workout workout, {
    int? durationMinutes,
  }) async {
    final i = _index(workout.id);
    final end = _clock();
    final started = _workouts[i].startedAt;
    final minutes =
        (durationMinutes ??
                (started == null
                    ? workout.estimatedDuration ?? 30
                    : end.difference(started).inMinutes))
            .clamp(1, 600);
    final start = started ?? end.subtract(Duration(minutes: minutes));
    final activity = Activity(
      id: _id('act'),
      userId: workout.userId,
      type: workout.activityType,
      source: ActivitySource.fitflex,
      // Local workouts only run in sample mode.
      isSample: true,
      startedAt: start,
      durationMinutes: minutes,
      activeMinutes: minutes,
      workoutId: workout.id,
      gymId: workout.gymId,
      notes: workout.name,
    );
    log.add(activity);
    _workouts[i] = workout.copy(
      status: WorkoutStatus.completed,
      startedAt: start,
      completedAt: end,
      activityId: activity.id,
    );
    return WorkoutCompletion(_workouts[i].copy(), activity);
  }

  @override
  Future<Workout> skip(String id) async {
    final i = _index(id);
    _workouts[i] = _workouts[i].copy(status: WorkoutStatus.skipped);
    return _workouts[i].copy();
  }

  @override
  Future<Workout> feedback(
    String workoutId, {
    String? rating,
    String? exerciseId,
    String? reason,
  }) async {
    final w = _workouts[_index(workoutId)];
    if (rating != null) w.feedbackRating = rating;
    if (exerciseId != null) {
      w.exercises.firstWhere((e) => e.id == exerciseId).feedback = reason;
    }
    return w.copy();
  }

  // Sample workouts come from fixed templates, not the exercise library,
  // so there is nothing to swap them for.
  @override
  Future<List<ExerciseAlternative>> alternatives(
    String workoutId,
    String exerciseId, {
    String? lang,
  }) async => const [];

  @override
  Future<Workout> replaceExercise(
    String workoutId,
    String exerciseId,
    String libraryId,
  ) => throw UnsupportedError('Sample workouts have no alternatives.');
}
