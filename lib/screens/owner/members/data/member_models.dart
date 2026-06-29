// Typed data models for the Owner "Members Management" flow.
// Pure data layer — no Flutter / UI imports so the contracts stay portable
// and unit-testable, mirroring the backend member-management-service shapes.

/// Whether a member is a gym-direct subscriber or a FitFlex roaming visitor.
enum OwnerMemberType {
  direct,
  fitflex;

  static OwnerMemberType fromJson(String? value) =>
      value == 'fitflex' ? OwnerMemberType.fitflex : OwnerMemberType.direct;
}

/// Lifecycle status used by the status badge + filters.
enum OwnerMemberStatus {
  active,
  checkedIn,
  expiringSoon,
  expired,
  suspended;

  static OwnerMemberStatus fromJson(String? value) => switch (value) {
    'checked_in' => OwnerMemberStatus.checkedIn,
    'expiring_soon' => OwnerMemberStatus.expiringSoon,
    'expired' => OwnerMemberStatus.expired,
    'suspended' => OwnerMemberStatus.suspended,
    _ => OwnerMemberStatus.active,
  };

  /// Wire value matching the backend status filter contract.
  String get wire => switch (this) {
    OwnerMemberStatus.checkedIn => 'checked_in',
    OwnerMemberStatus.expiringSoon => 'expiring_soon',
    OwnerMemberStatus.expired => 'expired',
    OwnerMemberStatus.suspended => 'suspended',
    OwnerMemberStatus.active => 'active',
  };
}

DateTime? _parseDate(Object? value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}

/// Row in the members list.
class OwnerMember {
  final String id;
  final String publicId;
  final String? displayName;
  final String? phone;
  final String? photoUrl;
  final OwnerMemberType memberType;
  final String? tier;
  final OwnerMemberStatus status;
  final DateTime? lastCheckinAt;
  final DateTime? startDate;
  final DateTime? expiresAt;
  final int? daysLeft;

  const OwnerMember({
    required this.id,
    required this.publicId,
    this.displayName,
    this.phone,
    this.photoUrl,
    required this.memberType,
    this.tier,
    required this.status,
    this.lastCheckinAt,
    this.startDate,
    this.expiresAt,
    this.daysLeft,
  });

  factory OwnerMember.fromJson(Map<String, dynamic> json) => OwnerMember(
    id: json['id'] as String? ?? '',
    publicId: json['publicId'] as String? ?? '',
    displayName: json['displayName'] as String?,
    phone: json['phone'] as String?,
    photoUrl: json['photoUrl'] as String?,
    memberType: OwnerMemberType.fromJson(json['memberType'] as String?),
    tier: json['tier'] as String?,
    status: OwnerMemberStatus.fromJson(json['status'] as String?),
    lastCheckinAt: _parseDate(json['lastCheckinAt']),
    startDate: _parseDate(json['startDate']),
    expiresAt: _parseDate(json['expiresAt']),
    daysLeft: (json['daysLeft'] as num?)?.toInt(),
  );

  String get resolvedName =>
      (displayName?.trim().isNotEmpty ?? false) ? displayName! : publicId;
}

/// Aggregate header stats (Total / Active today / Expiring soon).
class MemberStats {
  final int totalMembers;
  final int activeToday;
  final int expiringSoon;

  const MemberStats({
    this.totalMembers = 0,
    this.activeToday = 0,
    this.expiringSoon = 0,
  });

  factory MemberStats.fromJson(Map<String, dynamic> json) => MemberStats(
    totalMembers: (json['totalMembers'] as num?)?.toInt() ?? 0,
    activeToday: (json['activeToday'] as num?)?.toInt() ?? 0,
    expiringSoon: (json['expiringSoon'] as num?)?.toInt() ?? 0,
  );
}

/// Combined list response.
class MembersResult {
  final List<OwnerMember> members;
  final MemberStats stats;

  const MembersResult({required this.members, required this.stats});

