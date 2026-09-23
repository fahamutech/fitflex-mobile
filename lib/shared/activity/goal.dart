/// Activity & Progress Engine — member goals.
library;

/// What a goal measures. Wire values match the backend.
enum GoalType {
  steps('steps'),
  workouts('workouts'),
  activeMinutes('active_minutes'),
  distanceKm('distance_km');

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
    this.currentProgress,
  });

  Goal withProgress(num progress) => Goal(
    id: id,
    userId: userId,
    type: type,
    target: target,
    period: period,
    startDate: startDate,
    endDate: endDate,
    source: source,
    trainerId: trainerId,
    challengeId: challengeId,
    status: status,
    currentProgress: progress,
  );

  Goal copyWith({num? target, GoalStatus? status}) => Goal(
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
    currentProgress: currentProgress,
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
    return Goal(
      id: json['id'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      type: type,
      target: target,
      period: period,
      startDate: start,
      endDate: _parseDate(json['endDate']),
      source: GoalSource.fromWire(json['source'] as String?),
      trainerId: json['trainerId'] as String?,
      challengeId: json['challengeId'] as String?,
      status: GoalStatus.fromWire(json['status'] as String?),
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
