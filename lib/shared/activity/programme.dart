import '../api_client.dart';
import 'training_plan.dart';

// Programmes P1 (slice M1): FitFlex's free, fixed-length, day-by-day plans.
// Backend: fitflex-functions docs/programmes-api.md (member routes, B2).
// The routes answer 404 `feature_disabled` while PROGRAMMES_CATALOGUE is off;
// screens then show nothing of programmes at all.

/// The server has programmes switched off (or doesn't know them yet).
class ProgrammesDisabled implements Exception {
  const ProgrammesDisabled();
}

/// The programme is a draft, retired or gone.
class ProgrammeUnavailable implements Exception {
  const ProgrammeUnavailable();
}

/// The member is on a plan. [sameProgramme] when it is this programme.
class ProgrammePlanExists implements Exception {
  const ProgrammePlanExists({this.planId, this.sameProgramme = false});
  final String? planId;
  final bool sameProgramme;
}

/// The start date was refused: `start_in_past`, `start_too_far` or
/// `invalid_start_date`.
class ProgrammeStartRefused implements Exception {
  const ProgrammeStartRefused(this.code);
  final String code;
}

/// A day of a programme: `gym`, `home` or `rest`.
class ProgrammeDay {
  const ProgrammeDay({
    required this.day,
    required this.type,
    this.workoutName,
    this.estimatedDuration,
    this.exerciseCount = 0,
  });

  final int day;
  final String type;
  final String? workoutName;
  final int? estimatedDuration;
  final int exerciseCount;

  bool get isRest => type == 'rest';
  bool get hasWorkout => workoutName != null;

