// Programmes P1 (M1): the catalogue, a programme's detail and starting it,
// and the ways in that only show when the server offers programmes.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_programme_summary_page.dart';
import 'package:fitflexmobile/screens/member/member_programmes_page.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/programme_widgets.dart';
import 'package:fitflexmobile/shared/activity/programme.dart';
import 'package:fitflexmobile/shared/activity/training_plan.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Map<String, dynamic> _programmeJson({String id = 'prg_1', bool days = true}) =>
    {
      'id': id,
      'title': '7-day home starter',
      'summary': 'Build the habit.',
      'goal': 'stay_fit',
      'level': 'beginner',
      'environment': 'home',
      'equipment': ['none'],
      'lengthDays': 7,
      'dayTypes': ['home', 'rest', 'gym', 'home', 'rest', 'gym', 'home'],
      'free': true,
      if (days)
        'days': [
          {
            'day': 1,
            'type': 'home',
            'workout': {
              'name': 'Legs at home',
              'estimatedDuration': 20,
              'exerciseCount': 4,
            },
          },
          {'day': 2, 'type': 'rest', 'workout': null},
          {'day': 3, 'type': 'gym', 'workout': null},
          {
            'day': 4,
            'type': 'home',
            'workout': {
              'name': 'Core',
              'estimatedDuration': 15,
              'exerciseCount': 3,
            },
          },
          {'day': 5, 'type': 'rest', 'workout': null},
          {
            'day': 6,
            'type': 'gym',
            'workout': {
              'name': 'Suggested',
              'estimatedDuration': 30,
              'exerciseCount': 5,
            },
          },
          {
            'day': 7,
            'type': 'home',
            'workout': {
              'name': 'Full body',
              'estimatedDuration': 25,
              'exerciseCount': 5,
            },
          },
        ],
    };

TrainingPlan _plan({
  String? programmeId,
  String createdBy = 'fitflex',
  String name = '',
}) => TrainingPlan.tryParse({
  'id': 'tpl_current',
  'name': name,
  'createdByType': createdBy,
  if (createdBy == 'trainer') 'trainer': {'displayName': 'Coach Amani'},
  'programmeId': ?programmeId,
  'lengthDays': 7,
  'durationWeeks': 1,
  'startDate': '2026-11-20',
  'endDate': '2026-11-26',
  'progress': {'currentDay': 3},
})!;

class _Fake implements ProgrammeRepository {
  _Fake({this.disabled = false, this.exists = false, this.refuse});

  bool disabled;
  bool exists;
  String? refuse;
  List<Map<String, dynamic>> rows = [_programmeJson(days: false)];
  final catalogueCalls = <Map<String, String>>[];
  final starts = <(String, String?, bool)>[];

  @override
  Future<List<Programme>> catalogue({
    ProgrammeFilters filters = const ProgrammeFilters(),
    String? lang,
  }) async {
    if (disabled) throw const ProgrammesDisabled();
    catalogueCalls.add(filters.toQuery());
    final goal = filters.goal;
    return [
      for (final r in rows)
        if (goal == null || r['goal'] == goal) Programme.tryParse(r)!,
    ];
  }

  /// Ids that answer as retired.
  final gone = <String>{};

  @override
  Future<Programme> programme(String id, {String? lang}) async {
    if (disabled) throw const ProgrammesDisabled();
    if (gone.contains(id)) throw const ProgrammeUnavailable();
    return Programme.tryParse({
      ..._programmeJson(id: id),
      if (id != 'prg_1') 'title': 'Programme $id',
    })!;
  }

  @override
  Future<TrainingPlan> start(
    String id, {
    DateTime? startDate,
    bool replace = false,
    String? lang,
  }) async {
    final d = startDate?.toIso8601String().substring(0, 10);
    starts.add((id, d, replace));
    if (refuse != null) throw ProgrammeStartRefused(refuse!);
    if (exists && !replace) {
      throw const ProgrammePlanExists(planId: 'tpl_current');
    }
    return _plan(programmeId: id);
  }

  TrainingPlan? finishedPlan;

  @override
  Future<TrainingPlan?> finished({
    DateTime? now,
    Duration within = const Duration(days: 30),
  }) async => finishedPlan;
}

