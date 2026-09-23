/// Challenge engine — time-boxed challenges from FitFlex, trainers, gyms
/// and companies. Progress is computed here from the member's own activity
/// and check-ins, with the same rules as the server
/// (fitflex-functions src/shared/member-progress.mjs `challengeProgress`).
library;

import 'activity.dart';
import 'activity_summary.dart';

enum ChallengeType {
  steps('steps'),
  distanceKm('distance_km'),
  workouts('workouts'),
  activeMinutes('active_minutes'),
  consistency('consistency'),
  gymAttendance('gym_attendance');

  const ChallengeType(this.wire);

  final String wire;

  static ChallengeType? fromWire(String? v) {
    for (final t in values) {
      if (t.wire == v) return t;
    }
    return null;
  }
}

enum ChallengeCreator {
  fitflex('fitflex'),
  trainer('trainer'),
  gym('gym'),
  corporate('corporate'),
  partner('partner');

  const ChallengeCreator(this.wire);

  final String wire;

  static ChallengeCreator fromWire(String? v) => values.firstWhere(
    (c) => c.wire == v,
    orElse: () => ChallengeCreator.fitflex,
  );
}

/// `upcoming`, `active`, `ended` or `cancelled`.
enum ChallengePhase {
  upcoming,
  active,
  ended,
  cancelled;

  static ChallengePhase fromWire(String? v) => values.firstWhere(
    (p) => p.name == v,
    orElse: () => ChallengePhase.active,
  );
}

class Challenge {
  final String id;
  final String name;
  final String? description;
  final ChallengeType type;
  final num target;

  /// Local calendar dates, inclusive.
  final DateTime startDate;
  final DateTime endDate;
  final ChallengeCreator creatorType;
  final String? creatorId;

  /// Trainer or gym name, when the creator is one.
  final String? creatorName;
  final List<String> rewards;

  /// `public` or `audience` (the creator's clients, members or staff).
  final String visibility;
  final ChallengePhase phase;
  final int participantCount;
  final bool joined;

  const Challenge({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    required this.target,
    required this.startDate,
    required this.endDate,
    required this.creatorType,
    this.creatorId,
    this.creatorName,
    this.rewards = const [],
    this.visibility = 'audience',
    this.phase = ChallengePhase.active,
    this.participantCount = 0,
    this.joined = false,
  });

  static DateTime? _date(Object? v) {
    final d = DateTime.tryParse(
      (v as String? ?? '').padRight(10).substring(0, 10),
    );
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  /// Null for challenge kinds this build doesn't know.
  static Challenge? tryParse(Map<String, dynamic> json) {
    final type = ChallengeType.fromWire(json['type'] as String?);
    final start = _date(json['startDate']);
    final end = _date(json['endDate']);
    if (type == null || start == null || end == null) return null;
    final creator = json['creator'] is Map ? json['creator'] as Map : const {};
    return Challenge(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      type: type,
      target: json['target'] as num? ?? 0,
      startDate: start,
      endDate: end,
      creatorType: ChallengeCreator.fromWire(json['creatorType'] as String?),
      creatorId: json['creatorId'] as String?,
      creatorName: creator['name'] as String?,
      rewards: [
        for (final r in (json['rewards'] as List? ?? const [])) r.toString(),
      ],
      visibility: json['visibility'] as String? ?? 'audience',
      phase: ChallengePhase.fromWire(json['phase'] as String?),
      participantCount: (json['participantCount'] as num?)?.toInt() ?? 0,
      joined: json['joined'] == true,
    );
  }

  /// Whole days left including today, from [now]'s local date.
  int daysLeft(DateTime now) => endDate.difference(dayOf(now)).inDays + 1;

  int daysUntilStart(DateTime now) => startDate.difference(dayOf(now)).inDays;
}

bool _inRange(Challenge c, DateTime t) {
  final d = dayOf(t.toLocal());
  return !d.isBefore(c.startDate) && !d.isAfter(c.endDate);
}

/// Progress on [c] from the member's activity and check-ins. Gym challenges
/// count only check-ins at that gym.
num challengeProgress(
  Challenge c,
  Iterable<Activity> activities, {
  Iterable<({DateTime at, String? gymId})> checkIns = const [],
}) {
  final acts = activities.where((a) => _inRange(c, a.startedAt)).toList();
  switch (c.type) {
    case ChallengeType.steps:
      return acts.fold<int>(0, (n, a) => n + (a.steps ?? 0));
    case ChallengeType.distanceKm:
      final km = acts.fold<double>(0, (n, a) => n + (a.distanceKm ?? 0));
      return (km * 100).round() / 100;
    case ChallengeType.activeMinutes:
      return acts.fold<int>(
        0,
        (n, a) => n + (a.activeMinutes ?? a.durationMinutes ?? 0),
      );
    case ChallengeType.workouts:
      return acts.where((a) => a.isWorkout).length;
    case ChallengeType.consistency:
      final days = <DateTime, List<Activity>>{};
      for (final a in acts) {
        days.putIfAbsent(dayOf(a.startedAt.toLocal()), () => []).add(a);
      }
      return days.entries
          .where((e) => summarizeDay(e.value, e.key).countsForStreak)
          .length;
    case ChallengeType.gymAttendance:
      final gymId = c.creatorType == ChallengeCreator.gym ? c.creatorId : null;
      return {
        for (final ci in checkIns)
          if ((gymId == null || ci.gymId == gymId) && _inRange(c, ci.at))
            dayOf(ci.at.toLocal()),
      }.length;
  }
}

/// Where the member stands on a challenge they joined.
class ChallengeStanding {
  final Challenge challenge;
  final num progress;

