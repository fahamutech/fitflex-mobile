import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/trainer_sharing.dart';
import 'package:fitflexmobile/screens/member/widgets/workout_widgets.dart';
import 'package:fitflexmobile/screens/trainer/trainer_client_page.dart';
import 'package:fitflexmobile/screens/trainer/trainer_clients_tab.dart';
import 'package:fitflexmobile/screens/trainer/trainer_plan_editor_page.dart';
import 'package:fitflexmobile/shared/activity/trainer_connection.dart';
import 'package:fitflexmobile/shared/activity/workout.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 24, 9);

Widget _app(ApiClient api, Widget child, {MemberData? data}) => AppScope(
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
      home: Scaffold(
        body: data == null ? child : MemberDataScope(data: data, child: child),
      ),
    ),
  ),
);

Map<String, dynamic> _connectionJson({
  String status = 'pending',
  Map<String, bool> permissions = const {},
}) => {
  'id': 'tmr_1',
  'trainerId': 'trn_1',
  'memberId': 'm1',
  'status': status,
  'permissions': permissions,
  'requestedAt': '2026-09-24T06:00:00.000Z',
  'trainer': {'id': 'trn_1', 'displayName': 'Coach Amani'},
  'member': {'id': 'm1', 'displayName': 'Amina'},
};

class _FakeApi extends ApiClient {
  final calls = <(String, Object?)>[];
  List<Map<String, dynamic>> clients = [];
  List<Map<String, dynamic>> plans = [];
  Map<String, dynamic> overview = {};

  @override
  Future<Map<String, dynamic>> requestTrainerConnection(
    String trainerId,
    Map<String, bool> permissions,
  ) async {
    calls.add(('request', {'trainerId': trainerId, ...permissions}));
    return {'connection': _connectionJson(permissions: permissions)};
  }

  @override
  Future<Map<String, dynamic>> updateTrainerConnection(
    String id,
    Map<String, bool> permissions,
  ) async {
    calls.add(('update', permissions));
    return {'connection': _connectionJson(permissions: permissions)};
  }

  @override
  Future<Map<String, dynamic>> endTrainerConnection(String id) async {
    calls.add(('end', id));
    return {};
  }

  @override
  Future<List<dynamic>> trainerClients() async => clients;

  @override
  Future<List<dynamic>> trainerPlans() async => plans;

  @override
  Future<Map<String, dynamic>> trainerDecideClient(
    String id, {
    required bool accept,
  }) async {
    calls.add((accept ? 'accept' : 'decline', id));
    clients = [
      {...clients.first, 'status': accept ? 'active' : 'declined'},
    ];
    return {};
  }

  @override
  Future<Map<String, dynamic>> trainerClientOverview(String id) async =>
      overview;

  @override
  Future<Map<String, dynamic>> trainerAssignWorkout(
    String clientId,
    Map<String, dynamic> data,
  ) async {
    calls.add(('assign', data));
    return {'workouts': []};
  }

  @override
  Future<Map<String, dynamic>> trainerSavePlan(
    String? id,
    Map<String, dynamic> plan,
  ) async {
    calls.add(('savePlan', plan));
    return {'plan': plan};
  }
}