Widget _app(
  _Fake repo, {
  required String at,
  TrainingPlan? plan,
  Widget? home,
}) {
  final data = MemberData()
    ..trainingPlan = plan
    ..trainingLoaded = true
    ..workoutsLoaded = true;
  Widget page(Widget child) => Scaffold(
    body: MemberDataScope(data: data, child: child),
  );
  final router = GoRouter(
    initialLocation: at,
    routes: [
      GoRoute(path: '/', builder: (_, _) => page(home ?? const SizedBox())),
      GoRoute(
        path: '/member/activity/training',
        builder: (_, _) => page(const Text('plan-page')),
        routes: [
          GoRoute(
            path: 'summary',
            builder: (_, _) => page(const MemberProgrammeSummaryPage()),
          ),
          GoRoute(
            path: 'programmes',
            builder: (_, s) => page(
              MemberProgrammesPage(initialGoal: s.uri.queryParameters['goal']),
            ),
            routes: [
              GoRoute(
                path: ':programmeId',
                builder: (_, s) => page(
                  MemberProgrammePage(
                    programmeId: s.pathParameters['programmeId']!,
                    now: DateTime(2026, 11, 23, 9),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  final api = ApiClient();
  return AppScope(
    api: api,
    auth: AuthState(api),
    programmeRepository: repo,
    child: FFLocaleScope(
      notifier: FFLocale()..set(const Locale('en')),
      child: MaterialApp.router(
        theme: buildTheme(),
        routerConfig: router,
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('sw')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
      ),
    ),
  );
}

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  group('model', () {
    test('reads a programme and its days', () {
      final p = Programme.tryParse(_programmeJson())!;
      expect(p.days.length, 7);
      expect(p.count('gym'), 2);
      expect(p.count('rest'), 2);
      expect(p.needs, isEmpty);
      expect(p.days[2].hasWorkout, isFalse);
      expect(p.days[0].workoutName, 'Legs at home');
    });
    test('filters become the query the server reads', () {
      expect(
        const ProgrammeFilters(
          goal: 'stay_fit',
          length: 14,
          where: 'home',
        ).toQuery(lang: 'sw'),
        {
          'goal': 'stay_fit',
          'environment': 'home',
          'minDays': '14',
          'maxDays': '14',
          'lang': 'sw',
        },
      );
      expect(const ProgrammeFilters(length: 28).toQuery(), {'minDays': '28'});
    });
    test('a plan knows it came from a programme', () {
      final plan = _plan(programmeId: 'prg_1');
      expect(plan.isProgramme, isTrue);
      expect(plan.currentDay, 3);
      expect(plan.lengthDays, 7);
      expect(_plan().isProgramme, isFalse);
    });
  });

  testWidgets('the catalogue lists programmes and filters them', (
    tester,
  ) async {
    await _tall(tester);
    final repo = _Fake()
      ..rows.add({
        ..._programmeJson(id: 'prg_2', days: false),
        'title': 'Lose it',
        'goal': 'lose_weight',
      });
    await tester.pumpWidget(
      _app(repo, at: '/member/activity/training/programmes'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('programme-card-prg_1')), findsOneWidget);
    expect(find.text('7 days · Beginner · Home'), findsWidgets);
    expect(find.text('Free'), findsWidgets);

    await tester.tap(find.byKey(const Key('programmes-filter-goal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('programmes-option-lose_weight')));
    await tester.pumpAndSettle();
    expect(repo.catalogueCalls.last['goal'], 'lose_weight');
    expect(find.byKey(const Key('programme-card-prg_1')), findsNothing);
    expect(find.byKey(const Key('programme-card-prg_2')), findsOneWidget);

    repo.rows.clear();
    await tester.tap(find.byKey(const Key('programmes-filter-level')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('programmes-option-advanced')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('programmes-no-match')), findsOneWidget);
    await tester.tap(find.byKey(const Key('programmes-clear-filters')));
    await tester.pumpAndSettle();
    expect(repo.catalogueCalls.last, isEmpty);
    expect(find.byKey(const Key('programmes-empty')), findsOneWidget);
  });

  testWidgets('with programmes off the catalogue says not available', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_Fake(disabled: true), at: '/member/activity/training/programmes'),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('programmes-not-available')), findsOneWidget);
  });

  testWidgets('the detail shows the day mix and starts the programme today', (
    tester,
  ) async {
    await _tall(tester);
    final repo = _Fake();
    await tester.pumpWidget(
      _app(repo, at: '/member/activity/training/programmes/prg_1'),
    );
    await tester.pumpAndSettle();
    expect(find.text('No equipment'), findsOneWidget);
    expect(find.text('Check in at any FitFlex gym'), findsOneWidget);
    expect(find.text('Suggested · ~30 min'), findsOneWidget);

    await tester.tap(find.byKey(const Key('programme-start')));
    await tester.pumpAndSettle();
    expect(find.text('Ends on Sun 29 Nov 2026.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('programme-start-go')));
    await tester.pumpAndSettle();
    expect(repo.starts, [('prg_1', '2026-11-23', false)]);
    expect(find.text('plan-page'), findsOneWidget);
    expect(find.text('Programme started'), findsOneWidget);
  });

  testWidgets('a member on a trainer plan is asked before it is replaced', (
    tester,
  ) async {
    await _tall(tester);
    final repo = _Fake(exists: true);
    await tester.pumpWidget(
      _app(
        repo,
        at: '/member/activity/training/programmes/prg_1',
        plan: _plan(createdBy: 'trainer', name: 'Strength block'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('programme-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomorrow'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('programme-start-go')));
    // The button spins while the question is open: pump, don't settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining("You're on Strength block."), findsOneWidget);
    expect(
      find.textContaining('This plan was made by Coach Amani.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('programme-replace-keep')));
    await tester.pumpAndSettle();
    expect(repo.starts, [('prg_1', '2026-11-24', false)]);

    // Keeping the plan closes the sheet; nothing else happens.
    expect(find.byKey(const Key('programme-start-go')), findsNothing);
    await tester.tap(find.byKey(const Key('programme-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomorrow'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('programme-start-go')));
    // The button spins while the question is open: pump, don't settle.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const Key('programme-replace-confirm')));
    await tester.pumpAndSettle();
    expect(repo.starts.last, ('prg_1', '2026-11-24', true));
    expect(find.text('plan-page'), findsOneWidget);
  });

  testWidgets('a refused start date is said under the picker', (tester) async {
    await _tall(tester);
    await tester.pumpWidget(
      _app(
        _Fake(refuse: 'start_too_far'),
        at: '/member/activity/training/programmes/prg_1',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('programme-start')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('programme-start-go')));
    await tester.pumpAndSettle();
    expect(
      find.text('Pick a start date within the next 30 days.'),
      findsOneWidget,
    );
  });

  testWidgets('on this programme already, the button goes to the plan', (
    tester,
  ) async {
    await _tall(tester);
    final repo = _Fake();
    await tester.pumpWidget(
      _app(
        repo,
        at: '/member/activity/training/programmes/prg_1',
        plan: _plan(programmeId: 'prg_1'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Go to my programme'), findsOneWidget);
    await tester.tap(find.byKey(const Key('programme-start')));
    await tester.pumpAndSettle();
    expect(repo.starts, isEmpty);
    expect(find.text('plan-page'), findsOneWidget);
  });

  testWidgets(
    'the Programmes tile shows only when the server offers programmes',
    (tester) async {
      await tester.pumpWidget(
        _app(_Fake(disabled: true), at: '/', home: const ProgrammesTile()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('programmes-tile')), findsNothing);

      await tester.pumpWidget(
        _app(_Fake(), at: '/', home: const ProgrammesTile()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('programmes-tile')), findsOneWidget);
      await tester.tap(find.byKey(const Key('programmes-tile')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('programmes-scroll')), findsOneWidget);
    },
  );

  test('every programmes string has a marked Swahili placeholder', () {
    final keys = FFLocale.keysOf(
      'en',
    ).where((k) => k.startsWith('programmes.'));
    expect(keys.length, greaterThan(40));
    for (final k in keys) {
      expect(FFLocale.textOf('sw', k), startsWith('[SW-PENDING] '), reason: k);
    }
  });

  TrainingPlan finishedPlan({int completed = 4}) => TrainingPlan.tryParse({
    'id': 'tpl_done',
    'name': '7-day home starter',
    'goal': 'lose_weight',
    'programmeId': 'prg_1',
    'status': 'completed',
    'lengthDays': 7,
    'durationWeeks': 1,
    'startDate': '2026-11-10',
    'endDate': '2026-11-16',
    'progress': {
      'sessions': 5,
      'completed': completed,
      'byWorkout': 3,
      'byCheckin': completed > 3 ? completed - 3 : 0,
      'bestStreak': 3,
    },
  })!;

  testWidgets('the summary says what was done and finds the next programme', (
    tester,
  ) async {
    await _tall(tester);
    final repo = _Fake()..finishedPlan = finishedPlan();
    await tester.pumpWidget(
      _app(repo, at: '/member/activity/training/summary'),
    );
    await tester.pumpAndSettle();
    expect(find.text('You finished 7-day home starter!'), findsOneWidget);
    expect(find.text('4/5'), findsOneWidget);
    expect(find.text('Best streak'), findsOneWidget);
    await tester.tap(find.byKey(const Key('summary-next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('programmes-scroll')), findsOneWidget);
    expect(repo.catalogueCalls.last['goal'], 'lose_weight');
  });

  testWidgets('under half done, the summary says the programme has ended', (
    tester,
  ) async {
    await _tall(tester);
    final repo = _Fake()..finishedPlan = finishedPlan(completed: 2);
    await tester.pumpWidget(
      _app(repo, at: '/member/activity/training/summary'),
    );
    await tester.pumpAndSettle();
    expect(find.text('7-day home starter has ended'), findsOneWidget);
  });

  testWidgets('the summary card shows only after a programme ended', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_Fake(), at: '/', home: const ProgrammeSummaryCard()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('programme-summary-card')), findsNothing);
    await tester.pumpWidget(
      _app(
        _Fake()..finishedPlan = finishedPlan(),
        at: '/',
        home: const ProgrammeSummaryCard(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('programme-summary-card')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('summary-stats')), findsOneWidget);
  });

  // UAT 2026-11-24 D-2: the same page shown for another id starts over.
  testWidgets('the detail page reloads when its programme id changes', (
    tester,
  ) async {
    await _tall(tester);
    final repo = _Fake()..gone.add('prg_gone');
    final id = ValueNotifier('prg_gone');
    addTearDown(id.dispose);
    await tester.pumpWidget(
      _app(
        repo,
        at: '/',
        home: ValueListenableBuilder<String>(
          valueListenable: id,
          builder: (_, v, _) =>
              MemberProgrammePage(programmeId: v, now: DateTime(2026, 11, 23)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('programme-not-available')), findsOneWidget);

    id.value = 'prg_2';
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('programme-not-available')), findsNothing);
    expect(find.text('Programme prg_2'), findsOneWidget);
  });

  // UAT 2026-11-24 D-4: the three stat tiles line up.
  testWidgets('the detail stat tiles are the same height and aligned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(_Fake(), at: '/member/activity/training/programmes/prg_1'),
    );
    await tester.pumpAndSettle();
    final rects = [
      for (final t in ['gym', 'home', 'rest'])
        tester.getRect(find.byKey(Key('programme-stat-$t'))),
    ];
    for (final r in rects.skip(1)) {
      expect(r.top, rects.first.top);
      expect(r.height, rects.first.height);
    }
  });

  // UAT 2026-11-24 D-4: Clear stays on screen on a narrow phone.
  testWidgets('Clear stays in view on a 375 px phone', (tester) async {
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final repo = _Fake();
    await tester.pumpWidget(
      _app(repo, at: '/member/activity/training/programmes'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('programmes-filter-length')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('programmes-option-14')));
    await tester.pumpAndSettle();
    final clear = tester.getRect(find.byKey(const Key('programmes-clear')));
    expect(clear.right, lessThanOrEqualTo(375));
    await tester.tap(find.byKey(const Key('programmes-clear')));
    await tester.pumpAndSettle();
    expect(repo.catalogueCalls.last, isEmpty);
  });
}
