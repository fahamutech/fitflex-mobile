/// Trainer ↔ member connections and what a member shares with a trainer.
///
/// A connection starts as the member's request; nothing is shared until
/// the member switches individual permissions on.
library;

import 'challenge.dart';
import 'goal.dart';
import 'workout.dart';

/// What a member can let a trainer see. Wire keys match the backend.
enum TrainerPermission {
  steps('steps'),
  distance('distance'),
  activeMinutes('activeMinutes'),
  workoutHistory('workoutHistory'),
  workoutDetails('workoutDetails'),
  goals('goals'),
  streaks('streaks'),
  challenges('challenges');

  const TrainerPermission(this.wire);

  final String wire;
}

/// An immutable set of granted permissions. Anything not granted is off.
class TrainerPermissions {
  final Set<TrainerPermission> granted;

  const TrainerPermissions([this.granted = const {}]);

  factory TrainerPermissions.fromJson(Object? json) {
    final map = json is Map ? json : const {};
    return TrainerPermissions({
      for (final p in TrainerPermission.values)
        if (map[p.wire] == true) p,
    });
  }

  bool has(TrainerPermission p) => granted.contains(p);

  bool get isEmpty => granted.isEmpty;

  /// Toggles [p]. Details only make sense with history, so turning history
  /// off turns details off too, and turning details on turns history on.
  TrainerPermissions toggle(TrainerPermission p, bool on) {
    final next = {...granted};
    if (on) {
      next.add(p);
      if (p == TrainerPermission.workoutDetails) {
        next.add(TrainerPermission.workoutHistory);
      }
    } else {
      next.remove(p);
      if (p == TrainerPermission.workoutHistory) {
        next.remove(TrainerPermission.workoutDetails);
      }
    }
    return TrainerPermissions(next);
  }

  Map<String, bool> toJson() => {
    for (final p in TrainerPermission.values) p.wire: granted.contains(p),
  };
}

enum TrainerConnectionStatus {
  pending('pending'),
  active('active'),
  declined('declined'),
  ended('ended');

  const TrainerConnectionStatus(this.wire);

  final String wire;

  static TrainerConnectionStatus fromWire(String? v) => values.firstWhere(
    (s) => s.wire == v,
    orElse: () => TrainerConnectionStatus.ended,
  );

  bool get isOpen =>
      this == TrainerConnectionStatus.pending ||
      this == TrainerConnectionStatus.active;
}

/// Name and photo of the other side of a connection.
class ConnectionPerson {
  final String id;
  final String? displayName;
  final String? photoUrl;

  const ConnectionPerson({required this.id, this.displayName, this.photoUrl});

  static ConnectionPerson? tryParse(Object? json) => json is Map
      ? ConnectionPerson(
          id: json['id'] as String? ?? '',
          displayName: json['displayName'] as String?,
          photoUrl: json['photoUrl'] as String?,
        )
      : null;
}

/// TrainerMemberRelationship.
class TrainerConnection {
  final String id;
  final String trainerId;
  final String memberId;
  final TrainerConnectionStatus status;
  final TrainerPermissions permissions;
  final DateTime? requestedAt;
  final DateTime? connectedAt;

  /// Present on the member's side.
  final ConnectionPerson? trainer;

  /// Present on the trainer's side.
  final ConnectionPerson? member;

  /// Trainer's side, active clients only: this week at a glance.
  final ClientSummary? summary;

  const TrainerConnection({
    required this.id,
    required this.trainerId,
    required this.memberId,
    required this.status,
    this.permissions = const TrainerPermissions(),
    this.requestedAt,
    this.connectedAt,
    this.trainer,
    this.member,
    this.summary,
  });

  TrainerConnection withPermissions(TrainerPermissions p) => TrainerConnection(
    id: id,
    trainerId: trainerId,
    memberId: memberId,
    status: status,
    permissions: p,
    requestedAt: requestedAt,
    connectedAt: connectedAt,
    trainer: trainer,
    member: member,
    summary: summary,
  );

