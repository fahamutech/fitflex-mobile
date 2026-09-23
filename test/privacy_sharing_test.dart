import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_privacy_page.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/trainer/widgets/client_summary_card.dart';
import 'package:fitflexmobile/screens/trainer/widgets/clients_digest.dart';
import 'package:fitflexmobile/shared/activity/trainer_connection.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

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

Map<String, dynamic> _conn({
  String id = 'tmr_1',
  String status = 'active',
  Map<String, bool> permissions = const {},
  Map<String, dynamic>? summary,
  String member = 'Aisha',
}) => {
  'id': id,
  'trainerId': 'trn_1',
  'memberId': 'm_$id',
  'status': status,
  'permissions': permissions,
  'trainer': {'id': 'trn_1', 'displayName': 'Sarah'},
  'member': {'id': 'm_$id', 'displayName': member},
  'summary': ?summary,
};

class _FakeApi extends ApiClient {
  final calls = <(String, Object?)>[];
  bool fail = false;
  List<Map<String, dynamic>> clients = [];

  @override
  Future<Map<String, dynamic>> updateTrainerConnection(
    String id,
    Map<String, bool> permissions,
  ) async {
    calls.add(('update', permissions));
    if (fail) throw Exception('offline');
    return {};
  }

  @override
  Future<Map<String, dynamic>> endTrainerConnection(String id) async {
    calls.add(('end', id));
    return {};
  }

  @override
  Future<List<dynamic>> myTrainerConnections() async => [];

  @override
  Future<List<dynamic>> trainerClients() async => clients;
}

final _aisha = {
  'weekStart': '2026-09-21',
  'week': {'workouts': 4, 'steps': 42320, 'activeMinutes': 184},
  'goal': {
    'type': 'workouts',
    'period': 'week',
    'target': 4,
    'current': 3,
    'completed': false,
  },
  'streak': {'current': 6, 'best': 9},
  'plannedNext7Days': 0,
  'attention': [
    {'kind': 'attention', 'code': 'missed_workouts', 'value': 1},
    {'kind': 'attention', 'code': 'nothing_planned'},
  ],
};

