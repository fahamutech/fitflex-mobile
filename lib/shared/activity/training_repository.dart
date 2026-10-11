import '../api_client.dart';
import 'activity_summary.dart';
import 'training_plan.dart';
import 'workout.dart';
import 'workout_repository.dart';

/// Thrown when a plan is asked for while the member is already on one.
class ActivePlanExists implements Exception {
  const ActivePlanExists();
}

/// Where a member's training preferences and plan live. Screens depend only
/// on this interface.
abstract class TrainingRepository {
  /// The preferences a plan would be built from, gaps filled in.
  Future<TrainingPreferences> preferences();

  Future<TrainingPreferences> savePreferences(TrainingPreferences preferences);

  /// The plan the member is on, or null.
  Future<TrainingPlan?> currentPlan();

  /// Has FitFlex make a plan from the saved preferences. Throws
  /// [ActivePlanExists] unless [replace] ends the plan they are on.
  /// [lang] is the language the plan's session names are written in.
  Future<TrainingPlan> generate({
    required int weeks,
    bool replace = false,
    String? lang,
  });

  Future<void> cancel(String planId);
}

/// Training plans made and stored by the FitFlex backend.
class ApiTrainingRepository implements TrainingRepository {
  ApiTrainingRepository(this.api);

  final ApiClient api;

  @override
  Future<TrainingPreferences> preferences() async {
    final res = await api.trainingPreferences();
    return TrainingPreferences.fromJson(
      Map<String, dynamic>.from(res['effective'] as Map? ?? const {}),
    );
  }

  @override
  Future<TrainingPreferences> savePreferences(TrainingPreferences p) async {
    final res = await api.saveTrainingPreferences(p.toJson());
    return TrainingPreferences.fromJson(
      Map<String, dynamic>.from(res['effective'] as Map? ?? const {}),
    );
  }

  @override
  Future<TrainingPlan?> currentPlan() async =>
      TrainingPlan.tryParse((await api.currentTrainingPlan())['plan']);

  @override
  Future<TrainingPlan> generate({
    required int weeks,
    bool replace = false,
    String? lang,
  }) async {
    try {
      final res = await api.createTrainingPlan({
        'durationWeeks': weeks,
        'replace': replace,
        'lang': ?lang,
      });
      final plan = TrainingPlan.tryParse(res['plan']);
      if (plan == null) throw const FormatException('plan');
      return plan;
    } on ApiException catch (e) {
      if (e.code == 'active_plan_exists') throw const ActivePlanExists();
      rethrow;
    }
  }

  @override
  Future<void> cancel(String planId) async =>
      await api.cancelTrainingPlan(planId);
}

/// Sample-data mode: a small stand-in for the backend's engine. It lays the
/// built-in workout templates out across the weeks so the screens can be
/// tried without an account; nothing is persisted. Real plans always come
/// from the backend.
class LocalTrainingRepository implements TrainingRepository {
  LocalTrainingRepository({required this.workouts, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final WorkoutRepository workouts;
  final DateTime Function() _clock;

  TrainingPreferences _preferences = const TrainingPreferences();
  TrainingPlan? _plan;
  int _seq = 1;

  // Days into the week each session falls, as the backend spaces them.
  static const _offsets = {
    2: [0, 3],
    3: [0, 2, 4],
    4: [0, 1, 3, 5],
    5: [0, 1, 2, 4, 5],
    6: [0, 1, 2, 3, 4, 5],
  };

  @override
  Future<TrainingPreferences> preferences() async => _preferences;

  @override
  Future<TrainingPreferences> savePreferences(TrainingPreferences p) async =>
      _preferences = p;

  Future<List<Workout>> _sessions(TrainingPlan plan) async {
    final ids = plan.days.map((d) => d.workoutId).toSet();
    final all = await workouts.list(from: plan.startDate, to: plan.endDate);
    return all.where((w) => ids.contains(w.id)).toList();
  }

  @override
  Future<TrainingPlan?> currentPlan() async {
    final plan = _plan;
    if (plan == null) return null;
    final today = dayOf(_clock());
    if (plan.endDate.isBefore(today)) return _plan = null;
    final byId = {for (final w in await _sessions(plan)) w.id: w};
    String status(TrainingPlanDay d) =>
        byId[d.workoutId]?.status.wire ?? 'removed';
    final weeks = [
      for (final w in plan.weeks)
        TrainingPlanWeek(
          week: w.week,
          days: [
            for (final d in w.days)
              TrainingPlanDay(
                date: d.date,
                focusAreas: d.focusAreas,
                name: d.name,
                workoutId: byId.containsKey(d.workoutId) ? d.workoutId : null,
                status: status(d),
                estimatedDuration: d.estimatedDuration,
                exerciseCount: d.exerciseCount,
              ),
          ],
        ),
    ];
    final days = weeks
        .expand((w) => w.days)
        .where((d) => d.status != 'removed');
    return TrainingPlan(
      id: plan.id,
      name: plan.name,
      goal: plan.goal,
      targetAreas: plan.targetAreas,
      experience: plan.experience,
      environment: plan.environment,
      durationWeeks: plan.durationWeeks,
      daysPerWeek: plan.daysPerWeek,
      sessionMinutes: plan.sessionMinutes,
      startDate: plan.startDate,
      endDate: plan.endDate,
      weeks: weeks,
      sessions: days.length,
      completed: days.where((d) => d.isDone).length,
      skipped: days.where((d) => d.status == 'skipped').length,
      missed: days.where((d) => d.isOpen && d.date.isBefore(today)).length,
      currentWeek: (today.difference(plan.startDate).inDays ~/ 7 + 1).clamp(
        1,
        plan.durationWeeks,
      ),
    );
  }

  @override
  Future<TrainingPlan> generate({
    required int weeks,
    bool replace = false,
    String? lang,
  }) async {
    final existing = await currentPlan();
    if (existing != null) {
      if (!replace) throw const ActivePlanExists();
      await cancel(existing.id);
    }
    final templates = await workouts.templates();
    final p = _preferences;
    final start = dayOf(_clock());
    final offsets = _offsets[p.daysPerWeek] ?? _offsets[3]!;
    final planWeeks = <TrainingPlanWeek>[];
    var n = 0;
    for (var week = 1; week <= weeks; week += 1) {
      final days = <TrainingPlanDay>[];
      for (final offset in offsets) {
        final date = start.add(Duration(days: (week - 1) * 7 + offset));
        final template = templates[n++ % templates.length];
        final w = await workouts.plan(templateId: template.id, date: date);
        days.add(
          TrainingPlanDay(
            date: date,
            name: w.name,
            workoutId: w.id,
            estimatedDuration: w.estimatedDuration,
            exerciseCount: w.exercises.length,
          ),
        );
      }
      planWeeks.add(TrainingPlanWeek(week: week, days: days));
    }
    _plan = TrainingPlan(
      id: 'local_plan_${_seq++}',
      name: '',
      goal: p.goal,
      targetAreas: p.targetAreas,
      experience: p.experience,
      environment: p.environment,
      durationWeeks: weeks,
      daysPerWeek: offsets.length,
      sessionMinutes: p.sessionMinutes,
      startDate: start,
      endDate: start.add(Duration(days: weeks * 7 - 1)),
      weeks: planWeeks,
    );
    return (await currentPlan())!;
  }

  @override
  Future<void> cancel(String planId) async {
    final plan = _plan;
    if (plan == null || plan.id != planId) return;
    // Sessions never started are set aside; ones done stay in history.
    for (final w in await _sessions(plan)) {
      if (w.status == WorkoutStatus.planned) await workouts.skip(w.id);
    }
    _plan = null;
  }
}