void main() {
  group('permissions', () {
    test(
      'parse defaults to nothing shared; toggling keeps details with history',
      () {
        expect(TrainerPermissions.fromJson(null).isEmpty, isTrue);
        var p = TrainerPermissions.fromJson({'steps': true, 'goals': 'yes'});
        expect(p.granted, {TrainerPermission.steps});
        p = p.toggle(TrainerPermission.workoutDetails, true);
        expect(p.has(TrainerPermission.workoutHistory), isTrue);
        p = p.toggle(TrainerPermission.workoutHistory, false);
        expect(p.has(TrainerPermission.workoutDetails), isFalse);
        expect(p.toJson().length, 8);
        expect(p.toJson()['steps'], isTrue);
      },
    );

    test('overview leaves unshared sections null', () {
      final o = ClientOverview.fromJson({
        'client': _connectionJson(status: 'active'),
        'workouts': [
          {
            'id': 'w',
            'name': 'Legs',
            'scheduledDate': '2026-09-25',
            'assignedByYou': true,
          },
        ],
      });
      expect(o.activity, isNull);
      expect(o.goals, isNull);
      expect(o.streaks, isNull);
      expect(o.workouts.single.status, isNull);
      expect(o.client.member?.displayName, 'Amina');
    });
  });

  group('member', () {
    testWidgets('Connect sends a request sharing only what was switched on', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final api = _FakeApi();
      final data = MemberData();
      await tester.pumpWidget(
        _app(
          api,
          const TrainerConnectCard(
            trainerId: 'trn_1',
            trainerName: 'Coach Amani',
          ),
          data: data,
        ),
      );
      expect(find.text('Train with Coach Amani'), findsOneWidget);
      await tester.tap(find.byKey(const Key('trainer-connect')));
      await tester.pumpAndSettle();

      // Everything starts off.
      final sheetList = find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(Scrollable),
      );
      for (final p in TrainerPermission.values) {
        final f = find.byKey(Key('share-${p.wire}'));
        await tester.scrollUntilVisible(f, 60, scrollable: sheetList);
        expect(tester.widget<SwitchListTile>(f).value, isFalse, reason: p.wire);
      }
      await tester.scrollUntilVisible(
        find.byKey(const Key('share-workoutHistory')),
        -60,
        scrollable: sheetList,
      );
      await tester.tap(find.byKey(const Key('share-workoutHistory')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('share-save')));
      await tester.pumpAndSettle();

      final (op, payload) = api.calls.single;
      expect(op, 'request');
      expect((payload as Map)['trainerId'], 'trn_1');
      expect(payload['workoutHistory'], isTrue);
      expect(payload['steps'], isFalse);
      expect(payload['workoutDetails'], isFalse);
    });

    testWidgets('An open connection shows what is shared instead of Connect', (
      tester,
    ) async {
      final data = MemberData()
        ..trainerConnections = [
          TrainerConnection.fromJson(
            _connectionJson(permissions: {'steps': true, 'goals': true}),
          ),
        ];
      await tester.pumpWidget(
        _app(
          _FakeApi(),
          const TrainerConnectCard(
            trainerId: 'trn_1',
            trainerName: 'Coach Amani',
          ),
          data: data,
        ),
      );
      expect(find.text('Request sent'), findsOneWidget);
      expect(find.text('Can see: Steps, Goals'), findsOneWidget);
      expect(find.byKey(const Key('trainer-connect')), findsNothing);
    });

    testWidgets('Connections page changes sharing and disconnects', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final api = _FakeApi();
      final data = MemberData()
        ..trainerConnections = [
          TrainerConnection.fromJson(
            _connectionJson(status: 'active', permissions: {'steps': true}),
          ),
        ];
      await tester.pumpWidget(
        _app(api, const MemberTrainerConnectionsPage(), data: data),
      );
      expect(find.text('Coach Amani'), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('connection-edit-tmr_1')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('share-steps')))
            .value,
        isTrue,
      );
      await tester.tap(find.byKey(const Key('share-steps')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('share-save')));
      await tester.pumpAndSettle();
      expect(api.calls.last.$1, 'update');
      expect((api.calls.last.$2 as Map)['steps'], isFalse);

      await tester.tap(find.byKey(const Key('connection-end-tmr_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('connect-end-confirm')));
      await tester.pumpAndSettle();
      expect(api.calls.last, ('end', 'tmr_1'));
    });

    testWidgets('My trainer plan lists what the trainer planned', (
      tester,
    ) async {
      Workout w(String id, String date, {String status = 'planned'}) =>
          Workout.fromJson({
            'id': id,
            'userId': 'm1',
            'trainerId': 'trn_1',
            'source': 'trainer',
            'name': 'Push Day $id',
            'activityType': 'strength',
            'scheduledDate': date,
            'status': status,
            'exercises': [],
          });
      final data = MemberData()
        ..workoutsLoaded = true
        ..trainers = [
          TrainerProfile.fromJson({
            'id': 'trn_1',
            'displayName': 'Coach Amani',
          }),
        ]
        ..workouts = [
          w('a', '2026-09-24'),
          w('b', '2026-09-26'),
          w('c', '2026-09-20', status: 'completed'),
        ];
      await tester.pumpWidget(
        _app(
          _FakeApi(),
          ListView(
            children: [
              TodayWorkoutCard(data: data, now: _now),
              TrainerPlanBlock(data: data, now: _now),
            ],
          ),
          data: data,
        ),
      );
      expect(find.text('My trainer plan'), findsOneWidget);
      expect(find.text('Coach Amani'), findsOneWidget);
      expect(find.text('2 coming up · 1 completed'), findsOneWidget);
      expect(find.text('Push Day b'), findsOneWidget);
      expect(find.byKey(const Key('today-workout-trainer')), findsOneWidget);
      expect(find.text('From Coach Amani'), findsOneWidget);
    });
  });

  group('trainer', () {
    testWidgets('Clients tab accepts a request', (tester) async {
      final api = _FakeApi()
        ..clients = [
          _connectionJson(permissions: {'workoutHistory': true}),
        ];
      await tester.pumpWidget(_app(api, const TrainerClientsTab()));
      await tester.pumpAndSettle();
      expect(find.text('Requests'), findsOneWidget);
      expect(find.text('Will share: Workout history'), findsOneWidget);
      await tester.tap(find.byKey(const Key('client-accept-tmr_1')));
      await tester.pumpAndSettle();
      expect(api.calls.single, ('accept', 'tmr_1'));
      expect(find.byKey(const Key('client-tmr_1')), findsOneWidget);
      expect(find.text('Requests'), findsNothing);
    });

    testWidgets(
      'Client page shows only shared data and assigns on chosen days',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 3000);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        final plan = TrainerPlan.fromJson({
          'id': 'wpl_1',
          'name': 'Push Day',
          'activityType': 'strength',
          'exercises': [
            {'exerciseName': 'Bench Press', 'sets': 3, 'reps': 8},
          ],
        });
        final api = _FakeApi()
          ..overview = {
            'client': _connectionJson(
              status: 'active',
              permissions: {'steps': true, 'goals': true},
            ),
            'activity': {
              'days': [
                for (var d = 11; d <= 24; d++)
                  {
                    'date': '2026-09-${d.toString().padLeft(2, '0')}',
                    'steps': 1000 * (d - 10),
                  },
              ],
            },
            'goals': [
              {
                'type': 'steps',
                'period': 'day',
                'target': 8000,
                'current': 14000,
                'completed': true,
              },
            ],
            'workouts': [
              {
                'id': 'w1',
                'name': 'Legs',
                'scheduledDate': '2030-01-01',
                'assignedByYou': true,
              },
            ],
          };
        await tester.pumpWidget(
          _app(
            api,
            TrainerClientPage(
              connection: TrainerConnection.fromJson(
                _connectionJson(status: 'active'),
              ),
              plans: [plan],
              now: _now,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('client-activity')), findsOneWidget);
        expect(find.text('8,000 steps a day'), findsOneWidget);
        expect(find.textContaining("Amina doesn't share:"), findsOneWidget);
        expect(find.textContaining('Workout history'), findsWidgets);
        expect(find.text('Current streak'), findsNothing);
        expect(find.text('Legs'), findsOneWidget);

        await tester.tap(find.byKey(const Key('client-assign')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('assign-plan-wpl_1')));
        await tester.tap(find.byKey(const Key('assign-day-2026-09-25')));
        await tester.tap(find.byKey(const Key('assign-day-2026-09-27')));
        await tester.pump();
        expect(find.text('Assign on 2 days'), findsOneWidget);
        await tester.tap(find.byKey(const Key('assign-save')));
        await tester.pumpAndSettle();
        expect(api.calls.last.$1, 'assign');
        expect(api.calls.last.$2, {
          'planId': 'wpl_1',
          'dates': ['2026-09-25', '2026-09-27'],
        });
      },
    );

    testWidgets(
      'Plan editor saves exercises with sets, reps, time and instructions',
      (tester) async {
        tester.view.physicalSize = const Size(1080, 4000);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final api = _FakeApi();
        await tester.pumpWidget(_app(api, const TrainerPlanEditorPage()));
        final list = find.byType(Scrollable).first;
        Future<void> tapVisible(Key key) async {
          await tester.scrollUntilVisible(
            find.byKey(key),
            200,
            scrollable: list,
          );
          await tester.tap(find.byKey(key));
          await tester.pump();
        }

        await tapVisible(const Key('plan-save'));
        expect(find.text('Required'), findsWidgets);
        expect(api.calls, isEmpty);
        await tester.fling(list, const Offset(0, 3000), 3000);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('plan-name')),
          'Core Blast',
        );
        await tester.tap(find.byKey(const Key('plan-type-hiit')));
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byKey(const Key('exercise-name-0')),
          200,
          scrollable: list,
        );
        await tester.enterText(
          find.byKey(const Key('exercise-name-0')),
          'Plank',
        );
        await tester.tap(
          find.descendant(
            of: find.byKey(const Key('exercise-mode-0')),
            matching: find.text('Time'),
          ),
        );
        await tester.pump();
        await tester.enterText(
          find.byKey(const Key('exercise-target-0-t')),
          '45',
        );
        await tester.enterText(
          find.byKey(const Key('exercise-instructions-0')),
          'Straight line',
        );
        await tapVisible(const Key('plan-add-exercise'));
        await tester.scrollUntilVisible(
          find.byKey(const Key('exercise-name-1')),
          200,
          scrollable: list,
        );
        await tester.enterText(
          find.byKey(const Key('exercise-name-1')),
          'Goblet Squat',
        );
        await tapVisible(const Key('exercise-weight-1'));
        await tapVisible(const Key('plan-save'));
        await tester.pumpAndSettle();
        final saved = api.calls.single.$2 as Map;
        expect(saved['name'], 'Core Blast');
        expect(saved['activityType'], 'hiit');
        final ex = saved['exercises'] as List;
        expect(ex[0], {
          'exerciseName': 'Plank',
          'sets': 3,
          'duration': 45,
          'instructions': 'Straight line',
          'tracksWeight': false,
        });
        expect(ex[1]['exerciseName'], 'Goblet Squat');
        expect(ex[1]['reps'], 10);
        expect(ex[1]['tracksWeight'], isTrue);
      },
    );
  });
}
