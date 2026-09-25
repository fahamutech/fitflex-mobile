// Typed models for owner communications (campaigns to a gym's direct
// members). Parsing is lenient: unknown values map to a safe default so a
// newer backend never crashes an older app.

enum CampaignPurpose {
  promotion,
  renewal,
  payment,
  announcement,
  engagement,
  general;

  static CampaignPurpose? parse(String? v) =>
      values.where((p) => p.name == v).firstOrNull;

  /// Service messages reach members even if they turned offers off.
  bool get isTransactional =>
      this == renewal || this == payment || this == announcement;
}

enum CampaignStatus {
  draft,
  scheduled,
  sending,
  sent,
  partiallyFailed,
  failed,
  cancelled;

  static CampaignStatus parse(String? v) => switch (v) {
    'scheduled' => scheduled,
    'sending' => sending,
    'sent' => sent,
    'partially_failed' => partiallyFailed,
    'failed' => failed,
    'cancelled' => cancelled,
    _ => draft,
  };

  String get wire => switch (this) {
    partiallyFailed => 'partially_failed',
    _ => name,
  };

  bool get editable => this == draft;
  bool get sendable => this == draft || this == scheduled;
}

enum CommChannel {
  inApp('in_app'),
  push('push'),
  whatsapp('whatsapp');

  const CommChannel(this.wire);
  final String wire;

  static CommChannel? parse(String? v) =>
      values.where((c) => c.wire == v).firstOrNull;
}

/// Where the message's button takes the member.
enum DeepLink {
  message,
  membership,
  renewal,
  payment,
  gym;

  static DeepLink parse(String? v) =>
      values.where((d) => d.name == v).firstOrNull ?? message;
}

/// Preset audiences offered to gyms (see backend src/shared/audience.mjs).
const kGymAudiencePresets = [
  'all',
  'active',
  'expiring',
  'expired',
  'recently_expired',
  'new',
  'inactive',
];

/// Variables an owner can put in a message.
const kMessageVariables = [
  'member_name',
  'gym_name',
  'plan_name',
  'expiry_date',
  'offer_name',
  'discount',
  'amount',
];

class CampaignContent {
  const CampaignContent({
    this.title = '',
    this.body = '',
    this.ctaLabel,
    this.deepLink = DeepLink.message,
    this.offerName,
    this.discount,
    this.amountTzs,
  });

  final String title;
  final String body;
  final String? ctaLabel;
  final DeepLink deepLink;
  final String? offerName;
  final String? discount;
  final int? amountTzs;

  CampaignContent copyWith({
    String? title,
    String? body,
    String? Function()? ctaLabel,
    DeepLink? deepLink,
    String? Function()? offerName,
    String? Function()? discount,
    int? Function()? amountTzs,
  }) => CampaignContent(
    title: title ?? this.title,
    body: body ?? this.body,
    ctaLabel: ctaLabel != null ? ctaLabel() : this.ctaLabel,
    deepLink: deepLink ?? this.deepLink,
    offerName: offerName != null ? offerName() : this.offerName,
    discount: discount != null ? discount() : this.discount,
    amountTzs: amountTzs != null ? amountTzs() : this.amountTzs,
  );

