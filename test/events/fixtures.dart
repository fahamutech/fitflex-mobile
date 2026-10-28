// Shared fixtures for the events S2 tests (spec §14.1 / §14.2 shapes).
import 'package:fitflexmobile/shared/events/events_options.dart';

const optionsOn = {
  'discovery': true,
  'favourites': false,
  'registration': false,
  'currency': 'TZS',
  'closingSoonHours': 72,
  'regions': [
    {
      'code': 'dar',
      'name': {'en': 'Dar es Salaam', 'sw': 'Dar es Salaam'},
    },
    {
      'code': 'arusha',
      'name': {'en': 'Arusha', 'sw': 'Arusha'},
    },
  ],
  'timezones': ['Africa/Dar_es_Salaam'],
};

EventsOptions opts({
  bool discovery = true,
  bool favourites = false,
  bool registration = false,
}) => EventsOptions.fromJson({
  ...optionsOn,
  'discovery': discovery,
  'favourites': favourites,
  'registration': registration,
});

Map<String, dynamic> summary(
  String id, {
  String title = 'Dar Half Marathon',
  String availability = 'open',
  int? fromPriceTzs = 25000,
  String? heroThumbUrl = 'https://img.fixtures.local/$_thumb',
  List<int> distancesM = const [5000, 10000, 21097],
  bool verified = true,
  bool? isSaved,
  String startsAt = '2027-03-14T03:30:00Z',
  String? registrationOpensAt = '2027-01-01T00:00:00Z',
  String? registrationClosesAt = '2027-03-12T20:59:00Z',
  int utcOffsetMinutes = 180,
  String timezone = 'Africa/Dar_es_Salaam',
  String timezoneAbbr = 'EAT',
  String type = 'road',
}) => {
  'id': id,
  'slug': id,
  'title': title,
  'type': type,
  'status': 'published',
  'startsAt': startsAt,
  'endsAt': '2027-03-14T08:00:00Z',
  'timezone': timezone,
  'utcOffsetMinutes': utcOffsetMinutes,
  'timezoneAbbr': timezoneAbbr,
  'registrationOpensAt': registrationOpensAt,
  'registrationClosesAt': registrationClosesAt,
  'availability': availability,
  'venue': {'name': 'Coco Beach', 'city': 'Dar es Salaam', 'region': 'dar'},
  'heroThumbUrl': heroThumbUrl,
  'heroImageAlt': 'Runners at Coco Beach',
  'distancesM': distancesM,
  'fromPriceTzs': fromPriceTzs,
  'currency': 'TZS',
  'organizer': {'id': 'org_1', 'name': 'Dar Runners', 'verified': verified},
  'isSaved': ?isSaved,
  'updatedAt': '2027-03-02T10:00:00Z',
};

const _thumb = 'thumb.webp';

