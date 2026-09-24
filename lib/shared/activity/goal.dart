/// Activity & Progress Engine — member goals.
library;

/// What a goal measures. Wire values match the backend.
enum GoalType {
  steps('steps'),
  workouts('workouts'),
  activeMinutes('active_minutes'),
  distanceKm('distance_km'),

  /// A trainer's coaching goal ("Stretch after every session"): counted
  /// from the times the member marks it done, not from activity.
  custom('custom');

  const GoalType(this.wire);

  final String wire;

  static GoalType? fromWire(String? value) {
    for (final t in values) {
      if (t.wire == value) return t;
    }
    return null;
  }
}

/// How often the target resets. `custom` runs once from start to end date.
enum GoalPeriod {
  day('day'),
  week('week'),
  month('month'),
  custom('custom');

  const GoalPeriod(this.wire);

  final String wire;

  static GoalPeriod? fromWire(String? value) {
    for (final p in values) {
      if (p.wire == value) return p;
    }
    return null;
  }
}

/// Who set the goal.
enum GoalSource {
  member('member'),
  defaults('default'),
  trainer('trainer'),
  challenge('challenge');

  const GoalSource(this.wire);

  final String wire;

  static GoalSource fromWire(String? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => GoalSource.member,
  );

  /// Trainer and challenge targets aren't the member's to change.
  bool get memberCanRetarget =>
      this == GoalSource.member || this == GoalSource.defaults;
}

/// Who created a goal: the member, their trainer, or FitFlex (defaults and
/// challenges). Kept for the audit trail and "Assigned by Sarah".
enum GoalCreatorType {
  member('member'),
  trainer('trainer'),
  system('system');

  const GoalCreatorType(this.wire);

  final String wire;

  static GoalCreatorType fromWire(String? value, GoalSource source) {
    for (final t in values) {
      if (t.wire == value) return t;
    }
    return switch (source) {
      GoalSource.member => GoalCreatorType.member,
      GoalSource.trainer => GoalCreatorType.trainer,
      _ => GoalCreatorType.system,
    };
  }
}

enum GoalStatus {
  active('active'),
  paused('paused'),
  archived('archived');

  const GoalStatus(this.wire);

  final String wire;

  static GoalStatus fromWire(String? value) => values.firstWhere(
    (s) => s.wire == value,
    orElse: () => GoalStatus.active,
  );
}

class Goal {
  final String id;
  final String userId;
  final GoalType type;
  final num target;
  final GoalPeriod period;

  /// Calendar dates (local), no time component.
  final DateTime startDate;
  final DateTime? endDate;

  final GoalSource source;
  final String? trainerId;
  final String? challengeId;
  final GoalStatus status;

  final GoalCreatorType createdByType;
  final String? createdById;

  /// The trainer's name for "Assigned by Sarah".
  final String? createdByName;

  /// A coaching goal's text, or a challenge goal's challenge name.
  final String? title;

  /// When the member marked a coaching goal done.
  final List<DateTime> completions;

  /// Progress within the current period. Never stored on the server — the
  /// progress engine derives it from activity history (see [withProgress]).
  final num? currentProgress;

  const Goal({
    required this.id,
    required this.userId,
    required this.type,
    required this.target,
    required this.period,
    required this.startDate,
    this.endDate,
    this.source = GoalSource.member,
    this.trainerId,
    this.challengeId,
    this.status = GoalStatus.active,
    this.createdByType = GoalCreatorType.member,
    this.createdById,
    this.createdByName,
    this.title,
    this.completions = const [],
    this.currentProgress,
  });

  bool get isFromTrainer => createdByType == GoalCreatorType.trainer;
  bool get isCoaching => type == GoalType.custom;

  Goal withProgress(num progress) => copyWith(currentProgress: progress);

  Goal copyWith({
    num? target,
    GoalStatus? status,
    List<DateTime>? completions,
    num? currentProgress,
  }) => Goal(
    id: id,
    userId: userId,
    type: type,
    target: target ?? this.target,
    period: period,
    startDate: startDate,
    endDate: endDate,
    source: source,
    trainerId: trainerId,
    challengeId: challengeId,
    status: status ?? this.status,
    createdByType: createdByType,
    createdById: createdById,
    createdByName: createdByName,
    title: title,
    completions: completions ?? this.completions,
    currentProgress: currentProgress ?? this.currentProgress,
  );

  /// Returns null for goals this app version doesn't understand, so a newer
  /// backend can add goal kinds without breaking older builds.
  static Goal? tryParse(Map<String, dynamic> json) {
    final type = GoalType.fromWire(json['type'] as String?);
    final period = GoalPeriod.fromWire(json['period'] as String?);
    final start = _parseDate(json['startDate']);
    final target = json['target'] as num?;
    if (type == null || period == null || start == null || target == null) {
      return null;
    }
    final source = GoalSource.fromWire(json['source'] as String?);
    final by = json['createdBy'];
    return Goal(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      type: type,
      target: target,
      period: period,
      startDate: start,
      endDate: _parseDate(json['endDate']),
      source: source,
      trainerId: json['trainerId'] as String?,
      challengeId: json['challengeId'] as String?,
      status: GoalStatus.fromWire(json['status'] as String?),
      createdByType: GoalCreatorType.fromWire(
        json['createdByType'] as String?,
        source,
      ),
      createdById: json['createdById'] as String?,
      createdByName: by is Map ? by['name'] as String? : null,
      title: json['title'] as String?,
      completions: [
        for (final c in (json['completions'] as List? ?? const []))
          ?DateTime.tryParse(c.toString()),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'type': type.wire,
    'target': target,
    'period': period.wire,
    'startDate': formatGoalDate(startDate),
    'endDate': ?(endDate == null ? null : formatGoalDate(endDate!)),
    'source': source.wire,
    'trainerId': ?trainerId,
    'challengeId': ?challengeId,
    'status': status.wire,
    'createdByType': createdByType.wire,
    'createdById': ?createdById,
    'title': ?title,
    if (completions.isNotEmpty)
      'completions': [for (final c in completions) c.toUtc().toIso8601String()],
  };
}

DateTime? _parseDate(Object? value) {
  if (value is! String || value.length < 10) return null;
  final d = DateTime.tryParse(value.substring(0, 10));
  return d == null ? null : DateTime(d.year, d.month, d.day);
}

String formatGoalDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';
