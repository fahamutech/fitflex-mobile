// Communication analytics (M10): how a campaign or automation did —
// delivery, engagement and business results. A null value means there is
// no data for it (shown as "—"), never zero.

int? _intOrNull(Object? v) => (v as num?)?.toInt();
int _int(Object? v) => (v as num?)?.toInt() ?? 0;
DateTime? _date(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// Member counts through the funnel.
class ResultCounts {
  const ResultCounts({
    this.recipients = 0,
    this.sent = 0,
    this.delivered,
    this.failed = 0,
    this.opened = 0,
    this.clicked = 0,
    this.ctaCompleted,
    this.renewed = 0,
    this.paid = 0,
  });

  final int recipients;
  final int sent;

  /// Null when only push was used (push can't confirm delivery).
  final int? delivered;
  final int failed;
  final int opened;
  final int clicked;

  /// Null when no message had a button leading somewhere.
  final int? ctaCompleted;
  final int renewed;
  final int paid;

  factory ResultCounts.fromJson(Map<String, dynamic>? j) => ResultCounts(
    recipients: _int(j?['recipients']),
    sent: _int(j?['sent']),
    delivered: _intOrNull(j?['delivered']),
    failed: _int(j?['failed']),
    opened: _int(j?['opened']),
    clicked: _int(j?['clicked']),
    ctaCompleted: _intOrNull(j?['ctaCompleted']),
    renewed: _int(j?['renewed']),
    paid: _int(j?['paid']),
  );
}

/// One payment credited to the message.
class Conversion {
  const Conversion({
    required this.memberId,
    required this.amountTzs,
    this.memberName,
    this.paidAt,
    this.via = 'click',
    this.renewal = false,
  });

  final String memberId;
  final String? memberName;
  final int amountTzs;
  final DateTime? paidAt;

  /// click | open — what the payment was credited through.
  final String via;
  final bool renewal;

  factory Conversion.fromJson(Map<String, dynamic> j) => Conversion(
    memberId: j['memberId'].toString(),
    memberName: j['memberName']?.toString(),
    amountTzs: _int(j['amountTzs']),
    paidAt: _date(j['paidAt']),
    via: j['via']?.toString() ?? 'click',
    renewal: j['renewal'] == true,
  );
}

/// Results for a campaign, an automation, or everything over a period.
class CommsResults {
  const CommsResults({
    this.counts = const ResultCounts(),
    this.revenueTzs = 0,
    this.payments = 0,
    this.clickWindowDays = 7,
    this.openWindowDays = 3,
    this.conversions = const [],
    this.periodDays,
    this.sources = const [],
  });

  final ResultCounts counts;
  final int revenueTzs;
  final int payments;
  final int clickWindowDays;
  final int openWindowDays;
  final List<Conversion> conversions;

  /// For the overview: the period, and each campaign or automation.
  final int? periodDays;
  final List<ResultSource> sources;

  factory CommsResults.fromJson(Map<String, dynamic> j) {
    final attribution = (j['attribution'] as Map?)?.cast<String, dynamic>();
    final revenue = (j['revenue'] as Map?)?.cast<String, dynamic>();
    return CommsResults(
      counts: ResultCounts.fromJson((j['members'] as Map?)?.cast()),
      revenueTzs: _int(revenue?['attributedTzs']),
      payments: _int(revenue?['payments']),
      clickWindowDays: _int(attribution?['clickWindowDays'] ?? 7),
      openWindowDays: _int(attribution?['openWindowDays'] ?? 3),
      conversions: ((j['conversions'] as List?) ?? const [])
          .map((c) => Conversion.fromJson((c as Map).cast()))
          .toList(),
      periodDays: _intOrNull((j['period'] as Map?)?['days']),
      sources: ((j['sources'] as List?) ?? const [])
          .map((s) => ResultSource.fromJson((s as Map).cast()))
          .toList(),
    );
  }
}

/// A campaign or automation in the overview.
class ResultSource {
  const ResultSource({
    required this.type,
    required this.id,
    this.name,
    this.trigger,
    this.offsetDays,
    this.recipients = 0,
    this.opened = 0,
    this.clicked = 0,
    this.paid = 0,
    this.revenueTzs = 0,
  });

  /// campaign | automation
  final String type;
  final String id;
  final String? name;
  final String? trigger;
  final int? offsetDays;
  final int recipients;
  final int opened;
  final int clicked;
  final int paid;
  final int revenueTzs;

  factory ResultSource.fromJson(Map<String, dynamic> j) => ResultSource(
    type: j['type']?.toString() ?? 'campaign',
    id: j['id'].toString(),
    name: j['name']?.toString(),
    trigger: j['trigger']?.toString(),
    offsetDays: _intOrNull(j['offsetDays']),
    recipients: _int(j['recipients']),
    opened: _int(j['opened']),
    clicked: _int(j['clicked']),
    paid: _int(j['paid']),
    revenueTzs: _int(j['attributedTzs']),
  );
}
