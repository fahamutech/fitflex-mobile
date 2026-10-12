// A trainer picks exercises from the FitFlex library when writing a saved
// workout.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/trainer/trainer_plan_editor_page.dart';
import 'package:fitflexmobile/shared/activity/trainer_connection.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _lib(
  String id,
  String name, {
  List<String> areas = const ['chest'],
  List<String> equipment = const ['none'],
  String difficulty = 'beginner',
  int sets = 3,
  int? reps = 10,
  int? seconds,
  bool weight = false,
}) => {
  'id': id,
  'name': name,
  'description': 'About $name.',
  'targetAreas': areas,
  'equipment': equipment,
  'difficulty': difficulty,
  'defaultSets': sets,
  'defaultReps': ?reps,
  'defaultDuration': ?seconds,
  'tracksWeight': weight,
  'instructions': ['First step.', 'Second step.'],
};

class _FakeApi extends ApiClient {
  final saved = <Map<String, dynamic>>[];
  final langs = <String?>[];
  bool fail = false;
  List<Map<String, dynamic>> library = [
    _lib('ex_push_up', 'Push-up'),
    _lib(
      'ex_bench_press',
      'Barbell Bench Press',
      equipment: ['free_weights'],
      difficulty: 'intermediate',
      weight: true,
    ),
    _lib(
      'ex_back_squat',
      'Barbell Back Squat',
      areas: ['quadriceps', 'glutes'],
      equipment: ['free_weights'],
      reps: 8,
      weight: true,
    ),
    _lib('ex_plank', 'Plank', areas: ['abs'], reps: null, seconds: 30),
  ];

  @override
  Future<List<dynamic>> trainingExercises({String? lang}) async {
    langs.add(lang);
    if (fail) throw ApiException(500, null);
    return library;
  }

  @override
  Future<Map<String, dynamic>> trainerSavePlan(
    String? id,
    Map<String, dynamic> plan,
  ) async {
    saved.add(plan);
    return {
      'plan': {'id': 'wpl_1', ...plan},
    };
  }
}

Widget _app(ApiClient api, Widget home) => AppScope(
  api: api,
  auth: AuthState(api),
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
      home: home,
    ),
  ),
);

