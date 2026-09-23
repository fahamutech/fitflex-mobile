import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/api_activity_provider.dart';
import 'package:fitflexmobile/shared/activity/goal.dart';
import 'package:fitflexmobile/shared/activity/goal_repository.dart';
import 'package:fitflexmobile/shared/activity/progress_engine.dart';
import 'package:fitflexmobile/shared/activity/streaks.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

// Wednesday 23 Sep 2026, evening. Week = Mon 21 – Sun 27.
final _now = DateTime(2026, 9, 23, 20);

DateTime _d(int month, int day, [int hour = 8]) =>
    DateTime(2026, month, day, hour);

var _seq = 0;
Activity _walk(DateTime at, int steps, {int minutes = 10}) => Activity(
  id: 'w${_seq++}',
  userId: 'u1',
  type: ActivityType.walking,
  source: ActivitySource.device,
  startedAt: at,
  steps: steps,
  activeMinutes: minutes,
  durationMinutes: minutes,
);

Activity _workout(
  DateTime at, {
  ActivityType type = ActivityType.strength,
  int minutes = 45,
  double? km,
}) => Activity(
  id: 'x${_seq++}',
  userId: 'u1',
  type: type,
  source: ActivitySource.fitflex,
  startedAt: at,
  durationMinutes: minutes,
  activeMinutes: minutes,
  distanceKm: km,
);

Goal _goal(
  GoalType type,
  GoalPeriod period,
  num target, {
  DateTime? start,
  DateTime? end,
  GoalStatus status = GoalStatus.active,
}) => Goal(
  id: '${type.wire}-${period.wire}',
  userId: 'u1',
  type: type,
  target: target,
  period: period,
  startDate: start ?? DateTime(2026, 9, 1),
  endDate: end,
  status: status,
);

