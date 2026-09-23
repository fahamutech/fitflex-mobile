import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/today_activity_card.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/activity_summary.dart';
import 'package:fitflexmobile/shared/activity/goal.dart';
import 'package:fitflexmobile/shared/activity/streaks.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 23, 20);

Activity _act(
  String id,
  DateTime at, {
  ActivityType type = ActivityType.walking,
  ActivitySource source = ActivitySource.device,
  int? steps,
  int? minutes,
  double? km,
  int? calories,
}) => Activity(
  id: id,
  userId: 'u1',
  type: type,
  source: source,
  startedAt: at,
  steps: steps,
  durationMinutes: minutes,
  activeMinutes: minutes,
  distanceKm: km,
  calories: calories,
);

DateTime _daysAgo(int n, [int hour = 8]) =>
    DateTime(_now.year, _now.month, _now.day - n, hour);

/// Today: 6,240 steps (78% of 8,000), a 52-min run → 1 workout.
/// Streak: today + 7 previous days of ≥30 active minutes, then a gap.
List<Activity> _history() => [
  _act('today-walk', _daysAgo(0, 7), steps: 6240, minutes: 40, km: 4.7),
  _act(
    'today-run',
    _daysAgo(0, 18),
    type: ActivityType.running,
    source: ActivitySource.fitflex,
    minutes: 12,
    km: 2.1,
    calories: 120,
  ),
  for (var d = 1; d <= 7; d++)
    _act('walk-$d', _daysAgo(d), steps: 5000, minutes: 45),
  _act('gap-walk', _daysAgo(9), steps: 900, minutes: 8),
];

Widget _wrap(Widget child, MemberData data) => FFLocaleScope(
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
);

final _stepGoal = Goal(
  id: 'g-steps',
  userId: 'u1',
  type: GoalType.steps,
  target: 8000,
  period: GoalPeriod.day,
  startDate: DateTime(2026, 9, 1),
  source: GoalSource.defaults,
);

MemberData _data({
  bool sample = false,
  List<Activity>? activities,
  List<Goal>? goals,
}) => MemberData()
  ..activities = activities ?? _history()
  ..activityLoaded = true
  ..activityIsSample = sample
  ..goals = goals ?? [_stepGoal]
  ..goalsLoaded = true;

int _activityStreak(List<Activity> acts) =>
    computeStreak(StreakKind.activity, today: _now, activities: acts)!.current;

void main() {
  group('activity summary', () {
    test('totals today and separates workouts from passive steps', () {
      final s = summarizeDay(_history(), _now);
      expect(s.steps, 6240);
      expect(s.distanceKm, closeTo(6.8, 1e-9));
      expect(s.activeMinutes, 52);
      expect(s.calories, 120);
      expect(s.activityCount, 2);
      expect(s.workoutCount, 1);
      expect((s.goalProgress() * 100).round(), 78);
    });

    test('calories are unknown, not zero, when nothing reports them', () {
      expect(summarizeDay(_history(), _daysAgo(1)).calories, isNull);
    });

    test('manual walks count as workouts, device step walks do not', () {
      final manual = _act(
        'm',
        _now,
        source: ActivitySource.manual,
        minutes: 30,
      );
      expect(manual.isWorkout, isTrue);
      expect(_act('d', _now, steps: 100).isWorkout, isFalse);
    });

    test('streak counts back until the first inactive day', () {
      expect(_activityStreak(_history()), 8);
    });

    test('an unfinished today does not break the streak', () {
      final noToday = _history()
          .where((a) => !a.id.startsWith('today'))
          .toList();
      expect(_activityStreak(noToday), 7);
    });
  });

  testWidgets('Home card shows today, streak and goal progress', (
    tester,
  ) async {
    final data = _data(sample: true);
    await tester.pumpWidget(
      _wrap(TodayActivityCard(data: data, now: _now), data),
    );

    expect(find.text("TODAY'S ACTIVITY"), findsOneWidget);
    expect(find.textContaining('6,240'), findsOneWidget);
    expect(find.text('52'), findsOneWidget); // active minutes
    expect(find.text('8'), findsOneWidget); // streak
    expect(find.text("78% of today's goal"), findsOneWidget);
    expect(find.byKey(const Key('activity-sample-badge')), findsOneWidget);
    expect(find.text('View activity'), findsOneWidget);
  });

  testWidgets('Home card stays hidden until activity has loaded', (
    tester,
  ) async {
    final data = MemberData();
    await tester.pumpWidget(_wrap(TodayActivityCard(data: data), data));
    expect(find.byKey(const Key('today-activity-card')), findsNothing);
  });

  testWidgets('Home card hides the goal bar without a daily step goal', (
    tester,
  ) async {
    final data = _data(goals: []);
    await tester.pumpWidget(
      _wrap(TodayActivityCard(data: data, now: _now), data),
    );
    expect(find.byKey(const Key('activity-goal-percent')), findsNothing);
    expect(find.textContaining('6,240'), findsOneWidget);
  });

  testWidgets('Home card hides the sample badge for real data', (tester) async {
    final data = _data();
    await tester.pumpWidget(
      _wrap(TodayActivityCard(data: data, now: _now), data),
    );
    expect(find.byKey(const Key('activity-sample-badge')), findsNothing);
  });

  testWidgets('Activity tab overview and section switching', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final data = _data(sample: true);
    await tester.pumpWidget(_wrap(MemberActivityTab(now: _now), data));

    for (final label in ['Overview', 'Workouts', 'Challenges', 'Progress']) {
      expect(find.text(label), findsWidgets);
    }
    expect(find.text('6,240'), findsWidgets);
    expect(find.text('120'), findsOneWidget); // calories
    expect(find.byKey(const Key('activity-daily-goal')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('activity-streak')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('8-day activity streak'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('activity-no-challenge')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No active challenge'), findsOneWidget);

    Finder section(String label) => find.descendant(
      of: find.byKey(const Key('activity-sections')),
      matching: find.text(label),
    );
    // Back to the top, where the section control lives.
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 3000),
      3000,
    );
    await tester.pumpAndSettle();
    await tester.tap(section('Workouts'));
    await tester.pumpAndSettle();
    expect(find.text('Running'), findsOneWidget);
    expect(find.text('Walking'), findsNothing);

    await tester.tap(section('Progress'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('progress-goals')), findsOneWidget);
  });

  testWidgets('Activity tab shows empty states without history', (
    tester,
  ) async {
    final data = _data(activities: []);
    await tester.pumpWidget(_wrap(MemberActivityTab(now: _now), data));
    await tester.scrollUntilVisible(
      find.text('No activity logged yet.'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('No activity logged yet.'), findsOneWidget);
    expect(find.text('Start a streak today.'), findsOneWidget);
  });
}
