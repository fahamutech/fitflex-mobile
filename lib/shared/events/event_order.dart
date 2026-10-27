// Events S3 (docs/design/events-s3-registration-and-orders.md §3): the
// wire shapes of quotes, orders, registrations, claims and teams. Field names
// are the server's; the client never invents one. Everything is tolerant of
// a missing key (an older or newer server) and never throws on parse.
import 'event_detail.dart';
import 'event_summary.dart';

int _int(Object? v, [int fallback = 0]) => v is num
    ? v.toInt()
    : (v is String ? int.tryParse(v) ?? fallback : fallback);

String _str(Object? v) => v?.toString() ?? '';

String? _opt(Object? v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? null : s;
}

List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? [
        for (final m in v)
          if (m is Map) Map<String, dynamic>.from(m),
      ]
    : const [];

// ── Field policy (§3.3) ──────────────────────────────────────────────────

/// `required | optional | off` for one participant field.
enum FieldPolicy {
  required,
  optional,
  off;

  static FieldPolicy parse(Object? v, FieldPolicy fallback) =>
      switch (v?.toString()) {
        'required' => required,
        'optional' => optional,
        'off' => off,
        _ => fallback,
      };
}

/// The effective `participantFields` the server echoes in a quote (§3.4
/// `fields`). The defaults are the spec's (§3.3) and only stand in until the
/// quote answers; the form is rendered from the server's answer.
class ParticipantFields {
  const ParticipantFields({
    this.phone = FieldPolicy.required,
    this.email = FieldPolicy.optional,
    this.dateOfBirth = FieldPolicy.off,
    this.gender = FieldPolicy.off,
    this.emergencyContact = FieldPolicy.optional,
    this.kitSize = FieldPolicy.off,
  });

  final FieldPolicy phone;
  final FieldPolicy email;
  final FieldPolicy dateOfBirth;
  final FieldPolicy gender;
  final FieldPolicy emergencyContact;
  final FieldPolicy kitSize;

  /// Spec defaults when any category carries a minimum age: the date of
  /// birth is collected (age cannot be checked without it).
  static ParticipantFields defaultsFor({required bool anyMinAge}) =>
      ParticipantFields(
        dateOfBirth: anyMinAge ? FieldPolicy.required : FieldPolicy.off,
      );

  static ParticipantFields fromJson(Object? json, {bool anyMinAge = false}) {
    final base = defaultsFor(anyMinAge: anyMinAge);
    if (json is! Map) return base;
    return ParticipantFields(
      phone: FieldPolicy.parse(json['phone'], base.phone),
      email: FieldPolicy.parse(json['email'], base.email),
      dateOfBirth: FieldPolicy.parse(json['dateOfBirth'], base.dateOfBirth),
      gender: FieldPolicy.parse(json['gender'], base.gender),
      emergencyContact: FieldPolicy.parse(
        json['emergencyContact'],
        base.emergencyContact,
      ),
      kitSize: FieldPolicy.parse(json['kitSize'], base.kitSize),
    );
  }
}

/// Closed set of kit sizes (§3.2 CHECK).
const kitSizes = ['xs', 's', 'm', 'l', 'xl', 'xxl', 'xxxl'];

/// Closed set of genders on the wire (§3.3).
const participantGenders = ['male', 'female', 'other'];

/// Closed set of cancel reasons (§3.8 `MEMBER_CANCEL_REASONS`).
const memberCancelReasons = [
  'changed_mind',
  'wrong_details',
  'duplicate',
  'other',
];

// ── Quote (§3.4) ─────────────────────────────────────────────────────────

class QuoteLine {
  const QuoteLine({
    required this.ticketTypeId,
    this.ticketTypeName = '',
    this.categoryId = '',
    this.categoryName = '',
    this.quantity = 0,
    this.unitPriceTzs = 0,
    this.discountTzs = 0,
    this.feesTzs = 0,
    this.lineTotalTzs = 0,
  });

  final String ticketTypeId;
  final String ticketTypeName;
  final String categoryId;
  final String categoryName;
  final int quantity;
  final int unitPriceTzs;
  final int discountTzs;
  final int feesTzs;
  final int lineTotalTzs;