  const ChallengeStanding(this.challenge, this.progress);

  double get fraction =>
      challenge.target <= 0 ? 0 : (progress / challenge.target).toDouble();

  bool get reached => progress >= challenge.target;
}

/// My Challenges, grouped the way the member sees them.
class ChallengeGroups {
  /// Joined, still running (or about to start), target not yet reached.
  final List<ChallengeStanding> active;

  /// Joined and either reached or over.
  final List<ChallengeStanding> completed;

  /// Not joined, and still open to join.
  final List<Challenge> available;

  const ChallengeGroups({
    this.active = const [],
    this.completed = const [],
    this.available = const [],
  });
}

ChallengeGroups groupChallenges(
  Iterable<Challenge> challenges,
  Iterable<Activity> activities, {
  Iterable<({DateTime at, String? gymId})> checkIns = const [],
}) {
  final acts = activities.toList();
  final ins = checkIns.toList();
  final active = <ChallengeStanding>[];
  final completed = <ChallengeStanding>[];
  final available = <Challenge>[];
  for (final c in challenges) {
    if (!c.joined) {
      if (c.phase == ChallengePhase.active ||
          c.phase == ChallengePhase.upcoming) {
        available.add(c);
      }
      continue;
    }
    if (c.phase == ChallengePhase.cancelled) continue;
    final s = ChallengeStanding(c, challengeProgress(c, acts, checkIns: ins));
    if (s.reached || c.phase == ChallengePhase.ended) {
      completed.add(s);
    } else {
      active.add(s);
    }
  }
  active.sort((a, b) => a.challenge.endDate.compareTo(b.challenge.endDate));
  completed.sort((a, b) => b.challenge.endDate.compareTo(a.challenge.endDate));
  available.sort((a, b) => a.startDate.compareTo(b.startDate));
  return ChallengeGroups(
    active: active,
    completed: completed,
    available: available,
  );
}

/// A trainer's or gym's view of one member's progress on one of their
/// challenges (only sent when the member shares challenge data).
class SharedChallengeProgress {
  final String name;
  final ChallengeType type;
  final num target;
  final num progress;
  final bool completed;
  final ChallengePhase phase;

  const SharedChallengeProgress({
    required this.name,
    required this.type,
    required this.target,
    required this.progress,
    required this.completed,
    required this.phase,
  });

  static List<SharedChallengeProgress>? parseList(Object? json) {
    if (json is! List) return null;
    return [
      for (final r in json.whereType<Map>())
        if (ChallengeType.fromWire(r['type'] as String?) case final type?)
          SharedChallengeProgress(
            name: r['name'] as String? ?? '',
            type: type,
            target: r['target'] as num? ?? 0,
            progress: r['progress'] as num? ?? 0,
            completed: r['completed'] == true,
            phase: ChallengePhase.fromWire(r['phase'] as String?),
          ),
    ];
  }
}
