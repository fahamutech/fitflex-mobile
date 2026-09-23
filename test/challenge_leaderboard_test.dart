import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/challenge_leaderboard.dart';
import 'package:fitflexmobile/shared/activity/challenge.dart';
import 'package:fitflexmobile/shared/activity/gym_sharing.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/widgets/challenge_manager_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Thursday 24 Sep 2026.
final _now = DateTime(2026, 9, 24, 9);

Map<String, dynamic> _json({
  String id = 'c1',
  String mode = 'individual',
  bool joined = true,
  bool optIn = false,
  String? myTeamId,
  List<Map<String, dynamic>> teams = const [],
}) => {
  'id': id,
  'name': '50K Step Challenge',
  'type': 'steps',
  'target': 50000,
  'startDate': '2026-09-20',
  'endDate': '2026-09-27',
  'creatorType': 'fitflex',
  'creator': {'type': 'fitflex'},
  'phase': 'active',
  'joined': joined,
  'participantCount': 4,
  'mode': mode,
  'teams': teams,
  'myTeamId': ?myTeamId,
  'leaderboardOptIn': optIn,
};

Challenge _c({
  String mode = 'individual',
  bool joined = true,
  bool optIn = false,
  String? myTeamId,
  List<Map<String, dynamic>> teams = const [],
}) => Challenge.tryParse(
  _json(
    mode: mode,
    joined: joined,
    optIn: optIn,
    myTeamId: myTeamId,
    teams: teams,
  ),
)!;

const _redBlue = [
  {'id': 't_red', 'name': 'Red'},
  {'id': 't_blue', 'name': 'Blue'},
];

class _FakeApi extends ApiClient {
  final calls = <(String, Object?)>[];
  Map<String, dynamic> board = {};
  List<Map<String, dynamic>> created = [];

  @override
  Future<Map<String, dynamic>> joinChallenge(
    String id, {
    String? teamId,
    String? gymId,
    bool leaderboardOptIn = false,
  }) async {
    calls.add((
      'join',
      {'id': id, 'teamId': teamId, 'gymId': gymId, 'optIn': leaderboardOptIn},
    ));
    return {};
  }

  @override
  Future<Map<String, dynamic>> setLeaderboardOptIn(
    String id,
    bool optIn,
  ) async {
    calls.add(('optIn', optIn));
    return {'leaderboardOptIn': optIn};
  }

  @override
  Future<Map<String, dynamic>> challengeLeaderboard(String id) async {
    calls.add(('board', id));
    return board;
  }

  @override
  Future<List<dynamic>> creatorChallenges(
    String scope, {
    String? gymId,
  }) async => created;

  @override
  Future<Map<String, dynamic>> createChallenge(
    String scope,
    Map<String, dynamic> body, {
    String? gymId,
  }) async {
    calls.add(('create', body));
    return {};
  }
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

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Object? _joined(_FakeApi api) => api.calls.firstWhere((x) => x.$1 == 'join').$2;

bool _switchOn(WidgetTester tester, String key) =>
    tester.widget<SwitchListTile>(find.byKey(Key(key))).value;

void main() {
  test('parses the leaderboard without anything it was not sent', () {
    final b = ChallengeLeaderboard.fromJson({
      'participants': 4,
      'individuals': [
        {'rank': 1, 'name': 'Chausiku A.', 'progress': 50000, 'fraction': 1},
        {'rank': 2, 'name': 'Aisha M.', 'progress': 40000, 'you': true},
      ],
      'you': {'optedIn': true, 'rank': 2, 'of': 3, 'progress': 40000},
      'teams': [
        {
          'rank': 1,
          'teamId': 't_red',
          'name': 'Red',
          'members': 3,
          'averageCompletion': 0.767,
        },
      ],
      'hiddenTeams': 1,
      'minTeamSize': 3,
    });
    expect(b.individuals.map((e) => e.name), ['Chausiku A.', 'Aisha M.']);
    expect(b.individuals.last.isYou, isTrue);
    expect(b.you?.rank, 2);
    expect(b.teams.single.averageCompletion, 0.767);
    expect(b.hiddenTeams, 1);
    expect(ChallengeMode.fromWire('gym_vs_gym'), ChallengeMode.gymVsGym);
    expect(ChallengeMode.fromWire(null), ChallengeMode.individual);
    expect(ChallengeMode.individual.hasTeams, isFalse);
  });

  testWidgets('joining keeps you off the leaderboard unless you switch it on', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi();
    final data = MemberData()
      ..challengesLoaded = true
      ..challenges = [_c(joined: false)];
    await tester.pumpWidget(
      _app(
        api,
        MemberChallengePage(challengeId: 'c1', now: _now),
        data: data,
      ),
    );
    await tester.tap(find.byKey(const Key('challenge-join')));
    await tester.pumpAndSettle();
    expect(_switchOn(tester, 'join-leaderboard'), isFalse);
    expect(
      find.textContaining('first name, last initial and progress'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('join-confirm')));
    await tester.pumpAndSettle();
    expect(_joined(api), {
      'id': 'c1',
      'teamId': null,
      'gymId': null,
      'optIn': false,
    });
    expect(data.challenges.single.joined, isTrue);
    expect(data.challenges.single.leaderboardOptIn, isFalse);
  });

