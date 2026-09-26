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

/// A message's title, body and button text in one language.
class MessageText {
  const MessageText({this.title = '', this.body = '', this.ctaLabel});

  final String title;
  final String body;
  final String? ctaLabel;

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  MessageText copyWith({
    String? title,
    String? body,
    String? Function()? ctaLabel,
  }) => MessageText(
    title: title ?? this.title,
    body: body ?? this.body,
    ctaLabel: ctaLabel != null ? ctaLabel() : this.ctaLabel,
  );

  factory MessageText.fromJson(Map<String, dynamic>? j) => MessageText(
    title: j?['title']?.toString() ?? '',
    body: j?['body']?.toString() ?? '',
    ctaLabel: j?['ctaLabel']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'title': title.trim(),
    'body': body.trim(),
    if (ctaLabel != null && ctaLabel!.trim().isNotEmpty)
      'ctaLabel': ctaLabel!.trim(),
  };
}

/// Languages a message can be written in.
const kMessageLocales = ['en', 'sw'];

class CampaignContent {
  const CampaignContent({
    this.title = '',
    this.body = '',
    this.ctaLabel,
    this.deepLink = DeepLink.message,
    this.offerName,
    this.discount,
    this.amountTzs,
    this.locale = 'en',
    this.translations = const {},
  });

  final String title;
  final String body;
  final String? ctaLabel;
  final DeepLink deepLink;
  final String? offerName;
  final String? discount;
  final int? amountTzs;

  /// The language the main text is written in.
  final String locale;

  /// The same message in the other app language, e.g. {'sw': …}. Members
  /// get the version in their app language when there is one.
  final Map<String, MessageText> translations;

  MessageText get main =>
      MessageText(title: title, body: body, ctaLabel: ctaLabel);

  /// The other app language (the one a translation would be in).
  String get otherLocale => kMessageLocales.firstWhere((l) => l != locale);

  CampaignContent copyWith({
    String? title,
    String? body,
    String? Function()? ctaLabel,
    DeepLink? deepLink,
    String? Function()? offerName,
    String? Function()? discount,
    int? Function()? amountTzs,
    String? locale,
    Map<String, MessageText>? translations,
  }) => CampaignContent(
    title: title ?? this.title,
    body: body ?? this.body,
    ctaLabel: ctaLabel != null ? ctaLabel() : this.ctaLabel,
    deepLink: deepLink ?? this.deepLink,
    offerName: offerName != null ? offerName() : this.offerName,
    discount: discount != null ? discount() : this.discount,
    amountTzs: amountTzs != null ? amountTzs() : this.amountTzs,
    locale: locale ?? this.locale,
    translations: translations ?? this.translations,
  );

  /// The same content with one language's text replaced (main or translation).
  CampaignContent withText(String lang, MessageText text) => lang == locale
      ? copyWith(
          title: text.title,
          body: text.body,
          ctaLabel: () => text.ctaLabel,
        )
      : copyWith(translations: {...translations, lang: text});

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
      locale: j['locale']?.toString() ?? 'en',
      translations: {
        for (final e in ((j['translations'] as Map?) ?? const {}).entries)
          e.key.toString(): MessageText.fromJson((e.value as Map).cast()),
      },
    );
  }

  Map<String, dynamic> toJson() {
    final tr = {
      for (final e in translations.entries)
        if (!e.value.isEmpty && e.key != locale) e.key: e.value.toJson(),
    };
    return {
      'title': title.trim(),
      'body': body.trim(),
      if (ctaLabel != null && ctaLabel!.trim().isNotEmpty)
        'ctaLabel': ctaLabel!.trim(),
      'deepLink': deepLink.name,
      'locale': locale,
      if (tr.isNotEmpty) 'translations': tr,
      if (offerName != null && offerName!.trim().isNotEmpty)
        'offerName': offerName!.trim(),
      if (discount != null && discount!.trim().isNotEmpty)
        'discount': discount!.trim(),
      if (amountTzs != null) 'amountTzs': amountTzs,
    };
  }

  /// Variable names used in the title and body, in every language.
  Set<String> get variables => RegExp(r'\{\{\s*([a-z_]+)\s*\}\}')
      .allMatches(
        [
          '$title $body',
          for (final t in translations.values) '${t.title} ${t.body}',
        ].join(' '),
      )
      .map((m) => m.group(1)!)
      .toSet();
}

/// Groups templates are browsed by.
const kTemplateGroups = [
  'membership',
  'payment',
  'marketing',
  'engagement',
  'general',
];

