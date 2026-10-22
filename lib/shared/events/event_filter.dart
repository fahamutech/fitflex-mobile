/// What the member asked the event list for (spec §11.2 item 3). A pure
/// model, like `GymFilter`: [toQuery] is exactly the `GET /events` query
/// string the server accepts (§14.1); nothing else is sent.
enum EventDateRange { anytime, thisMonth, next3Months, custom }

enum EventPriceFilter { any, free, under20k, under50k }

enum EventSort { soonest, priceLow, newest }

class EventFilter {
  const EventFilter({
    this.q = '',
    this.dateRange = EventDateRange.anytime,
    this.from,
    this.to,
    this.distances = const {},
    this.types = const {},
    this.region,
    this.price = EventPriceFilter.any,
    this.openOnly = false,
    this.savedOnly = false,
    this.sort = EventSort.soonest,
  });

  final String q;
  final EventDateRange dateRange;

  /// Only read for [EventDateRange.custom].
  final DateTime? from;
  final DateTime? to;

  /// `5k`, `10k`, `21k`, `42k`, `other` (server buckets).
  final Set<String> distances;

  /// `road`, `trail`, `fun`, `charity`, `virtual`.
  final Set<String> types;
  final String? region;
  final EventPriceFilter price;
  final bool openOnly;
  final bool savedOnly;
  final EventSort sort;

  static const distanceBuckets = ['5k', '10k', '21k', '42k', 'other'];
  static const typeCodes = ['road', 'trail', 'fun', 'charity', 'virtual'];

  EventFilter copyWith({
    String? q,
    EventDateRange? dateRange,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    Set<String>? distances,
    Set<String>? types,
    String? region,
    bool clearRegion = false,
    EventPriceFilter? price,
    bool? openOnly,
    bool? savedOnly,
    EventSort? sort,
  }) => EventFilter(
    q: q ?? this.q,
    dateRange: dateRange ?? this.dateRange,
    from: clearDates ? null : (from ?? this.from),
    to: clearDates ? null : (to ?? this.to),
    distances: distances ?? this.distances,
    types: types ?? this.types,
    region: clearRegion ? null : (region ?? this.region),
    price: price ?? this.price,
    openOnly: openOnly ?? this.openOnly,
    savedOnly: savedOnly ?? this.savedOnly,
    sort: sort ?? this.sort,
  );

  /// The same filter with the search and sort kept but every other choice
  /// reset ("Clear all" in the sheet).
  EventFilter cleared() => EventFilter(q: q, sort: sort);

  /// Everything reset, including the search ("Clear filters" on the empty
  /// state).
  static const none = EventFilter();

  /// How many sheet choices are active (the count on the Filters chip). The
  /// search text, the sort and the Saved chip are not counted.
  int get activeCount =>
      (dateRange != EventDateRange.anytime ? 1 : 0) +
      (distances.isNotEmpty ? 1 : 0) +
      (types.isNotEmpty ? 1 : 0) +
      ((region ?? '').isNotEmpty ? 1 : 0) +
      (price != EventPriceFilter.any ? 1 : 0) +
      (openOnly ? 1 : 0);

  /// Whether anything narrows the list (search included).
  bool get isNarrowing => activeCount > 0 || q.trim().isNotEmpty || savedOnly;

  /// Query parameters for `GET /events` (§14.1). [now] resolves the relative
  /// date ranges; repeated keys (`type`, `distance`) are sent as lists.
  Map<String, List<String>> toQuery({DateTime? now}) {
    final out = <String, List<String>>{};
    final search = q.trim();
    if (search.isNotEmpty) out['q'] = [search];
    final (from, to) = dateBounds(now ?? DateTime.now());
    if (from != null) out['from'] = [_day(from)];
    if (to != null) out['to'] = [_day(to)];
    if (types.isNotEmpty) {
      out['type'] = typeCodes.where(types.contains).toList();
    }
    if (distances.isNotEmpty) {
      out['distance'] = distanceBuckets.where(distances.contains).toList();
    }
    if ((region ?? '').isNotEmpty) out['region'] = [region!];
    switch (price) {
      case EventPriceFilter.free:
        out['price'] = ['free'];
      case EventPriceFilter.under20k:
        out['price'] = ['under_20k'];
      case EventPriceFilter.under50k:
        out['price'] = ['under_50k'];
      case EventPriceFilter.any:
        break;
    }
    if (openOnly) out['availability'] = ['open'];
    if (savedOnly) out['saved'] = ['1'];
    if (sort != EventSort.soonest) {
      out['sort'] = [
        switch (sort) {
          EventSort.priceLow => 'price_low',
          EventSort.newest => 'newest',
          EventSort.soonest => 'soonest',
        },
      ];
    }
    return out;
  }

  /// The calendar bounds of [dateRange] on [now]'s calendar (inclusive
  /// days). Null bounds mean "no limit".
  (DateTime?, DateTime?) dateBounds(DateTime now) => switch (dateRange) {
    EventDateRange.anytime => (null, null),
    EventDateRange.thisMonth => (
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month + 1, 0),
    ),
    EventDateRange.next3Months => (
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month + 3, now.day),
    ),
    EventDateRange.custom => (from, to),
  };

  /// A stable key for caching and "did the filter change" checks.
  String get signature {
    final parts = toQuery(now: DateTime.utc(2000)).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return parts.map((e) => '${e.key}=${e.value.join(',')}').join('&');
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}
