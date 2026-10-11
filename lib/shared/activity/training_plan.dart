/// Training Plans — what a plan is built from (the member's goal, target
/// areas and preferences) and the plan itself.
///
/// The ids here are wire values and match the backend's vocabulary
/// (`training-taxonomy.mjs`); the words for them live in the translations
/// under `training.<kind>.<id>`.
library;

/// Fitness goals: the same ones chosen at onboarding and on the profile.
const trainingGoals = [
  'lose_weight',
  'gain_muscle',
  'stay_fit',
  'improve_endurance',
  'improve_flexibility',
  'learn_new_skill',
  'stress_relief',
];

/// Where training is focused, in the groups the picker shows.
const trainingAreaGroups = <String, List<String>>{
  'upper_body': ['chest', 'back', 'shoulders', 'biceps', 'triceps'],
  'lower_body': ['glutes', 'quadriceps', 'hamstrings', 'calves'],
  'core': ['abs', 'obliques', 'lower_back'],
  'general': ['full_body', 'mobility', 'cardio'],
};
const maxTrainingAreas = 6;

const trainingExperienceLevels = ['beginner', 'intermediate', 'advanced'];
const trainingEnvironments = ['gym', 'home', 'outdoor', 'any'];
const trainingEquipment = [
  'none',
  'dumbbells',
  'resistance_bands',
  'free_weights',
  'machines',
  'full_gym',
];
const trainingSessionMinutes = [15, 30, 45, 60, 75];
const trainingDaysPerWeek = [2, 3, 4, 5, 6];
const trainingPlanWeeks = [2, 4, 6, 8, 12];

List<String> _strings(Object? v) => [
  for (final x in (v as List? ?? const [])) x.toString(),
];

/// The preferences a plan is built from. Every field is filled: what the
/// member hasn't chosen comes from their profile and FitFlex's defaults.
class TrainingPreferences {
  final String goal;
  final List<String> targetAreas;
  final String experience;
  final String environment;
  final List<String> equipment;
  final int sessionMinutes;
  final int daysPerWeek;

  const TrainingPreferences({
    this.goal = 'stay_fit',
    this.targetAreas = const ['full_body'],
    this.experience = 'beginner',
    this.environment = 'any',
    this.equipment = const ['none'],
    this.sessionMinutes = 30,
    this.daysPerWeek = 3,
  });

  factory TrainingPreferences.fromJson(Map<String, dynamic> json) {
    const d = TrainingPreferences();
    final areas = _strings(json['targetAreas']);
    final equipment = _strings(json['equipment']);
    return TrainingPreferences(
      goal: json['goal'] as String? ?? d.goal,
      targetAreas: areas.isEmpty ? d.targetAreas : areas,
      experience: json['experience'] as String? ?? d.experience,
      environment: json['environment'] as String? ?? d.environment,
      equipment: equipment.isEmpty ? d.equipment : equipment,
      sessionMinutes:
          (json['sessionMinutes'] as num?)?.toInt() ?? d.sessionMinutes,
      daysPerWeek: (json['daysPerWeek'] as num?)?.toInt() ?? d.daysPerWeek,
    );
  }

  TrainingPreferences copyWith({
    String? goal,
    List<String>? targetAreas,
    String? experience,
    String? environment,
    List<String>? equipment,
    int? sessionMinutes,
    int? daysPerWeek,
  }) => TrainingPreferences(
    goal: goal ?? this.goal,
    targetAreas: targetAreas ?? this.targetAreas,
    experience: experience ?? this.experience,
    environment: environment ?? this.environment,
    equipment: equipment ?? this.equipment,
    sessionMinutes: sessionMinutes ?? this.sessionMinutes,
    daysPerWeek: daysPerWeek ?? this.daysPerWeek,
  );

  Map<String, dynamic> toJson() => {
    'goal': goal,
    'targetAreas': targetAreas,
    'experience': experience,
    'environment': environment,
    'equipment': equipment,
    'sessionMinutes': sessionMinutes,
    'daysPerWeek': daysPerWeek,
  };
}

/// One session of a plan: the day it falls on and the workout it runs.
class TrainingPlanDay {
  /// Local calendar day.
  final DateTime date;
  final List<String> focusAreas;
  final String? name;

  /// Null once the workout has been removed.
  final String? workoutId;

  /// `planned`, `in_progress`, `completed`, `skipped` or `removed`.
  final String status;
  final int? estimatedDuration;
  final int exerciseCount;

