/// One row of `GET /events` (spec §14.1). Field names are the server's; the
/// client never invents one.
class EventVenue {
  const EventVenue({
    this.name = '',
    this.city = '',
    this.region = '',
    this.address,
    this.lat,
    this.lng,
  });

  final String name;
  final String city;
  final String region;
  final String? address;
  final double? lat;
  final double? lng;

  /// "Dar es Salaam, Dar es Salaam" collapses to one name.
  String get cityLine {
    final parts = [
      city.trim(),
      region.trim(),
    ].where((s) => s.isNotEmpty).toList();
    if (parts.length == 2 && parts[0].toLowerCase() == parts[1].toLowerCase()) {
      return parts.first;
    }
    return parts.join(', ');
  }

  bool get hasCoordinates => lat != null && lng != null;

  static EventVenue fromJson(Object? json) {
    if (json is! Map) return const EventVenue();
    double? num_(Object? v) => v is num ? v.toDouble() : null;
    return EventVenue(
      name: json['name']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      region: json['region']?.toString() ?? '',
      address: json['address']?.toString(),
      lat: num_(json['lat']),
      lng: num_(json['lng']),
    );
  }
}

class EventOrganizer {
  const EventOrganizer({this.id = '', this.name = '', this.verified = false});

  final String id;
  final String name;
  final bool verified;

  static EventOrganizer fromJson(Object? json) {
    if (json is! Map) return const EventOrganizer();
    return EventOrganizer(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      verified: json['verified'] == true,
    );
  }
}

/// `availability` as the server computes it (spec §11.3, EVT-005).
enum EventAvailability {
  open,
  closingSoon,
  soldOut,
  closed,
  notYetOpen,
  cancelled,
  inProgress,
  completed;

  /// The server's spelling.
  String get wire => switch (this) {
    open => 'open',
    closingSoon => 'closing_soon',
    soldOut => 'sold_out',
    closed => 'closed',
    notYetOpen => 'not_yet_open',
    cancelled => 'cancelled',
    inProgress => 'in_progress',
    completed => 'completed',
  };

  static EventAvailability parse(Object? value) {
    final v = value?.toString().trim().toLowerCase();
    for (final a in values) {
      if (a.wire == v) return a;
    }
    // Unknown words are treated as "closed": nothing to buy, nothing broken.
    return closed;
  }
}

class EventSummary {
  const EventSummary({
    required this.id,
    this.slug,
    required this.title,
    this.type = '',
    this.status = '',
    this.startsAt,
    this.endsAt,
    this.timezone = '',
    this.utcOffsetMinutes = 0,
    this.timezoneAbbr = '',
    this.registrationOpensAt,
    this.registrationClosesAt,
    this.availability = EventAvailability.closed,
    this.venue = const EventVenue(),
    this.heroThumbUrl,
    this.heroImageAlt,
    this.distancesM = const [],
    this.fromPriceTzs,
    this.currency = 'TZS',
    this.organizer = const EventOrganizer(),
    this.isSaved,
    this.updatedAt,
  });

  final String id;
  final String? slug;
  final String title;
  final String type;
  final String status;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String timezone;
  final int utcOffsetMinutes;
  final String timezoneAbbr;
  final DateTime? registrationOpensAt;
  final DateTime? registrationClosesAt;
  final EventAvailability availability;
  final EventVenue venue;
  final String? heroThumbUrl;
  final String? heroImageAlt;
  final List<int> distancesM;

  /// Whole shillings; 0 is free; null when the server sent none.
  final int? fromPriceTzs;
  final String currency;
  final EventOrganizer organizer;
  final bool? isSaved;
  final DateTime? updatedAt;

  bool get isFree => fromPriceTzs == 0;

  EventSummary copyWith({bool? isSaved}) => EventSummary(
    id: id,
    slug: slug,
    title: title,
    type: type,
    status: status,
    startsAt: startsAt,
    endsAt: endsAt,
    timezone: timezone,
    utcOffsetMinutes: utcOffsetMinutes,
    timezoneAbbr: timezoneAbbr,
    registrationOpensAt: registrationOpensAt,
    registrationClosesAt: registrationClosesAt,
    availability: availability,
    venue: venue,
    heroThumbUrl: heroThumbUrl,
    heroImageAlt: heroImageAlt,
    distancesM: distancesM,
    fromPriceTzs: fromPriceTzs,
    currency: currency,
    organizer: organizer,
    isSaved: isSaved ?? this.isSaved,
    updatedAt: updatedAt,
  );

  static EventSummary fromJson(Map<String, dynamic> json) => EventSummary(
    id: json['id']?.toString() ?? '',
    slug: json['slug']?.toString(),
    title: json['title']?.toString() ?? '',
    type: json['type']?.toString() ?? '',
    status: json['status']?.toString() ?? '',
    startsAt: parseInstant(json['startsAt']),
    endsAt: parseInstant(json['endsAt']),
    timezone: json['timezone']?.toString() ?? '',
    utcOffsetMinutes: json['utcOffsetMinutes'] is num
        ? (json['utcOffsetMinutes'] as num).toInt()
        : 0,
    timezoneAbbr: json['timezoneAbbr']?.toString() ?? '',
    registrationOpensAt: parseInstant(json['registrationOpensAt']),
    registrationClosesAt: parseInstant(json['registrationClosesAt']),
    availability: EventAvailability.parse(json['availability']),
    venue: EventVenue.fromJson(json['venue']),
    heroThumbUrl: _url(json['heroThumbUrl']),
    heroImageAlt: json['heroImageAlt']?.toString(),
    distancesM: json['distancesM'] is List
        ? [
            for (final d in json['distancesM'] as List)
              if (d is num) d.toInt(),
          ]
        : const [],
    fromPriceTzs: json['fromPriceTzs'] is num
        ? (json['fromPriceTzs'] as num).toInt()
        : null,
    currency: (json['currency']?.toString() ?? '').isEmpty
        ? 'TZS'
        : json['currency'].toString(),
    organizer: EventOrganizer.fromJson(json['organizer']),
    isSaved: json['isSaved'] is bool ? json['isSaved'] as bool : null,
    updatedAt: parseInstant(json['updatedAt']),
  );
}

/// A UTC instant from an ISO string, or null. Always UTC: the event's own
/// zone is applied for display (event_time.dart), never the device's.
DateTime? parseInstant(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value.trim())?.toUtc();
}

String? _url(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

/// "5K", "10K", "21K", "42K" (half and full marathons round to their
/// customary labels); anything else to one decimal.
String distanceLabel(int metres) {
  if (metres >= 42000 && metres <= 42400) return '42K';
  if (metres >= 21000 && metres <= 21200) return '21K';
  final km = metres / 1000;
  if (km == km.roundToDouble()) return '${km.round()}K';
  return '${km.toStringAsFixed(1)}K';
}