  factory CampaignContent.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const CampaignContent();
    return CampaignContent(
      title: j['title']?.toString() ?? '',
      body: j['body']?.toString() ?? '',
      ctaLabel: j['ctaLabel']?.toString(),
      deepLink: DeepLink.parse(j['deepLink']?.toString()),
      offerName: j['offerName']?.toString(),
      discount: j['discount']?.toString(),
      amountTzs: (j['amountTzs'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'body': body.trim(),
    if (ctaLabel != null && ctaLabel!.trim().isNotEmpty)
      'ctaLabel': ctaLabel!.trim(),
    'deepLink': deepLink.name,
    if (offerName != null && offerName!.trim().isNotEmpty)
      'offerName': offerName!.trim(),
    if (discount != null && discount!.trim().isNotEmpty)
      'discount': discount!.trim(),
    if (amountTzs != null) 'amountTzs': amountTzs,
  };

  /// Variable names used in the title and body.
  Set<String> get variables => RegExp(
    r'\{\{\s*([a-z_]+)\s*\}\}',
  ).allMatches('$title $body').map((m) => m.group(1)!).toSet();
}

/// An audience: a preset and optional extra conditions (AND-ed).
class CampaignAudience {
  const CampaignAudience({this.preset = 'all', this.filter});

  final String? preset;
  final Map<String, dynamic>? filter;

  factory CampaignAudience.fromJson(Map<String, dynamic>? j) =>
      CampaignAudience(
        preset: j?['preset']?.toString(),
        filter: (j?['filter'] as Map?)?.cast<String, dynamic>(),
      );

  Map<String, dynamic> toJson() => {
    'preset': preset,
    if (filter != null && ((filter!['all'] as List?)?.isNotEmpty ?? true))
      'filter': filter,
  };
}

class Campaign {
  const Campaign({
    required this.id,
    required this.name,
    required this.status,
    this.gymId,
    this.purpose,
    this.audience = const CampaignAudience(),
    this.content = const CampaignContent(),
    this.channels = const [],
    this.scheduledAt,
    this.sentAt,
    this.createdAt,
    this.counts,
    this.title,
  });

  final String id;
  final String name;
  final CampaignStatus status;
  final String? gymId;
  final CampaignPurpose? purpose;
  final CampaignAudience audience;
  final CampaignContent content;
  final List<CommChannel> channels;
  final DateTime? scheduledAt;
  final DateTime? sentAt;
  final DateTime? createdAt;
  final CampaignCounts? counts;

  /// List rows carry the title instead of the full content.
  final String? title;

  String get displayTitle => title ?? content.title;

  factory Campaign.fromJson(Map<String, dynamic> j) => Campaign(
    id: j['id'].toString(),
    name: j['name']?.toString() ?? '',
    status: CampaignStatus.parse(j['status']?.toString()),
    gymId: j['gymId']?.toString(),
    purpose: CampaignPurpose.parse(j['purpose']?.toString()),
    audience: j['audience'] is Map
        ? CampaignAudience.fromJson((j['audience'] as Map).cast())
        : CampaignAudience(preset: j['preset']?.toString()),
    content: CampaignContent.fromJson((j['content'] as Map?)?.cast()),
    channels: ((j['channels'] as List?) ?? const [])
        .map((c) => CommChannel.parse(c?.toString()))
        .whereType<CommChannel>()
        .toList(),
    scheduledAt: _date(j['scheduledAt']),
    sentAt: _date(j['sentAt']),
    createdAt: _date(j['createdAt']),
    counts: j['counts'] is Map
        ? CampaignCounts.fromJson((j['counts'] as Map).cast())
        : null,
    title: j['title']?.toString(),
  );
}

/// What a send queued: how many members were targeted, how many messages
/// were queued, and why the rest were skipped.
class CampaignCounts {
  const CampaignCounts({
    this.targeted = 0,
    this.queued = 0,
    this.skipped = const {},
    this.byChannel = const {},
  });

  final int targeted;
  final int queued;
  final Map<String, int> skipped;
  final Map<CommChannel, ({int queued, int skipped})> byChannel;

  factory CampaignCounts.fromJson(Map<String, dynamic> j) => CampaignCounts(
    targeted: (j['targeted'] as num?)?.toInt() ?? 0,
    queued: (j['queued'] as num?)?.toInt() ?? 0,
    skipped: _intMap(j['skipped']),
    byChannel: {
      for (final e in ((j['byChannel'] as Map?) ?? const {}).entries)
        if (CommChannel.parse(e.key.toString()) != null)
          CommChannel.parse(e.key.toString())!: (
            queued: ((e.value as Map)['queued'] as num?)?.toInt() ?? 0,
            skipped: ((e.value as Map)['skipped'] as num?)?.toInt() ?? 0,
          ),
    },
  );
}

class CampaignDetail {
  const CampaignDetail({required this.campaign, this.progress = const {}});

  final Campaign campaign;

  /// Ledger counts per channel and message status (queued, sent, skipped…).
  final Map<CommChannel, Map<String, int>> progress;

  factory CampaignDetail.fromJson(Map<String, dynamic> j) => CampaignDetail(
    campaign: Campaign.fromJson((j['campaign'] as Map).cast()),
    progress: {
      for (final e in ((j['progress'] as Map?) ?? const {}).entries)
        if (CommChannel.parse(e.key.toString()) != null)
          CommChannel.parse(e.key.toString())!: _intMap(e.value),
    },
  );
}

class ChannelAvailability {
  const ChannelAvailability({
    this.inApp = true,
    this.push = false,
    this.whatsapp = false,
  });

  final bool inApp;
  final bool push;
  final bool whatsapp;

  bool of(CommChannel c) => switch (c) {
    CommChannel.inApp => inApp,
    CommChannel.push => push,
    CommChannel.whatsapp => whatsapp,
  };

  factory ChannelAvailability.fromJson(Map<String, dynamic>? j) =>
      ChannelAvailability(
        inApp: j?['in_app'] != false,
        push: j?['push'] == true,
        whatsapp: j?['whatsapp'] == true,
      );
}

class CommunicationOverview {
  const CommunicationOverview({
    this.members,
    this.campaigns = const {},
    this.recent = const [],
    this.channels = const ChannelAvailability(),
    this.largeSendThreshold = 200,
    this.marketingWeeklyCap = 2,
  });

  /// Direct members who can be messaged (null if unknown).
  final int? members;
  final Map<CampaignStatus, int> campaigns;
  final List<Campaign> recent;
  final ChannelAvailability channels;
  final int largeSendThreshold;
  final int marketingWeeklyCap;

  int count(CampaignStatus s) => campaigns[s] ?? 0;

  factory CommunicationOverview.fromJson(Map<String, dynamic> j) {
    final limits = (j['limits'] as Map?) ?? const {};
    return CommunicationOverview(
      members: (j['members'] as num?)?.toInt(),
      campaigns: {
        for (final e in ((j['campaigns'] as Map?) ?? const {}).entries)
          CampaignStatus.parse(e.key.toString()): (e.value as num).toInt(),
      },
      recent: ((j['recent'] as List?) ?? const [])
          .map((c) => Campaign.fromJson((c as Map).cast()))
          .toList(),
      channels: ChannelAvailability.fromJson((j['channels'] as Map?)?.cast()),
      largeSendThreshold:
          (limits['largeSendThreshold'] as num?)?.toInt() ?? 200,
      marketingWeeklyCap: (limits['marketingWeeklyCap'] as num?)?.toInt() ?? 2,
    );
  }
}

/// Live audience count while building the audience.
class AudienceCount {
  const AudienceCount({required this.count, this.sample = const []});

  final int count;
  final List<String> sample;

  factory AudienceCount.fromJson(Map<String, dynamic> j) => AudienceCount(
    count: (j['count'] as num?)?.toInt() ?? 0,
    sample: ((j['sample'] as List?) ?? const [])
        .map((s) => (s as Map)['displayName']?.toString() ?? '')
        .where((s) => s.isNotEmpty)
        .toList(),
  );
}

class RenderedMessage {
  const RenderedMessage({
    required this.title,
    required this.body,
    this.memberName,
    this.ctaLabel,
    this.deepLink = DeepLink.message,
  });

  final String title;
  final String body;
  final String? memberName;
  final String? ctaLabel;
  final DeepLink deepLink;

  factory RenderedMessage.fromJson(Map<String, dynamic> j) => RenderedMessage(
    title: j['title']?.toString() ?? '',
    body: j['body']?.toString() ?? '',
    memberName: j['memberName']?.toString(),
    ctaLabel: j['ctaLabel']?.toString(),
    deepLink: DeepLink.parse(j['deepLink']?.toString()),
  );
}

class CampaignWarning {
  const CampaignWarning(this.code, {this.count, this.channel});

  final String code;
  final int? count;
  final CommChannel? channel;

  factory CampaignWarning.fromJson(Map<String, dynamic> j) => CampaignWarning(
    j['code'].toString(),
    count: (j['count'] as num?)?.toInt(),
    channel: CommChannel.parse(j['channel']?.toString()),
  );
}

/// Server preview of a campaign: reach per channel, one member's real
/// message, and anything worth a second look before sending.
class CampaignPreview {
  const CampaignPreview({
    required this.counts,
    this.example,
    this.warnings = const [],
    this.largeSendThreshold = 200,
  });

  final CampaignCounts counts;
  final RenderedMessage? example;
  final List<CampaignWarning> warnings;
  final int largeSendThreshold;

  bool get needsLargeSendConfirm => counts.targeted >= largeSendThreshold;
  bool get nobodyReachable => warnings.any((w) => w.code == 'nobody_reachable');

  factory CampaignPreview.fromJson(Map<String, dynamic> j) => CampaignPreview(
    counts: CampaignCounts.fromJson((j['counts'] as Map).cast()),
    example: j['example'] is Map
        ? RenderedMessage.fromJson((j['example'] as Map).cast())
        : null,
    warnings: ((j['warnings'] as List?) ?? const [])
        .map((w) => CampaignWarning.fromJson((w as Map).cast()))
        .toList(),
    largeSendThreshold: (j['largeSendThreshold'] as num?)?.toInt() ?? 200,
  );
}

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

Map<String, int> _intMap(dynamic v) => {
  for (final e in ((v as Map?) ?? const {}).entries)
    e.key.toString(): (e.value as num).toInt(),
};