/// A message template: FitFlex's (system) or the gym's own.
class CommTemplate {
  const CommTemplate({
    required this.id,
    required this.key,
    required this.name,
    required this.system,
    this.group = 'general',
    this.purpose,
    this.deepLink = DeepLink.message,
    this.bodies = const {},
    this.variables = const [],
    this.basedOn,
  });

  final String id;
  final String key;
  final String name;
  final bool system;
  final String group;
  final CampaignPurpose? purpose;
  final DeepLink deepLink;
  final Map<String, MessageText> bodies;
  final List<String> variables;
  final String? basedOn;

  /// The text in [lang], or in any language the template has.
  MessageText textIn(String lang) =>
      bodies[lang] ?? bodies.values.firstOrNull ?? const MessageText();

  /// Offer values the sender types in once for the whole campaign.
  List<String> get senderVariables => variables
      .where((v) => const {'offer_name', 'discount', 'amount'}.contains(v))
      .toList();

  factory CommTemplate.fromJson(Map<String, dynamic> j) => CommTemplate(
    id: j['id'].toString(),
    key: j['key']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    system: j['system'] == true,
    group: j['group']?.toString() ?? 'general',
    purpose: CampaignPurpose.parse(j['purpose']?.toString()),
    deepLink: DeepLink.parse(j['deepLink']?.toString()),
    bodies: {
      for (final e in ((j['bodies'] as Map?) ?? const {}).entries)
        e.key.toString(): MessageText.fromJson((e.value as Map).cast()),
    },
    variables: ((j['variables'] as List?) ?? const [])
        .map((v) => v.toString())
        .toList(),
    basedOn: j['basedOn']?.toString(),
  );

  /// Campaign content from this template: the main text in [lang] (falling
  /// back to a language it has), the other language as a translation.
  CampaignContent toContent(String lang, {CampaignContent? keepValuesFrom}) {
    final main = bodies.containsKey(lang)
        ? lang
        : (bodies.keys.firstOrNull ?? 'en');
    final text = bodies[main] ?? const MessageText();
    final prev = keepValuesFrom;
    return CampaignContent(
      title: text.title,
      body: text.body,
      ctaLabel: text.ctaLabel,
      deepLink: deepLink,
      locale: main,
      translations: {
        for (final e in bodies.entries)
          if (e.key != main) e.key: e.value,
      },
      offerName: prev?.offerName,
      discount: prev?.discount,
      amountTzs: prev?.amountTzs,
    );
  }
}

/// How a template looks on each channel in one language.
class TemplateChannelPreview {
  const TemplateChannelPreview({
    required this.inApp,
    required this.pushTitle,
    required this.pushBody,
    this.pushTruncated = false,
  });

  final RenderedMessage inApp;
  final String pushTitle;
  final String pushBody;
  final bool pushTruncated;
}

class TemplatePreview {
  const TemplatePreview({
    required this.senderName,
    required this.byLocale,
    this.whatsappReady = const {},
    this.needsValues = const [],
  });

  final String senderName;
  final Map<String, TemplateChannelPreview> byLocale;

  /// Per language: can this template go out on WhatsApp yet.
  final Map<String, bool> whatsappReady;
  final List<String> needsValues;

  factory TemplatePreview.fromJson(Map<String, dynamic> j) => TemplatePreview(
    senderName: j['senderName']?.toString() ?? '',
    byLocale: {
      for (final e in ((j['byLocale'] as Map?) ?? const {}).entries)
        e.key.toString(): () {
          final v = (e.value as Map).cast<String, dynamic>();
          final inApp = (v['in_app'] as Map).cast<String, dynamic>();
          final push = (v['push'] as Map).cast<String, dynamic>();
          return TemplateChannelPreview(
            inApp: RenderedMessage.fromJson(inApp),
            pushTitle: push['title']?.toString() ?? '',
            pushBody: push['body']?.toString() ?? '',
            pushTruncated: push['truncated'] == true,
          );
        }(),
    },
    whatsappReady: {
      for (final e
          in ((((j['whatsapp'] as Map?) ?? const {})['byLocale'] as Map?) ??
                  const {})
              .entries)
        e.key.toString(): (e.value as Map)['ready'] == true,
    },
    needsValues: ((j['needsValues'] as List?) ?? const [])
        .map((v) => v.toString())
        .toList(),
  );
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
    this.templateId,
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

  /// The template the message was started from, if any.
  final String? templateId;

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
    templateId: j['templateId']?.toString(),
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