  static QuoteLine fromJson(Map json) => QuoteLine(
    ticketTypeId: _str(json['ticketTypeId']),
    ticketTypeName: _str(json['ticketTypeName']),
    categoryId: _str(json['categoryId']),
    categoryName: _str(json['categoryName']),
    quantity: _int(json['quantity']),
    unitPriceTzs: _int(json['unitPriceTzs']),
    discountTzs: _int(json['discountTzs']),
    feesTzs: _int(json['feesTzs']),
    lineTotalTzs: _int(json['lineTotalTzs']),
  );
}

/// One problem the server found on a field (`events.validation.<code>`).
class FieldProblem {
  const FieldProblem({required this.field, required this.code, this.extra});
  final String field;
  final String code;
  final Map<String, dynamic>? extra;

  static FieldProblem fromJson(Map json) => FieldProblem(
    field: _str(json['field']),
    code: _str(json['code']),
    extra: Map<String, dynamic>.from(json)
      ..remove('field')
      ..remove('code'),
  );
}

/// `participants[]` of a quote or of a 422 `participant_invalid`.
class ParticipantCheck {
  const ParticipantCheck({
    required this.index,
    this.ok = true,
    this.problems = const [],
  });
  final int index;
  final bool ok;
  final List<FieldProblem> problems;

  static ParticipantCheck fromJson(Map json) => ParticipantCheck(
    index: _int(json['index']),
    ok: json['ok'] != false,
    problems: [
      for (final p in _maps(json['problems'])) FieldProblem.fromJson(p),
    ],
  );

  /// Problems from a `participants` list of either shape, by index.
  static Map<int, List<FieldProblem>> byIndex(Object? list) {
    final out = <int, List<FieldProblem>>{};
    for (final m in _maps(list)) {
      final c = ParticipantCheck.fromJson(m);
      if (c.problems.isNotEmpty) out[c.index] = c.problems;
    }
    return out;
  }
}

class QuoteTeam {
  const QuoteTeam({
    this.mode,
    this.name = '',
    this.memberCount = 0,
    this.maxMembers = 0,
    this.ok = true,
    this.problems = const [],
  });
  final String? mode;
  final String name;
  final int memberCount;
  final int maxMembers;
  final bool ok;
  final List<String> problems;

  static QuoteTeam? fromJson(Object? json) {
    if (json is! Map) return null;
    return QuoteTeam(
      mode: _opt(json['mode']),
      name: _str(json['name']),
      memberCount: _int(json['memberCount']),
      maxMembers: _int(json['maxMembers']),
      ok: json['ok'] != false,
      problems: [
        for (final p
            in json['problems'] is List ? json['problems'] as List : [])
          p is Map ? _str(p['code']) : _str(p),
      ],
    );
  }
}

/// `consentText` of a quote: version plus the copy per consent basis in
/// both languages (the apps never hard-code it, §3.11).
class ConsentText {
  const ConsentText({this.version = '', this.texts = const {}});
  final String version;

  /// `self` / `purchaser_authorised` / `organisation` → `{en, sw}`.
  final Map<String, EventText> texts;

  EventText of(String basis) => texts[basis] ?? const EventText();

  static ConsentText fromJson(Object? json) {
    if (json is! Map) return const ConsentText();
    final texts = <String, EventText>{};
    for (final basis in const [
      'self',
      'purchaser_authorised',
      'organisation',
    ]) {
      final v = json[basis];
      if (v != null) texts[basis] = EventText.fromJson(v);
    }
    // A flat `{version, en, sw}` is the self text.
    if (texts.isEmpty && (json['en'] != null || json['sw'] != null)) {
      texts['self'] = EventText.fromJson(json);
    }
    return ConsentText(version: _str(json['version']), texts: texts);
  }
}

