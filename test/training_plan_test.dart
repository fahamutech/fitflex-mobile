// Training plans in the app: the plan model, sample-mode stand-in, the
// set-up screen, the weekly plan view and the cards on the Activity tab.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/member_training_offer_page.dart';
import 'package:fitflexmobile/screens/member/member_training_plan_page.dart';
import 'package:fitflexmobile/screens/member/member_training_setup_page.dart';
import 'package:fitflexmobile/screens/member/widgets/progress_section.dart';
import 'package:fitflexmobile/screens/member/widgets/training_offer.dart';
import 'package:fitflexmobile/screens/member/widgets/training_widgets.dart';
import 'package:fitflexmobile/screens/member/widgets/workout_widgets.dart';
import 'package:fitflexmobile/shared/activity/sample_activity_log.dart';
import 'package:fitflexmobile/shared/activity/training_plan.dart';
import 'package:fitflexmobile/shared/activity/training_repository.dart';
import 'package:fitflexmobile/shared/activity/workout.dart';
import 'package:fitflexmobile/shared/activity/workout_repository.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/inbox/inbox_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Monday 12 Oct 2026.
final _now = DateTime(2026, 10, 12, 9);

Map<String, dynamic> _day(
  String date,
  String name, {
  String status = 'planned',
  String? workoutId,
}) => {
  'day': 1,
  'date': date,
  'focusAreas': ['chest', 'triceps'],
  'name': name,
  'workoutId': workoutId ?? 'w_$date',
  'status': status,
  'estimatedDuration': 45,
  'exerciseCount': 7,
};

/// A plan as the server sends it: Monday done, today (Wednesday in the
/// later tests) open, one missed, later weeks ahead.
Map<String, dynamic> _planJson() => {
  'id': 'tpn_1',
  'name': '4-Week Strength Plan',
  'goal': 'gain_muscle',
  'targetAreas': ['chest', 'triceps'],
  'experience': 'intermediate',
  'environment': 'gym',
  'durationWeeks': 2,
  'daysPerWeek': 3,
  'sessionMinutes': 45,
  'status': 'active',
  'createdByType': 'fitflex',
  'startDate': '2026-10-05',
  'endDate': '2026-10-18',
  'weeks': [
    {
      'week': 1,
      'days': [
        _day('2026-10-05', 'Chest + Triceps', status: 'completed'),
        _day('2026-10-07', 'Lower Body', status: 'skipped'),
        _day('2026-10-09', 'Upper Body'),
      ],
    },
    {
      'week': 2,
      'days': [
        _day('2026-10-12', 'Chest + Triceps', workoutId: 'w_today'),
        _day('2026-10-14', 'Lower Body'),
        _day('2026-10-16', 'Full Body'),
      ],
    },
  ],
  'progress': {
    'sessions': 6,
    'completed': 1,
    'skipped': 1,
    'missed': 1,
    'completionRate': 0.17,
    'currentWeek': 2,
  },
};

class _FakeTraining implements TrainingRepository {
  _FakeTraining({this.prefs = const TrainingPreferences(), this.plan});

  TrainingPreferences prefs;
  TrainingPlan? plan;
  final calls = <(String, Object?)>[];
  final langs = <String?>[];
  bool externalPlan = false;
  bool fail = false;

  @override
  Future<TrainingPreferences> preferences() async => prefs;

  @override
  Future<TrainingPreferences> savePreferences(TrainingPreferences p) async {
    calls.add(('save', p.toJson()));
    return prefs = p;
  }

  @override
  Future<TrainingPlan?> currentPlan() async => plan;

  @override
  Future<TrainingPlan> generate({
    required int weeks,
    bool replace = false,
    String? lang,
  }) async {
    calls.add(('generate', (weeks, replace)));
    langs.add(lang);
    if (fail) throw ApiException(500, {'error': 'boom'});
    if (externalPlan && !replace) throw const ActivePlanExists();
    return plan = TrainingPlan.tryParse(_planJson())!;
  }

  @override
  Future<void> cancel(String planId) async {
    calls.add(('cancel', planId));
    plan = null;
  }

  List<TrainingPlanOffer> waiting = [];

  @override
  Future<List<TrainingPlanOffer>> offers() async => waiting;