  factory MembersResult.fromJson(Map<String, dynamic> json) => MembersResult(
    members:
        (json['members'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(OwnerMember.fromJson)
            .toList() ??
        const [],
    stats: json['stats'] is Map<String, dynamic>
        ? MemberStats.fromJson(json['stats'] as Map<String, dynamic>)
        : const MemberStats(),
  );

  static const empty = MembersResult(members: [], stats: MemberStats());
}

/// Period presets for the check-in summary selector.
enum CheckInPeriod {
  week,
  month,
  year,
  custom;

  /// Wire value sent to the backend `period` query param.
  String get wire => name;
}

class CheckInSummary {
  final int visits;
  final DateTime? lastCheckinAt;
  final int streakDays;

  const CheckInSummary({
    this.visits = 0,
    this.lastCheckinAt,
    this.streakDays = 0,
  });

  factory CheckInSummary.fromJson(Map<String, dynamic> json) => CheckInSummary(
    visits: (json['visits'] as num?)?.toInt() ?? 0,
    lastCheckinAt: _parseDate(json['lastCheckinAt']),
    streakDays: (json['streakDays'] as num?)?.toInt() ?? 0,
  );
}

/// Generic paginated response wrapper (offset-cursor based) used by the
/// member check-ins and payments "View all" data tables.
class PagedResult<T> {
  final List<T> items;
  final int total;
  final int? nextCursor;

  const PagedResult({required this.items, this.total = 0, this.nextCursor});

  bool get hasMore => nextCursor != null;

  static PagedResult<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromItem,
  ) => PagedResult<T>(
    items:
        (json['items'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(fromItem)
            .toList() ??
        const [],
    total: (json['total'] as num?)?.toInt() ?? 0,
    nextCursor: (json['nextCursor'] as num?)?.toInt(),
  );
}

class MembershipPlan {
  final String? tier;
  final DateTime? startDate;
  final DateTime? expiresAt;
  final int? daysLeft;
  final String status;

  const MembershipPlan({
    this.tier,
    this.startDate,
    this.expiresAt,
    this.daysLeft,
    this.status = 'active',
  });

  factory MembershipPlan.fromJson(Map<String, dynamic> json) => MembershipPlan(
    tier: json['tier'] as String?,
    startDate: _parseDate(json['startDate']),
    expiresAt: _parseDate(json['expiresAt']),
    daysLeft: (json['daysLeft'] as num?)?.toInt(),
    status: json['status'] as String? ?? 'active',
  );
}

class MemberCheckin {
  final String id;
  final DateTime? timestamp;
  final String? gymId;
  final String? gymName;

  const MemberCheckin({
    required this.id,
    this.timestamp,
    this.gymId,
    this.gymName,
  });

  factory MemberCheckin.fromJson(Map<String, dynamic> json) => MemberCheckin(
    id: json['id'] as String? ?? '',
    timestamp: _parseDate(json['timestamp']),
    gymId: json['gymId'] as String?,
    gymName: json['gymName'] as String?,
  );
}

class MemberPayment {
  final String id;
  final num amountTzs;
  final String? tier;
  final String status;
  final DateTime? requestedAt;

  const MemberPayment({
    required this.id,
    this.amountTzs = 0,
    this.tier,
    this.status = 'approved',
    this.requestedAt,
  });

  factory MemberPayment.fromJson(Map<String, dynamic> json) => MemberPayment(
    id: json['id'] as String? ?? '',
    amountTzs: json['amountTzs'] as num? ?? 0,
    tier: json['tier'] as String?,
    status: json['status'] as String? ?? 'approved',
    requestedAt: _parseDate(json['requestedAt']),
  );
}

/// Full member detail powering the Member Details screen.
class MemberDetail {
  final String id;
  final String publicId;
  final String? displayName;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final OwnerMemberType memberType;
  final OwnerMemberStatus status;
  final String accountStatus;
  final DateTime? joinedAt;
  final CheckInSummary checkInSummary;
  final MembershipPlan? plan;
  final List<MemberCheckin> recentCheckins;
  final List<MemberPayment> paymentHistory;

  const MemberDetail({
    required this.id,
    required this.publicId,
    this.displayName,
    this.email,
    this.phone,
    this.photoUrl,
    required this.memberType,
    required this.status,
    this.accountStatus = 'active',
    this.joinedAt,
    this.checkInSummary = const CheckInSummary(),
    this.plan,
    this.recentCheckins = const [],
    this.paymentHistory = const [],
  });

  factory MemberDetail.fromJson(Map<String, dynamic> json) => MemberDetail(
    id: json['id'] as String? ?? '',
    publicId: json['publicId'] as String? ?? '',
    displayName: json['displayName'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    photoUrl: json['photoUrl'] as String?,
    memberType: OwnerMemberType.fromJson(json['memberType'] as String?),
    status: OwnerMemberStatus.fromJson(json['status'] as String?),
    accountStatus: json['accountStatus'] as String? ?? 'active',
    joinedAt: _parseDate(json['joinedAt']),
    checkInSummary: json['checkInSummary'] is Map<String, dynamic>
        ? CheckInSummary.fromJson(
            json['checkInSummary'] as Map<String, dynamic>,
          )
        : const CheckInSummary(),
    plan: json['plan'] is Map<String, dynamic>
        ? MembershipPlan.fromJson(json['plan'] as Map<String, dynamic>)
        : null,
    recentCheckins:
        (json['recentCheckins'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(MemberCheckin.fromJson)
            .toList() ??
        const [],
    paymentHistory:
        (json['paymentHistory'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .map(MemberPayment.fromJson)
            .toList() ??
        const [],
  );

  String get resolvedName =>
      (displayName?.trim().isNotEmpty ?? false) ? displayName! : publicId;

  bool get isSuspended =>
      accountStatus == 'suspended' || status == OwnerMemberStatus.suspended;
}