class EventQuote {
  const EventQuote({
    this.valid = true,
    this.currency = 'TZS',
    this.lines = const [],
    this.subtotalTzs = 0,
    this.discountTzs = 0,
    this.feesTzs = 0,
    this.totalTzs = 0,
    this.feeLabel,
    this.quoteExpiresAt,
    this.holdTtlMinutes = 30,
    this.availability = const {},
    this.participants = const [],
    this.problems = const [],
    this.team,
    this.fields = const ParticipantFields(),
    this.refundPolicy = const EventRefundPolicy(),
    this.termsVersion,
    this.consentText = const ConsentText(),
  });

  final bool valid;
  final String currency;
  final List<QuoteLine> lines;
  final int subtotalTzs;
  final int discountTzs;
  final int feesTzs;
  final int totalTzs;

  /// Null when no fee rule is configured (D21: then no fee line shows).
  final EventText? feeLabel;
  final DateTime? quoteExpiresAt;
  final int holdTtlMinutes;

  /// ticketTypeId → (availability, remaining).
  final Map<String, ({EventAvailability availability, int? remaining})>
  availability;
  final List<ParticipantCheck> participants;
  final List<FieldProblem> problems;
  final QuoteTeam? team;
  final ParticipantFields fields;
  final EventRefundPolicy refundPolicy;
  final int? termsVersion;
  final ConsentText consentText;

  bool get isFree => totalTzs == 0;

  Map<int, List<FieldProblem>> get participantProblems => {
    for (final p in participants)
      if (p.problems.isNotEmpty) p.index: p.problems,
  };

  static EventQuote fromJson(
    Map<String, dynamic> json, {
    bool anyMinAge = false,
  }) {
    final q = json['quote'] is Map ? json['quote'] as Map : const {};
    final avail =
        <String, ({EventAvailability availability, int? remaining})>{};
    if (json['availability'] is Map) {
      (json['availability'] as Map).forEach((k, v) {
        if (v is Map) {
          avail[k.toString()] = (
            availability: EventAvailability.parse(v['availability']),
            remaining: v['remaining'] is num
                ? (v['remaining'] as num).toInt()
                : null,
          );
        }
      });
    }
    return EventQuote(
      valid: json['valid'] != false,
      currency: _opt(q['currency']) ?? 'TZS',
      lines: [for (final l in _maps(q['lines'])) QuoteLine.fromJson(l)],
      subtotalTzs: _int(q['subtotalTzs']),
      discountTzs: _int(q['discountTzs']),
      feesTzs: _int(q['feesTzs']),
      totalTzs: _int(q['totalTzs']),
      feeLabel: q['feeLabel'] is Map ? EventText.fromJson(q['feeLabel']) : null,
      quoteExpiresAt: parseInstant(json['quoteExpiresAt']),
      holdTtlMinutes: _int(json['holdTtlMinutes'], 30),
      availability: avail,
      participants: [
        for (final p in _maps(json['participants']))
          ParticipantCheck.fromJson(p),
      ],
      problems: [
        for (final p in _maps(json['problems']))
          FieldProblem(field: '', code: _str(p['code']), extra: p),
      ],
      team: QuoteTeam.fromJson(json['team']),
      fields: ParticipantFields.fromJson(json['fields'], anyMinAge: anyMinAge),
      refundPolicy: EventRefundPolicy.fromJson(json['refundPolicy']),
      termsVersion: json['termsVersion'] is num
          ? (json['termsVersion'] as num).toInt()
          : null,
      consentText: ConsentText.fromJson(json['consentText']),
    );
  }
}

// ── Orders (§3.5, §3.6) ──────────────────────────────────────────────────

/// Order statuses this app knows (§3.12; `confirmed` and refunds are S4).
enum EventOrderStatus {
  awaitingPayment,
  confirmed,
  cancelled,
  expired,
  other;

  static EventOrderStatus parse(Object? v) => switch (v?.toString()) {
    'awaiting_payment' => awaitingPayment,
    'confirmed' => confirmed,
    'cancelled' => cancelled,
    'expired' => expired,
    _ => other,
  };
}

enum EventRegistrationStatus {
  reserved,
  confirmed,
  cancelled,
  other;

  static EventRegistrationStatus parse(Object? v) => switch (v?.toString()) {
    'reserved' => reserved,
    'confirmed' => confirmed,
    'cancelled' => cancelled,
    _ => other,
  };
}