Map<String, dynamic> detail(
  String id, {
  String availability = 'open',
  bool registration = false,
  String? heroImageUrl = 'https://img.fixtures.local/hero.webp',
  Map<String, String> description = const {
    'en': 'A flat, fast course along the ocean road.',
    'sw': 'Njia tambarare na ya kasi kando ya barabara ya bahari.',
  },
  Map<String, dynamic>? cancellation,
  int utcOffsetMinutes = 180,
  String timezone = 'Africa/Dar_es_Salaam',
  String timezoneAbbr = 'EAT',
  String? registrationClosesAt = '2027-03-12T20:59:00Z',
  String? registrationOpensAt = '2027-01-01T00:00:00Z',
  int? fromPriceTzs = 25000,
}) => {
  ...summary(
    id,
    availability: availability,
    utcOffsetMinutes: utcOffsetMinutes,
    timezone: timezone,
    timezoneAbbr: timezoneAbbr,
    registrationClosesAt: registrationClosesAt,
    registrationOpensAt: registrationOpensAt,
    fromPriceTzs: fromPriceTzs,
  ),
  'description': description,
  'heroImageUrl': heroImageUrl,
  'coverAlt': 'Runners at Coco Beach',
  'routeUrl': 'https://routes.fixtures.local/dar-half',
  'routeImageUrl': null,
  'routeImageAlt': null,
  'venue': {
    'name': 'Coco Beach',
    'city': 'Dar es Salaam',
    'region': 'dar',
    'address': 'Toure Drive, Msasani',
    'lat': -6.76,
    'lng': 39.27,
  },
  'accessibility': {'en': 'Wheelchair access at the start.', 'sw': ''},
  'inclusions': {
    'en': 'Race kit, medal and water.',
    'sw': 'Kiti, medali na maji.',
  },
  'categories': [
    {
      'id': 'cat_21',
      'name': '21K Half Marathon',
      'distanceM': 21097,
      'startsAt': '2027-03-14T03:30:00Z',
      'capacity': 500,
      'availability': availability,
      'remaining': 7,
      'eligibility': {'en': 'Ages 18 and over.', 'sw': 'Miaka 18 na zaidi.'},
      'minAge': 18,
      'ticketTypes': [
        {
          'id': 'tt_early',
          'name': 'Early bird',
          'priceTzs': 20000,
          'currency': 'TZS',
          'saleOpensAt': '2027-01-01T00:00:00Z',
          'saleClosesAt': '2027-03-01T20:59:00Z',
          'minPerOrder': 1,
          'maxPerOrder': 10,
          'availability': 'sold_out',
        },
        {
          'id': 'tt_std',
          'name': 'Standard',
          'priceTzs': 25000,
          'currency': 'TZS',
          'saleOpensAt': '2027-01-01T00:00:00Z',
          'saleClosesAt': '2027-03-12T20:59:00Z',
          'minPerOrder': 1,
          'maxPerOrder': 10,
          'availability': 'open',
        },
      ],
    },
    {
      'id': 'cat_5',
      'name': '5K Fun Run',
      'distanceM': 5000,
      'startsAt': '2027-03-14T04:30:00Z',
      'capacity': null,
      'availability': 'open',
      'remaining': null,
      'eligibility': {'en': '', 'sw': ''},
      'minAge': null,
      'ticketTypes': [
        {
          'id': 'tt_free',
          'name': 'Free entry',
          'priceTzs': 0,
          'currency': 'TZS',
          'saleOpensAt': '2027-01-01T00:00:00Z',
          'saleClosesAt': '2027-03-12T20:59:00Z',
          'minPerOrder': 1,
          'maxPerOrder': 5,
          'availability': 'open',
        },
      ],
    },
  ],
  'collectionPoints': [
    {
      'id': 'cp_1',
      'name': 'Slipway kit tent',
      'address': 'Slipway, Msasani',
      'lat': -6.75,
      'lng': 39.28,
      'windows': [
        {'opensAt': '2027-03-12T06:00:00Z', 'closesAt': '2027-03-12T15:00:00Z'},
      ],
      'instructions': {
        'en': 'Bring your ID.',
        'sw': 'Leta kitambulisho chako.',
      },
    },
  ],
  'schedule': [
    {
      'at': '2027-03-14T03:00:00Z',
      'label': {'en': 'Warm-up', 'sw': 'Kupasha mwili moto'},
    },
  ],
  'sponsors': [
    {'name': 'Kilimanjaro Water', 'logoUrl': null, 'url': null},
  ],
  'contact': {
    'email': 'hello@darrunners.example',
    'phone': '+255700000000',
    'whatsapp': '+255700000000',
  },
  'terms': {
    'en': 'Participants run at their own risk. ' * 6,
    'sw': 'Washiriki hukimbia kwa hatari yao wenyewe. ' * 6,
  },
  'refundPolicy': {
    'preset': 'refund_until_close',
    'text': {'en': '', 'sw': ''},
  },
  'cancellation': cancellation,
  'shareUrl': 'https://fitflex.africa/member/events/$id',
  'publishedAt': '2027-02-01T10:00:00Z',
  'updatedAt': '2027-03-02T10:00:00Z',
  'version': 3,
};

Map<String, dynamic> page(List<Map<String, dynamic>> items, {String? next}) => {
  'items': items,
  'nextCursor': next,
  'total': items.length,
};

// ── Events S3 (registration, orders, claims, teams; spec §3) ─────────────

final optionsS3 = <String, dynamic>{
  ...optionsOn,
  'registration': true,
  'holdTtlMinutes': 30,
  'maxParticipantsPerOrder': 10,
  'payment': 'none',
  'teams': true,
  'corporate': true,
  'claim': {'smsCodes': true, 'emailCodes': false},
  'consentTextVersion': '2026-10-draft',
};