Future<_FakeApi> _open(
  WidgetTester tester, {
  _FakeApi? api,
  TrainerPlan? plan,
}) async {
  tester.view.physicalSize = const Size(1080, 12000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final a = api ?? _FakeApi();
  await tester.pumpWidget(_app(a, TrainerPlanEditorPage(plan: plan)));
  await tester.pumpAndSettle();
  return a;
}

String _field(WidgetTester tester, String key) =>
    tester.widget<TextFormField>(find.byKey(Key(key))).initialValue ?? '';

void main() {
  test('a library exercise becomes a workout line ready to adjust', () {
    final squat = LibraryExercise.tryParse(
      _lib(
        'ex_back_squat',
        'Barbell Back Squat',
        areas: ['quadriceps', 'glutes'],
        reps: 8,
        weight: true,
      ),
    )!.toPlanExercise();
    expect(squat.libraryId, 'ex_back_squat');
    expect(squat.exerciseName, 'Barbell Back Squat');
    expect(squat.muscleGroup, 'quadriceps');
    expect((squat.sets, squat.reps, squat.duration), (3, 8, null));
    expect(squat.tracksWeight, isTrue);
    expect(squat.instructions, 'First step. Second step.');
    expect(squat.toJson()['libraryId'], 'ex_back_squat');

    final plank = LibraryExercise.tryParse(
      _lib('ex_plank', 'Plank', reps: null, seconds: 30),
    )!.toPlanExercise();
    expect((plank.reps, plank.duration), (null, 30));
    expect(plank.isTimed, isTrue);
    expect(LibraryExercise.tryParse({'id': 'x'}), isNull);
  });

  test('renaming a picked exercise to something else drops the link', () {
    final e = PlanExercise(exerciseName: 'Push-up', libraryId: 'ex_push_up');
    expect(e.fromLibrary, isTrue);
    e.renamed('Push-up ');
    expect(e.fromLibrary, isTrue, reason: 'a stray space is still Push-up');
    e.renamed('Slow push-up');
    expect(e.fromLibrary, isFalse);
    expect(e.toJson().containsKey('libraryId'), isFalse);
    // One typed by hand never had a link.
    expect(PlanExercise(exerciseName: 'My move').fromLibrary, isFalse);
    // And the link survives the round trip to the server and back.
    final back = PlanExercise.fromJson(
      PlanExercise(exerciseName: 'Push-up', libraryId: 'ex_push_up').toJson(),
    );
    expect(back.libraryId, 'ex_push_up');
  });

  testWidgets('add from the library: the first blank line is filled', (
    tester,
  ) async {
    final api = await _open(tester);
    await tester.enterText(find.byKey(const Key('plan-name')), 'Push day');
    await tester.tap(find.byKey(const Key('plan-add-from-library')));
    await tester.pumpAndSettle();
    expect(find.text('FitFlex exercise library'), findsOneWidget);
    expect(api.langs.single, 'en');
    expect(find.text('Chest · No equipment · 3 × 10'), findsOneWidget);
    expect(find.text('Abs · No equipment · 3 × 30 s'), findsOneWidget);
    expect(find.text('Intermediate'), findsOneWidget);

    await tester.tap(find.byKey(const Key('exercise-pick-ex_bench_press')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-picker')), findsNothing);
    expect(find.byKey(const Key('plan-exercise-1')), findsNothing);
    expect(_field(tester, 'exercise-name-0'), 'Barbell Bench Press');
    expect(
      _field(tester, 'exercise-instructions-0'),
      'First step. Second step.',
    );
    expect(find.byKey(const Key('exercise-linked-0')), findsOneWidget);
    expect(find.textContaining('Your client can swap it'), findsOneWidget);

    // A second one is added below.
    await tester.tap(find.byKey(const Key('plan-add-from-library')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exercise-pick-ex_plank')));
    await tester.pumpAndSettle();
    expect(_field(tester, 'exercise-name-1'), 'Plank');

    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();
    final exercises = (api.saved.single['exercises'] as List).cast<Map>();
    expect(exercises[0], {
      'exerciseName': 'Barbell Bench Press',
      'libraryId': 'ex_bench_press',
      'muscleGroup': 'chest',
      'sets': 3,
      'reps': 10,
      'instructions': 'First step. Second step.',
      'tracksWeight': true,
    });
    expect(exercises[1]['libraryId'], 'ex_plank');
    expect(exercises[1]['duration'], 30);
    expect(exercises[1].containsKey('reps'), isFalse);
  });

  testWidgets('search and area narrow the list; nothing found says so', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('plan-add-from-library')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-pick-ex_push_up')), findsOneWidget);
    // Only areas the library has something for are offered.
    expect(find.byKey(const Key('exercise-picker-area-chest')), findsOneWidget);
    expect(find.byKey(const Key('exercise-picker-area-calves')), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('exercise-picker-area-quadriceps')),
    );
    await tester.tap(find.byKey(const Key('exercise-picker-area-quadriceps')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('exercise-pick-ex_back_squat')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('exercise-pick-ex_push_up')), findsNothing);

    await tester.ensureVisible(
      find.byKey(const Key('exercise-picker-area-all')),
    );
    await tester.tap(find.byKey(const Key('exercise-picker-area-all')));
    await tester.enterText(
      find.byKey(const Key('exercise-picker-search')),
      'barbell',
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('exercise-pick-ex_bench_press')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('exercise-pick-ex_back_squat')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('exercise-pick-ex_plank')), findsNothing);

    await tester.enterText(
      find.byKey(const Key('exercise-picker-search')),
      'zzz',
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('exercise-picker-none')), findsOneWidget);
  });

  testWidgets('choose for one line, then type over it', (tester) async {
    final api = await _open(tester);
    await tester.enterText(find.byKey(const Key('plan-name')), 'Legs');
    await tester.tap(find.byKey(const Key('exercise-pick-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exercise-pick-ex_back_squat')));
    await tester.pumpAndSettle();
    expect(_field(tester, 'exercise-name-0'), 'Barbell Back Squat');
    expect(_field(tester, 'exercise-target-0-r'), '8');
    expect(find.text('Choose a different one'), findsOneWidget);
    // Its area is a finer one than the short list has, and still shows.
    expect(find.text('Quadriceps'), findsOneWidget);

    // Adjusting sets keeps it a library exercise.
    await tester.enterText(find.byKey(const Key('exercise-sets-0')), '5');
    await tester.pump();
    expect(find.byKey(const Key('exercise-linked-0')), findsOneWidget);

    // Typing a different name makes it the trainer's own.
    await tester.enterText(
      find.byKey(const Key('exercise-name-0')),
      'Pause squat',
    );
    await tester.pump();
    expect(find.byKey(const Key('exercise-linked-0')), findsNothing);
    expect(find.text('Choose from the FitFlex library'), findsOneWidget);

    await tester.tap(find.byKey(const Key('plan-save')));
    await tester.pumpAndSettle();
    final e = (api.saved.single['exercises'] as List).single as Map;
    expect(e['exerciseName'], 'Pause squat');
    expect(e['sets'], 5);
    expect(e.containsKey('libraryId'), isFalse);
  });

  testWidgets('a saved workout opens with its library exercises marked', (
    tester,
  ) async {
    await _open(
      tester,
      plan: TrainerPlan.fromJson({
        'id': 'wpl_1',
        'name': 'Push day',
        'exercises': [
          {
            'exerciseName': 'Push-up',
            'libraryId': 'ex_push_up',
            'sets': 3,
            'reps': 12,
          },
          {'exerciseName': 'Coach special', 'sets': 2, 'reps': 8},
        ],
      }),
    );
    expect(find.byKey(const Key('exercise-linked-0')), findsOneWidget);
    expect(find.byKey(const Key('exercise-linked-1')), findsNothing);
  });

  testWidgets(
    'the library failing to load can be retried; typing still works',
    (tester) async {
      final api = _FakeApi()..fail = true;
      await _open(tester, api: api);
      await tester.tap(find.byKey(const Key('plan-add-from-library')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exercise-picker-failed')), findsOneWidget);
      api.fail = false;
      await tester.tap(find.byKey(const Key('exercise-picker-retry')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('exercise-pick-ex_push_up')), findsOneWidget);
      expect(api.langs.length, 2);
    },
  );
}