  const TrainingPlanDay({
    required this.date,
    this.focusAreas = const [],
    this.name,
    this.workoutId,
    this.status = 'planned',
    this.estimatedDuration,
    this.exerciseCount = 0,
  });

  bool get isOpen => status == 'planned' || status == 'in_progress';
  bool get isDone => status == 'completed';

  static TrainingPlanDay? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final date = DateTime.tryParse(raw['date'] as String? ?? '');
    if (date == null) return null;
    return TrainingPlanDay(
      date: DateTime(date.year, date.month, date.day),
      focusAreas: _strings(raw['focusAreas']),
      name: raw['name'] as String?,
      workoutId: raw['workoutId'] as String?,
      status: raw['status'] as String? ?? 'planned',
      estimatedDuration: (raw['estimatedDuration'] as num?)?.toInt(),
      exerciseCount: (raw['exerciseCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class TrainingPlanWeek {
  final int week;
  final List<TrainingPlanDay> days;
  const TrainingPlanWeek({required this.week, required this.days});
}

/// A member's training plan, week by week, with where they stand.
class TrainingPlan {
  final String id;
  final String name;
  final String goal;
  final List<String> targetAreas;
  final String experience;
  final String environment;
  final int durationWeeks;
  final int daysPerWeek;
  final int sessionMinutes;

  /// `active`, `completed` or `cancelled`.
  final String status;

  /// `member`, `fitflex` or `trainer`.
  final String createdByType;
  final DateTime startDate;
  final DateTime endDate;
  final List<TrainingPlanWeek> weeks;

  final int sessions;
  final int completed;
  final int skipped;

  /// Open sessions whose day has passed.
  final int missed;
  final int currentWeek;

  const TrainingPlan({
    required this.id,
    required this.name,
    required this.goal,
    this.targetAreas = const [],
    this.experience = 'beginner',
    this.environment = 'any',
    required this.durationWeeks,
    required this.daysPerWeek,
    required this.sessionMinutes,
    this.status = 'active',
    this.createdByType = 'fitflex',
    required this.startDate,
    required this.endDate,
    this.weeks = const [],
    this.sessions = 0,
    this.completed = 0,
    this.skipped = 0,
    this.missed = 0,
    this.currentWeek = 1,
  });

  bool get isActive => status == 'active';

  /// 0–1 of the plan's sessions completed.
  double get completion => sessions == 0 ? 0 : completed / sessions;

  Iterable<TrainingPlanDay> get days => weeks.expand((w) => w.days);

  /// The first open session on or after [day], if any.
  TrainingPlanDay? nextOpen(DateTime day) {
    final from = DateTime(day.year, day.month, day.day);
    final open = days.where((d) => d.isOpen && !d.date.isBefore(from)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return open.firstOrNull;
  }

  static DateTime? _day(Object? v) {
    final d = DateTime.tryParse(v as String? ?? '');
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  static TrainingPlan? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final start = _day(json['startDate']);
    final end = _day(json['endDate']);
    final id = json['id'] as String?;
    if (id == null || start == null || end == null) return null;
    final progress = json['progress'] is Map
        ? json['progress'] as Map
        : const {};
    int n(Object? v, [int fallback = 0]) => (v as num?)?.toInt() ?? fallback;
    final weeks = [
      for (final w in (json['weeks'] as List? ?? const []).whereType<Map>())
        TrainingPlanWeek(
          week: n(w['week'], 1),
          days: [
            for (final d in (w['days'] as List? ?? const []))
              ?TrainingPlanDay.tryParse(d),
          ],
        ),
    ];
    return TrainingPlan(
      id: id,
      name: json['name'] as String? ?? '',
      goal: json['goal'] as String? ?? 'stay_fit',
      targetAreas: _strings(json['targetAreas']),
      experience: json['experience'] as String? ?? 'beginner',
      environment: json['environment'] as String? ?? 'any',
      durationWeeks: n(json['durationWeeks'], weeks.length),
      daysPerWeek: n(json['daysPerWeek'], 3),
      sessionMinutes: n(json['sessionMinutes'], 30),
      status: json['status'] as String? ?? 'active',
      createdByType: json['createdByType'] as String? ?? 'fitflex',
      startDate: start,
      endDate: end,
      weeks: weeks,
      sessions: n(progress['sessions'], weeks.expand((w) => w.days).length),
      completed: n(progress['completed']),
      skipped: n(progress['skipped']),
      missed: n(progress['missed']),
      currentWeek: n(progress['currentWeek'], 1),
    );
  }
}