  testWidgets('a team challenge needs a team before you can join', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi();
    final data = MemberData()
      ..challengesLoaded = true
      ..challenges = [_c(joined: false, mode: 'teams', teams: _redBlue)];
    await tester.pumpWidget(
      _app(
        api,
        MemberChallengePage(challengeId: 'c1', now: _now),
        data: data,
      ),
    );
    expect(find.textContaining('team challenge'), findsOneWidget);
    await tester.tap(find.byKey(const Key('challenge-join')));
    await tester.pumpAndSettle();
    FilledButton confirm() =>
        tester.widget<FilledButton>(find.byKey(const Key('join-confirm')));
    expect(confirm().onPressed, isNull);
    await tester.tap(find.byKey(const Key('join-team-t_red')));
    await tester.tap(find.byKey(const Key('join-leaderboard')));
    await tester.pumpAndSettle();
    expect(confirm().onPressed, isNotNull);
    await tester.tap(find.byKey(const Key('join-confirm')));
    await tester.pumpAndSettle();
    expect(_joined(api), {
      'id': 'c1',
      'teamId': 't_red',
      'gymId': null,
      'optIn': true,
    });
  });

  testWidgets('gym vs gym preselects your only home gym', (tester) async {
    _tall(tester);
    JoinChoice? choice;
    final c = _c(joined: false, mode: 'gym_vs_gym');
    await tester.pumpWidget(
      _app(
        _FakeApi(),
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => choice = await showJoinChallengeSheet(
              context,
              challenge: c,
              myGyms: const [
                GymSharing(
                  gym: GymCard(id: 'g1', name: 'Mikocheni Fitness'),
                  reasons: ['member'],
                ),
                GymSharing(
                  gym: GymCard(id: 'g2', name: 'Oyster Bay Gym'),
                  reasons: ['visited'],
                ),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ChoiceChip>(find.byKey(const Key('join-gym-g1'))).selected,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('join-gym-g2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('join-confirm')));
    await tester.pumpAndSettle();
    expect(choice, (teamId: null, gymId: 'g2', leaderboardOptIn: false));
  });

  testWidgets(
    'leaderboard: where you would be, who chose to be listed, teams',
    (tester) async {
      _tall(tester);
      final api = _FakeApi()
        ..board = {
          'participants': 4,
          'individuals': [
            {
              'rank': 1,
              'name': 'Chausiku A.',
              'progress': 50000,
              'fraction': 1,
            },
            {'rank': 2, 'name': 'Aisha M.', 'progress': 40000, 'fraction': 0.8},
          ],
          'you': {'optedIn': false, 'rank': 3, 'of': 3, 'progress': 25000},
          'teams': [
            {
              'rank': 1,
              'teamId': 't_red',
              'name': 'Red',
              'members': 3,
              'averageCompletion': 0.767,
            },
          ],
          'hiddenTeams': 1,
          'minTeamSize': 3,
        };
      final c = _c(mode: 'teams', teams: _redBlue, myTeamId: 't_red');
      final data = MemberData()
        ..challengesLoaded = true
        ..challenges = [c];
      await tester.pumpWidget(
        _app(
          api,
          ListView(children: [ChallengeLeaderboardSection(challenge: c)]),
          data: data,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.byKey(const Key('leaderboard-you'))).data,
        "You'd be #3 of 3. You're not listed",
      );
      expect(find.text('Your team: Red'), findsOneWidget);
      expect(find.text('Chausiku A.'), findsOneWidget);
      expect(find.text('Aisha M.'), findsOneWidget);
      expect(find.text('Red · 3 members'), findsOneWidget);
      expect(find.text('77%'), findsOneWidget);
      expect(
        find.text('One smaller team will appear once it reaches 3 members.'),
        findsOneWidget,
      );
      expect(find.textContaining('never weight or body'), findsOneWidget);
      expect(_switchOn(tester, 'leaderboard-opt-in'), isFalse);

      await tester.tap(find.byKey(const Key('leaderboard-opt-in')));
      await tester.pumpAndSettle();
      expect(api.calls.where((x) => x.$1 == 'optIn').single, ('optIn', true));
      expect(data.challenges.single.leaderboardOptIn, isTrue);
      expect(api.calls.where((x) => x.$1 == 'board'), hasLength(2));
    },
  );

  testWidgets('nobody listed yet, and no team big enough', (tester) async {
    final api = _FakeApi()
      ..board = {
        'participants': 2,
        'you': {'optedIn': true, 'rank': 1, 'of': 1, 'progress': 100},
        'hiddenTeams': 2,
        'minTeamSize': 3,
      };
    final c = _c(mode: 'teams', teams: _redBlue, optIn: true);
    await tester.pumpWidget(
      _app(
        api,
        ListView(children: [ChallengeLeaderboardSection(challenge: c)]),
        data: MemberData()..challenges = [c],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text("You're #1 of 1 on the leaderboard"), findsOneWidget);
    expect(find.text('Nobody has chosen to appear yet.'), findsOneWidget);
    expect(
      find.text('Team standings appear once a team has 3 members.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('team-row-1')), findsNothing);
  });

  testWidgets('creators can set up a team challenge', (tester) async {
    _tall(tester);
    final api = _FakeApi();
    await tester.pumpWidget(
      _app(api, ChallengeManagerPage(scope: 'owner', gymId: 'g1', now: _now)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('challenge-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('challenge-name')), 'Team 50K');
    await tester.ensureVisible(find.byKey(const Key('challenge-teams')));
    await tester.tap(find.byKey(const Key('challenge-teams')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('challenge-team-names')),
      'Red, red',
    );
    await tester.ensureVisible(find.byKey(const Key('challenge-create')));
    await tester.tap(find.byKey(const Key('challenge-create')));
    await tester.pumpAndSettle();
    expect(find.text('Add at least two different team names.'), findsOneWidget);
    expect(api.calls.where((x) => x.$1 == 'create'), isEmpty);

    await tester.enterText(
      find.byKey(const Key('challenge-team-names')),
      'Red, Blue, ',
    );
    await tester.ensureVisible(find.byKey(const Key('challenge-create')));
    await tester.tap(find.byKey(const Key('challenge-create')));
    await tester.pumpAndSettle();
    final body = api.calls.firstWhere((x) => x.$1 == 'create').$2 as Map;
    expect(body['mode'], 'teams');
    expect(body['teams'], ['Red', 'Blue']);
  });

  test('leaderboard strings are translated', () {
    final sw = FFLocale()..set(const Locale('sw'));
    for (final k in ['optIn', 'optInHint', 'fairPlay', 'teamRule', 'youAre']) {
      final v = sw.t('leaderboard.$k');
      expect(v, isNot('leaderboard.$k'));
      expect(v, isNot(FFLocale().t('leaderboard.$k')), reason: k);
    }
  });
}
