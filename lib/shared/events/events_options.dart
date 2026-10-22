/// What the server switched on for events (`GET /events/options`, spec §13).
/// The endpoint is public and answers even while the server module is off
/// (`discovery: false`), so a 404 or a network error simply means "off".
class EventsRegion {
  const EventsRegion({required this.code, required this.nameEn, this.nameSw});

  final String code;
  final String nameEn;
  final String? nameSw;

  /// The region's name in [lang] (Swahili when given, else English).
  String name(String lang) =>
      lang == 'sw' && (nameSw ?? '').trim().isNotEmpty ? nameSw! : nameEn;

  static EventsRegion? fromJson(Object? json) {
    if (json is! Map) return null;
    final code = json['code']?.toString() ?? '';
    if (code.isEmpty) return null;
    final name = json['name'];
    if (name is Map) {
      return EventsRegion(
        code: code,
        nameEn: name['en']?.toString() ?? code,
        nameSw: name['sw']?.toString(),
      );
    }
    return EventsRegion(code: code, nameEn: name?.toString() ?? code);
  }
}

class EventsOptions {
  const EventsOptions({
    this.discovery = false,
    this.favourites = false,
    this.registration = false,
    this.currency = 'TZS',
    this.closingSoonHours = 72,
    this.regions = const [],
    this.timezones = const [],
  });

  /// Everything off: the probe failed or the module is off.
  static const off = EventsOptions();

  final bool discovery;
  final bool favourites;
  final bool registration;
  final String currency;
  final int closingSoonHours;
  final List<EventsRegion> regions;
  final List<String> timezones;

  static EventsOptions fromJson(Object? json) {
    if (json is! Map) return off;
    return EventsOptions(
      discovery: json['discovery'] == true,
      favourites: json['favourites'] == true,
      registration: json['registration'] == true,
      currency: (json['currency']?.toString() ?? '').isEmpty
          ? 'TZS'
          : json['currency'].toString(),
      closingSoonHours: json['closingSoonHours'] is num
          ? (json['closingSoonHours'] as num).toInt()
          : 72,
      regions: json['regions'] is List
          ? [for (final r in json['regions'] as List) ?EventsRegion.fromJson(r)]
          : const [],
      timezones: json['timezones'] is List
          ? [for (final t in json['timezones'] as List) t.toString()]
          : const [],
    );
  }
}
