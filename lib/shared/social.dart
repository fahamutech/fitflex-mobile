/// Sharing activities between members: people, the feed, comments, groups.
///
/// Who sees a shared activity: mutual followers ("friends"), members of the
/// groups it's shared with, and (if chosen) colleagues at the same company.
/// Everything is private until the member shares it.
library;

/// Who one activity is shared with. `null` everywhere means private.
class ShareWith {
  const ShareWith({
    this.followers = false,
    this.groups = const [],
    this.company = false,
  });

  final bool followers;
  final List<String> groups;
  final bool company;

  bool get isPrivate => !followers && groups.isEmpty && !company;

  static ShareWith? fromJson(Object? v) {
    if (v is! Map) return null;
    final s = ShareWith(
      followers: v['followers'] == true,
      groups: [
        for (final g in (v['groups'] as List? ?? const [])) g.toString(),
      ],
      company: v['company'] == true,
    );
    return s.isPrivate ? null : s;
  }

  Map<String, dynamic> toJson() => {
    'followers': followers,
    'groups': groups,
    'company': company,
  };

  /// The JSON to send: null for private.
  static Object? wire(ShareWith? s) =>
      s == null || s.isPrivate ? null : s.toJson();
}

enum Relationship {
  you('you'),
  friends('friends'),
  following('following'),
  followsYou('follows_you'),
  none('none');

  const Relationship(this.wire);
  final String wire;

  static Relationship fromWire(Object? v) =>
      values.firstWhere((r) => r.wire == v, orElse: () => Relationship.none);
}

class SocialPerson {
  const SocialPerson({
    required this.id,
    this.displayName,
    this.relationship = Relationship.none,
  });

  final String id;
  final String? displayName;
  final Relationship relationship;

  String get name => (displayName ?? '').trim().isEmpty
      ? 'FitFlex member'
      : displayName!.trim();

  factory SocialPerson.fromJson(Map json) => SocialPerson(
    id: json['id'] as String? ?? '',
    displayName: json['displayName'] as String?,
    relationship: Relationship.fromWire(json['relationship']),
  );
}

/// A shared activity as others see it (never calories or the route).
class SharedActivity {
  const SharedActivity({
    required this.id,
    required this.type,
    required this.startedAt,
    this.title,
    this.durationMinutes,
    this.distanceKm,
    this.steps,
    this.movingSeconds,
    this.elevationGainM,
    this.splits = const [],
  });

  final String id;
  final String type;
  final DateTime startedAt;
  final String? title;
  final int? durationMinutes;
  final double? distanceKm;
  final int? steps;
  final int? movingSeconds;
  final double? elevationGainM;
  final List<int> splits;

