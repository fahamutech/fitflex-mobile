import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/goal.dart';
import 'package:fitflexmobile/shared/activity/goal_repository.dart';
import 'package:fitflexmobile/shared/activity/mock/mock_activity_data.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 23, 20);

Widget _app(MemberData data, GoalRepository goals) {
  final api = ApiClient();
  return AppScope(
    api: api,
    auth: AuthState(api),
    goalRepository: goals,
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
            child: MemberActivityTab(now: _now, initialSection: 'progress'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder f) => tester
    .scrollUntilVisible(f, 400, scrollable: find.byType(Scrollable).first);

void main() {
  testWidgets('Progress shows goals, comparisons, charts, streaks, records', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final repo = LocalGoalRepository(clock: () => _now);
    final data = MemberData()
      ..activities = generateMockActivities(
        userId: 'u1',
        today: _now,
        days: 91,
      ).reversed.toList()
      ..activityLoaded = true
      ..goals = await repo.list()
      ..goalsLoaded = true;

    await tester.pumpWidget(_app(data, repo));

    expect(find.text('Current goals'), findsOneWidget);
    expect(find.text('8,000 steps a day'), findsOneWidget);
    expect(find.text('3 workouts a week'), findsOneWidget);

    for (final key in [
      'progress-weekly',
      'progress-monthly',
      'progress-trends',
      'progress-consistency',
      'progress-streaks',
      'progress-milestones',
      'progress-records',
    ]) {
      await _scrollTo(tester, find.byKey(Key(key)));
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
      if (key == 'progress-streaks') {
        await _scrollTo(tester, find.byKey(const Key('streak-workout')));
        expect(find.byKey(const Key('streak-activity')), findsOneWidget);
        expect(find.byKey(const Key('streak-challenge')), findsNothing);
      }
    }
  });

  testWidgets('Trend chart shows the tapped week', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final repo = LocalGoalRepository(clock: () => _now);
    final data = MemberData()
      ..activities = generateMockActivities(userId: 'u1', today: _now, days: 91)
      ..activityLoaded = true
      ..goalsLoaded = true;
    await tester.pumpWidget(_app(data, repo));

    await _scrollTo(tester, find.byKey(const Key('bar-0')));
    await tester.ensureVisible(find.byKey(const Key('bar-0')));
    await tester.pumpAndSettle();
    final readout = find.byKey(const Key('bar-chart-readout'));
    expect(tester.widget<Text>(readout).data, contains('(so far)'));
    await tester.tap(find.byKey(const Key('bar-0')));
    await tester.pump();
    expect(tester.widget<Text>(readout).data, startsWith('Week of 3 Aug'));
    expect(tester.widget<Text>(readout).data, isNot(contains('(so far)')));
  });

  testWidgets('An ended streak reads as a fresh start, not a failure', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    // Active the 8 days before yesterday; nothing yesterday or today.
    final acts = [
      for (var n = 2; n <= 9; n++)
        Activity(
          id: 'a$n',
          userId: 'u1',
          type: ActivityType.running,
          source: ActivitySource.fitflex,
          startedAt: DateTime(2026, 9, 23 - n, 7),
          durationMinutes: 30,
        ),
    ];
    final data = MemberData()
      ..activities = acts
      ..activityLoaded = true
      ..goalsLoaded = true;
    await tester.pumpWidget(_app(data, LocalGoalRepository(clock: () => _now)));
    await _scrollTo(tester, find.byKey(const Key('streak-activity')));
    expect(
      find.text('Your 8-day streak has ended. Start a new streak today.'),
      findsOneWidget,
    );
  });

  testWidgets('Add goal sheet creates a goal through the repository', (
    tester,
  ) async {
    final repo = _RecordingRepo();
    final data = MemberData()
      ..activityLoaded = true
      ..goalsLoaded = true;
    await tester.pumpWidget(_app(data, repo));

    await tester.tap(find.byKey(const Key('goal-add')));
    await tester.pumpAndSettle();
    expect(find.text('New goal'), findsOneWidget);

    await tester.tap(find.byKey(const Key('goal-type-distance_km')));
    await tester.pump();
    await tester.tap(find.text('Monthly'));
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('goal-target')))
          .controller!
          .text,
      '80',
    );

    await tester.enterText(find.byKey(const Key('goal-target')), '0');
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pump();
    expect(find.text('Enter a target above zero.'), findsOneWidget);
    expect(repo.created, isEmpty);

    await tester.enterText(find.byKey(const Key('goal-target')), '100');
    await tester.tap(find.byKey(const Key('goal-save')));
    await tester.pumpAndSettle();
    expect(repo.created.single, (GoalType.distanceKm, GoalPeriod.month, 100));
    expect(find.text('New goal'), findsNothing);
  });
}

class _RecordingRepo implements GoalRepository {
  final created = <(GoalType, GoalPeriod, num)>[];

  @override
  Future<List<Goal>> list() async => const [];

  @override
  Future<Goal> create({
    required GoalType type,
    required GoalPeriod period,
    required num target,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    created.add((type, period, target));
    return Goal(
      id: 'new',
      userId: 'u1',
      type: type,
      target: target,
      period: period,
      startDate: DateTime(2026, 9, 23),
    );
  }

  @override
  Future<Goal> update(String id, {num? target, GoalStatus? status}) =>
      throw UnimplementedError();
}