  @override
  Future<TrainingPlan> accept(String offerId) async {
    calls.add(('accept', offerId));
    if (fail) throw ApiException(500, {'error': 'boom'});
    final json = _planJson()
      ..['createdByType'] = 'trainer'
      ..['name'] = 'Strength block'
      ..['trainer'] = {'id': 't1', 'displayName': 'Coach Amani'};
    return plan = TrainingPlan.tryParse(json)!;
  }

  @override
  Future<void> decline(String offerId) async {
    calls.add(('decline', offerId));
  }
}

Map<String, dynamic> _offerJson() => {
  'id': 'tpn_offer',
  'name': 'Strength block',
  'note': 'Go steady in week one.',
  'status': 'offered',
  'durationWeeks': 4,
  'daysPerWeek': 2,
  'startDate': '2026-10-12',
  'trainer': {'id': 't1', 'displayName': 'Coach Amani'},
  'weeks': [
    {
      'week': 1,
      'days': [
        {
          'day': 1,
          'date': '2026-10-12',
          'name': 'Push day',
          'estimatedDuration': 50,
          'exercises': [
            {'exerciseName': 'Bench Press', 'sets': 3, 'reps': 8},
            {'exerciseName': 'Plank', 'sets': 2, 'duration': 40},
          ],
        },
        {'day': 4, 'date': '2026-10-15', 'name': 'Leg day', 'exercises': []},
      ],
    },
  ],
};