void main() {
  group('Goal model', () {
    test('parses backend JSON and round-trips', () {
      final g = Goal.tryParse({
        'id': 'goal_1',
        'userId': 'u1',
        'type': 'active_minutes',
        'period': 'custom',
        'target': 600,
        'startDate': '2026-10-01',
        'endDate': '2026-10-31',
        'source': 'trainer',
        'trainerId': 't1',
        'status': 'paused',
        'createdAt': '2026-09-23T10:00:00.000Z',
      })!;
      expect(g.type, GoalType.activeMinutes);
      expect(g.period, GoalPeriod.custom);
      expect(g.startDate, DateTime(2026, 10, 1));
      expect(g.endDate, DateTime(2026, 10, 31));
      expect(g.source, GoalSource.trainer);
      expect(g.source.memberCanRetarget, isFalse);
      expect(g.status, GoalStatus.paused);
      expect(g.currentProgress, isNull);
      expect(g.toJson()['startDate'], '2026-10-01');
      expect(Goal.tryParse(g.toJson())!.endDate, DateTime(2026, 10, 31));
    });

    test('skips goal kinds this build does not know', () {
      expect(
        Goal.tryParse({
          'type': 'pushups',
          'period': 'day',
          'target': 50,
          'startDate': '2026-09-01',
        }),
        isNull,
      );
    });
  });

  group('goal progress', () {
    final acts = [
      _walk(_d(9, 20), 9000), // last Sunday — previous week
      _walk(_d(9, 21), 4000),
      _walk(_d(9, 23, 7), 5000),
      _workout(_d(9, 21, 18)),
      _workout(_d(9, 23, 6), type: ActivityType.running, minutes: 30, km: 5),
      _workout(_d(9, 2)),
    ];

    test('daily steps count only today', () {
      final p = evaluateGoal(
        _goal(GoalType.steps, GoalPeriod.day, 8000),
        acts,
        _now,
      );
      expect(p.current, 5000);
      expect(p.fraction, closeTo(0.625, 1e-9));
      expect(p.completed, isFalse);
      expect(p.goal.currentProgress, 5000);
    });

    test('weekly goals count Monday to now; monthly the calendar month', () {
      final week = evaluateGoal(
        _goal(GoalType.workouts, GoalPeriod.week, 2),
        acts,
        _now,
      );
      expect(week.current, 2);
      expect(week.completed, isTrue);
      expect(week.window.start, DateTime(2026, 9, 21));

      final month = evaluateGoal(
        _goal(GoalType.workouts, GoalPeriod.month, 12),
        acts,
        _now,
      );
      expect(month.current, 3);
      expect(
        evaluateGoal(
          _goal(GoalType.activeMinutes, GoalPeriod.week, 150),
          acts,
          _now,
        ).current,
        95, // two 10-min walks + 45-min strength + 30-min run
      );
      expect(
        evaluateGoal(
          _goal(GoalType.distanceKm, GoalPeriod.week, 20),
          acts,
          _now,
        ).current,
        5,
      );
    });

    test('custom goals know when they are upcoming or ended', () {
      final upcoming = evaluateGoal(
        _goal(
          GoalType.steps,
          GoalPeriod.custom,
          100000,
          start: DateTime(2026, 10, 1),
          end: DateTime(2026, 10, 31),
        ),
        acts,
        _now,
      );
      expect(upcoming.upcoming, isTrue);
      expect(upcoming.current, 0);
      final ended = evaluateGoal(
        _goal(
          GoalType.workouts,
          GoalPeriod.custom,
          5,
          start: DateTime(2026, 9, 1),
          end: DateTime(2026, 9, 10),
        ),
        acts,
        _now,
      );
      expect(ended.ended, isTrue);
      expect(ended.current, 1);
    });

    test('dailyStepGoal ignores paused and non-daily goals', () {
      expect(
        dailyStepGoal([
          _goal(GoalType.steps, GoalPeriod.week, 50000),
          _goal(
            GoalType.steps,
            GoalPeriod.day,
            6000,
            status: GoalStatus.paused,
          ),
        ]),
        isNull,
      );
      expect(
        dailyStepGoal([_goal(GoalType.steps, GoalPeriod.day, 10000)])!.target,
        10000,
      );
    });
  });

  group('totals, milestones and records', () {
    final acts = [
      for (var i = 0; i < 12; i++) _workout(_d(9, 1 + i)),
      _workout(_d(9, 14), type: ActivityType.running, minutes: 60, km: 10.5),
      _workout(_d(9, 15), type: ActivityType.jogging, minutes: 25, km: 3),
      _walk(_d(9, 16), 21000),
      _walk(_d(9, 17), 12000),
    ];

    test('weeklyTotals returns 8 Monday-start weeks, oldest first', () {
      final weeks = weeklyTotals(acts, today: _now);
      expect(weeks, hasLength(8));
      expect(weeks.last.window.start, DateTime(2026, 9, 21));
      expect(weeks.first.window.start, DateTime(2026, 8, 3));
      final wk14 = weeks.firstWhere(
        (w) => w.window.start == DateTime(2026, 9, 14),
      );
      expect(wk14.workouts, 2);
      expect(wk14.steps, 33000);
      expect(wk14.distanceKm, closeTo(13.5, 1e-9));
    });

    test('only reached milestones are reported', () {
      final ids = reachedMilestones(acts).map((m) => m.id);
      expect(ids, containsAll(['workouts_1', 'workouts_10']));
      expect(ids, isNot(contains('workouts_25')));
      expect(ids, isNot(contains('steps_100k')));
      expect(reachedMilestones(const []), isEmpty);
    });

    test('personal records pick the best of each', () {
      final r = personalRecords(acts, today: _now);
      expect(r.longestRun!.distanceKm, 10.5);
      expect(r.mostStepsDay!.steps, 21000);
      expect(r.longestWorkout!.durationMinutes, 60);
      expect(r.bestWeek, isNotNull);
      expect(personalRecords(const [], today: _now).isEmpty, isTrue);
    });
  });

  group('streaks', () {
    // Active (30+ min) on each of the 5 days up to and including yesterday.
    List<Activity> activeDays(Iterable<int> daysAgo) => [
      for (final n in daysAgo)
        _walk(DateTime(2026, 9, 23 - n, 8), 3000, minutes: 35),
    ];

    test('activity streak counts days and forgives an unfinished today', () {
      final s = computeStreak(
        StreakKind.activity,
        today: _now,
        activities: activeDays([1, 2, 3, 4, 5]),
      )!;
      expect(s.unit, StreakUnit.day);
      expect(s.current, 5);
      expect(s.justEnded, isFalse);
    });

    test('a missed day ends the streak once, without a penalty', () {
      // Active 2–9 days ago, nothing yesterday or today.
      final s = computeStreak(
        StreakKind.activity,
        today: _now,
        activities: activeDays([2, 3, 4, 5, 6, 7, 8, 9]),
      )!;
      expect(s.current, 0);
      expect(s.justEnded, isTrue);
      expect(s.endedLength, 8);
      expect(s.best, 8);

      // Two missed days: the old streak is not brought up again.
      final later = computeStreak(
        StreakKind.activity,
        today: _now.add(const Duration(days: 1)),
        activities: activeDays([2, 3, 4, 5, 6, 7, 8, 9]),
      )!;
      expect(later.justEnded, isFalse);
      expect(later.best, 8);
    });

    test('workout streak is weekly with 2+ workouts per week', () {
      final acts = [
        // This week so far: 1 workout (not yet qualifying — no penalty).
        _workout(_d(9, 22)),
        // Last three weeks: 2 each.
        for (final day in [14, 16, 7, 9, 1, 3]) _workout(_d(9, day)),
      ];
      final s = computeStreak(
        StreakKind.workout,
        today: _now,
        activities: acts,
      )!;
      expect(s.unit, StreakUnit.week);
      expect(s.current, 3);
    });

    test('goal streak needs every active daily goal; none means no streak', () {
      final goals = [_goal(GoalType.steps, GoalPeriod.day, 5000)];
      final acts = [
        _walk(_d(9, 22), 6000),
        _walk(_d(9, 21), 5200),
        _walk(_d(9, 20), 4000),
      ];
      final s = computeStreak(
        StreakKind.goal,
        today: _now,
        activities: acts,
        goals: goals,
      )!;
      expect(s.current, 2);
      expect(
        computeStreak(StreakKind.goal, today: _now, activities: acts),
        isNull,
      );
    });

    test('goal streak ignores days before the goal existed', () {
      final goals = [
        _goal(
          GoalType.steps,
          GoalPeriod.day,
          5000,
          start: DateTime(2026, 9, 22),
        ),
      ];
      final acts = [
        for (final d in [22, 21, 20]) _walk(_d(9, d), 6000),
      ];
      expect(
        computeStreak(
          StreakKind.goal,
          today: _now,
          activities: acts,
          goals: goals,
        )!.current,
        1,
      );
    });

    test('gym attendance streak counts weeks with a visit', () {
      final s = computeStreak(
        StreakKind.gymAttendance,
        today: _now,
        checkIns: [_d(9, 22), _d(9, 15), _d(9, 8), _d(8, 25)],
      )!;
      expect(s.current, 3);
      expect(s.best, 3);
    });

    test('challenge streaks are unavailable until challenges exist', () {
      expect(computeStreak(StreakKind.challenge, today: _now), isNull);
    });
  });

  group('LocalGoalRepository', () {
    test(
      'starts with defaults and supports create, pause and archive',
      () async {
        final repo = LocalGoalRepository(clock: () => _now);
        final initial = await repo.list();
        expect(initial.map((g) => g.type), [
          GoalType.steps,
          GoalType.workouts,
          GoalType.activeMinutes,
        ]);
        final created = await repo.create(
          type: GoalType.distanceKm,
          period: GoalPeriod.week,
          target: 20,
        );
        expect(created.source, GoalSource.member);
        await repo.update(initial.first.id, status: GoalStatus.paused);
        await repo.update(created.id, status: GoalStatus.archived);
        final after = await repo.list();
        expect(after, hasLength(3));
        expect(after.first.status, GoalStatus.paused);
      },
    );
  });

  group('API-backed sources', () {
    test(
      'ApiActivityProvider skips malformed rows and sorts newest first',
      () async {
        final provider = ApiActivityProvider(
          _FakeApi(
            activities: [
              {
                'id': 'a',
                'type': 'walking',
                'startedAt': '2026-09-20T06:00:00Z',
              },
              {'id': 'bad', 'type': 'walking'},
              {
                'id': 'b',
                'type': 'running',
                'startedAt': '2026-09-22T06:00:00Z',
              },
            ],
          ),
        );
        final acts = await provider.activitiesBetween(
          userId: 'u1',
          from: DateTime(2026, 9, 1),
          to: DateTime(2026, 9, 30),
        );
        expect(acts.map((a) => a.id), ['b', 'a']);
      },
    );

    test(
      'ApiGoalRepository parses list and sends only changed fields',
      () async {
        final api = _FakeApi(
          goals: [
            {
              'id': 'g1',
              'type': 'steps',
              'period': 'day',
              'target': 8000,
              'startDate': '2026-09-01',
              'source': 'default',
              'status': 'active',
            },
            {'id': 'g2', 'type': 'unknown', 'period': 'day', 'target': 1},
          ],
        );
        final repo = ApiGoalRepository(api);
        expect((await repo.list()).map((g) => g.id), ['g1']);
        await repo.update('g1', status: GoalStatus.archived);
        expect(api.lastPatch, {'status': 'archived'});
      },
    );
  });
}

class _FakeApi extends ApiClient {
  _FakeApi({this.activities = const [], this.goals = const []});

  final List<Map<String, dynamic>> activities;
  final List<Map<String, dynamic>> goals;
  Map<String, dynamic>? lastPatch;

  @override
  Future<List<dynamic>> myActivities({
    required DateTime from,
    required DateTime to,
  }) async => activities;

  @override
  Future<List<dynamic>> myGoals() async => goals;

  @override
  Future<Map<String, dynamic>> updateGoal(
    String id,
    Map<String, dynamic> data,
  ) async {
    lastPatch = data;
    return {
      'goal': {...goals.firstWhere((g) => g['id'] == id), ...data},
    };
  }
}