EventsOptions optsS3({
  bool registration = true,
  bool teams = true,
  bool corporate = true,
  int maxParticipantsPerOrder = 10,
  bool smsCodes = true,
  bool emailCodes = false,
  String payment = 'none',
  bool ticketsQr = false,
  bool scanning = false,
}) => EventsOptions.fromJson({
  ...optionsS3,
  'registration': registration,
  'teams': teams,
  'corporate': corporate,
  'maxParticipantsPerOrder': maxParticipantsPerOrder,
  'claim': {'smsCodes': smsCodes, 'emailCodes': emailCodes},
  'payment': payment,
  // Events S4 (spec §3.1): only present when payment is on.
  if (payment != 'none') ...{
    'manualConfirmHours': 24,
    'refundDays': 5,
    'hold': {
      'manualExtendHours': 24,
      'manualMaxHours': 48,
      'providerExtendMinutes': 10,
      'lateGraceHours': 24,
    },
  },
  'tickets': {'qr': ticketsQr, 'scanning': scanning},
});

const consentTextJson = {
  'version': '2026-10-draft',
  'self': {
    'en': 'I agree to the event terms (self).',
    'sw': 'Nakubali (self).',
  },
  'purchaser_authorised': {
    'en': 'I confirm I have each listed person\'s permission.',
    'sw': 'Nathibitisha nina ruhusa.',
  },
  'organisation': {'en': 'We confirm.', 'sw': 'Tunathibitisha.'},
};

const fieldsDefault = {
  'phone': 'required',
  'email': 'optional',
  'dateOfBirth': 'required',
  'gender': 'off',
  'emergencyContact': 'optional',
  'kitSize': 'optional',
};

Map<String, dynamic> quoteLine({
  String ticketTypeId = 'tt_std',
  String name = 'Standard',
  String categoryId = 'cat_21',
  String categoryName = '21K Half Marathon',
  int quantity = 1,
  int unit = 25000,
  int fees = 0,
  int discount = 0,
}) => {
  'ticketTypeId': ticketTypeId,
  'ticketTypeName': name,
  'categoryId': categoryId,
  'categoryName': categoryName,
  'quantity': quantity,
  'unitPriceTzs': unit,
  'discountTzs': discount,
  'feesTzs': fees,
  'lineTotalTzs': unit * quantity - discount + fees,
};

Map<String, dynamic> quoteJson({
  List<Map<String, dynamic>>? lines,
  int? total,
  int fees = 0,
  int discount = 0,
  Map<String, String>? feeLabel,
  Map<String, dynamic> fields = fieldsDefault,
  List<Map<String, dynamic>> participants = const [],
  List<Map<String, dynamic>> problems = const [],
  Map<String, dynamic>? availability,
  Map<String, dynamic>? team,
  bool valid = true,
}) {
  final l = lines ?? [quoteLine()];
  final subtotal = l.fold<int>(0, (a, m) => a + (m['lineTotalTzs'] as int));
  return {
    'valid': valid,
    'quote': {
      'currency': 'TZS',
      'lines': l,
      'subtotalTzs': subtotal,
      'discountTzs': discount,
      'feesTzs': fees,
      'totalTzs': total ?? (subtotal - discount + fees),
      'feeLabel': feeLabel,
    },
    'quoteExpiresAt': '2027-03-10T12:05:00Z',
    'holdTtlMinutes': 30,
    'availability':
        availability ??
        {
          for (final m in l)
            m['ticketTypeId']: {'availability': 'open', 'remaining': null},
        },
    'participants': participants,
    'problems': problems,
    'team': team,
    'fields': fields,
    'refundPolicy': {
      'preset': 'refund_until_close',
      'text': {'en': '', 'sw': ''},
    },
    'termsVersion': 3,
    'consentText': consentTextJson,
  };
}

