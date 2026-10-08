/// A promotion on a listing, as the server describes it: what kind, the label
/// to show, and whether it is a commercial placement. The label is how a
/// customer can tell a paid placement from an organic result, so it is always
/// shown when it is present.
class PromotionTag {
  const PromotionTag({
    required this.id,
    required this.type,
    required this.label,
    this.commercial = false,
    this.token,
  });

  final String id;

  /// featured | promoted | sponsored | recommended | campaign
  final String type;
  final String label;
  final bool commercial;

  /// Short-lived proof from the server that this card was served to this app
  /// session; analytics events must carry it. Null on older servers, or when
  /// the request had no session.
  final String? token;

  static PromotionTag? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type'];
    if (type is! String || type.isEmpty) return null;
    return PromotionTag(
      id: json['id']?.toString() ?? '',
      type: type,
      label: json['label']?.toString() ?? '',
      commercial: json['commercial'] == true,
      token: switch (json['token']) {
        final String t when t.isNotEmpty => t,
        _ => null,
      },
    );
  }
}

/// One page of a ranked discovery list: the Featured section (first page only)
/// and the results below it, each already trimmed to what matched.
class DiscoverResult<T> {
  const DiscoverResult({
    required this.featured,
    required this.items,
    required this.total,
    this.nextCursor,
    this.placement,
    this.promotionsApplied = true,
  });

  final List<T> featured;
  final List<T> items;
  final int total;
  final int? nextCursor;
  final String? placement;

  /// False when the customer chose an explicit sort: nothing is promoted.
  final bool promotionsApplied;

  static DiscoverResult<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) {
    List<T> list(Object? v) =>
        (v as List?)?.whereType<Map<String, dynamic>>().map(parse).toList() ??
        <T>[];
    return DiscoverResult<T>(
      featured: list(json['featured']),
      items: list(json['items']),
      total: (json['total'] as num?)?.toInt() ?? 0,
      nextCursor: (json['nextCursor'] as num?)?.toInt(),
      placement: json['placement'] as String?,
      promotionsApplied: json['promotionsApplied'] != false,
    );
  }
}

/// The query for a discovery request. Only what is set is sent, so the server
/// applies its own defaults, and a build that sends nothing extra still works.
class DiscoverQuery {
  const DiscoverQuery({
    this.q,
    this.lat,
    this.lng,
    this.sort,
    this.filters = const {},
    this.limit,
    this.cursor,
    this.session,
  });

  final String? q;
  final double? lat;
  final double? lng;
  final String? sort;
  final Map<String, String> filters;
  final int? limit;
  final int? cursor;

  /// The app session id, so the server can sign promotion tokens for it.
  final String? session;

  static final _sessionRe = RegExp(r'^[A-Za-z0-9_-]{8,64}$');

  /// A copy that asks for tokens for [session]; unchanged if it is null or
  /// not a valid session id (nothing is sent rather than a bad value).
  DiscoverQuery withSession(String? session) => DiscoverQuery(
    q: q,
    lat: lat,
    lng: lng,
    sort: sort,
    filters: filters,
    limit: limit,
    cursor: cursor,
    session: session,
  );

  Map<String, String> toParams() {
    final out = <String, String>{};
    final text = q?.trim();
    if (text != null && text.isNotEmpty) out['q'] = text;
    if (lat != null && lng != null) {
      out['lat'] = lat!.toStringAsFixed(5);
      out['lng'] = lng!.toStringAsFixed(5);
    }
    if (sort != null && sort != 'relevance') out['sort'] = sort!;
    filters.forEach((k, v) {
      if (v.isNotEmpty) out[k] = v;
    });
    if (limit != null) out['limit'] = '$limit';
    if (cursor != null && cursor! > 0) out['cursor'] = '$cursor';
    final s = session;
    if (s != null && _sessionRe.hasMatch(s)) out['session'] = s;
    return out;
  }

  String toQueryString() {
    final params = toParams();
    if (params.isEmpty) return '';
    return '?${params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
  }
}