/// What the registration's claim state is: the purchaser's own, waiting
/// for the participant, or claimed.
enum ClaimState {
  self,
  unclaimed,
  claimed;

  static ClaimState parse(Object? v) => switch (v?.toString()) {
    'self' => self,
    'claimed' => claimed,
    _ => unclaimed,
  };
}

/// The small event block on list rows (`event` of §3.6) or a full summary.
EventSummary eventSummaryOf(Object? json) {
  if (json is! Map) return const EventSummary(id: '', title: '');
  return EventSummary.fromJson(Map<String, dynamic>.from(json));
}

class EventOrder {
  const EventOrder({
    required this.id,
    this.reference = '',
    this.eventId = '',
    this.status = EventOrderStatus.other,
    this.statusWire = '',
    this.currency = 'TZS',
    this.subtotalTzs = 0,
    this.discountTzs = 0,
    this.feesTzs = 0,
    this.totalTzs = 0,
    this.holdExpiresAt,
    this.createdAt,
    this.closedAt,
    this.closeReason,
    this.teamId,
    this.placesCount = 0,
    this.event,
  });

  final String id;
  final String reference;
  final String eventId;
  final EventOrderStatus status;
  final String statusWire;
  final String currency;
  final int subtotalTzs;
  final int discountTzs;
  final int feesTzs;
  final int totalTzs;
  final DateTime? holdExpiresAt;
  final DateTime? createdAt;
  final DateTime? closedAt;

  /// `cancelled` | `expired` | `admin` | `payment_failed` (store reason).
  final String? closeReason;
  final String? teamId;
  final int placesCount;
  final EventSummary? event;

  bool get isAwaitingPayment => status == EventOrderStatus.awaitingPayment;

  static EventOrder fromJson(Map json, {EventSummary? event}) => EventOrder(
    id: _str(json['id']),
    reference: _str(json['reference']),
    eventId: _str(
      json['eventId'] ??
          (json['event'] is Map ? (json['event'] as Map)['id'] : null),
    ),
    status: EventOrderStatus.parse(json['status']),
    statusWire: _str(json['status']),
    currency: _opt(json['currency']) ?? 'TZS',
    subtotalTzs: _int(json['subtotalTzs']),
    discountTzs: _int(json['discountTzs']),
    feesTzs: _int(json['feesTzs']),
    totalTzs: _int(json['totalTzs']),
    holdExpiresAt: parseInstant(json['holdExpiresAt']),
    createdAt: parseInstant(json['createdAt']),
    closedAt: parseInstant(json['closedAt']),
    closeReason: _opt(json['closeReason']),
    teamId: _opt(json['teamId']),
    placesCount: _int(json['placesCount']),
    event:
        event ?? (json['event'] is Map ? eventSummaryOf(json['event']) : null),
  );
}

class EmergencyContact {
  const EmergencyContact({this.name = '', this.phone = ''});
  final String name;
  final String phone;
  bool get isEmpty => name.trim().isEmpty && phone.trim().isEmpty;

  Map<String, dynamic> toJson() => {'name': name.trim(), 'phone': phone.trim()};

  static EmergencyContact? fromJson(Object? json) {
    if (json is! Map) return null;
    return EmergencyContact(
      name: _str(json['name']),
      phone: _str(json['phone']),
    );
  }
}

/// A registration as the server returns it (order detail rows, the
/// registrations list and detail; §3.5, §3.6). Contact fields are null when
/// the server did not send them (a list row).
class EventRegistration {
  const EventRegistration({
    required this.id,
    this.ticketTypeId = '',
    this.ticketTypeName = '',
    this.categoryId = '',
    this.categoryName = '',
    this.categoryDistanceM = 0,
    this.categoryStartsAt,
    this.firstName = '',
    this.lastName = '',
    this.status = EventRegistrationStatus.other,
    this.statusWire = '',
    this.consentBasis = '',
    this.consentAt,
    this.isSelf = false,
    this.claimState = ClaimState.unclaimed,
    this.relation = '',
    this.phone,
    this.email,
    this.dateOfBirth,
    this.gender,
    this.kitSize,
    this.emergencyContact,
    this.cancelReason,
    this.orderId = '',
    this.orderReference = '',
    this.orderStatus = EventOrderStatus.other,
    this.holdExpiresAt,
    this.createdAt,
    this.teamId,
    this.teamName,
    this.purchaserNameMasked,
    this.allowedActions = const [],
    this.event,
  });