Map<String, dynamic> registrationJson({
  String id = 'reg_1',
  String ticketTypeId = 'tt_std',
  String ticketTypeName = 'Standard',
  String categoryId = 'cat_21',
  String categoryName = '21K Half Marathon',
  String firstName = 'Asha',
  String lastName = 'Mollel',
  String status = 'reserved',
  String consentBasis = 'self',
  bool isSelf = true,
  String claimState = 'self',
  String relation = 'self',
  String orderId = 'ord_1',
  String orderReference = 'EV-3F9A2B7C1D',
  String orderStatus = 'awaiting_payment',
  String? holdExpiresAt = '2027-03-10T12:27:00Z',
  String? phone = '+255712345678',
  String? email,
  String? dateOfBirth = '1990-05-09',
  String? gender,
  String? kitSize = 'm',
  Map<String, String>? emergencyContact,
  List<String> allowedActions = const ['cancel'],
  Map<String, dynamic>? team,
  Map<String, dynamic>? purchaser,
  Map<String, dynamic>? event,
  Map<String, dynamic>? ticket,
  List<Map<String, dynamic>>? refunds,
  String? claimInvitedAt,
  int claimInviteCount = 0,
}) => {
  'id': id,
  'ticketTypeId': ticketTypeId,
  'ticketTypeName': ticketTypeName,
  'categoryId': categoryId,
  'categoryName': categoryName,
  'firstName': firstName,
  'lastName': lastName,
  'status': status,
  'consentBasis': consentBasis,
  'consentAt': '2027-03-10T11:57:00Z',
  'isSelf': isSelf,
  'claimState': claimState,
  'relation': relation,
  'orderId': orderId,
  'orderReference': orderReference,
  'orderStatus': orderStatus,
  'holdExpiresAt': holdExpiresAt,
  'phone': phone,
  'email': email,
  'dateOfBirth': dateOfBirth,
  'gender': gender,
  'kitSize': kitSize,
  'emergencyContact': emergencyContact,
  'allowedActions': allowedActions,
  'ticket': ticket,
  'refunds': ?refunds,
  'claimInvitedAt': claimInvitedAt,
  'claimInviteCount': claimInviteCount,
  'team': team,
  'purchaser': purchaser,
  'createdAt': '2027-03-10T11:57:00Z',
  'event': event ?? summary('evt_1'),
  'category': {
    'id': categoryId,
    'name': categoryName,
    'distanceM': 21097,
    'startsAt': '2027-03-14T03:30:00Z',
  },
  'ticketType': {'name': ticketTypeName},
  'participant': {'firstName': firstName, 'lastName': lastName},
};

Map<String, dynamic> orderJson({
  String id = 'ord_1',
  String reference = 'EV-3F9A2B7C1D',
  String status = 'awaiting_payment',
  String? holdExpiresAt = '2027-03-10T12:27:00Z',
  String? closeReason,
  String? closedAt,
  int total = 25000,
  List<Map<String, dynamic>>? lines,
  List<Map<String, dynamic>>? registrations,
  String payment = 'none',
  List<String>? allowedActions,
  Map<String, dynamic>? team,
  Map<String, dynamic>? event,
  bool replayed = false,
  Map<String, dynamic>? paymentView,
  Map<String, dynamic>? instructions,
  String? paymentRequestId,
  List<Map<String, dynamic>>? refunds,
}) => {
  'order': {
    'id': id,
    'reference': reference,
    'eventId': 'evt_1',
    'status': status,
    'currency': 'TZS',
    'subtotalTzs': total,
    'discountTzs': 0,
    'feesTzs': 0,
    'totalTzs': total,
    'holdExpiresAt': holdExpiresAt,
    'holdCycle': 1,
    'createdAt': '2027-03-10T11:57:00Z',
    'closedAt': closedAt,
    'closeReason': closeReason,
    'teamId': team?['id'],
  },
  'lines': lines ?? [quoteLine()],
  'registrations': registrations ?? [registrationJson(orderStatus: status)],
  'holdExpiresAt': holdExpiresAt,
  'next': {
    'payment': payment,
    'instructions': instructions,
    'paymentRequestId': paymentRequestId,
  },
  'payment': paymentView,
  'refunds': ?refunds,
  'event': event ?? detail('evt_1', registration: true),
  'team': team,
  'allowedActions':
      allowedActions ?? (status == 'awaiting_payment' ? ['cancel'] : []),
  'replayed': replayed,
};

Map<String, dynamic> orderRow({
  String id = 'ord_1',
  String reference = 'EV-3F9A2B7C1D',
  String status = 'awaiting_payment',
  String? holdExpiresAt = '2027-03-10T12:27:00Z',
  int placesCount = 1,
  int total = 25000,
}) => {
  'id': id,
  'reference': reference,
  'status': status,
  'event': summary('evt_1'),
  'placesCount': placesCount,
  'totalTzs': total,
  'currency': 'TZS',
  'holdExpiresAt': holdExpiresAt,
  'createdAt': '2027-03-10T11:57:00Z',
  'closedAt': null,
  'closeReason': null,
};

Map<String, dynamic> claimableJson({
  String id = 'reg_9',
  String purchaser = 'N**** A*******',
  String type = 'phone',
  String masked = '••• 678',
  String status = 'reserved',
}) => {
  'id': id,
  'event': summary('evt_1'),
  'category': {'name': '10K'},
  'participant': {'firstNameMasked': 'A***', 'lastInitial': 'M'},
  'purchaser': {'nameMasked': purchaser},
  'matchedContact': {'type': type, 'masked': masked},
  'status': status,
};

