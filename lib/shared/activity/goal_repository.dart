import '../api_client.dart';
import 'goal.dart';

/// Where a member's goals are stored. Screens depend only on this interface.
abstract class GoalRepository {
  /// Active and paused goals.
  Future<List<Goal>> list();

  Future<Goal> create({
    required GoalType type,
    required GoalPeriod period,
    required num target,
    DateTime? startDate,
    DateTime? endDate,
  });

  Future<Goal> update(String id, {num? target, GoalStatus? status});

  /// Coaching goals: mark done now, or undo this period's latest mark.
  Future<Goal> checkIn(String id, {bool undo = false});
}

/// Goals stored on the FitFlex backend (`/me/goals`).
class ApiGoalRepository implements GoalRepository {
  ApiGoalRepository(this.api);

  final ApiClient api;

  @override
  Future<List<Goal>> list() async {
    final rows = await api.myGoals();
    return [
      for (final r in rows.whereType<Map>())
        ?Goal.tryParse(Map<String, dynamic>.from(r)),
    ];
  }

  @override
  Future<Goal> create({
    required GoalType type,
    required GoalPeriod period,
    required num target,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final res = await api.createGoal({
      'type': type.wire,
      'period': period.wire,
      'target': target,
      'startDate': ?(startDate == null ? null : formatGoalDate(startDate)),
      'endDate': ?(endDate == null ? null : formatGoalDate(endDate)),
    });
    return _parse(res);
  }

  @override
  Future<Goal> update(String id, {num? target, GoalStatus? status}) async {
    final res = await api.updateGoal(id, {
      'target': ?target,
      'status': ?status?.wire,
    });
    return _parse(res);
  }

  @override
  Future<Goal> checkIn(String id, {bool undo = false}) async =>
      _parse(await api.goalCheckIn(id, undo: undo));

  Goal _parse(Map<String, dynamic> res) {
    final goal = Goal.tryParse(
      Map<String, dynamic>.from(res['goal'] as Map? ?? const {}),
    );
    if (goal == null) throw const FormatException('Unexpected goal response');
    return goal;
  }
}

/// In-memory goals for sample-data mode. Starts with the same defaults the
/// backend seeds; nothing is persisted.
class LocalGoalRepository implements GoalRepository {
  LocalGoalRepository({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;
  List<Goal>? _goals;
  var _seq = 0;

  List<Goal> get _store {
    final now = _clock();
    final today = DateTime(now.year, now.month, now.day);
    return _goals ??= [
      _make(GoalType.steps, GoalPeriod.day, 8000, today, GoalSource.defaults),
      _make(GoalType.workouts, GoalPeriod.week, 3, today, GoalSource.defaults),
      _make(
        GoalType.activeMinutes,
        GoalPeriod.week,
        150,
        today,
        GoalSource.defaults,
      ),
    ];
  }

  Goal _make(
    GoalType type,
    GoalPeriod period,
    num target,
    DateTime start,
    GoalSource source, {
    DateTime? end,
  }) => Goal(
    id: 'local_goal_${_seq++}',
    userId: '',
    type: type,
    target: target,
    period: period,
    startDate: start,
    endDate: end,
    source: source,
  );

  @override
  Future<List<Goal>> list() async =>
      _store.where((g) => g.status != GoalStatus.archived).toList();

  @override
  Future<Goal> create({
    required GoalType type,
    required GoalPeriod period,
    required num target,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final now = _clock();
    final goal = _make(
      type,
      period,
      target,
      startDate ?? DateTime(now.year, now.month, now.day),
      GoalSource.member,
      end: endDate,
    );
    _store.add(goal);
    return goal;
  }

  @override
  Future<Goal> update(String id, {num? target, GoalStatus? status}) async {
    final i = _store.indexWhere((g) => g.id == id);
    if (i < 0) throw StateError('Unknown goal $id');
    return _store[i] = _store[i].copyWith(target: target, status: status);
  }

  @override
  Future<Goal> checkIn(String id, {bool undo = false}) async {
    final i = _store.indexWhere((g) => g.id == id);
    if (i < 0) throw StateError('Unknown goal $id');
    final done = [..._store[i].completions];
    if (undo) {
      if (done.isNotEmpty) done.removeLast();
    } else {
      done.add(_clock());
    }
    return _store[i] = _store[i].copyWith(completions: done);
  }
}
