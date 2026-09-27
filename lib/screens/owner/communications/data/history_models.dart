// Communication history (M8): what the message ledger says about each
// message, a member's communications, a campaign's recipients and its
// numbers. Read-only views of the backend's /communications history API.

import 'communication_models.dart';

DateTime? _date(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// A page of results; pass [nextCursor] back for the next one.
class HistoryPage<T> {
  const HistoryPage(this.items, this.nextCursor);

  final List<T> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}

/// Delivery numbers for a campaign (or any set of messages).
class HistoryTotals {
  const HistoryTotals({
    this.pending = 0,
    this.sent = 0,
    this.delivered = 0,
    this.opened = 0,
    this.clicked = 0,
    this.failed = 0,
    this.skipped = 0,
  });

  final int pending;

  /// Handed to the member's inbox, FCM or WhatsApp.
  final int sent;

  /// Confirmed as arrived (the inbox always, WhatsApp by receipt; push
  /// can't confirm).
  final int delivered;
  final int opened;
  final int clicked;
  final int failed;
  final int skipped;

  factory HistoryTotals.fromJson(Map<String, dynamic>? j) => HistoryTotals(
    pending: _int(j?['pending']),
    sent: _int(j?['sent']),
    delivered: _int(j?['delivered']),
    opened: _int(j?['opened']),
    clicked: _int(j?['clicked']),
    failed: _int(j?['failed']),
    skipped: _int(j?['skipped']),
  );
}

class CampaignStats {
  const CampaignStats({
    this.targeted = 0,
    this.messages = 0,
    this.totals = const HistoryTotals(),
  });

  /// Members the campaign went to.
  final int targeted;

  /// Messages across all channels.
  final int messages;
  final HistoryTotals totals;

  static CampaignStats? fromJson(Object? j) {
    if (j is! Map) return null;
    final m = j.cast<String, dynamic>();
    return CampaignStats(
      targeted: _int(m['targeted']),
      messages: _int(m['messages']),
      totals: HistoryTotals.fromJson((m['totals'] as Map?)?.cast()),
    );
  }
}

/// Who delivered a message and their reference for it. Never credentials.
class ProviderRef {
  const ProviderRef({
    required this.name,
    this.messageId,
    this.templateName,
    this.language,
    this.devices,
    this.failedDevices,
    this.errors = const [],
  });

  /// inbox | fcm | whatsapp
  final String name;
  final String? messageId;
  final String? templateName;
  final String? language;
  final int? devices;
  final int? failedDevices;
  final List<String> errors;

  factory ProviderRef.fromJson(Map<String, dynamic>? j) => ProviderRef(
    name: j?['name']?.toString() ?? 'inbox',
    messageId: j?['messageId']?.toString(),
    templateName: j?['templateName']?.toString(),
    language: j?['language']?.toString(),
    devices: (j?['devices'] as num?)?.toInt(),
    failedDevices: (j?['failedDevices'] as num?)?.toInt(),
    errors: ((j?['errors'] as List?) ?? const [])
        .map((e) => e.toString())
        .toList(),
  );
}

/// One message on one channel, as the ledger records it.
class CommMessage {
  const CommMessage({
    required this.id,
    required this.memberId,
    required this.channel,
    required this.status,
    this.campaignId,
    this.campaignName,
    this.memberName,
    this.category,
    this.messageType,
    this.title = '',
    this.body = '',
    this.locale,
    this.skipReason,
    this.failureReason,
    this.failurePermanent = false,
    this.attempts = 0,
    this.provider = const ProviderRef(name: 'inbox'),
    this.createdAt,
    this.sentAt,
    this.deliveredAt,
    this.openedAt,
    this.clickedAt,
    this.failedAt,
    this.nextAttemptAt,
    this.templateName,
    this.templateKey,
    this.templateSystem = false,
  });

  final String id;
  final String memberId;
  final CommChannel? channel;

  /// queued | sending | sent | delivered | read | clicked | failed | skipped
  final String status;
  final String? campaignId;
  final String? campaignName;
  final String? memberName;
  final String? category;
  final CampaignPurpose? messageType;
  final String title;
  final String body;
  final String? locale;
  final String? skipReason;
  final String? failureReason;
  final bool failurePermanent;
  final int attempts;
  final ProviderRef provider;
  final DateTime? createdAt;
  final DateTime? sentAt;
  final DateTime? deliveredAt;
  final DateTime? openedAt;
  final DateTime? clickedAt;
  final DateTime? failedAt;
  final DateTime? nextAttemptAt;

  /// Only on a single message: the template the campaign started from.
  final String? templateName;
  final String? templateKey;
  final bool templateSystem;

  bool get isFailed => status == 'failed';
  bool get isSkipped => status == 'skipped';

  factory CommMessage.fromJson(Map<String, dynamic> j) {
    final template = (j['template'] as Map?)?.cast<String, dynamic>();
    return CommMessage(
      id: j['id'].toString(),
      memberId: j['memberId']?.toString() ?? '',
      channel: CommChannel.parse(j['channel']?.toString()),
      status: j['status']?.toString() ?? 'queued',
      campaignId: j['campaignId']?.toString(),
      campaignName:
          j['campaignName']?.toString() ??
          (j['campaign'] as Map?)?['name']?.toString(),
      memberName: j['memberName']?.toString(),
      category: j['category']?.toString(),
      messageType: CampaignPurpose.parse(j['messageType']?.toString()),
      title: j['title']?.toString() ?? '',
      body: j['body']?.toString() ?? '',
      locale: j['locale']?.toString(),
      skipReason: j['skipReason']?.toString(),
      failureReason: j['failureReason']?.toString(),
      failurePermanent: j['failurePermanent'] == true,
      attempts: _int(j['attempts']),
      provider: ProviderRef.fromJson((j['provider'] as Map?)?.cast()),
      createdAt: _date(j['createdAt']),
      sentAt: _date(j['sentAt']),
      deliveredAt: _date(j['deliveredAt']),
      openedAt: _date(j['openedAt']),
      clickedAt: _date(j['clickedAt']),
      failedAt: _date(j['failedAt']),
      nextAttemptAt: _date(j['nextAttemptAt']),
      templateName: template?['name']?.toString(),
      templateKey: template?['key']?.toString(),
      templateSystem: template?['system'] == true,
    );
  }
}

/// One communication with a member: every channel it went on.
class CommunicationItem {
  const CommunicationItem({
    required this.key,
    required this.outcome,
    required this.channels,
    this.campaignId,
    this.campaignName,
    this.category,
    this.messageType,
    this.title = '',
    this.body = '',
    this.createdAt,
  });

  final String key;

  /// reached | pending | failed | skipped
  final String outcome;
  final List<CommMessage> channels;
  final String? campaignId;
  final String? campaignName;
  final String? category;
  final CampaignPurpose? messageType;
  final String title;
  final String body;
  final DateTime? createdAt;

  factory CommunicationItem.fromJson(Map<String, dynamic> j) =>
      CommunicationItem(
        key: j['key'].toString(),
        outcome: j['outcome']?.toString() ?? 'pending',
        channels: ((j['channels'] as List?) ?? const [])
            .map((c) => CommMessage.fromJson((c as Map).cast()))
            .toList(),
        campaignId: j['campaignId']?.toString(),
        campaignName: j['campaignName']?.toString(),
        category: j['category']?.toString(),
        messageType: CampaignPurpose.parse(j['messageType']?.toString()),
        title: j['title']?.toString() ?? '',
        body: j['body']?.toString() ?? '',
        createdAt: _date(j['createdAt']),
      );
}

/// One member a campaign went to, with every channel.
class Recipient {
  const Recipient({
    required this.memberId,
    required this.outcome,
    required this.channels,
    this.memberName,
  });

  final String memberId;
  final String? memberName;
  final String outcome;
  final List<CommMessage> channels;

  factory Recipient.fromJson(Map<String, dynamic> j) => Recipient(
    memberId: j['memberId'].toString(),
    memberName: j['memberName']?.toString(),
    outcome: j['outcome']?.toString() ?? 'pending',
    channels: ((j['channels'] as List?) ?? const [])
        .map((c) => CommMessage.fromJson((c as Map).cast()))
        .toList(),
  );
}

/// Status filters the history API understands, in the order they're offered.
const kHistoryStatusFilters = [
  'reached',
  'pending',
  'opened',
  'failed',
  'skipped',
];

/// Filters for a member's timeline or a campaign's recipients.
class HistoryFilter {
  const HistoryFilter({
    this.channel,
    this.status,
    this.category,
    this.from,
    this.to,
    this.search,
  });

  final CommChannel? channel;
  final String? status;
  final String? category;
  final DateTime? from;
  final DateTime? to;
  final String? search;

  bool get isEmpty =>
      channel == null &&
      status == null &&
      category == null &&
      from == null &&
      to == null &&
      (search == null || search!.isEmpty);

  HistoryFilter copyWith({
    CommChannel? Function()? channel,
    String? Function()? status,
    String? Function()? category,
    DateTime? Function()? from,
    DateTime? Function()? to,
    String? Function()? search,
  }) => HistoryFilter(
    channel: channel != null ? channel() : this.channel,
    status: status != null ? status() : this.status,
    category: category != null ? category() : this.category,
    from: from != null ? from() : this.from,
    to: to != null ? to() : this.to,
    search: search != null ? search() : this.search,
  );

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, String> toQuery() => {
    if (channel != null) 'channel': channel!.wire,
    'status': ?status,
    'category': ?category,
    if (from != null) 'from': _day(from!),
    if (to != null) 'to': _day(to!),
    if (search != null && search!.trim().isNotEmpty) 'search': search!.trim(),
  };
}