  factory TrainerConnection.fromJson(Map<String, dynamic> json) =>
      TrainerConnection(
        id: json['id'] as String? ?? '',
        trainerId: json['trainerId'] as String? ?? '',
        memberId: json['memberId'] as String? ?? '',
        status: TrainerConnectionStatus.fromWire(json['status'] as String?),
        permissions: TrainerPermissions.fromJson(json['permissions']),
        requestedAt: DateTime.tryParse(json['requestedAt'] as String? ?? ''),
        connectedAt: DateTime.tryParse(json['connectedAt'] as String? ?? ''),
        trainer: ConnectionPerson.tryParse(json['trainer']),
        member: ConnectionPerson.tryParse(json['member']),
        summary: ClientSummary.tryParse(json['summary']),
      );
}

/// Something a trainer can act on, or celebrate. [value] depends on [code]:
/// `missed_workouts` → count, `inactive` → days since last workout (null
/// when none in 13 weeks), `streak_ended` → the streak's length.
class ClientPrompt {
  final bool positive;
  final String code;
  final int? value;

  const ClientPrompt({required this.positive, required this.code, this.value});
}

/// A client's week at a glance, built by the server from shared data only.
/// Fields the member doesn't share are null.
class ClientSummary {
  final DateTime weekStart;
  final int? workouts;
  final int? steps;
  final double? distanceKm;
  final int? activeMinutes;
  final ClientGoal? goal;
  final int? streak;
  final int plannedNext7Days;
  final DateTime? lastWorkoutDate;
  final List<ClientPrompt> prompts;

  const ClientSummary({
    required this.weekStart,
    this.workouts,
    this.steps,
    this.distanceKm,
    this.activeMinutes,
    this.goal,
    this.streak,
    this.plannedNext7Days = 0,
    this.lastWorkoutDate,
    this.prompts = const [],
  });

  List<ClientPrompt> get needsAttention =>
      prompts.where((p) => !p.positive).toList();

  bool get hasWeekNumbers =>
      workouts != null ||
      steps != null ||
      distanceKm != null ||
      activeMinutes != null;

  static ClientSummary? tryParse(Object? json) {
    if (json is! Map) return null;
    final week = json['week'] is Map ? json['week'] as Map : const {};
    final g = json['goal'];
    ClientGoal? goal;
    if (g is Map) {
      final type = GoalType.fromWire(g['type'] as String?);
      final period = GoalPeriod.fromWire(g['period'] as String?);
      if (type != null && period != null) {
        goal = ClientGoal(
          type: type,
          period: period,
          target: g['target'] as num? ?? 0,
          current: g['current'] as num? ?? 0,
          completed: g['completed'] == true,
        );
      }
    }
    final last = DateTime.tryParse(json['lastWorkoutDate'] as String? ?? '');
    return ClientSummary(
      weekStart:
          DateTime.tryParse(json['weekStart'] as String? ?? '') ??
          DateTime(1970),
      workouts: (week['workouts'] as num?)?.toInt(),
      steps: (week['steps'] as num?)?.toInt(),
      distanceKm: (week['distanceKm'] as num?)?.toDouble(),
      activeMinutes: (week['activeMinutes'] as num?)?.toInt(),
      goal: goal,
      streak: json['streak'] is Map
          ? ((json['streak'] as Map)['current'] as num?)?.toInt()
          : null,
      plannedNext7Days: (json['plannedNext7Days'] as num?)?.toInt() ?? 0,
      lastWorkoutDate: last == null
          ? null
          : DateTime(last.year, last.month, last.day),
      prompts: [
        for (final a
            in (json['attention'] as List? ?? const []).whereType<Map>())
          ClientPrompt(
            positive: a['kind'] == 'positive',
            code: a['code'] as String? ?? '',
            value: (a['value'] as num?)?.toInt(),
          ),
      ],
    );
  }
}

