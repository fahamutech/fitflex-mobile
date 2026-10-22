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