  final String id;
  final String ticketTypeId;
  final String ticketTypeName;
  final String categoryId;
  final String categoryName;
  final int categoryDistanceM;
  final DateTime? categoryStartsAt;
  final String firstName;
  final String lastName;
  final EventRegistrationStatus status;
  final String statusWire;
  final String consentBasis;
  final DateTime? consentAt;
  final bool isSelf;
  final ClaimState claimState;

  /// `self` | `purchased` | `claimed` (list rows, §3.6).
  final String relation;
  final String? phone;
  final String? email;
  final String? dateOfBirth;
  final String? gender;
  final String? kitSize;
  final EmergencyContact? emergencyContact;
  final String? cancelReason;
  final String orderId;
  final String orderReference;
  final EventOrderStatus orderStatus;
  final DateTime? holdExpiresAt;
  final DateTime? createdAt;
  final String? teamId;
  final String? teamName;

  /// Set when the viewer is the participant and someone else bought.
  final String? purchaserNameMasked;
  final List<String> allowedActions;
  final EventSummary? event;

  String get fullName =>
      [firstName, lastName].where((s) => s.trim().isNotEmpty).join(' ');

  bool get canCancel => allowedActions.contains('cancel');

  /// Any personal detail came back. After a participant claims a place the
  /// server masks the purchaser's view (phone, email, date of birth,
  /// gender, emergency contact are null), so the section is then hidden.
  bool get hasParticipantDetails =>
      phone != null ||
      email != null ||
      dateOfBirth != null ||
      gender != null ||
      kitSize != null ||
      (emergencyContact != null && !emergencyContact!.isEmpty);

  /// The viewer bought this place (relation `self` or `purchased`); a
  /// `claimed` relation means someone else did.
  bool get viewerIsPurchaser => relation != 'claimed';

  static EventRegistration fromJson(Map json) {
    final participant = json['participant'] is Map
        ? json['participant'] as Map
        : const {};
    final category = json['category'] is Map
        ? json['category'] as Map
        : const {};
    final ticketType = json['ticketType'] is Map
        ? json['ticketType'] as Map
        : const {};
    final team = json['team'] is Map ? json['team'] as Map : null;
    final purchaser = json['purchaser'] is Map
        ? json['purchaser'] as Map
        : null;
    return EventRegistration(
      id: _str(json['id']),
      ticketTypeId: _str(json['ticketTypeId'] ?? ticketType['id']),
      ticketTypeName: _str(json['ticketTypeName'] ?? ticketType['name']),
      categoryId: _str(json['categoryId'] ?? category['id']),
      categoryName: _str(json['categoryName'] ?? category['name']),
      categoryDistanceM: _int(category['distanceM']),
      categoryStartsAt: parseInstant(category['startsAt']),
      firstName: _str(json['firstName'] ?? participant['firstName']),
      lastName: _str(json['lastName'] ?? participant['lastName']),
      status: EventRegistrationStatus.parse(json['status']),
      statusWire: _str(json['status']),
      consentBasis: _str(json['consentBasis']),
      consentAt: parseInstant(json['consentAt']),
      isSelf: json['isSelf'] == true || json['relation'] == 'self',
      claimState: ClaimState.parse(json['claimState']),
      relation: _str(json['relation']),
      phone: _opt(json['phone']),
      email: _opt(json['email']),
      dateOfBirth: _opt(json['dateOfBirth']),
      gender: _opt(json['gender']),
      kitSize: _opt(json['kitSize']),
      emergencyContact: EmergencyContact.fromJson(json['emergencyContact']),
      cancelReason: _opt(json['cancelReason']),
      orderId: _str(json['orderId']),
      orderReference: _str(json['orderReference']),
      orderStatus: EventOrderStatus.parse(json['orderStatus']),
      holdExpiresAt: parseInstant(json['holdExpiresAt']),
      createdAt: parseInstant(json['createdAt']),
      teamId: _opt(team?['id']),
      teamName: _opt(team?['name']),
      purchaserNameMasked: _opt(purchaser?['nameMasked']),
      allowedActions: json['allowedActions'] is List
          ? [for (final a in json['allowedActions'] as List) _str(a)]
          : const [],
      event: json['event'] is Map ? eventSummaryOf(json['event']) : null,
    );
  }
}