void main() {
  group('member: Privacy & data → Activity sharing', () {
    Future<(MemberData, _FakeApi)> pump(
      WidgetTester tester, {
      Map<String, bool> permissions = const {},
      String status = 'active',
    }) async {
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final api = _FakeApi();
      final data = MemberData()
        ..trainerConnections = [
          TrainerConnection.fromJson(
            _conn(status: status, permissions: permissions),
          ),
        ];
      await tester.pumpWidget(
        _app(api, const MemberActivitySharingPage(), data: data),
      );
      return (data, api);
    }

    bool switchOn(WidgetTester tester, String key) =>
        tester.widget<Switch>(find.byKey(Key('sharing-$key-tmr_1'))).value;

    testWidgets('shows each trainer with the example rows', (tester) async {
      await pump(
        tester,
        permissions: {
          'steps': true,
          'distance': true,
          'activeMinutes': true,
          'workoutHistory': true,
          'workoutDetails': true,
          'goals': true,
          'challenges': true,
        },
      );
      expect(find.text('Sarah'), findsOneWidget);
      for (final label in [
        'Activity data',
        'Workout history',
        'Workout details',
        'Goals',
        'Streaks',
        'Challenge data',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expect(switchOn(tester, 'activity'), isTrue);
      expect(switchOn(tester, 'workoutHistory'), isTrue);
      expect(switchOn(tester, 'goals'), isTrue);
      expect(switchOn(tester, 'streaks'), isFalse);
      expect(switchOn(tester, 'challenges'), isTrue);
    });

    testWidgets('each switch saves straight away and updates the app', (
      tester,
    ) async {
      final (data, api) = await pump(tester);
      await tester.tap(find.byKey(const Key('sharing-activity-tmr_1')));
      await tester.pumpAndSettle();
      final sent = api.calls.single.$2 as Map;
      expect(
        [sent['steps'], sent['distance'], sent['activeMinutes']],
        [true, true, true],
      );
      expect(sent['goals'], isFalse);
      expect(
        data.trainerConnections.single.permissions.has(
          TrainerPermission.distance,
        ),
        isTrue,
      );
      expect(
        find.text('Saved. Sarah sees this change right away.'),
        findsOneWidget,
      );

      // Fine-tune: switch distance back off.
      await tester.tap(find.byKey(const Key('sharing-activity-expand-tmr_1')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('sharing-distance-tmr_1')));
      await tester.pumpAndSettle();
      expect((api.calls.last.$2 as Map)['distance'], isFalse);
      // The group now reads as partly shared.
      expect(find.byType(Switch), findsWidgets);
      expect(
        tester.widget(find.byKey(const Key('sharing-activity-tmr_1'))),
        isA<IconButton>(),
      );
    });

    testWidgets('a failed save leaves sharing as it was', (tester) async {
      final (data, api) = await pump(tester, permissions: {'goals': true});
      api.fail = true;
      await tester.tap(find.byKey(const Key('sharing-goals-tmr_1')));
      await tester.pumpAndSettle();
      expect(switchOn(tester, 'goals'), isTrue);
      expect(
        data.trainerConnections.single.permissions.has(TrainerPermission.goals),
        isTrue,
      );
      expect(
        find.text("Couldn't save. Check your connection and try again."),
        findsOneWidget,
      );
    });

    testWidgets('revoke: stop sharing everything, or disconnect', (
      tester,
    ) async {
      final (_, api) = await pump(
        tester,
        permissions: {'steps': true, 'workoutHistory': true},
      );
      await tester.tap(find.byKey(const Key('sharing-stop-tmr_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sharing-confirm')));
      await tester.pumpAndSettle();
      expect(
        (api.calls.last.$2 as Map).values.every((v) => v == false),
        isTrue,
      );
      expect(find.byKey(const Key('sharing-stop-tmr_1')), findsNothing);

      await tester.tap(find.byKey(const Key('sharing-disconnect-tmr_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sharing-confirm')));
      await tester.pumpAndSettle();
      expect(api.calls.last, ('end', 'tmr_1'));
    });

    testWidgets('Privacy & data summarises who you share with', (tester) async {
      final data = MemberData()
        ..trainerConnections = [
          TrainerConnection.fromJson(_conn(permissions: {'steps': true})),
          TrainerConnection.fromJson(_conn(id: 'tmr_2')),
        ];
      await tester.pumpWidget(
        _app(_FakeApi(), const MemberPrivacyPage(), data: data),
      );
      expect(find.text('Activity sharing'), findsOneWidget);
      expect(find.text('Sharing with 1 of 2 trainers'), findsOneWidget);
    });
  });

  group('trainer: summaries', () {
    test('summary parses; unshared fields stay null', () {
      final s = ClientSummary.tryParse({
        'weekStart': '2026-09-21',
        'week': {'steps': 100},
        'attention': [
          {'kind': 'positive', 'code': 'goal_met'},
        ],
      })!;
      expect(s.steps, 100);
      expect(s.workouts, isNull);
      expect(s.goal, isNull);
      expect(s.streak, isNull);
      expect(s.needsAttention, isEmpty);
      expect(s.prompts.single.positive, isTrue);
    });

    testWidgets('card reads like the brief', (tester) async {
      await tester.pumpWidget(
        _app(
          _FakeApi(),
          ClientSummaryCard(
            name: 'Aisha',
            summary: ClientSummary.tryParse(_aisha)!,
          ),
        ),
      );
      expect(find.text('Aisha'), findsOneWidget);
      expect(find.text('THIS WEEK'), findsOneWidget);
      expect(
        find.text(
          '4\u00A0workouts · 42,320\u00A0steps · 184\u00A0active\u00A0min',
        ),
        findsOneWidget,
      );
      expect(find.text('Goal: 3 / 4 workouts a week'), findsOneWidget);
      expect(find.text('6-day activity streak'), findsOneWidget);
      expect(find.text('Missed 1 planned workout'), findsOneWidget);
      expect(find.text('Nothing planned for the next 7 days'), findsOneWidget);
    });

    testWidgets('card with nothing shared says so, without numbers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _FakeApi(),
          ClientSummaryCard(
            name: 'Baraka',
            summary: ClientSummary.tryParse({
              'weekStart': '2026-09-21',
              'week': {},
              'attention': [],
            })!,
          ),
        ),
      );
      expect(find.text("Activity isn't shared"), findsOneWidget);
      expect(find.byKey(const Key('summary-goal')), findsNothing);
      expect(find.byKey(const Key('summary-streak')), findsNothing);
    });

    testWidgets('home digest lists who to check in with', (tester) async {
      var opened = false;
      final api = _FakeApi()
        ..clients = [
          _conn(id: 'p', status: 'pending', member: 'New Member'),
          _conn(summary: _aisha),
          _conn(
            id: 'ok',
            member: 'Juma',
            summary: {
              'weekStart': '2026-09-21',
              'week': {},
              'plannedNext7Days': 2,
              'attention': [
                {'kind': 'positive', 'code': 'goal_met'},
              ],
            },
          ),
        ];
      await tester.pumpWidget(
        _app(api, ClientsDigest(onOpenClients: () => opened = true)),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('2 clients · 1 requests · 1 to check in with'),
        findsOneWidget,
      );
      expect(find.textContaining('Missed 1 planned workout'), findsOneWidget);
      expect(find.textContaining('Juma'), findsNothing);
      await tester.tap(find.byKey(const Key('trainer-digest-open')));
      expect(opened, isTrue);
    });
  });
}
