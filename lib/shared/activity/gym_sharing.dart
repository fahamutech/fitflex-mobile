/// Gym ↔ member activity sharing.
///
/// A gym always sees its own records: check-ins and the visit patterns
/// derived from them. Anything from the member's activity log is shared
/// with a gym only when the member switches it on for that gym.
library;

import 'challenge.dart';

/// What a member can additionally share with a gym. Wire keys match the
/// backend.
enum GymPermission {
  classAttendance('classAttendance'),
  gymWorkouts('gymWorkouts'),
  challenges('challenges');

  const GymPermission(this.wire);

  final String wire;
}

class GymCard {
  final String id;
  final String? name;
  final String? location;

  const GymCard({required this.id, this.name, this.location});

  static GymCard? tryParse(Object? json) => json is Map
      ? GymCard(
          id: json['id'] as String? ?? '',
          name: json['name'] as String?,
          location: json['location'] as String?,
        )
      : null;
}

Set<GymPermission> parseGymPermissions(Object? json) {
  final map = json is Map ? json : const {};
  return {
    for (final p in GymPermission.values)
      if (map[p.wire] == true) p,
  };
}

Map<String, bool> gymPermissionsJson(Set<GymPermission> granted) => {
  for (final p in GymPermission.values) p.wire: granted.contains(p),
};

/// One gym on the member's sharing screen.
class GymSharing {
  final GymCard gym;

  /// Why the gym is listed: `member` (home gym) and/or `visited`.
  final List<String> reasons;
  final Set<GymPermission> permissions;

  const GymSharing({
    required this.gym,
    this.reasons = const [],
    this.permissions = const {},
  });

  GymSharing withPermissions(Set<GymPermission> p) =>
      GymSharing(gym: gym, reasons: reasons, permissions: p);

  static GymSharing? tryParse(Map<String, dynamic> json) {
    final gym = GymCard.tryParse(json['gym']);
    if (gym == null) return null;
    return GymSharing(
      gym: gym,
      reasons: [
        for (final r in (json['reasons'] as List? ?? const [])) r.toString(),
      ],
      permissions: parseGymPermissions(json['permissions']),
    );
  }
}

/// Visit patterns from a member's check-ins at one gym.
class GymEngagement {
  final int visits30;
  final int previous30;
  final DateTime? lastVisit;
  final int? daysSinceLastVisit;
  final int weekStreak;
  final double avgVisitsPerWeek;

  /// `active`, `slipping`, `at_risk`, `lapsed` or `none`.
  final String status;

  const GymEngagement({
    this.visits30 = 0,
    this.previous30 = 0,
    this.lastVisit,
    this.daysSinceLastVisit,
    this.weekStreak = 0,
    this.avgVisitsPerWeek = 0,
    this.status = 'none',
  });

  factory GymEngagement.fromJson(Map json) => GymEngagement(
    visits30: (json['visits30'] as num?)?.toInt() ?? 0,
    previous30: (json['previous30'] as num?)?.toInt() ?? 0,
    lastVisit: DateTime.tryParse(json['lastVisit'] as String? ?? ''),
    daysSinceLastVisit: (json['daysSinceLastVisit'] as num?)?.toInt(),
    weekStreak: (json['weekStreak'] as num?)?.toInt() ?? 0,
    avgVisitsPerWeek: (json['avgVisitsPerWeek'] as num?)?.toDouble() ?? 0,
    status: json['status'] as String? ?? 'none',
  );
}

/// A class or workout the member did at the gym: when, what, how long.
class GymVisitItem {
  final DateTime date;
  final String type;
  final int? durationMinutes;

  const GymVisitItem({
    required this.date,
    required this.type,
    this.durationMinutes,
  });
}

/// What one gym may see about one member.
class GymMemberActivity {
  final GymCard gym;
  final Set<GymPermission> permissions;
  final GymEngagement engagement;

  /// Null unless the member shares it with this gym.
  final List<GymVisitItem>? classAttendance;
  final List<GymVisitItem>? gymWorkouts;
  final List<SharedChallengeProgress>? challenges;

  const GymMemberActivity({
    required this.gym,
    required this.permissions,
    required this.engagement,
    this.classAttendance,
    this.gymWorkouts,
    this.challenges,
  });

  static List<GymVisitItem>? _items(Object? json) => json is List
      ? [
          for (final i in json.whereType<Map>())
            GymVisitItem(
              date:
                  DateTime.tryParse(i['date'] as String? ?? '') ??
                  DateTime(1970),
              type: i['type'] as String? ?? 'other',
              durationMinutes: (i['durationMinutes'] as num?)?.toInt(),
            ),
        ]
      : null;

  static GymMemberActivity? tryParse(Map<String, dynamic> json) {
    final gym = GymCard.tryParse(json['gym']);
    if (gym == null) return null;
    return GymMemberActivity(
      gym: gym,
      permissions: parseGymPermissions(json['permissions']),
      engagement: GymEngagement.fromJson(
        json['engagement'] is Map ? json['engagement'] as Map : const {},
      ),
      classAttendance: _items(json['classAttendance']),
      gymWorkouts: _items(json['gymWorkouts']),
      challenges: SharedChallengeProgress.parseList(json['challenges']),
    );
  }
}

/// A member the gym may want to contact: they used to come and have
/// stopped.
class GymCheckInItem {
  final String memberId;
  final String? displayName;
  final GymEngagement engagement;

  const GymCheckInItem({
    required this.memberId,
    this.displayName,
    required this.engagement,
  });
}

/// Gym-wide membership engagement, from check-ins only.
class GymEngagementOverview {
  final int members;
  final int active;
  final int slipping;
  final int atRisk;
  final int lapsed;
  final int newThisMonth;
  final int visits30;
  final int previous30;
  final List<GymCheckInItem> checkIn;

  const GymEngagementOverview({
    this.members = 0,
    this.active = 0,
    this.slipping = 0,
    this.atRisk = 0,
    this.lapsed = 0,
    this.newThisMonth = 0,
    this.visits30 = 0,
    this.previous30 = 0,
    this.checkIn = const [],
  });

  factory GymEngagementOverview.fromJson(Map<String, dynamic> json) =>
      GymEngagementOverview(
        members: (json['members'] as num?)?.toInt() ?? 0,
        active: (json['active'] as num?)?.toInt() ?? 0,
        slipping: (json['slipping'] as num?)?.toInt() ?? 0,
        atRisk: (json['at_risk'] as num?)?.toInt() ?? 0,
        lapsed: (json['lapsed'] as num?)?.toInt() ?? 0,
        newThisMonth: (json['newThisMonth'] as num?)?.toInt() ?? 0,
        visits30: (json['visits30'] as num?)?.toInt() ?? 0,
        previous30: (json['previous30'] as num?)?.toInt() ?? 0,
        checkIn: [
          for (final c
              in (json['checkIn'] as List? ?? const []).whereType<Map>())
            GymCheckInItem(
              memberId: (c['member'] as Map?)?['id'] as String? ?? '',
              displayName: (c['member'] as Map?)?['displayName'] as String?,
              engagement: GymEngagement.fromJson(c),
            ),
        ],
      );
}