  static ProgrammeDay? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final day = (raw['day'] as num?)?.toInt();
    final type = raw['type'] as String?;
    if (day == null || !const ['gym', 'home', 'rest'].contains(type)) {
      return null;
    }
    final w = raw['workout'] is Map ? raw['workout'] as Map : null;
    return ProgrammeDay(
      day: day,
      type: type!,
      workoutName: w?['name'] as String?,
      estimatedDuration: (w?['estimatedDuration'] as num?)?.toInt(),
      exerciseCount: (w?['exerciseCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A programme as the catalogue lists it; [days] only on the detail answer.
class Programme {
  const Programme({
    required this.id,
    required this.title,
    this.summary,
    required this.goal,
    required this.level,
    required this.environment,
    this.equipment = const [],
    required this.lengthDays,
    this.dayTypes = const [],
    this.days = const [],
    this.free = true,
  });

  final String id;
  final String title;
  final String? summary;
  final String goal;
  final String level;
  final String environment;
  final List<String> equipment;
  final int lengthDays;

  /// One type per day, in order (the catalogue's day-mix strip).
  final List<String> dayTypes;
  final List<ProgrammeDay> days;
  final bool free;

  List<String> get types =>
      days.isNotEmpty ? [for (final d in days) d.type] : dayTypes;
  int count(String type) => types.where((t) => t == type).length;

  /// Every equipment entry except "none" (bodyweight needs nothing).
  List<String> get needs => [
    for (final e in equipment)
      if (e != 'none') e,
  ];

  static Programme? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String?;
    final title = raw['title'] as String?;
    final length = (raw['lengthDays'] as num?)?.toInt();
    if (id == null || title == null || length == null) return null;
    List<String> strings(Object? v) => [
      for (final x in (v as List? ?? const [])) x.toString(),
    ];
    return Programme(
      id: id,
      title: title,
      summary: raw['summary'] as String?,
      goal: raw['goal'] as String? ?? 'stay_fit',
      level: raw['level'] as String? ?? 'beginner',
      environment: raw['environment'] as String? ?? 'any',
      equipment: strings(raw['equipment']),
      lengthDays: length,
      dayTypes: strings(raw['dayTypes']),
      days: [
        for (final d in (raw['days'] as List? ?? const []))
          ?ProgrammeDay.tryParse(d),
      ],
      free: raw['free'] != false,
    );
  }
}

/// Catalogue filters. Length buckets: 7, 14, 21 days, or 28 and more.
class ProgrammeFilters {
  const ProgrammeFilters({this.goal, this.level, this.length, this.where});

  final String? goal;
  final String? level;

  /// 7, 14, 21 or 28 (28 = "28+").
  final int? length;
  final String? where;

  bool get isEmpty =>
      goal == null && level == null && length == null && where == null;

  ProgrammeFilters copyWith({
    String? Function()? goal,
    String? Function()? level,
    int? Function()? length,
    String? Function()? where,
  }) => ProgrammeFilters(
    goal: goal != null ? goal() : this.goal,
    level: level != null ? level() : this.level,
    length: length != null ? length() : this.length,
    where: where != null ? where() : this.where,
  );

  Map<String, String> toQuery({String? lang}) => {
    'goal': ?goal,
    'level': ?level,
    'environment': ?where,
    if (length != null) 'minDays': '$length',
    if (length != null && length! < 28) 'maxDays': '$length',
    'lang': ?lang,
  };
}

/// Where members' programmes come from. Screens depend only on this.
abstract class ProgrammeRepository {
  /// Live programmes; throws [ProgrammesDisabled] while they are off.
  Future<List<Programme>> catalogue({
    ProgrammeFilters filters = const ProgrammeFilters(),
    String? lang,
  });

  /// One live programme with its days; throws [ProgrammeUnavailable].
  Future<Programme> programme(String id, {String? lang});

  /// Starts [id] as the member's plan. Throws [ProgrammePlanExists] unless
  /// [replace], [ProgrammeStartRefused] or [ProgrammeUnavailable].
  Future<TrainingPlan> start(
    String id, {
    DateTime? startDate,
    bool replace = false,
    String? lang,
  });

  /// The member's most recent programme plan that ran to its end within
  /// the last [within], in full (for the summary); null when there is none.
  Future<TrainingPlan?> finished({
    DateTime? now,
    Duration within = const Duration(days: 30),
  });
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class ApiProgrammeRepository implements ProgrammeRepository {
  ApiProgrammeRepository(this.api);

  final ApiClient api;

  Never _rethrow(ApiException e) {
    if (e.code == 'feature_disabled') throw const ProgrammesDisabled();
    if (e.code == 'programme_unavailable' ||
        (e.status == 404 && e.code == 'not_found')) {
      throw const ProgrammeUnavailable();
    }
    throw e;
  }

  @override
  Future<List<Programme>> catalogue({
    ProgrammeFilters filters = const ProgrammeFilters(),
    String? lang,
  }) async {
    try {
      final res = await api.programmes(filters.toQuery(lang: lang));
      return [
        for (final raw in res['programmes'] as List? ?? const [])
          ?Programme.tryParse(raw),
      ];
    } on ApiException catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<Programme> programme(String id, {String? lang}) async {
    try {
      final p = Programme.tryParse(
        (await api.programme(id, lang: lang))['programme'],
      );
      if (p == null) throw const ProgrammeUnavailable();
      return p;
    } on ApiException catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<TrainingPlan> start(
    String id, {
    DateTime? startDate,
    bool replace = false,
    String? lang,
  }) async {
    try {
      final res = await api.startProgramme(id, {
        if (startDate != null) 'startDate': _date(startDate),
        if (replace) 'replace': true,
        'lang': ?lang,
      });
      final plan = TrainingPlan.tryParse(res['plan']);
      if (plan == null) throw const FormatException('plan');
      return plan;
    } on ApiException catch (e) {
      final body = e.body is Map ? e.body as Map : const {};
      switch (e.code) {
        case 'active_plan_exists':
          throw ProgrammePlanExists(planId: body['planId'] as String?);
        case 'already_on_programme':
          throw ProgrammePlanExists(
            planId: body['planId'] as String?,
            sameProgramme: true,
          );
        case 'start_in_past' || 'start_too_far' || 'invalid_start_date':
          throw ProgrammeStartRefused(e.code!);
      }
      _rethrow(e);
    }
  }

  @override
  Future<TrainingPlan?> finished({
    DateTime? now,
    Duration within = const Duration(days: 30),
  }) => _latestFinished(api, now: now, within: within);
}

/// The latest completed programme plan from the member's plan list.
Future<TrainingPlan?> _latestFinished(
  ApiClient api, {
  DateTime? now,
  required Duration within,
}) async {
  final today = now ?? DateTime.now();
  final cutoff = DateTime(today.year, today.month, today.day).subtract(within);
  final rows = (await api.trainingPlans())['plans'] as List? ?? const [];
  for (final raw in rows.whereType<Map>()) {
    if (raw['programmeId'] == null || raw['status'] != 'completed') continue;
    final end = DateTime.tryParse(raw['endDate'] as String? ?? '');
    if (end == null || end.isBefore(cutoff)) continue;
    final id = raw['id'] as String?;
    if (id == null) continue;
    return TrainingPlan.tryParse((await api.trainingPlan(id))['plan']);
  }
  return null;
}

/// Sample-data mode: programmes are a backend feature, so there are none.
/// The screens then hide every way in, as when the server has them off.
class LocalProgrammeRepository implements ProgrammeRepository {
  const LocalProgrammeRepository();

  @override
  Future<List<Programme>> catalogue({
    ProgrammeFilters filters = const ProgrammeFilters(),
    String? lang,
  }) async => throw const ProgrammesDisabled();

  @override
  Future<Programme> programme(String id, {String? lang}) async =>
      throw const ProgrammesDisabled();

  @override
  Future<TrainingPlan> start(
    String id, {
    DateTime? startDate,
    bool replace = false,
    String? lang,
  }) async => throw const ProgrammesDisabled();

  @override
  Future<TrainingPlan?> finished({
    DateTime? now,
    Duration within = const Duration(days: 30),
  }) async => null;
}
