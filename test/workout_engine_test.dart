import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/activity_summary.dart';
import 'package:fitflexmobile/shared/activity/goal.dart';
import 'package:fitflexmobile/shared/activity/mock/mock_activity_provider.dart';
import 'package:fitflexmobile/shared/activity/progress_engine.dart';
import 'package:fitflexmobile/shared/activity/sample_activity_log.dart';
import 'package:fitflexmobile/shared/activity/streaks.dart';
import 'package:fitflexmobile/shared/activity/workout.dart';
import 'package:fitflexmobile/shared/activity/workout_repository.dart';
import 'package:fitflexmobile/shared/activity/workout_summary.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 23, 18);

Map<String, dynamic> _workoutJson({
  String id = 'w1',
  String status = 'planned',
  double? benchWeight,
  bool benchDone = false,
  int? plankSeconds,
}) => {
  'id': id,
  'userId': 'u1',
  'name': 'Upper Body Strength',
  'activityType': 'strength',
  'scheduledDate': '2026-09-23',
  'estimatedDuration': 45,
  'status': status,
  'exercises': [
    {
      'id': '$id-bench',
      'workoutId': id,
      'exerciseName': 'Bench Press',
      'muscleGroup': 'chest',
      'sets': 2,
      'reps': 10,
      'tracksWeight': true,
      'workoutSets': [
        for (var i = 1; i <= 2; i++)
          {
            'id': '$id-bench-$i',
            'exerciseId': '$id-bench',
            'setNumber': i,
            'reps': 10,
            'weight': benchWeight,
            'completed': benchDone,
          },
      ],
    },
    {
      'id': '$id-plank',
      'workoutId': id,
      'exerciseName': 'Plank',
      'sets': 1,
      'duration': 30,
      'workoutSets': [
        {
          'id': '$id-plank-1',
          'exerciseId': '$id-plank',
          'setNumber': 1,
          'duration': plankSeconds ?? 30,
          'completed': plankSeconds != null,
        },
      ],
    },
  ],
};