Widget _app(
  Widget child, {
  required MemberData data,
  TrainingRepository? training,
  String lang = 'en',
}) {
  final api = ApiClient();
  return AppScope(
    api: api,
    auth: AuthState(api),
    trainingRepository: training,
    child: FFLocaleScope(
      notifier: FFLocale()..set(Locale(lang)),
      child: MaterialApp(
        theme: buildTheme(),
        locale: Locale(lang),
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

MemberData _data({TrainingPlan? plan, List<Workout> workouts = const []}) =>
    MemberData()
      ..trainingPlan = plan
      ..trainingLoaded = true
      ..workouts = workouts
      ..workoutsLoaded = true;

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 15000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('plan model', () {
    test('reads the plan the server sends', () {
      final plan = TrainingPlan.tryParse(_planJson())!;
      expect(plan.durationWeeks, 2);
      expect(plan.weeks.length, 2);
      expect(plan.days.length, 6);
      expect(plan.completed, 1);
      expect(plan.missed, 1);
      expect(plan.currentWeek, 2);
      expect(plan.completion, closeTo(1 / 6, 0.001));
      expect(plan.startDate, DateTime(2026, 10, 5));
      final first = plan.weeks.first.days.first;
      expect(first.isDone, isTrue);
      expect(first.focusAreas, ['chest', 'triceps']);
      // The next open session from today skips the one already missed.
      expect(plan.nextOpen(_now)!.date, DateTime(2026, 10, 12));
      expect(
        plan.nextOpen(DateTime(2026, 10, 13))!.date,
        DateTime(2026, 10, 14),
      );
      expect(plan.nextOpen(DateTime(2026, 10, 17)), isNull);
    });

    test('no plan, or a broken one, is null', () {
      expect(TrainingPlan.tryParse(null), isNull);
      expect(TrainingPlan.tryParse({'id': 'x'}), isNull);
    });

    test('preferences fall back to FitFlex defaults', () {
      final p = TrainingPreferences.fromJson({'goal': 'gain_muscle'});
      expect(p.goal, 'gain_muscle');
      expect(p.targetAreas, ['full_body']);
      expect(p.equipment, ['none']);
      expect(p.daysPerWeek, 3);
      expect(p.copyWith(daysPerWeek: 5).toJson()['daysPerWeek'], 5);
    });
  });

  group('sample mode', () {
    late LocalWorkoutRepository workouts;
    late LocalTrainingRepository repo;

    setUp(() {
      workouts = LocalWorkoutRepository(
        log: SampleActivityLog(),
        clock: () => _now,
      );
      repo = LocalTrainingRepository(workouts: workouts, clock: () => _now);
    });

    test('a plan lays workouts out across the weeks', () async {
      expect(await repo.currentPlan(), isNull);
      await repo.savePreferences(const TrainingPreferences(daysPerWeek: 4));
      final plan = await repo.generate(weeks: 2);
      expect(plan.sessions, 8);
      expect(plan.weeks.first.days.map((d) => d.date.day), [12, 13, 15, 17]);
      expect(plan.endDate, DateTime(2026, 10, 25));
      final listed = await workouts.list(
        from: plan.startDate,
        to: plan.endDate,
      );
      expect(listed.length, 8, reason: 'each session is an ordinary workout');
      expect(plan.nextOpen(_now)!.workoutId, isNotNull);
    });

    test('one plan at a time; stopping it clears the way', () async {
      final first = await repo.generate(weeks: 1);
      expect(() => repo.generate(weeks: 1), throwsA(isA<ActivePlanExists>()));
      final second = await repo.generate(weeks: 1, replace: true);
      expect(second.id, isNot(first.id));
      await repo.cancel(second.id);
      expect(await repo.currentPlan(), isNull);
    });
  });

  group('set-up screen', () {
    testWidgets('starts from the profile and makes the plan', (tester) async {
      await _tall(tester);
      final repo = _FakeTraining(
        prefs: const TrainingPreferences(
          goal: 'gain_muscle',
          experience: 'intermediate',
        ),
      );
      final data = _data();
      await tester.pumpWidget(
        _app(const MemberTrainingSetupPage(), data: data, training: repo),
      );
      await tester.pumpAndSettle();

      ChoiceChip chip(String key) => tester.widget(find.byKey(Key(key)));
      FilterChip filter(String key) => tester.widget(find.byKey(Key(key)));
      expect(chip('training-goal-gain_muscle').selected, isTrue);
      expect(chip('training-experience-intermediate').selected, isTrue);
      expect(filter('training-area-full_body').selected, isTrue);
      expect(filter('training-equipment-none').selected, isTrue);

      await tester.tap(find.byKey(const Key('training-area-chest')));
      await tester.tap(find.byKey(const Key('training-area-triceps')));
      await tester.tap(find.byKey(const Key('training-area-full_body')));
      await tester.tap(find.byKey(const Key('training-env-gym')));
      await tester.tap(find.byKey(const Key('training-minutes-45')));
      await tester.tap(find.byKey(const Key('training-days-4')));
      await tester.tap(find.byKey(const Key('training-weeks-6')));
      await tester.pump();
      expect(
        filter('training-equipment-full_gym').selected,
        isTrue,
        reason: 'a gym comes with its equipment',
      );

      await tester.tap(find.byKey(const Key('training-generate')));
      await tester.pumpAndSettle();
      final saved = repo.calls.firstWhere((c) => c.$1 == 'save').$2 as Map;
      expect(saved['goal'], 'gain_muscle');
      expect(saved['targetAreas'], ['chest', 'triceps']);
      expect(saved['environment'], 'gym');
      expect(saved['equipment'], ['full_gym']);
      expect(saved['sessionMinutes'], 45);
      expect(saved['daysPerWeek'], 4);
      expect(repo.calls.last, ('generate', (6, false)));
      expect(repo.langs.single, 'en', reason: 'names in the app language');
      expect(data.trainingPlan, isNotNull, reason: 'the plan is in place');
    });

    testWidgets('equipment and areas behave sensibly', (tester) async {
      await _tall(tester);
      final repo = _FakeTraining();
      await tester.pumpWidget(
        _app(const MemberTrainingSetupPage(), data: _data(), training: repo),
      );
      await tester.pumpAndSettle();
      FilterChip filter(String key) => tester.widget(find.byKey(Key(key)));

      await tester.tap(find.byKey(const Key('training-equipment-dumbbells')));
      await tester.pump();
      expect(filter('training-equipment-none').selected, isFalse);
      await tester.tap(find.byKey(const Key('training-equipment-none')));
      await tester.pump();
      expect(filter('training-equipment-dumbbells').selected, isFalse);

      // Clearing every area goes back to the whole body.
      await tester.tap(find.byKey(const Key('training-area-full_body')));
      await tester.pump();
      expect(filter('training-area-full_body').selected, isTrue);

      for (final a in ['chest', 'back', 'shoulders', 'biceps', 'triceps']) {
        await tester.tap(find.byKey(Key('training-area-$a')));
      }
      await tester.pump();
      await tester.tap(find.byKey(const Key('training-area-glutes')));
      await tester.pump();
      expect(find.text('Choose up to 6 areas.'), findsOneWidget);
      expect(filter('training-area-glutes').selected, isFalse);
    });

    testWidgets('asks before replacing the plan they are on', (tester) async {
      await _tall(tester);
      final existing = TrainingPlan.tryParse(_planJson())!;
      final repo = _FakeTraining(plan: existing);
      await tester.pumpWidget(
        _app(
          const MemberTrainingSetupPage(),
          data: _data(plan: existing),
          training: repo,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('training-generate')));
      await tester.pumpAndSettle();
      expect(find.text('Replace your current plan?'), findsOneWidget);
      await tester.tap(find.text('Keep my plan'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty, reason: 'nothing happens until they agree');

      await tester.tap(find.byKey(const Key('training-generate')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('training-replace-confirm')));
      await tester.pumpAndSettle();
      expect(repo.calls.last, ('generate', (4, true)));
    });

    testWidgets('a failure is said plainly and nothing is lost', (
      tester,
    ) async {
      await _tall(tester);
      final repo = _FakeTraining()..fail = true;
      final data = _data();
      await tester.pumpWidget(
        _app(const MemberTrainingSetupPage(), data: data, training: repo),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('training-days-5')));
      await tester.tap(find.byKey(const Key('training-generate')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('training-error')), findsOneWidget);
      expect(data.trainingPlan, isNull);
      final days = tester.widget<ChoiceChip>(
        find.byKey(const Key('training-days-5')),
      );
      expect(days.selected, isTrue, reason: 'their choices are still there');
    });
  });

  group('plan screen', () {
    testWidgets('shows every week with each session and its state', (
      tester,
    ) async {
      await _tall(tester);
      final plan = TrainingPlan.tryParse(_planJson())!;
      await tester.pumpWidget(
        _app(
          MemberTrainingPlanPage(now: _now),
          data: _data(plan: plan),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2-week plan'), findsOneWidget);
      expect(find.textContaining('Gain Muscle'), findsOneWidget);
      expect(find.text('Week 2 of 2 · 1 of 6 sessions done'), findsOneWidget);
      expect(find.text('Focus: Chest, Triceps'), findsOneWidget);
      expect(find.text('Week 1'), findsOneWidget);
      expect(find.text('Week 2 · this week'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Skipped'), findsOneWidget);
      expect(find.text('Missed'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Coming up'), findsNWidgets(2));
      expect(find.textContaining('7 exercises · 45 min'), findsNWidgets(6));
      expect(find.byKey(const Key('training-day-2026-10-12')), findsOneWidget);
      // Every session opens, however far ahead it is.
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(6));
    });

    testWidgets('stopping the plan asks first', (tester) async {
      await _tall(tester);
      final plan = TrainingPlan.tryParse(_planJson())!;
      final repo = _FakeTraining(plan: plan);
      final data = _data(plan: plan);
      await tester.pumpWidget(
        _app(
          MemberTrainingPlanPage(now: _now),
          data: data,
          training: repo,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('training-plan-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('training-stop')));
      await tester.pumpAndSettle();
      expect(find.textContaining('stay in your history'), findsOneWidget);
      await tester.tap(find.byKey(const Key('training-stop-confirm')));
      await tester.pumpAndSettle();
      expect(repo.calls.single, ('cancel', 'tpn_1'));
      expect(data.trainingPlan, isNull);
      expect(find.byKey(const Key('training-plan-empty')), findsOneWidget);
    });

    testWidgets('reads in Swahili', (tester) async {
      await _tall(tester);
      final plan = TrainingPlan.tryParse(_planJson())!;
      await tester.pumpWidget(
        _app(
          MemberTrainingPlanPage(now: _now),
          data: _data(plan: plan),
          lang: 'sw',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mpango wa wiki 2'), findsOneWidget);
      expect(find.text('Wiki ya 2 · wiki hii'), findsOneWidget);
      expect(find.text('Kimekamilika'), findsOneWidget);
    });
  });

  group('Activity tab cards', () {
    testWidgets('no plan: an invitation to have one made', (tester) async {
      await tester.pumpWidget(
        _app(
          TrainingPlanCard(data: _data(), now: _now),
          data: _data(),
        ),
      );
      expect(find.byKey(const Key('training-none')), findsOneWidget);
      expect(find.text('Create my plan'), findsOneWidget);
    });

    testWidgets('on a plan: progress and what is next', (tester) async {
      final plan = TrainingPlan.tryParse(_planJson())!;
      final data = _data(plan: plan);
      await tester.pumpWidget(
        _app(
          TrainingPlanCard(data: data, now: _now),
          data: data,
        ),
      );
      expect(find.text('Week 2 of 2 · 1 of 6 sessions done'), findsOneWidget);
      expect(find.text('Today: Chest + Triceps'), findsOneWidget);

      final tuesday = DateTime(2026, 10, 13);
      await tester.pumpWidget(
        _app(
          TrainingPlanCard(data: data, now: tuesday),
          data: data,
        ),
      );
      expect(find.text('Next: Wed 14 Oct · Lower Body'), findsOneWidget);
    });

    testWidgets('a day without a session is a recovery day', (tester) async {
      final plan = TrainingPlan.tryParse(_planJson())!;
      final data = _data(plan: plan);
      await tester.pumpWidget(
        _app(
          TodayWorkoutCard(data: data, now: DateTime(2026, 10, 13)),
          data: data,
        ),
      );
      expect(find.text('Recovery day'), findsOneWidget);
      expect(find.text('Your next workout is on Wed 14 Oct.'), findsOneWidget);
      expect(find.byKey(const Key('today-view-plan')), findsOneWidget);

      // Without a plan the card still invites them to plan a workout.
      final none = _data();
      await tester.pumpWidget(
        _app(
          TodayWorkoutCard(data: none, now: _now),
          data: none,
        ),
      );
      expect(find.byKey(const Key('today-workout-empty')), findsOneWidget);
    });
  });

  testWidgets('a plan made in Swahili asks for Swahili names', (tester) async {
    await _tall(tester);
    final repo = _FakeTraining();
    await tester.pumpWidget(
      _app(
        const MemberTrainingSetupPage(),
        data: _data(),
        training: repo,
        lang: 'sw',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mpango wako wa mazoezi'), findsOneWidget);
    await tester.tap(find.byKey(const Key('training-generate')));
    await tester.pumpAndSettle();
    expect(repo.langs.single, 'sw');
  });

  testWidgets('Progress shows how far through the plan they are', (
    tester,
  ) async {
    await _tall(tester);
    final plan = TrainingPlan.tryParse(_planJson())!;
    final data = _data(plan: plan)..activityIsSample = true;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) =>
              ListView(children: buildProgressSection(context, data, _now)),
        ),
        data: data,
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('progress-training')), findsOneWidget);
    expect(find.text('2-week plan · Gain Muscle'), findsOneWidget);
    expect(find.text('Week 2 of 2 · 1 of 6 sessions done'), findsOneWidget);
    expect(find.text('1 skipped · 1 missed'), findsOneWidget);

    // No plan, no block.
    final none = _data()..activityIsSample = true;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) =>
              ListView(children: buildProgressSection(context, none, _now)),
        ),
        data: none,
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('progress-training')), findsNothing);
  });

  testWidgets('plan exercises name their area in words', (tester) async {
    late String quads, legacy, unknown;
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) {
            quads = muscleLabel(context, 'quadriceps');
            legacy = muscleLabel(context, 'arms');
            unknown = muscleLabel(context, 'left_elbow');
            return const SizedBox();
          },
        ),
        data: _data(),
      ),
    );
    expect(quads, 'Quadriceps');
    expect(legacy, 'Arms');
    expect(unknown, 'left elbow');
  });

  group("a trainer's plan offer", () {
    test('reads the offer the server sends', () {
      final o = TrainingPlanOffer.tryParse(_offerJson())!;
      expect(o.trainerName, 'Coach Amani');
      expect(o.durationWeeks, 4);
      expect(o.firstWeek.map((s) => (s.day, s.name)), [
        (1, 'Push day'),
        (4, 'Leg day'),
      ]);
      expect(o.firstWeek.first.exercises, [
        'Bench Press 3 × 8',
        'Plank 2 × 40 s',
      ]);
      expect(TrainingPlanOffer.tryParse({'name': 'x'}), isNull);
    });

    testWidgets('look inside, then accept: it replaces the plan they are on', (
      tester,
    ) async {
      await _tall(tester);
      final offer = TrainingPlanOffer.tryParse(_offerJson())!;
      final own = TrainingPlan.tryParse(_planJson())!;
      final repo = _FakeTraining(plan: own)..waiting = [offer];
      final data = _data(plan: own)..trainingOffers = [offer];
      await tester.pumpWidget(
        _app(
          ListenableBuilder(
            listenable: data,
            builder: (context, _) => ListView(
              children: [
                for (final o in data.trainingOffers)
                  TrainingOfferCard(offer: o),
                TrainingPlanCard(data: data, now: _now),
              ],
            ),
          ),
          data: data,
          training: repo,
        ),
      );
      expect(find.text('Coach Amani made you a plan'), findsOneWidget);
      expect(
        find.text('Strength block · 4 weeks · 2 days a week'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('training-offer-open-tpn_offer')));
      await tester.pumpAndSettle();
      expect(find.text('Go steady in week one.'), findsOneWidget);
      expect(find.text('Monday · Push day · 50 min'), findsOneWidget);
      expect(find.text('Bench Press 3 × 8'), findsOneWidget);
      expect(find.text('Thursday · Leg day'), findsOneWidget);
      expect(find.textContaining('Nothing changes until you accept'), findsOne);

      await tester.tap(find.byKey(const Key('offer-accept')));
      await tester.pumpAndSettle();
      expect(find.text('Replace your current plan?'), findsOneWidget);
      expect(repo.calls, isEmpty, reason: 'not before they confirm');
      await tester.tap(find.byKey(const Key('offer-replace-confirm')));
      await tester.pumpAndSettle();
      expect(repo.calls.single, ('accept', 'tpn_offer'));
      expect(data.trainingOffers, isEmpty);
      expect(data.trainingPlan!.fromTrainer, isTrue);
      expect(find.byKey(const Key('offer-sheet')), findsNothing);
      expect(find.text('From Coach Amani'), findsOneWidget);
      expect(find.text('This is now your plan.'), findsOneWidget);
    });

    testWidgets('declining changes nothing of theirs', (tester) async {
      await _tall(tester);
      final offer = TrainingPlanOffer.tryParse(_offerJson())!;
      final own = TrainingPlan.tryParse(_planJson())!;
      final repo = _FakeTraining(plan: own)..waiting = [offer];
      final data = _data(plan: own)..trainingOffers = [offer];
      await tester.pumpWidget(
        _app(
          ListenableBuilder(
            listenable: data,
            builder: (context, _) => ListView(
              children: [
                for (final o in data.trainingOffers)
                  TrainingOfferCard(offer: o),
              ],
            ),
          ),
          data: data,
          training: repo,
        ),
      );
      await tester.tap(find.byKey(const Key('training-offer-open-tpn_offer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('offer-decline')));
      await tester.pumpAndSettle();
      expect(repo.calls.single, ('decline', 'tpn_offer'));
      expect(data.trainingPlan!.id, own.id);
      expect(data.trainingOffers, isEmpty);
      expect(find.text('Plan declined.'), findsOneWidget);
    });

    testWidgets('a failed accept keeps the offer open and says so', (
      tester,
    ) async {
      await _tall(tester);
      final offer = TrainingPlanOffer.tryParse(_offerJson())!;
      final repo = _FakeTraining()..fail = true;
      final data = _data()..trainingOffers = [offer];
      await tester.pumpWidget(
        _app(
          TrainingOfferCard(offer: offer),
          data: data,
          training: repo,
        ),
      );
      await tester.tap(find.byKey(const Key('training-offer-open-tpn_offer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('offer-accept')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offer-error')), findsOneWidget);
      expect(data.trainingOffers.length, 1);
      expect(data.trainingPlan, isNull);
    });
  });

  group('notifications lead to the plan', () {
    test('each plan message knows where it goes', () {
      String? route(String type, {String? planId}) =>
          memberRouteFor(deepLink: '', type: type, planId: planId);
      expect(
        route('training_plan_offered', planId: 'tpn_offer'),
        '/member/activity/training/offers/tpn_offer',
      );
      expect(route('training_plan_updated'), '/member/activity/training');
      expect(route('training_plan_stopped'), '/member/activity/training');
      // No plan, or an id that isn't one: the message is shown instead.
      expect(route('training_plan_offered'), isNull);
      expect(route('training_plan_offered', planId: '../../admin'), isNull);
      // Messages meant for the trainer lead nowhere on a member's phone.
      expect(route('training_plan_accepted', planId: 'tpn_offer'), isNull);

      expect(opensScreenDirectly('training_plan_offered'), isTrue);
      expect(opensScreenDirectly('training_plan_updated'), isTrue);
      expect(opensScreenDirectly('trainer_enquiry_reply'), isFalse);
      expect(opensScreenDirectly('subscription_renewal'), isFalse);
      // A campaign's own link still wins over the type.
      expect(
        memberLinkFor(deepLink: 'payment', type: 'training_plan_offered'),
        'payment',
      );
    });

    testWidgets('the button on each message says where it leads', (
      tester,
    ) async {
      final labels = <String, String>{};
      InboxMessage message(String type, {String? link}) => InboxMessage(
        id: 'n',
        type: type,
        title: '',
        body: '',
        data: {'deepLink': ?link},
      );
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              for (final t in [
                'training_plan_offered',
                'training_plan_updated',
                'trainer_enquiry_reply',
                'subscription_renewal',
                'something_else',
              ]) {
                labels[t] = inboxButtonLabel(context, message(t));
              }
              labels['campaign'] = inboxButtonLabel(
                context,
                message('campaign', link: 'renewal'),
              );
              return const SizedBox();
            },
          ),
          data: _data(),
        ),
      );
      expect(labels['training_plan_offered'], 'View the plan');
      expect(labels['training_plan_updated'], 'View my plan');
      expect(labels['trainer_enquiry_reply'], 'View trainer');
      expect(labels['subscription_renewal'], 'View membership');
      expect(labels['campaign'], 'Renew membership');
      expect(labels['something_else'], 'Open');
    });

    testWidgets('the offer opens on a page of its own and can be answered', (
      tester,
    ) async {
      await _tall(tester);
      final offer = TrainingPlanOffer.tryParse(_offerJson())!;
      final repo = _FakeTraining()..waiting = [offer];
      final data = _data()..trainingOffers = [offer];
      await tester.pumpWidget(
        _app(
          const MemberTrainingOfferPage(offerId: 'tpn_offer'),
          data: data,
          training: repo,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('training-back')), findsOneWidget);
      expect(find.text('Strength block'), findsOneWidget);
      expect(find.text('Go steady in week one.'), findsOneWidget);
      expect(find.text('Monday · Push day · 50 min'), findsOneWidget);

      await tester.tap(find.byKey(const Key('offer-accept')));
      await tester.pumpAndSettle();
      expect(repo.calls.single, ('accept', 'tpn_offer'));
      expect(data.trainingPlan!.fromTrainer, isTrue);
      expect(data.trainingOffers, isEmpty);
    });

    testWidgets('an offer that is no longer waiting says so', (tester) async {
      await _tall(tester);
      final data = _data();
      await tester.pumpWidget(
        _app(const MemberTrainingOfferPage(offerId: 'tpn_offer'), data: data),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('offer-gone')), findsOneWidget);
      expect(
        find.text('This plan is no longer waiting for your answer'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('offer-accept')), findsNothing);
      expect(find.byKey(const Key('offer-gone-plan')), findsOneWidget);

      // Already accepted (the notification was opened a second time).
      final json = _planJson()..['id'] = 'tpn_offer';
      final mine = _data(plan: TrainingPlan.tryParse(json));
      await tester.pumpWidget(
        _app(const MemberTrainingOfferPage(offerId: 'tpn_offer'), data: mine),
      );
      await tester.pumpAndSettle();
      expect(find.text('You are already on this plan'), findsOneWidget);
    });
  });

  test('every training line exists in English and Swahili', () {
    final en = FFLocale.keysOf('en').where((k) => k.startsWith('training.'));
    final sw = FFLocale.keysOf('sw').where((k) => k.startsWith('training.'));
    expect(en.length, greaterThan(60));
    expect(sw.toSet(), en.toSet());
    for (final g in trainingGoals) {
      expect(FFLocale.keysOf('sw'), contains('onboarding.goal_$g'));
    }
    for (final a in trainingAreaGroups.values.expand((x) => x)) {
      expect(FFLocale.keysOf('en'), contains('training.area.$a'));
    }
  });
}
