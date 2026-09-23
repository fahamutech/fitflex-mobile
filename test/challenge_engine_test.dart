import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/challenge_widgets.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/challenge.dart';
import 'package:fitflexmobile/shared/activity/trainer_connection.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/widgets/challenge_manager_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Thursday 24 Sep 2026.
final _now = DateTime(2026, 9, 24, 9);

Activity _act(
  String id,
  int day, {
  ActivityType type = ActivityType.walking,
  ActivitySource source = ActivitySource.device,
  int? steps,
  int? minutes,
  double? km,
}) => Activity(
  id: id,
  userId: 'u1',
  type: type,
  source: source,
  startedAt: DateTime(2026, 9, day, 8),
  steps: steps,
  durationMinutes: minutes,
  activeMinutes: minutes,
  distanceKm: km,
);

final _acts = [
  _act('a1', 21, steps: 20000, minutes: 60),
  _act('a2', 23, steps: 12450, minutes: 40),
  _act(
    'a3',
    22,
    type: ActivityType.running,
    source: ActivitySource.fitflex,
    minutes: 30,
    km: 5,
  ),
  _act('a4', 10, steps: 99999),
];

Map<String, dynamic> _json({
  String id = 'c1',
  String name = '50K Step Challenge',
  String type = 'steps',
  num target = 50000,
  String start = '2026-09-20',
  String end = '2026-09-27',
  String phase = 'active',
  bool joined = true,
  String creatorType = 'fitflex',
  String? creatorId,
  String? creatorName,
  List<String> rewards = const [],
}) => {
  'id': id,
  'name': name,
  'type': type,
  'target': target,
  'startDate': start,
  'endDate': end,
  'creatorType': creatorType,
  'creatorId': ?creatorId,
  'creator': {'type': creatorType, 'id': creatorId, 'name': creatorName},
  'rewards': rewards,
  'phase': phase,
  'joined': joined,
  'participantCount': 12,
};

Challenge _c({
  String id = 'c1',
  String name = '50K Step Challenge',
  String type = 'steps',
  num target = 50000,
  String start = '2026-09-20',
  String end = '2026-09-27',
  String phase = 'active',
  bool joined = true,
  String creatorType = 'fitflex',
  String? creatorId,
  String? creatorName,
  List<String> rewards = const [],
}) => Challenge.tryParse(
  _json(
    id: id,
    name: name,
    type: type,
    target: target,
    start: start,
    end: end,
    phase: phase,
    joined: joined,
    creatorType: creatorType,
    creatorId: creatorId,
    creatorName: creatorName,
    rewards: rewards,
  ),
)!;

class _FakeApi extends ApiClient {
  final calls = <(String, Object?)>[];
  List<Map<String, dynamic>> created = [];
  Map<String, dynamic> participants = {};

  @override
  Future<Map<String, dynamic>> joinChallenge(String id) async {
    calls.add(('join', id));
    return {};
  }

  @override
  Future<Map<String, dynamic>> leaveChallenge(String id) async {
    calls.add(('leave', id));
    return {};
  }

  @override
  Future<List<dynamic>> creatorChallenges(String scope, {String? gymId}) async {
    calls.add(('list', '$scope/$gymId'));
    return created;
  }

  @override
  Future<Map<String, dynamic>> createChallenge(
    String scope,
    Map<String, dynamic> body, {
    String? gymId,
  }) async {
    calls.add(('create', body));
    created = [_json(id: 'new', name: body['name'] as String, joined: false)];
    return {};
  }

  @override
  Future<Map<String, dynamic>> challengeParticipants(
    String scope,
    String id, {
    String? gymId,
  }) async => participants;
}

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