// ── Trainer plans ───────────────────────────────────────────────────────────

/// One exercise in a trainer's plan: what to do, not what was done.
class PlanExercise {
  String exerciseName;
  String? muscleGroup;
  int sets;

  /// Exactly one of [reps] and [duration] (seconds) is set.
  int? reps;
  int? duration;
  String? instructions;
  bool tracksWeight;

  PlanExercise({
    this.exerciseName = '',
    this.muscleGroup,
    this.sets = 3,
    this.reps = 10,
    this.duration,
    this.instructions,
    this.tracksWeight = false,
  });

  factory PlanExercise.fromJson(Map<String, dynamic> json) => PlanExercise(
    exerciseName: json['exerciseName'] as String? ?? '',
    muscleGroup: json['muscleGroup'] as String?,
    sets: (json['sets'] as num?)?.toInt() ?? 1,
    reps: (json['reps'] as num?)?.toInt(),
    duration: (json['duration'] as num?)?.toInt(),
    instructions: json['instructions'] as String?,
    tracksWeight: json['tracksWeight'] == true,
  );

  bool get isTimed => reps == null && duration != null;

  Map<String, dynamic> toJson() => {
    'exerciseName': exerciseName.trim(),
    'muscleGroup': ?muscleGroup,
    'sets': sets,
    'reps': ?reps,
    'duration': ?duration,
    'instructions': ?((instructions ?? '').trim().isEmpty
        ? null
        : instructions!.trim()),
    'tracksWeight': tracksWeight,
  };
}

/// A trainer's reusable workout, assigned to clients on chosen dates.
class TrainerPlan {
  final String? id;
  String name;
  String? description;
  String activityType;
  int? estimatedDuration;
  final List<PlanExercise> exercises;

  TrainerPlan({
    this.id,
    this.name = '',
    this.description,
    this.activityType = 'strength',
    this.estimatedDuration,
    List<PlanExercise>? exercises,
  }) : exercises = exercises ?? [];

