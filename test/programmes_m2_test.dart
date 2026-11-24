// Programmes P1 (M2): the plan page in programme mode, the rest timer
// between sets, and an exercise's picture and clip.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/member_training_plan_page.dart';
import 'package:fitflexmobile/shared/activity/exercise_library_cache.dart';
import 'package:fitflexmobile/shared/activity/programme.dart';
import 'package:fitflexmobile/shared/activity/sample_activity_log.dart';
import 'package:fitflexmobile/shared/activity/trainer_connection.dart';
import 'package:fitflexmobile/shared/activity/training_plan.dart';
import 'package:fitflexmobile/shared/activity/workout.dart';
import 'package:fitflexmobile/shared/activity/workout_repository.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _day(
  int n,
  String date,
  String type, {
  String status = 'planned',
  String? name,
  String? workoutId,
  Map<String, dynamic>? by,
}) => {
  'day': DateTime.parse(date).weekday,
  'programmeDay': n,
  'date': date,
  'type': type,
  'name': name,
  'workoutId': workoutId,
  'status': type == 'rest' ? 'rest' : status,
  'completedBy': by,
};

TrainingPlan _programmePlan({
  String todayType = 'gym',
  bool todayDone = true,
}) => TrainingPlan.tryParse({
  'id': 'tpl_p',
  'name': '7-day home starter',
  'programmeId': 'prg_1',
  'lengthDays': 7,
  'durationWeeks': 1,
  'startDate': '2026-11-20',
  'endDate': '2026-11-26',
  'weeks': [
    {
      'week': 1,
      'days': [
        _day(
          1,
          '2026-11-20',
          'home',
          name: 'Legs at home',
          workoutId: 'w1',
          status: 'completed',
          by: {'source': 'workout', 'workoutId': 'w1'},
        ),
        _day(2, '2026-11-21', 'rest'),
        _day(
          3,
          '2026-11-22',
          todayType,
          name: todayType == 'gym' ? null : 'Core',
          workoutId: todayType == 'gym' ? null : 'w3',
          status: todayDone ? 'completed' : 'planned',
          by: todayDone
              ? {
                  'source': 'checkin',
                  'checkinId': 'c1',
                  'completedAt': '2026-11-22T06:30:00.000Z',
                }
              : null,
        ),
        _day(4, '2026-11-23', 'home', name: 'Core', workoutId: 'w4'),
      ],
    },
  ],
  'progress': {'currentDay': 3, 'lengthDays': 7, 'streak': 2, 'bestStreak': 2},
})!;

/// Programmes on (catalogue answers) or off (feature_disabled).
class _Programmes implements ProgrammeRepository {
  _Programmes({this.on = true});
  final bool on;

  @override
  Future<List<Programme>> catalogue({
    ProgrammeFilters filters = const ProgrammeFilters(),
    String? lang,
  }) async => on ? const [] : throw const ProgrammesDisabled();

  @override
  Future<Programme> programme(String id, {String? lang}) =>
      throw const ProgrammesDisabled();

  @override
  Future<TrainingPlan> start(
    String id, {
    DateTime? startDate,
    bool replace = false,
    String? lang,
  }) => throw const ProgrammesDisabled();
  @override
  Future<TrainingPlan?> finished({
    DateTime? now,
    Duration within = const Duration(days: 30),
  }) async => null;

}

Widget _app(
  MemberData data,
  Widget child, {
  WorkoutRepository? workouts,
  ProgrammeRepository? programmes,
}) {
  final api = ApiClient();
  return AppScope(
    api: api,
    auth: AuthState(api),
    workoutRepository: workouts,
    programmeRepository: programmes ?? _Programmes(),
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
          body: MemberDataScope(data: data, child: child),
        ),
      ),
    ),
  );
}

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Workout _workout() => Workout.fromJson({
  'id': 'w9',
  'userId': 'm1',
  'name': 'Legs at home',
  'activityType': 'strength',
  'scheduledDate': '2026-11-23',
  'status': 'in_progress',
  'startedAt': '2026-11-23T08:00:00',
  'exercises': [
    {
      'id': 'e1',
      'workoutId': 'w9',
      'exerciseName': 'Bodyweight Squat',
      'libraryId': 'ex_squat',
      'sets': 2,
      'reps': 12,
      'workoutSets': [
        {
          'id': 'e1-s1',
          'exerciseId': 'e1',
          'setNumber': 1,
          'reps': 12,
          'completed': false,
        },
        {
          'id': 'e1-s2',
          'exerciseId': 'e1',
          'setNumber': 2,
          'reps': 12,
          'completed': false,
        },
      ],
    },
    {
      'id': 'e2',
      'workoutId': 'w9',
      'exerciseName': 'My own move',
      'sets': 1,
      'reps': 5,
      'workoutSets': [
        {
          'id': 'e2-s1',
          'exerciseId': 'e2',
          'setNumber': 1,
          'reps': 5,
          'completed': false,
        },
      ],
    },
  ],
});