class EventTeam {
  const EventTeam({
    required this.id,
    this.eventId = '',
    this.name = '',
    this.teamType = '',
    this.joinCode,
    this.memberCount = 0,
    this.maxMembers = 0,
    this.isCaptain = false,
    this.captainName,
    this.members = const [],
  });

  final String id;
  final String eventId;
  final String name;
  final String teamType;

  /// Returned to the captain / creator only.
  final String? joinCode;
  final int memberCount;
  final int maxMembers;
  final bool isCaptain;

  /// "Asha M." from `captain: { firstName, lastInitial }` of a lookup.
  final String? captainName;
  final List<EventTeamMember> members;

  static EventTeam fromJson(Map json) {
    final captain = json['captain'] is Map ? json['captain'] as Map : null;
    return EventTeam(
      id: _str(json['id']),
      eventId: _str(json['eventId']),
      name: _str(json['name']),
      teamType: _str(json['teamType']),
      joinCode: _opt(json['joinCode']),
      memberCount: _int(json['memberCount']),
      maxMembers: _int(json['maxMembers']),
      isCaptain: json['isCaptain'] == true,
      captainName: captain == null
          ? null
          : participantShortName(captain['firstName'], captain['lastInitial']),
      members: [
        for (final m in _maps(json['members'])) EventTeamMember.fromJson(m),
      ],
    );
  }
}

class EventTeamMember {
  const EventTeamMember({
    required this.registrationId,
    this.name = '',
    this.role = 'member',
    this.status = '',
  });
  final String registrationId;
  final String name;
  final String role;
  final String status;

  static EventTeamMember fromJson(Map json) {
    final p = json['participant'] is Map
        ? json['participant'] as Map
        : const {};
    return EventTeamMember(
      registrationId: _str(json['registrationId']),
      name: participantShortName(p['firstName'], p['lastInitial']),
      role: _str(json['role']),
      status: _str(json['status']),
    );
  }
}

/// "Asha M." from a first name and a last initial.
String participantShortName(Object? firstName, Object? lastInitial) {
  final first = _str(firstName).trim();
  final initial = _str(lastInitial).trim();
  if (initial.isEmpty) return first;
  return '$first ${initial.endsWith('.') ? initial : '$initial.'}';
}

/// "A*** M." from the masked fields of a claim preview / claimable row.
String maskedParticipantName(Map? json) {
  if (json == null) return '';
  return participantShortName(json['firstNameMasked'], json['lastInitial']);
}

/// One `claimable` row (§3.6) or the link preview (§3.7). Masked only.
class ClaimPreview {
  const ClaimPreview({
    this.registrationId,
    this.event,
    this.categoryName = '',
    this.participantMasked = '',
    this.purchaserMasked = '',
    this.contactType = '',
    this.contactMasked = '',
    this.status = '',
    this.claimState = ClaimState.unclaimed,
  });

  /// Null for a link preview (the token resolves the registration).
  final String? registrationId;
  final EventSummary? event;
  final String categoryName;
  final String participantMasked;
  final String purchaserMasked;

  /// `phone` | `email`.
  final String contactType;
  final String contactMasked;
  final String status;
  final ClaimState claimState;