  factory SharedActivity.fromJson(Map json) => SharedActivity(
    id: json['id'] as String? ?? '',
    type: json['type'] as String? ?? 'other',
    startedAt:
        DateTime.tryParse(json['startedAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    title: json['title'] as String?,
    durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
    distanceKm: (json['distanceKm'] as num?)?.toDouble(),
    steps: (json['steps'] as num?)?.toInt(),
    movingSeconds: (json['movingSeconds'] as num?)?.toInt(),
    elevationGainM: (json['elevationGainM'] as num?)?.toDouble(),
    splits: [
      for (final s in (json['splits'] as List? ?? const []))
        if (s is num) s.toInt(),
    ],
  );
}

class FeedItem {
  const FeedItem({
    required this.activity,
    required this.owner,
    this.kudos = 0,
    this.youKudoed = false,
    this.comments = 0,
    this.sharedWith,
  });

  final SharedActivity activity;
  final SocialPerson owner;
  final int kudos;
  final bool youKudoed;
  final int comments;

  /// Only on your own items.
  final ShareWith? sharedWith;

  FeedItem copyWith({int? kudos, bool? youKudoed, int? comments}) => FeedItem(
    activity: activity,
    owner: owner,
    kudos: kudos ?? this.kudos,
    youKudoed: youKudoed ?? this.youKudoed,
    comments: comments ?? this.comments,
    sharedWith: sharedWith,
  );

  factory FeedItem.fromJson(Map json) => FeedItem(
    activity: SharedActivity.fromJson(json['activity'] as Map? ?? const {}),
    owner: SocialPerson.fromJson(json['owner'] as Map? ?? const {}),
    kudos: (json['kudos'] as num?)?.toInt() ?? 0,
    youKudoed: json['youKudoed'] == true,
    comments: (json['comments'] as num?)?.toInt() ?? 0,
    sharedWith: ShareWith.fromJson(json['sharedWith']),
  );
}

class SocialComment {
  const SocialComment({
    required this.id,
    required this.text,
    required this.createdAt,
    required this.author,
    this.canDelete = false,
  });

  final String id;
  final String text;
  final DateTime createdAt;
  final SocialPerson author;
  final bool canDelete;

  factory SocialComment.fromJson(Map json) => SocialComment(
    id: json['id'] as String? ?? '',
    text: json['text'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    author: SocialPerson.fromJson(json['author'] as Map? ?? const {}),
    canDelete: json['canDelete'] == true,
  );
}

class SocialGroup {
  const SocialGroup({
    required this.id,
    required this.name,
    this.description,
    this.ownerType = 'member',
    this.joinPolicy = 'approval',
    this.discoverable = false,
    this.memberCount = 0,
    this.role,
    this.status,
    this.inviteCode,
    this.canManage = false,
    this.pending = 0,
  });

  final String id;
  final String name;
  final String? description;

  /// member | trainer | gym | corporate
  final String ownerType;

  /// open | approval
  final String joinPolicy;
  final bool discoverable;
  final int memberCount;

  /// Your place in it, if any: admin | member, active | pending.
  final String? role;
  final String? status;

  /// Shown to people who manage the group.
  final String? inviteCode;
  final bool canManage;

  /// Requests waiting (for owners).
  final int pending;

  bool get isMember => status == 'active';
  bool get isPending => status == 'pending';

  factory SocialGroup.fromJson(Map json) {
    final you = json['you'] is Map ? json['you'] as Map : const {};
    return SocialGroup(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String?,
      ownerType: json['ownerType'] as String? ?? 'member',
      joinPolicy: json['joinPolicy'] as String? ?? 'approval',
      discoverable: json['discoverable'] == true,
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
      role: you['role'] as String?,
      status: you['status'] as String?,
      inviteCode: json['inviteCode'] as String?,
      canManage: json['canManage'] == true,
      pending: (json['pending'] as num?)?.toInt() ?? 0,
    );
  }
}

class GroupMember {
  const GroupMember({
    required this.id,
    this.displayName,
    this.role = 'member',
    this.status = 'active',
  });

  final String id;
  final String? displayName;
  final String role;
  final String status;

  String get name => (displayName ?? '').trim().isEmpty
      ? 'FitFlex member'
      : displayName!.trim();

  factory GroupMember.fromJson(Map json) => GroupMember(
    id: json['id'] as String? ?? '',
    displayName: json['displayName'] as String?,
    role: json['role'] as String? ?? 'member',
    status: json['status'] as String? ?? 'active',
  );
}

class SocialSettings {
  const SocialSettings({
    this.defaultShare,
    this.inviteCode = '',
    this.hasCompany = false,
    this.blocked = const [],
  });

  final ShareWith? defaultShare;
  final String inviteCode;
  final bool hasCompany;
  final List<SocialPerson> blocked;

  factory SocialSettings.fromJson(Map json) => SocialSettings(
    defaultShare: ShareWith.fromJson(json['defaultShare']),
    inviteCode: json['inviteCode'] as String? ?? '',
    hasCompany: json['hasCompany'] == true,
    blocked: [
      for (final b in (json['blocked'] as List? ?? const []))
        if (b is Map) SocialPerson.fromJson(b),
    ],
  );
}