Map<String, dynamic> claimPreviewJson({
  String status = 'reserved',
  String claimState = 'unclaimed',
  String type = 'phone',
}) => {
  'event': summary('evt_1'),
  'category': {'name': '10K'},
  'participant': {'firstNameMasked': 'A***', 'lastInitial': 'M'},
  'purchaser': {'nameMasked': 'N**** A*******'},
  'contact': {'type': type, 'masked': '••• 678'},
  'status': status,
  'claimState': claimState,
};

Map<String, dynamic> teamJson({
  String id = 'team_1',
  String name = 'Coco Runners',
  String teamType = 'community',
  String? joinCode = 'AB12CD34',
  int memberCount = 2,
  int maxMembers = 50,
  bool isCaptain = true,
  List<Map<String, dynamic>>? members,
}) => {
  'id': id,
  'eventId': 'evt_1',
  'name': name,
  'teamType': teamType,
  'joinCode': joinCode,
  'memberCount': memberCount,
  'maxMembers': maxMembers,
  'isCaptain': isCaptain,
  'captain': {'firstName': 'Asha', 'lastInitial': 'M'},
  'members':
      members ??
      [
        {
          'registrationId': 'reg_1',
          'participant': {'firstName': 'Asha', 'lastInitial': 'M'},
          'role': 'captain',
          'status': 'reserved',
        },
        {
          'registrationId': 'reg_2',
          'participant': {'firstName': 'Juma', 'lastInitial': 'K'},
          'role': 'member',
          'status': 'reserved',
        },
      ],
};

// ── Events S4 fixtures (spec §3.5, §3.8, §3.12) ──────────────────────────

/// `next.instructions` for a manual order: Lipa Namba plus the order's own
/// amount and reference.
Map<String, dynamic> manualInstructions({
  int amountTzs = 25000,
  bool payerPhoneRequired = true,
  String lipaNamba = '5123456',
  String accountName = 'FitFlex Africa',
  String? network = 'Vodacom',
}) => {
  'lipaNamba': lipaNamba,
  'accountName': accountName,
  'network': network,
  'instructions': {
    'en': 'Pay from M-Pesa, Tigo Pesa or Airtel Money.',
    'sw': 'Lipa kwa M-Pesa, Tigo Pesa au Airtel Money.',
  },
  'amountTzs': amountTzs,
  'reference': 'EV-3F9A2B7C1D',
  'referenceRequired': true,
  'payerPhoneRequired': payerPhoneRequired,
};

/// A `PaymentView`.
Map<String, dynamic> paymentView({
  String state = 'submitted',
  String method = 'manual',
  int amountTzs = 25000,
  String? reference = 'QGH7XK2L9P',
  String? payerPhoneMasked = '+255 7•• ••• 678',
  String? submittedAt = '2027-03-10T12:00:00Z',
  String? confirmTargetAt = '2027-03-11T12:00:00Z',
  String? rejectCode,
  String? memberNote,
  bool late = false,
  bool canRetry = false,
  String? refundId,
}) => {
  'id': 'evp_1',
  'state': state,
  'method': method,
  'amountTzs': amountTzs,
  'currency': 'TZS',
  'reference': reference,
  'payerPhoneMasked': payerPhoneMasked,
  'submittedAt': submittedAt,
  'decidedAt': null,
  'confirmTargetAt': confirmTargetAt,
  'rejectCode': rejectCode,
  'memberNote': memberNote,
  'late': late,
  'canRetry': canRetry,
  'refundId': refundId,
};

Map<String, dynamic> refundView({
  String id = 'rf_1',
  String status = 'requested',
  String scope = 'registration',
  int amountTzs = 25000,
  String? paidTo,
  String? paymentReference,
  String? rejectionNote,
}) => {
  'id': id,
  'status': status,
  'scope': scope,
  'amountTzs': amountTzs,
  'currency': 'TZS',
  'requestedAt': '2027-03-10T13:00:00Z',
  'decidedAt': null,
  'paidAt': status == 'paid' ? '2027-03-12T09:00:00Z' : null,
  'paidTo': paidTo,
  'paymentReference': paymentReference,
  'rejectionNote': rejectionNote,
};