  factory TrainerPlan.fromJson(Map<String, dynamic> json) => TrainerPlan(
    id: json['id'] as String?,
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    activityType: json['activityType'] as String? ?? 'strength',
    estimatedDuration: (json['estimatedDuration'] as num?)?.toInt(),
    exercises: (json['exercises'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => PlanExercise.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'description': ?((description ?? '').trim().isEmpty
        ? null
        : description!.trim()),
    'activityType': activityType,
    'estimatedDuration': ?estimatedDuration,
    'exercises': [for (final e in exercises) e.toJson()],
  };
}

// ── Trainer's view of a client ──────────────────────────────────────────────

class ClientDay {
  final DateTime date;
  final int? steps;
  final double? distanceKm;
  final int? activeMinutes;

  const ClientDay({
    required this.date,
    this.steps,
    this.distanceKm,
    this.activeMinutes,
  });
}

class ClientWorkout {
  final String id;
  final String name;
  final DateTime scheduledDate;
  final bool assignedByYou;

  /// Null unless the member shares workout history.
  final WorkoutStatus? status;
  final int? durationMinutes;
  final int? setsCompleted;
  final int? setsTotal;

  /// Null unless the member shares workout details.
  final List<WorkoutExercise>? exercises;
  final String? notes;

  const ClientWorkout({
    required this.id,
    required this.name,
    required this.scheduledDate,
    required this.assignedByYou,
    this.status,
    this.durationMinutes,
    this.setsCompleted,
    this.setsTotal,
    this.exercises,
    this.notes,
  });

  factory ClientWorkout.fromJson(Map<String, dynamic> json) {
    final d = DateTime.tryParse(json['scheduledDate'] as String? ?? '');
    return ClientWorkout(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      scheduledDate: d == null
          ? DateTime(1970)
          : DateTime(d.year, d.month, d.day),
      assignedByYou: json['assignedByYou'] == true,
      status: json['status'] == null
          ? null
          : WorkoutStatus.fromWire(json['status'] as String?),
      durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
      setsCompleted: (json['setsCompleted'] as num?)?.toInt(),
      setsTotal: (json['setsTotal'] as num?)?.toInt(),
      exercises: json['exercises'] is List
          ? (json['exercises'] as List)
                .whereType<Map>()
                .map(
                  (e) => WorkoutExercise.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : null,
      notes: json['notes'] as String?,
    );
  }
}

class ClientGoal {
  final GoalType type;
  final GoalPeriod period;
  final num target;
  final num current;
  final bool completed;

  const ClientGoal({
    required this.type,
    required this.period,
    required this.target,
    required this.current,
    required this.completed,
  });
}

class ClientStreak {
  final String unit;
  final int current;
  final int best;
  final int? endedLength;

  const ClientStreak({
    required this.unit,
    required this.current,
    required this.best,
    this.endedLength,
  });

  static ClientStreak? tryParse(Object? json) => json is Map
      ? ClientStreak(
          unit: json['unit'] as String? ?? 'day',
          current: (json['current'] as num?)?.toInt() ?? 0,
          best: (json['best'] as num?)?.toInt() ?? 0,
          endedLength: (json['endedLength'] as num?)?.toInt(),
        )
      : null;
}

/// What the trainer may see about one client. Every section is null when
/// the member doesn't share it.
class ClientOverview {
  final TrainerConnection client;
  final List<ClientDay>? activity;
  final List<ClientWorkout> workouts;
  final List<ClientGoal>? goals;
  final Map<String, ClientStreak?>? streaks;
  final ClientSummary? summary;

  /// Null unless the member shares challenge data with this trainer.
  final List<SharedChallengeProgress>? challenges;

  const ClientOverview({
    required this.client,
    this.summary,
    this.challenges,
    this.activity,
    this.workouts = const [],
    this.goals,
    this.streaks,
  });

  factory ClientOverview.fromJson(Map<String, dynamic> json) {
    final activity = json['activity'] is Map
        ? [
            for (final d
                in ((json['activity'] as Map)['days'] as List? ?? const [])
                    .whereType<Map>())
              ClientDay(
                date:
                    DateTime.tryParse(d['date'] as String? ?? '') ??
                    DateTime(1970),
                steps: (d['steps'] as num?)?.toInt(),
                distanceKm: (d['distanceKm'] as num?)?.toDouble(),
                activeMinutes: (d['activeMinutes'] as num?)?.toInt(),
              ),
          ]
        : null;
    final goals = json['goals'] is List
        ? [
            for (final g in (json['goals'] as List).whereType<Map>())
              if (GoalType.fromWire(g['type'] as String?) case final type?)
                if (GoalPeriod.fromWire(g['period'] as String?)
                    case final period?)
                  ClientGoal(
                    type: type,
                    period: period,
                    target: g['target'] as num? ?? 0,
                    current: g['current'] as num? ?? 0,
                    completed: g['completed'] == true,
                  ),
          ]
        : null;
    final streaks = json['streaks'] is Map
        ? {
            for (final e in (json['streaks'] as Map).entries)
              e.key.toString(): ClientStreak.tryParse(e.value),
          }
        : null;
    return ClientOverview(
      client: TrainerConnection.fromJson(
        Map<String, dynamic>.from(json['client'] as Map? ?? const {}),
      ),
      activity: activity,
      workouts: [
        for (final w
            in (json['workouts'] as List? ?? const []).whereType<Map>())
          ClientWorkout.fromJson(Map<String, dynamic>.from(w)),
      ],
      goals: goals,
      streaks: streaks,
      summary: ClientSummary.tryParse(json['summary']),
      challenges: SharedChallengeProgress.parseList(json['challenges']),
    );
  }
}