void main() {
  group('Workout model', () {
    test('parses exercises and sets with targets', () {
      final w = Workout.fromJson(_workoutJson());
      expect(w.activityType, ActivityType.strength);
      expect(w.scheduledDate, DateTime(2026, 9, 23));
      expect(w.status, WorkoutStatus.planned);
      final bench = w.exercises.first;
      expect(bench.tracksWeight, isTrue);
      expect(bench.isTimed, isFalse);
      expect(bench.workoutSets.first.targetReps, 10);
      final plank = w.exercises.last;
      expect(plank.isTimed, isTrue);
      expect(plank.workoutSets.single.targetDuration, 30);
      expect(w.setsTotal, 3);
      expect(w.setsCompleted, 0);
    });

    test(
      'log JSON carries only member-editable fields; weight only if tracked',
      () {
        final w = Workout.fromJson(
          _workoutJson(benchWeight: 60, benchDone: true),
        )..notes = 'Good';
        final log = w.toLogJson();
        expect(log['notes'], 'Good');
        final bench = (log['exercises'] as List).first as Map;
        final set = (bench['workoutSets'] as List).first as Map;
        expect(set, {
          'id': 'w1-bench-1',
          'reps': 10,
          'weight': 60.0,
          'duration': null,
          'completed': true,
        });
        final plankSet =
            ((log['exercises'] as List).last as Map)['workoutSets'][0] as Map;
        expect(plankSet.containsKey('weight'), isFalse);
      },
    );

    test('copy is deep — editing a session never touches the original', () {
      final original = Workout.fromJson(_workoutJson());
      final session = original.copy();
      session.exercises.first.workoutSets.first.completed = true;
      session.exercises.first.notes = 'x';
      expect(original.exercises.first.workoutSets.first.completed, isFalse);
      expect(original.exercises.first.notes, isNull);
      expect(session.exercisesCompleted, 0);
      session.exercises.first.workoutSets.last.completed = true;
      expect(session.exercisesCompleted, 1);
    });
  });

  group('workout summary and records', () {
    test('beats a previous best for weight and hold time', () {
      final history = [
        Workout.fromJson(
          _workoutJson(
            id: 'old',
            status: 'completed',
            benchWeight: 60,
            benchDone: true,
            plankSeconds: 40,
          ),
        ),
      ];
      final today = Workout.fromJson(
        _workoutJson(benchWeight: 62.5, benchDone: true, plankSeconds: 45),
      );
      final s = summarizeWorkout(today, durationMinutes: 47, history: history);
      expect(s.durationMinutes, 47);
      expect(s.exercisesCompleted, 2);
      expect(s.setsCompleted, 3);
      expect(
        s.records.map((r) => (r.exerciseName, r.kind, r.value, r.previous)),
        [
          ('Bench Press', WorkoutRecordKind.weight, 62.5, 60.0),
          ('Plank', WorkoutRecordKind.duration, 45, 40),
        ],
      );
    });

    test('first time, equal, planned or unfinished sets are not records', () {
      final first = Workout.fromJson(
        _workoutJson(benchWeight: 80, benchDone: true),
      );
      expect(workoutRecords(first, const []), isEmpty);

      final history = [
        Workout.fromJson(
          _workoutJson(
            id: 'old',
            status: 'completed',
            benchWeight: 80,
            benchDone: true,
          ),
        ),
        // Planned workouts with big numbers don't count as history.
        Workout.fromJson(
          _workoutJson(id: 'p', benchWeight: 200, benchDone: true),
        ),
      ];
      expect(
        workoutRecords(
          Workout.fromJson(_workoutJson(benchWeight: 80, benchDone: true)),
          history,
        ),
        isEmpty,
      );
      expect(
        workoutRecords(
          Workout.fromJson(_workoutJson(benchWeight: 100)), // not completed
          history,
        ),
        isEmpty,
      );
    });
  });

  group('LocalWorkoutRepository feeds activity, goals and streaks', () {
    test('plan → start → save → complete records an activity', () async {
      var clock = _now;
      final log = SampleActivityLog();
      final repo = LocalWorkoutRepository(log: log, clock: () => clock);
      final templates = await repo.templates();
      expect(templates.map((t) => t.name), contains('Upper Body Strength'));

      final planned = await repo.plan(
        templateId: 'tpl_upper_strength',
        date: DateTime(2026, 9, 23),
      );
      expect(planned.exercises, hasLength(5));
      expect(planned.exercises.first.workoutSets, hasLength(3));

      final started = await repo.start(planned.id);
      expect(started.status, WorkoutStatus.inProgress);

      final session = started.copy();
      session.exercises.first.workoutSets.first
        ..weight = 60
        ..completed = true;
      await repo.save(session);
      final listed = await repo.list(
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 30),
      );
      expect(listed.single.setsCompleted, 1);
      expect(listed.single.status, WorkoutStatus.inProgress);

      clock = _now.add(const Duration(minutes: 42));
      final done = await repo.complete(session);
      expect(done.workout.status, WorkoutStatus.completed);
      expect(done.activity.durationMinutes, 42);
      expect(done.activity.workoutId, planned.id);
      expect(done.activity.isWorkout, isTrue);
      expect(log.items.single.id, done.activity.id);

      // The sample provider now serves it, so goals and streaks move.
      final provider = MockActivityProvider(
        clock: () => clock,
        days: 1,
        log: log,
      );
      final acts = await provider.activitiesBetween(
        userId: 'u1',
        from: DateTime(2026, 9, 23),
        to: DateTime(2026, 9, 24),
      );
      expect(acts.any((a) => a.id == done.activity.id), isTrue);
      final weekly = Goal(
        id: 'g',
        userId: 'u1',
        type: GoalType.workouts,
        target: 3,
        period: GoalPeriod.week,
        startDate: DateTime(2026, 9, 1),
      );
      final onlyWorkout = [done.activity];
      expect(evaluateGoal(weekly, onlyWorkout, clock).current, 1);
      expect(
        computeStreak(
          StreakKind.activity,
          today: clock,
          activities: onlyWorkout,
        )!.current,
        1,
      );
    });

    test('skip marks the workout skipped without recording activity', () async {
      final log = SampleActivityLog();
      final repo = LocalWorkoutRepository(log: log, clock: () => _now);
      final w = await repo.plan(templateId: 'tpl_hiit_express', date: _now);
      expect((await repo.skip(w.id)).status, WorkoutStatus.skipped);
      expect(log.items, isEmpty);
    });
  });

  group('ApiWorkoutRepository', () {
    test('sends the plan, the log and the completion to the API', () async {
      final api = _FakeApi();
      final repo = ApiWorkoutRepository(api);
      await repo.plan(
        templateId: 'tpl_upper_strength',
        date: DateTime(2026, 9, 23),
      );
      expect(api.calls.last.$1, 'plan');
      expect(api.calls.last.$2, {
        'templateId': 'tpl_upper_strength',
        'scheduledDate': '2026-09-23',
      });

      final w = Workout.fromJson(
        _workoutJson(benchWeight: 60, benchDone: true),
      );
      await repo.save(w);
      expect(api.calls.last.$1, 'save');
      expect((api.calls.last.$2['exercises'] as List).length, 2);

      final done = await repo.complete(w, durationMinutes: 40);
      expect(api.calls.last.$2['durationMinutes'], 40);
      expect(done.activity.workoutId, 'w1');
      expect(done.workout.status, WorkoutStatus.completed);
    });
  });
}

class _FakeApi extends ApiClient {
  final calls = <(String, Map<String, dynamic>)>[];

  Map<String, dynamic> _w([String status = 'planned']) => {
    'workout': _workoutJson(status: status),
  };

  @override
  Future<Map<String, dynamic>> planWorkout(Map<String, dynamic> data) async {
    calls.add(('plan', data));
    return _w();
  }

  @override
  Future<Map<String, dynamic>> saveWorkout(
    String id,
    Map<String, dynamic> log,
  ) async {
    calls.add(('save', log));
    return _w('in_progress');
  }

  @override
  Future<Map<String, dynamic>> completeWorkout(
    String id,
    Map<String, dynamic> log,
  ) async {
    calls.add(('complete', log));
    return {
      ..._w('completed'),
      'activity': {
        'id': 'act_1',
        'userId': 'u1',
        'type': 'strength',
        'source': 'fitflex',
        'startedAt': '2026-09-23T17:00:00.000Z',
        'durationMinutes': 40,
        'workoutId': id,
      },
    };
  }
}