void main() {
  group('engine', () {
    test('progress for every challenge type', () {
      num p(
        String type, {
        List<({DateTime at, String? gymId})> ins = const [],
        String creator = 'fitflex',
        String? creatorId,
      }) => challengeProgress(
        _c(type: type, creatorType: creator, creatorId: creatorId),
        _acts,
        checkIns: ins,
      );
      expect(p('steps'), 32450, reason: 'the 10 Sep walk is outside the dates');
      expect(p('distance_km'), 5);
      expect(p('workouts'), 1);
      expect(p('active_minutes'), 130);
      expect(p('consistency'), 3);
      final ins = [
        (at: DateTime(2026, 9, 22, 7), gymId: 'g1'),
        (at: DateTime(2026, 9, 22, 18), gymId: 'g1'),
        (at: DateTime(2026, 9, 23, 7), gymId: 'g9'),
        (at: DateTime(2026, 9, 1, 7), gymId: 'g1'),
      ];
      expect(
        p('gym_attendance', ins: ins),
        2,
        reason: 'distinct days, any gym',
      );
      expect(
        p('gym_attendance', ins: ins, creator: 'gym', creatorId: 'g1'),
        1,
        reason: "a gym's challenge counts only its own check-ins",
      );
    });

    test('groups into active, completed and available', () {
      final g = groupChallenges([
        _c(id: 'running'),
        _c(id: 'reached', target: 30000),
        _c(id: 'over', phase: 'ended', end: '2026-09-23'),
        _c(id: 'open', joined: false),
        _c(
          id: 'soon',
          joined: false,
          phase: 'upcoming',
          start: '2026-10-01',
          end: '2026-10-10',
        ),
        _c(id: 'gone', joined: false, phase: 'ended'),
        _c(id: 'x', phase: 'cancelled'),
      ], _acts);
      expect(g.active.map((s) => s.challenge.id), ['running']);
      expect(g.completed.map((s) => s.challenge.id).toSet(), {
        'reached',
        'over',
      });
      expect(
        g.completed.firstWhere((s) => s.challenge.id == 'reached').reached,
        isTrue,
      );
      expect(g.available.map((c) => c.id), ['open', 'soon']);
    });

    test('days left and percent never shows 100 early', () {
      expect(_c().daysLeft(_now), 4, reason: '24–27 Sep inclusive');
      expect(challengePercent(0.649, false), 65);
      expect(challengePercent(0.996, false), 99);
      expect(challengePercent(1.2, true), 120);
    });
  });

  group('member screens', () {
    testWidgets('card reads like the brief', (tester) async {
      await tester.pumpWidget(
        _app(
          _FakeApi(),
          ListView(
            children: [
              ChallengeCard(challenge: _c(), progress: 32450, now: _now),
            ],
          ),
        ),
      );
      expect(find.text('50K Step Challenge'), findsOneWidget);
      expect(find.text('32,450 / 50,000'), findsOneWidget);
      expect(find.text('65%'), findsOneWidget);
      expect(find.text('Ends in 4 days'), findsOneWidget);
      expect(find.text('View challenge'), findsOneWidget);
      expect(find.text('By FitFlex'), findsOneWidget);
    });

    testWidgets('Challenges section shows Active, Available and Completed', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final data = MemberData()
        ..activities = _acts
        ..challengesLoaded = true
        ..challenges = [
          _c(id: 'running'),
          _c(
            id: 'open',
            name: 'Gym Month',
            joined: false,
            type: 'gym_attendance',
            target: 12,
            creatorType: 'gym',
            creatorId: 'g1',
            creatorName: 'Mikocheni Fitness',
          ),
          _c(
            id: 'over',
            name: 'September Sprint',
            phase: 'ended',
            end: '2026-09-23',
            target: 10,
            type: 'workouts',
          ),
        ];
      await tester.pumpWidget(
        _app(
          _FakeApi(),
          Builder(
            builder: (context) =>
                ListView(children: buildChallengesSection(context, data, _now)),
          ),
          data: data,
        ),
      );
      expect(find.text('Active'), findsOneWidget);
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('By Mikocheni Fitness'), findsOneWidget);
      expect(find.text('12 gym visits · 12 taking part'), findsOneWidget);
      expect(find.text('1 / 10'), findsOneWidget);
      expect(find.text('Ended 23 Sep'), findsOneWidget);
    });

    testWidgets('detail: join, and a clear note on what the trainer sees', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final api = _FakeApi();
      final data = MemberData()
        ..activities = _acts
        ..challengesLoaded = true
        ..challenges = [
          _c(
            joined: false,
            creatorType: 'trainer',
            creatorId: 'trn_1',
            creatorName: 'Coach Sarah',
            rewards: ['Finisher badge'],
          ),
        ]
        ..trainerConnections = [
          TrainerConnection.fromJson({
            'id': 'r1',
            'trainerId': 'trn_1',
            'memberId': 'u1',
            'status': 'active',
            'permissions': {'steps': true},
          }),
        ];
      await tester.pumpWidget(
        _app(
          api,
          MemberChallengePage(challengeId: 'c1', now: _now),
          data: data,
        ),
      );
      expect(find.text('Finisher badge'), findsOneWidget);
      expect(find.text('Goal: 50,000 steps'), findsOneWidget);
      expect(
        find.text(
          "Coach Sarah will see that you joined, but not your progress, unless you share challenge data with them.",
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('challenge-progress')), findsNothing);

      await tester.tap(find.byKey(const Key('challenge-join')));
      await tester.pumpAndSettle();
      expect(api.calls.single, ('join', 'c1'));
      expect(data.challenges.single.joined, isTrue);
      expect(find.text('32,450 / 50,000'), findsOneWidget);
      expect(find.byKey(const Key('challenge-leave')), findsOneWidget);
    });
  });

  group('creators', () {
    testWidgets('create a challenge, then see who joined', (tester) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final api = _FakeApi()
        ..participants = {
          'participants': [
            {
              'member': {'displayName': 'Aisha'},
              'progress': 32450,
              'completed': false,
            },
            {
              'member': {'displayName': 'Baraka'},
            },
          ],
        };
      await tester.pumpWidget(
        _app(api, ChallengeManagerPage(scope: 'owner', gymId: 'g1', now: _now)),
      );
      await tester.pumpAndSettle();
      expect(api.calls.first, ('list', 'owner/g1'));
      expect(find.text("You haven't created a challenge yet."), findsOneWidget);

      await tester.tap(find.byKey(const Key('challenge-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('challenge-name')),
        '50K Step Challenge',
      );
      await tester.enterText(
        find.byKey(const Key('challenge-rewards')),
        'Finisher badge, Free smoothie',
      );
      await tester.tap(find.byKey(const Key('challenge-create')));
      await tester.pumpAndSettle();
      final body = api.calls.firstWhere((c) => c.$1 == 'create').$2 as Map;
      expect(body['name'], '50K Step Challenge');
      expect(body['type'], 'steps');
      expect(body['target'], 50000);
      expect(body['startDate'], '2026-09-24');
      expect(body['endDate'], '2026-10-07');
      expect(body['rewards'], ['Finisher badge', 'Free smoothie']);
      expect(body['visibility'], 'audience');

      await tester.tap(find.byKey(const Key('managed-challenge-new')));
      await tester.pumpAndSettle();
      expect(find.text('Aisha'), findsOneWidget);
      expect(find.text('32,450 / 50,000'), findsOneWidget);
      expect(find.text('Baraka'), findsOneWidget);
      expect(find.text('Progress not shared'), findsOneWidget);
    });

    testWidgets(
      'trainer/gym view of a member lists shared challenge progress',
      (tester) async {
        await tester.pumpWidget(
          _app(
            _FakeApi(),
            ListView(
              children: [
                SharedChallengesList(
                  items: SharedChallengeProgress.parseList([
                    {
                      'name': 'Gym Month',
                      'type': 'gym_attendance',
                      'target': 12,
                      'progress': 5,
                      'completed': false,
                      'phase': 'active',
                    },
                    {
                      'name': '50K',
                      'type': 'steps',
                      'target': 50000,
                      'progress': 51000,
                      'completed': true,
                      'phase': 'ended',
                    },
                  ])!,
                ),
              ],
            ),
          ),
        );
        expect(find.text('5 / 12'), findsOneWidget);
        expect(find.text('Completed'), findsOneWidget);
      },
    );
  });

  test('check-ins feed gym challenges from member data', () {
    final data = MemberData()
      ..checkins = [
        CheckIn.fromJson({
          'id': 'x',
          'memberId': 'u1',
          'timestamp': '2026-09-22T05:00:00Z',
          'gymTier': 's',
          'gymId': 'g1',
        }),
      ];
    expect(data.checkInMoments.single.gymId, 'g1');
  });
}