void main() {
  tearDown(ExerciseLibraryCache.reset);

  test(
    'a programme day reads its type, programme day and what completed it',
    () {
      final plan = _programmePlan();
      final days = plan.days.toList();
      expect(plan.streak, 2);
      expect(days[1].isRest, isTrue);
      expect(days[1].isOpen, isFalse);
      expect(days[2].isGym, isTrue);
      expect(days[2].completedBy, 'checkin');
      expect(
        days[2].completedAt,
        DateTime.parse('2026-11-22T06:30:00.000Z').toLocal(),
      );
      expect(days[0].completedBy, 'workout');
    },
  );

  testWidgets(
    'a programme plan is shown day by day, with today done by a check-in',
    (tester) async {
      await _tall(tester);
      final data = MemberData()
        ..trainingPlan = _programmePlan()
        ..trainingLoaded = true;
      await tester.pumpWidget(
        _app(data, MemberTrainingPlanPage(now: DateTime(2026, 11, 22, 12))),
      );
      await tester.pumpAndSettle();
      expect(find.text('7-day home starter'), findsOneWidget);
      expect(find.text('Day 3 of 7'), findsOneWidget);
      expect(find.text('2 of 2 training days done so far'), findsOneWidget);
      expect(find.text('2-day streak'), findsOneWidget);
      final checkedIn = DateTime.parse('2026-11-22T06:30:00.000Z').toLocal();
      final hm =
          '${checkedIn.hour.toString().padLeft(2, '0')}:${checkedIn.minute.toString().padLeft(2, '0')}';
      expect(find.text('Done: checked in at $hm'), findsOneWidget);
      expect(find.text('Day 1 · Home · Workout'), findsOneWidget);
      expect(find.text('Day 3 · Gym · Check-in'), findsOneWidget);
      expect(find.text('Day 2 · Rest'), findsOneWidget);
      expect(find.text('Upcoming'), findsOneWidget);

      await tester.tap(find.byKey(const Key('training-plan-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Stop programme'), findsOneWidget);
    },
  );

  testWidgets('a gym day not yet done says to check in at any gym', (
    tester,
  ) async {
    await _tall(tester);
    final data = MemberData()
      ..trainingPlan = _programmePlan(todayDone: false)
      ..trainingLoaded = true;
    await tester.pumpWidget(
      _app(data, MemberTrainingPlanPage(now: DateTime(2026, 11, 22, 12))),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Gym day: check in at any FitFlex gym today.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('programme-today-suggested')), findsNothing);
  });

  testWidgets('a home day today offers to start its workout', (tester) async {
    await _tall(tester);
    final data = MemberData()
      ..trainingPlan = _programmePlan(todayType: 'home', todayDone: false)
      ..trainingLoaded = true;
    await tester.pumpWidget(
      _app(data, MemberTrainingPlanPage(now: DateTime(2026, 11, 22, 12))),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('programme-today-start')), findsOneWidget);
  });

  group('workout page', () {
    MemberData data() => MemberData()
      ..workouts = [_workout()]
      ..workoutsLoaded = true
      ..trainingLoaded = true;

    testWidgets(
      'ticking a set starts the rest from the library; +15 s and Skip',
      (tester) async {
        await _tall(tester);
        ExerciseLibraryCache.seed([
          const LibraryExercise(
            id: 'ex_squat',
            name: 'Bodyweight Squat',
            restSeconds: 30,
          ),
        ], lang: 'en');
        final repo = LocalWorkoutRepository(log: SampleActivityLog());
        await tester.pumpWidget(
          _app(
            data(),
            MemberWorkoutPage(
              workoutId: 'w9',
              now: () => DateTime(2026, 11, 23, 8, 5),
            ),
            workouts: repo,
          ),
        );
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('workout-rest-bar')), findsNothing);

        await tester.tap(find.byKey(const Key('set-e1-s1-done')));
        await tester.pump();
        expect(find.text('Rest 0:30'), findsOneWidget);
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Rest 0:29'), findsOneWidget);
        await tester.tap(find.byKey(const Key('workout-rest-add')));
        await tester.pump();
        expect(find.text('Rest 0:44'), findsOneWidget);
        await tester.pump(const Duration(seconds: 44));
        expect(find.text('Next set'), findsWidgets);
        await tester.tap(find.byKey(const Key('workout-rest-skip')));
        await tester.pump();
        expect(find.byKey(const Key('workout-rest-bar')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets(
      'no rest bar for an exercise without rest or outside the library',
      (tester) async {
        await _tall(tester);
        ExerciseLibraryCache.seed([
          const LibraryExercise(id: 'ex_squat', name: 'Bodyweight Squat'),
        ], lang: 'en');
        final repo = LocalWorkoutRepository(log: SampleActivityLog());
        await tester.pumpWidget(
          _app(
            data(),
            MemberWorkoutPage(
              workoutId: 'w9',
              now: () => DateTime(2026, 11, 23, 8, 5),
            ),
            workouts: repo,
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(const Key('set-e1-s1-done')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('set-e2-s1-done')));
        await tester.pump();
        expect(find.byKey(const Key('workout-rest-bar')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      },
    );

    testWidgets('an exercise shows its picture and a Watch clip button', (
      tester,
    ) async {
      await _tall(tester);
      ExerciseLibraryCache.seed([
        const LibraryExercise(
          id: 'ex_squat',
          name: 'Bodyweight Squat',
          stillUrl: 'https://media.example.test/squat.jpg',
          clipUrl: 'https://media.example.test/squat.mp4',
        ),
      ], lang: 'en');
      final repo = LocalWorkoutRepository(log: SampleActivityLog());
      await tester.pumpWidget(
        _app(
          data(),
          MemberWorkoutPage(
            workoutId: 'w9',
            now: () => DateTime(2026, 11, 23, 8, 5),
          ),
          workouts: repo,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('exercise-still-ex_squat')), findsOneWidget);
      expect(find.byKey(const Key('exercise-clip-ex_squat')), findsOneWidget);
      expect(find.text('Watch clip'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  testWidgets('with programmes off there is no rest timer and no media', (
    tester,
  ) async {
    await _tall(tester);
    ExerciseLibraryCache.seed([
      const LibraryExercise(
        id: 'ex_squat',
        name: 'Bodyweight Squat',
        restSeconds: 30,
        stillUrl: 'https://media.example.test/squat.jpg',
        clipUrl: 'https://media.example.test/squat.mp4',
      ),
    ], lang: 'en');
    final data = MemberData()
      ..workouts = [_workout()]
      ..workoutsLoaded = true
      ..trainingLoaded = true;
    await tester.pumpWidget(
      _app(
        data,
        MemberWorkoutPage(
          workoutId: 'w9',
          now: () => DateTime(2026, 11, 23, 8, 5),
        ),
        workouts: LocalWorkoutRepository(log: SampleActivityLog()),
        programmes: _Programmes(on: false),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('exercise-still-ex_squat')), findsNothing);
    await tester.tap(find.byKey(const Key('set-e1-s1-done')));
    await tester.pump();
    expect(find.byKey(const Key('workout-rest-bar')), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  test('library links are https only', () {
    final e = LibraryExercise.tryParse({
      'id': 'x',
      'name': 'X',
      'restSeconds': 45,
      'stillUrl': 'http://a.test/x.jpg',
      'clipUrl': 'https://a.test/x.mp4',
    })!;
    expect(e.restSeconds, 45);
    expect(e.stillUrl, isNull);
    expect(e.clipUrl, 'https://a.test/x.mp4');
  });

  test('every new Swahili string is a marked placeholder', () {
    for (final k in FFLocale.keysOf('en').where(
      (k) =>
          k.startsWith('programmes.') ||
          k.startsWith('workout.rest') ||
          k.startsWith('workout.clip') ||
          k == 'workout.watchClip' ||
          k == 'workout.nextSet',
    )) {
      expect(FFLocale.textOf('sw', k), startsWith('[SW-PENDING] '), reason: k);
    }
  });
}