  static ClaimPreview fromJson(Map json) {
    final contact = (json['matchedContact'] ?? json['contact']) is Map
        ? (json['matchedContact'] ?? json['contact']) as Map
        : const {};
    final category = json['category'] is Map
        ? json['category'] as Map
        : const {};
    final purchaser = json['purchaser'] is Map
        ? json['purchaser'] as Map
        : const {};
    return ClaimPreview(
      registrationId: _opt(json['id']),
      event: json['event'] is Map ? eventSummaryOf(json['event']) : null,
      categoryName: _str(category['name']),
      participantMasked: maskedParticipantName(
        json['participant'] is Map ? json['participant'] as Map : null,
      ),
      purchaserMasked: _str(purchaser['nameMasked']),
      contactType: _str(contact['type']),
      contactMasked: _str(contact['masked']),
      status: _str(json['status']),
      claimState: ClaimState.parse(json['claimState']),
    );
  }
}

/// `GET /me/event-orders/:id` (§3.6) and the 201 of `POST /me/event-orders`.
class EventOrderDetail {
  const EventOrderDetail({
    required this.order,
    this.lines = const [],
    this.registrations = const [],
    this.event,
    this.team,
    this.payment = 'none',
    this.paymentInstructions,
    this.allowedActions = const [],
    this.replayed = false,
  });

  final EventOrder order;
  final List<QuoteLine> lines;
  final List<EventRegistration> registrations;
  final EventDetail? event;
  final EventTeam? team;

  /// `next.payment`: `none` in S3; `manual` / `provider` are S4's slot.
  final String payment;
  final Map<String, dynamic>? paymentInstructions;
  final List<String> allowedActions;
  final bool replayed;

  bool get canCancel => allowedActions.contains('cancel');

  static EventOrderDetail fromJson(Map<String, dynamic> json) {
    final orderJson = json['order'] is Map ? json['order'] as Map : json;
    final eventJson = json['event'] is Map
        ? Map<String, dynamic>.from(json['event'] as Map)
        : null;
    final event = eventJson == null ? null : EventDetail.fromJson(eventJson);
    final next = json['next'] is Map ? json['next'] as Map : const {};
    final registrations = [
      for (final r in _maps(json['registrations']))
        EventRegistration.fromJson(r),
    ];
    return EventOrderDetail(
      order: EventOrder.fromJson(orderJson, event: event?.summary),
      lines: [for (final l in _maps(json['lines'])) QuoteLine.fromJson(l)],
      registrations: registrations,
      event: event,
      team: json['team'] is Map
          ? EventTeam.fromJson(json['team'] as Map)
          : null,
      payment: _opt(next['payment']) ?? 'none',
      paymentInstructions: next['instructions'] is Map
          ? Map<String, dynamic>.from(next['instructions'] as Map)
          : null,
      allowedActions: json['allowedActions'] is List
          ? [for (final a in json['allowedActions'] as List) _str(a)]
          : const [],
      replayed: json['replayed'] == true,
    );
  }
}

// ── Status vocabulary (§5.10) ─────────────────────────────────────────────

/// i18n key for an order's status pill.
String eventOrderStatusKey(EventOrderStatus s) => switch (s) {
  EventOrderStatus.awaitingPayment => 'events.status.order.awaiting',
  EventOrderStatus.confirmed => 'events.status.order.paid',
  EventOrderStatus.cancelled => 'events.status.order.cancelled',
  EventOrderStatus.expired => 'events.status.order.expired',
  EventOrderStatus.other => 'events.status.order.awaiting',
};

/// i18n key for a registration's status pill, read with its order's state:
/// a `reserved` row whose order expired or was cancelled reads as that.
String eventRegistrationStatusKey(
  EventRegistrationStatus s,
  EventOrderStatus order,
) => switch (s) {
  EventRegistrationStatus.confirmed => 'events.status.confirmed',
  EventRegistrationStatus.cancelled => 'events.status.cancelled',
  EventRegistrationStatus.reserved ||
  EventRegistrationStatus.other => switch (order) {
    EventOrderStatus.expired => 'events.status.expired',
    EventOrderStatus.cancelled => 'events.status.cancelled',
    _ => 'events.status.awaiting',
  },
};

/// Whether a registration (with its order's state) is still live.
bool registrationIsLive(EventRegistrationStatus s, EventOrderStatus order) =>
    s != EventRegistrationStatus.cancelled &&
    order != EventOrderStatus.expired &&
    order != EventOrderStatus.cancelled;
