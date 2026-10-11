// Skipping one exercise, and replacing one with an alternative, during a
// workout.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/workout.dart';
import 'package:fitflexmobile/shared/activity/workout_repository.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 10, 12, 18);

Map<String, dynamic> _exercise(
  String id,
  String name, {
  String? libraryId,
  int sets = 2,
}) => {
  'id': id,
  'workoutId': 'w1',
  'exerciseName': name,
  'libraryId': libraryId,
  'muscleGroup': 'chest',
  'sets': sets,
  'reps': 10,
  'tracksWeight': false,
  'workoutSets': [
    for (var i = 1; i <= sets; i++)
      {
        'id': '$id-s$i',
        'exerciseId': id,
        'setNumber': i,
        'reps': 10,
        'completed': false,
      },
  ],
};

Workout _workout({String status = 'in_progress'}) => Workout.fromJson({
  'id': 'w1',
  'userId': 'm1',
  'name': 'Chest + Triceps',
  'activityType': 'strength',
  'scheduledDate': '2026-10-12',
  'estimatedDuration': 30,
  'status': status,
  'startedAt': status == 'in_progress' ? '2026-10-12T17:50:00' : null,
  'exercises': [
    _exercise('e1', 'Barbell Bench Press', libraryId: 'ex_bench_press'),
    _exercise('e2', 'Push-up', libraryId: 'ex_push_up'),
    _exercise('e3', 'My own move'),
  ],
});

/// A stand-in for the backend that records what the screen asks for.
class _Repo implements WorkoutRepository {
  _Repo(this.workout);

  Workout workout;
  final calls = <(String, Object?)>[];
  List<ExerciseAlternative> options = const [
    ExerciseAlternative(
      id: 'ex_dumbbell_bench_press',
      name: 'Dumbbell Bench Press',
      description: 'A chest press with a dumbbell in each hand.',
      sets: 3,
      reps: 10,
    ),
  ];

  @override
  Future<Workout> save(Workout w) async {
    calls.add(('save', w.toLogJson()));
    return workout = w.copy();
  }

  @override
  Future<WorkoutCompletion> complete(Workout w, {int? durationMinutes}) async {
    calls.add(('complete', w.toLogJson()));
    workout = w.copy(status: WorkoutStatus.completed, completedAt: _now);
    return WorkoutCompletion(
      workout,
      Activity(
        id: 'a1',
        userId: 'm1',
        type: ActivityType.strength,
        source: ActivitySource.fitflex,
        startedAt: _now,
        durationMinutes: 40,
        calories: 163,
        workoutId: 'w1',
      ),
    );
  }

  @override
  Future<List<ExerciseAlternative>> alternatives(
    String workoutId,
    String exerciseId, {
    String? lang,
  }) async {
    calls.add(('alternatives', exerciseId));
    return options;
  }

  @override
  Future<Workout> replaceExercise(
    String workoutId,
    String exerciseId,
    String libraryId, {
    String? lang,
  }) async {
    calls.add(('replace', (exerciseId, libraryId)));
    final json = workout.toJson();
    json['exercises'] = [
      for (final e in workout.exercises)
        e.id == exerciseId
            ? _exercise(
                'e9',
                'Dumbbell Bench Press',
                libraryId: libraryId,
                sets: e.sets,
              )
            : e.toJson(),
    ];
    return workout = Workout.fromJson(json);
  }

  bool failFeedback = false;

  @override
  Future<Workout> feedback(
    String workoutId, {
    String? rating,
    String? exerciseId,
    String? reason,
  }) async {
    calls.add(('feedback', (rating, exerciseId, reason)));
    if (failFeedback) throw ApiException(500, {'error': 'boom'});
    return workout;
  }

  @override
  Future<Workout> start(String id) async =>
      workout = workout.copy(status: WorkoutStatus.inProgress, startedAt: _now);

  @override
  Future<Workout> skip(String id) async => workout;
  @override
  Future<List<Workout>> list({
    required DateTime from,
    required DateTime to,
  }) async => [workout];
  @override
  Future<Workout> plan({
    required String templateId,
    required DateTime date,
  }) async => workout;
  @override
  Future<List<WorkoutTemplate>> templates() async => const [];
  @override
  Future<Workout?> get(String id) async => id == workout.id ? workout : null;
}

