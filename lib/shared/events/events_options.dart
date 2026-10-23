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

/// Which contact types the claim screen can verify in the app (events S3
/// spec §3.1 `claim`, copied by the server from `/auth/options`).
class EventsClaimOptions {
  const EventsClaimOptions({this.smsCodes = false, this.emailCodes = false});

  final bool smsCodes;
  final bool emailCodes;

  /// Whether a contact of [type] (`phone` | `email`) can be verified now.
  bool verifiable(String type) => type == 'phone' ? smsCodes : emailCodes;

  static EventsClaimOptions fromJson(Object? json) {
    if (json is! Map) return const EventsClaimOptions();
    return EventsClaimOptions(
      smsCodes: json['smsCodes'] == true,
      emailCodes: json['emailCodes'] == true,
    );
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
    this.holdTtlMinutes = 30,
    this.maxParticipantsPerOrder = 10,
    this.payment = 'none',
    this.teams = false,
    this.corporate = false,
    this.claim = const EventsClaimOptions(),
    this.consentTextVersion = '',
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

  // ── Registration (S3 spec §3.1); present only with `registration: true` ──

  /// How long an unpaid order holds its places.
  final int holdTtlMinutes;

  /// Most people in one member order (`EVENTS_MAX_PARTICIPANTS_PER_ORDER`).
  final int maxParticipantsPerOrder;

  /// `none` (S3) | `manual` | `provider` (S4). The order page keeps a slot
  /// for the two S4 values and renders the placeholder for `none`.
  final String payment;
  final bool teams;
  final bool corporate;
  final EventsClaimOptions claim;

  /// `EVENTS_CONSENT_TEXT_VERSION`; the quote carries the authoritative one.
  final String consentTextVersion;

  static EventsOptions fromJson(Object? json) {
    if (json is! Map) return off;
    int intOf(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    return EventsOptions(
      discovery: json['discovery'] == true,
      favourites: json['favourites'] == true,
      registration: json['registration'] == true,
      holdTtlMinutes: intOf(json['holdTtlMinutes'], 30),
      maxParticipantsPerOrder: intOf(json['maxParticipantsPerOrder'], 10),
      payment: (json['payment']?.toString() ?? '').isEmpty
          ? 'none'
          : json['payment'].toString(),
      teams: json['teams'] == true,
      corporate: json['corporate'] == true,
      claim: EventsClaimOptions.fromJson(json['claim']),
      consentTextVersion: json['consentTextVersion']?.toString() ?? '',
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