/// An order awaiting payment in manual mode, with the instructions.
Map<String, dynamic> manualOrderJson({
  Map<String, dynamic>? paymentView,
  int total = 25000,
  String status = 'awaiting_payment',
  String? closeReason,
  String? closedAt,
  String? holdExpiresAt = '2027-03-10T12:27:00Z',
  List<Map<String, dynamic>>? refunds,
  List<Map<String, dynamic>>? registrations,
  List<String>? allowedActions,
}) => orderJson(
  payment: 'manual',
  total: total,
  status: status,
  closeReason: closeReason,
  closedAt: closedAt,
  holdExpiresAt: holdExpiresAt,
  instructions: manualInstructions(amountTzs: total),
  paymentView: paymentView,
  refunds: refunds,
  registrations: registrations,
  allowedActions: allowedActions,
);

/// The server's answer to `POST …/payment`.
Map<String, dynamic> paymentAccepted({
  String mode = 'manual',
  bool replayed = false,
  bool late = false,
  String? paymentRequestId = 'pr_1',
}) => {
  'payment': paymentView(),
  'order': {
    'id': 'ord_1',
    'reference': 'EV-3F9A2B7C1D',
    'status': 'awaiting_payment',
    'totalTzs': 25000,
    'currency': 'TZS',
    'holdExpiresAt': '2027-03-11T12:00:00Z',
  },
  'next': {'payment': mode, 'paymentRequestId': paymentRequestId},
  'late': late,
  'replayed': replayed,
};

/// One ticket wallet item.
Map<String, dynamic> ticketRow({
  String registrationId = 'reg_1',
  String state = 'active',
  String displayCode = 'T-3F9A2B',
  String relation = 'self',
  String eventId = 'evt_1',
  String title = 'Dar Half Marathon',
  String availability = 'open',
  String startsAt = '2027-03-14T03:30:00Z',
  String first = 'Asha',
  String last = 'Mollel',
}) => {
  'registrationId': registrationId,
  'ticketId': 'etk_$registrationId',
  'displayCode': displayCode,
  'state': state,
  'event': summary(
    eventId,
    title: title,
    availability: availability,
    startsAt: startsAt,
  ),
  'category': {
    'name': '21K Half Marathon',
    'distanceM': 21097,
    'startsAt': startsAt,
  },
  'ticketType': {'name': 'Standard'},
  'participant': {'firstName': first, 'lastName': last},
  'relation': relation,
  'orderReference': 'EV-3F9A2B7C1D',
  'issuedAt': '2027-03-10T12:30:00Z',
  'kit': null,
};

/// `GET /me/event-registrations/:id/ticket`.
Map<String, dynamic> ticketPayload({
  String registrationId = 'reg_1',
  String token = 'ev1.k1.etk_reg_1.1.AAAAAAAAAAAAAAAAAAAAAA',
  String displayCode = 'T-3F9A2B',
  bool scanning = false,
  String relation = 'self',
  String first = 'Asha',
}) => {
  'ticket': {
    'id': 'etk_$registrationId',
    'displayCode': displayCode,
    'state': 'active',
    'issuedAt': '2027-03-10T12:30:00Z',
    'rotatedAt': '2027-03-10T12:30:00Z',
  },
  'token': token,
  'qrPayload': 'FFEV1:$token',
  'event': summary('evt_1'),
  'category': {'name': '21K Half Marathon', 'distanceM': 21097},
  'ticketType': {'name': 'Standard'},
  'participant': {'firstName': first, 'lastName': 'Mollel'},
  'relation': relation,
  'scanning': scanning,
  'kit': null,
};

/// `cancel-preview`.
Map<String, dynamic> cancelPreview({
  String mode = 'auto',
  int percent = 100,
  int paidTzs = 25000,
  int? refundTzs,
  String? deadlineAt = '2027-03-12T20:59:00Z',
  String preset = 'refund_until_close',
  String? blocked,
  bool eligible = true,
}) => {
  'eligible': eligible,
  'mode': mode,
  'percent': percent,
  'paidTzs': paidTzs,
  'refundTzs': refundTzs ?? (paidTzs * percent ~/ 100),
  'currency': 'TZS',
  'deadlineAt': deadlineAt,
  'policy': {
    'preset': preset,
    'text': {
      'en': 'Refunds until registration closes.',
      'sw': 'Marejesho hadi usajili ufungwe.',
    },
  },
  'places': [
    {
      'registrationId': 'reg_1',
      'name': 'Asha Mollel',
      'paidTzs': paidTzs,
      'refundTzs': refundTzs ?? (paidTzs * percent ~/ 100),
    },
  ],
  'releaseInventory': true,
  'blocked': blocked,
};