Future<_Repo> _open(
  WidgetTester tester, {
  String status = 'in_progress',
  List<Activity> activities = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final repo = _Repo(_workout(status: status));
  final data = MemberData()
    ..workouts = [repo.workout]
    ..workoutsLoaded = true
    ..activities = activities;
  final api = ApiClient();
  await tester.pumpWidget(
    AppScope(
      api: api,
      auth: AuthState(api),
      workoutRepository: repo,
      child: FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp(
          theme: buildTheme(),
          supportedLocales: const [Locale('en'), Locale('sw')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: MemberDataScope(
              data: data,
              child: MemberWorkoutPage(workoutId: 'w1', now: () => _now),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return repo;
}

Future<void> _menu(WidgetTester tester, String exerciseId, String item) async {
  await tester.tap(find.byKey(Key('exercise-menu-$exerciseId')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('exercise-$item-$exerciseId')));
  await tester.pumpAndSettle();
}

Map _saved(_Repo repo, String call, String exerciseId) {
  final body = repo.calls.lastWhere((c) => c.$1 == call).$2 as Map;
  return (body['exercises'] as List).cast<Map>().firstWhere(
    (e) => e['id'] == exerciseId,
  );
}

void main() {
  test('a skipped exercise is never complete and its sets do not count', () {
    final w = _workout();
    expect(w.setsTotal, 6);
    final e = w.exercises.first;
    for (final s in e.workoutSets) {
      s.completed = true;
    }
    expect(e.isComplete, isTrue);
    e.skipped = true;
    expect(e.isComplete, isFalse);
    expect(w.setsTotal, 4);
    expect(w.setsCompleted, 0);
    expect(w.exercisesCompleted, 0);
    expect(e.toLogJson()['skipped'], true);
    // It survives a copy and a round trip.
    expect(w.copy().exercises.first.skipped, isTrue);
    expect(w.copy().exercises.first.libraryId, 'ex_bench_press');
  });

  testWidgets('skip an exercise: it is set aside, not marked done', (
    tester,
  ) async {
    final repo = await _open(tester);
    expect(find.textContaining('0/6 sets'), findsOneWidget);
    await tester.tap(find.byKey(const Key('set-e1-s1-done')));
    await tester.pump();
    expect(find.textContaining('1/6 sets'), findsOneWidget);

    await _menu(tester, 'e1', 'skip');
    expect(find.byKey(const Key('exercise-skipped-e1')), findsOneWidget);
    expect(find.byKey(const Key('set-e1-s1-done')), findsNothing);
    expect(find.byKey(const Key('exercise-done-e1')), findsNothing);
    expect(find.textContaining('0/4 sets'), findsOneWidget);

    // The save that follows says so, with none of its sets done.
    await tester.pump(const Duration(seconds: 2));
    final saved = _saved(repo, 'save', 'e1');
    expect(saved['skipped'], true);
    expect(
      (saved['workoutSets'] as List).every((s) => s['completed'] == false),
      isTrue,
    );

    // Do the next one and finish: one exercise done, not two.
    await tester.tap(find.byKey(const Key('exercise-done-e2')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('workout-finish')));
    await tester.pumpAndSettle();
    if (find.byKey(const Key('workout-confirm')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const Key('workout-confirm')));
      await tester.pumpAndSettle();
    }
    expect(_saved(repo, 'complete', 'e1')['skipped'], true);
    expect(_saved(repo, 'complete', 'e2')['skipped'], false);
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets('a skipped exercise can be brought back', (tester) async {
    await _open(tester);
    await _menu(tester, 'e2', 'skip');
    expect(find.byKey(const Key('exercise-skipped-e2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('exercise-menu-e2')));
    await tester.pumpAndSettle();
    expect(find.text('Bring this exercise back'), findsOneWidget);
    await tester.tap(find.byKey(const Key('exercise-skip-e2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-skipped-e2')), findsNothing);
    expect(find.byKey(const Key('set-e2-s1-done')), findsOneWidget);
    expect(find.textContaining('0/6 sets'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('replace an exercise with one that trains the same area', (
    tester,
  ) async {
    final repo = await _open(tester);
    await _menu(tester, 'e1', 'replace');
    expect(find.text('Replace Barbell Bench Press'), findsOneWidget);
    expect(find.textContaining('3 × 10'), findsWidgets);
    await tester.tap(
      find.byKey(const Key('alternative-ex_dumbbell_bench_press')),
    );
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.$1 == 'alternatives').single.$2, 'e1');
    expect(repo.calls.last, ('replace', ('e1', 'ex_dumbbell_bench_press')));
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    expect(find.text('Barbell Bench Press'), findsNothing);
    expect(find.text('Push-up'), findsOneWidget, reason: 'the rest stay put');
    expect(find.byKey(const Key('set-e9-s1-done')), findsOneWidget);
    expect(find.text('Exercise replaced.'), findsOneWidget);
  });

  testWidgets('replace is offered only where it makes sense', (tester) async {
    final repo = await _open(tester);
    // Not from the library: skip only.
    await tester.tap(find.byKey(const Key('exercise-menu-e3')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-skip-e3')), findsOneWidget);
    expect(find.byKey(const Key('exercise-replace-e3')), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // Already started: it stays.
    await tester.tap(find.byKey(const Key('set-e2-s1-done')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('exercise-menu-e2')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-replace-e2')), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // Nothing that fits: said plainly, with a way forward.
    repo.options = const [];
    await _menu(tester, 'e1', 'replace');
    expect(find.byKey(const Key('alternatives-none')), findsOneWidget);
    expect(find.textContaining('skip this exercise instead'), findsOneWidget);
    expect(repo.calls.any((c) => c.$1 == 'replace'), isFalse);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('an exercise can be skipped or replaced before starting', (
    tester,
  ) async {
    final repo = await _open(tester, status: 'planned');
    await _menu(tester, 'e2', 'skip');
    expect(find.byKey(const Key('exercise-skipped-e2')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(_saved(repo, 'save', 'e2')['skipped'], true);
    await _menu(tester, 'e1', 'replace');
    await tester.tap(
      find.byKey(const Key('alternative-ex_dumbbell_bench_press')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dumbbell Bench Press'), findsOneWidget);
    // The skip made before the swap is still there.
    expect(find.byKey(const Key('exercise-skipped-e2')), findsOneWidget);
  });

  testWidgets('finishing shows the calories and asks how it went', (
    tester,
  ) async {
    final repo = await _open(tester);
    await tester.tap(find.byKey(const Key('exercise-done-e1')));
    await tester.tap(find.byKey(const Key('exercise-done-e2')));
    await tester.tap(find.byKey(const Key('exercise-done-e3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('workout-finish')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workout-complete')), findsOneWidget);
    expect(find.textContaining('About 163 kcal'), findsOneWidget);
    expect(find.text('How was it?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('feedback-too_hard')));
    await tester.pumpAndSettle();
    expect(repo.calls.last, ('feedback', ('too_hard', null, null)));
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('feedback-too_hard')))
          .selected,
      isTrue,
    );
    // Tapping the same answer again asks nothing more of the server.
    await tester.tap(find.byKey(const Key('feedback-too_hard')));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c.$1 == 'feedback').length, 1);

    // One exercise didn't work.
    await tester.tap(find.byKey(const Key('feedback-exercises')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feedback-ex-e2')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('feedback-reason-e2-couldnt_perform')),
    );
    await tester.pumpAndSettle();
    expect(repo.calls.last, ('feedback', (null, 'e2', 'couldnt_perform')));
    expect(find.text("Couldn't do it"), findsOneWidget);

    // And it can be taken back.
    await tester.tap(find.byKey(const Key('feedback-ex-e2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feedback-clear-e2')));
    await tester.pumpAndSettle();
    expect(repo.calls.last, ('feedback', (null, 'e2', null)));
    expect(find.text("Couldn't do it"), findsNothing);
  });

  testWidgets('feedback that cannot be saved is put back', (tester) async {
    final repo = await _open(tester, status: 'completed');
    repo.failFeedback = true;
    expect(find.byKey(const Key('workout-calories')), findsNothing);
    await tester.tap(find.byKey(const Key('feedback-just_right')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('feedback-just_right')))
          .selected,
      isFalse,
    );
    expect(find.textContaining("Couldn't save that"), findsOneWidget);
  });

  testWidgets('a workout finished earlier shows its calories and feedback', (
    tester,
  ) async {
    final w = _workout(status: 'completed')
      ..feedbackRating = 'just_right'
      ..exercises[0].feedback = 'didnt_enjoy';
    expect(w.copy().feedbackRating, 'just_right');
    expect(w.copy().exercises[0].feedback, 'didnt_enjoy');

    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = _Repo(w);
    final data = MemberData()
      ..workouts = [w]
      ..workoutsLoaded = true
      ..activities = [
        Activity(
          id: 'a1',
          userId: 'm1',
          type: ActivityType.strength,
          source: ActivitySource.fitflex,
          startedAt: _now,
          calories: 210,
          workoutId: 'w1',
        ),
      ];
    final api = ApiClient();
    await tester.pumpWidget(
      AppScope(
        api: api,
        auth: AuthState(api),
        workoutRepository: repo,
        child: FFLocaleScope(
          notifier: FFLocale(),
          child: MaterialApp(
            theme: buildTheme(),
            home: Scaffold(
              body: MemberDataScope(
                data: data,
                child: MemberWorkoutPage(workoutId: 'w1', now: () => _now),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('About 210 kcal'), findsOneWidget);
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('feedback-just_right')))
          .selected,
      isTrue,
    );
    // The exercise list opens by itself when something was said.
    expect(find.text("Didn't enjoy it"), findsOneWidget);
  });

  testWidgets('a session further ahead than the app keeps is fetched', (
    tester,
  ) async {
    Future<void> open(_Repo repo, String id) async {
      final data = MemberData()..workoutsLoaded = true;
      final api = ApiClient();
      await tester.pumpWidget(
        AppScope(
          key: ValueKey(id),
          api: api,
          auth: AuthState(api),
          workoutRepository: repo,
          child: FFLocaleScope(
            notifier: FFLocale(),
            child: MaterialApp(
              theme: buildTheme(),
              home: Scaffold(
                body: MemberDataScope(
                  data: data,
                  child: MemberWorkoutPage(workoutId: id, now: () => _now),
                ),
              ),
            ),
          ),
        ),
      );
    }

    tester.view.physicalSize = const Size(1080, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = _Repo(_workout(status: 'planned'));
    await open(repo, 'w1');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Chest + Triceps'), findsOneWidget);
    expect(find.byKey(const Key('workout-start')), findsOneWidget);

    // One that isn't theirs, or is gone, says so with the way back.
    await open(repo, 'w_other');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workout-start')), findsNothing);
    expect(find.byKey(const Key('workout-back')), findsOneWidget);
  });
}
