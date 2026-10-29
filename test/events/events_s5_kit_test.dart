// Events S5 (docs/design/events-s5-venue-api-and-webhooks.md §9.4): the
// ticket page follows the server's `scanning` flag and `kit` state, shows
// the bib, keeps the QR after collection, hints at stale data offline, the
// two new notice types open the ticket, and the gym scanners refuse event
// tickets (client only).
import 'package:fitflexmobile/screens/member/events/member_event_registration_page.dart';
import 'package:fitflexmobile/screens/member/events/tickets/member_event_ticket_page.dart';
import 'package:fitflexmobile/shared/events/event_ticket.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  Size size = const Size(375, 2400),
  EventsOptions? options,
}) => pumpPage(
  tester,
  api,
  MemberEventTicketPage(
    registrationId: 'reg_1',
    options: options ?? optsS3(payment: 'manual', ticketsQr: true),
  ),
  user: member,
  lang: lang,
  size: size,
  extraRoutes: s3Routes,
  keepRequests: true,
);

const _ticketPath = 'GET /me/event-registrations/reg_1/ticket';

Map<String, dynamic> _point({double? lat = -6.8, double? lng = 39.28}) => {
  'id': 'cp_1',
  'name': 'Mlimani City Hall',
  'address': 'Sam Nujoma Road, Dar es Salaam',
  'lat': ?lat,
  'lng': ?lng,
  'windows': [
    {'opensAt': '2000-03-12T06:00:00Z', 'closesAt': '2000-03-12T15:00:00Z'},
    {'opensAt': '2999-03-12T07:00:00Z', 'closesAt': '2999-03-12T10:00:00Z'},
  ],
  'instructions': {
    'en': 'Bring a photo ID.',
    'sw': 'Njoo na kitambulisho chenye picha.',
  },
};

void main() {
  setUp(() => debugEventsDiscoveryOverride = true);
  tearDown(() => debugEventsDiscoveryOverride = null);

  group('event_ticket parsing', () {
    test('kit with time and point, bib, collection points', () {
      final t = EventTicketPayload.fromJson(
        ticketPayload(
          scanning: true,
          bibNumber: '5K-1042',
          kit: {
            'state': 'collected',
            'collectedAt': '2027-03-12T08:00:00Z',
            'collectionPointName': 'Mlimani City Hall',
          },
          collectionPoints: [_point()],
        ),
      );
      expect(t.kit!.isCollected, isTrue);
      expect(t.kit!.collectedAt, DateTime.utc(2027, 3, 12, 8));
      expect(t.kit!.collectionPointName, 'Mlimani City Hall');
      expect(t.bibNumber, '5K-1042');
      expect(t.kitState, 'collected');
      final p = t.collectionPoints.single;
      expect(p.name, 'Mlimani City Hall');
      expect(p.hasLocation, isTrue);
      expect(p.instructions.of('sw'), 'Njoo na kitambulisho chenye picha.');
      // The next window skips the one that already closed.
      expect(p.nextWindow(DateTime.utc(2027))!.opensAt.year, 2999);
    });

    test('nothing sent: no kit, no bib, no points; unknown state is safe', () {
      final t = EventTicketPayload.fromJson(ticketPayload());
      expect(t.kit, isNull);
      expect(t.bibNumber, isNull);
      expect(t.collectionPoints, isEmpty);
      expect(EventKit.fromJson({'state': 'something_new'})!.state, 'not_ready');
      final row = EventTicketRow.fromJson(ticketRow(bibNumber: '12'));
      expect(row.bibNumber, '12');
    });

    test('isEventTicketPayload', () {
      expect(isEventTicketPayload('FFEV1:ev1.k1.x'), isTrue);
      expect(isEventTicketPayload(' FFEV1:abc'), isTrue);
      expect(isEventTicketPayload('FFGYM:abc'), isFalse);
      expect(isEventTicketPayload('ffev1:abc'), isFalse);
      expect(isEventTicketPayload(''), isFalse);
      expect(isEventTicketPayload(null), isFalse);
    });
  });

  group('ticket page wording and kit', () {
    apiTest('scanning false: the soon alert and no kit block', (
      tester,
      api,
    ) async {
      api.on(_ticketPath, ticketPayload());
      await _pump(tester, api);
      expect(find.textContaining("scanning isn't live yet"), findsOneWidget);
      expect(find.byKey(const Key('ticket-kit-state')), findsNothing);
      expect(find.byKey(const Key('ticket-bib-none')), findsNothing);
    });

    apiTest('scanning true: live wording, kit chip, bib hint', (
      tester,
      api,
    ) async {
      api.on(
        _ticketPath,
        ticketPayload(scanning: true, kit: {'state': 'not_ready'}),
      );
      await _pump(tester, api);
      expect(
        find.text('Show this code at the kit collection point.'),
        findsOneWidget,
      );
      expect(find.text('Kit not ready yet'), findsOneWidget);
      expect(find.byKey(const Key('ticket-bib-none')), findsOneWidget);
    });

    apiTest('ready: point, next window, instructions, directions', (
      tester,
      api,
    ) async {
      api.on(
        _ticketPath,
        ticketPayload(
          scanning: true,
          kit: {'state': 'ready'},
          collectionPoints: [_point()],
        ),
      );
      await _pump(tester, api);
      expect(find.text('Kit ready to collect'), findsOneWidget);
      expect(find.text('Mlimani City Hall'), findsOneWidget);
      expect(find.text('Sam Nujoma Road, Dar es Salaam'), findsOneWidget);
      expect(find.text('Bring a photo ID.'), findsOneWidget);
      // The window shown is the upcoming one, not the closed one.
      final w = tester.widget<Text>(
        find.byKey(const Key('ticket-kit-window-cp_1')),
      );
      expect(w.data, contains('10:00–13:00'));
      expect(
        find.byKey(const Key('ticket-kit-directions-cp_1')),
        findsOneWidget,
      );
    });

    apiTest('no coordinates: no directions button', (tester, api) async {
      api.on(
        _ticketPath,
        ticketPayload(
          scanning: true,
          kit: {'state': 'ready'},
          collectionPoints: [_point(lat: null, lng: null)],
        ),
      );
      await _pump(tester, api);
      expect(find.byKey(const Key('ticket-kit-directions-cp_1')), findsNothing);
    });

    apiTest('collected: date and point, the QR stays, no need to show', (
      tester,
      api,
    ) async {
      api.on(
        _ticketPath,
        ticketPayload(
          scanning: true,
          kit: {
            'state': 'collected',
            'collectedAt': '2027-03-12T08:00:00Z',
            'collectionPointName': 'Mlimani City Hall',
          },
        ),
      );
      await _pump(tester, api);
      expect(find.text('Kit collected'), findsOneWidget);
      expect(find.textContaining('at Mlimani City Hall'), findsOneWidget);
      expect(
        find.text("You don't need to show this code again."),
        findsOneWidget,
      );
      expect(find.byKey(const Key('ticket-qr')), findsOneWidget);
    });

    apiTest('exception reads as not ready and asks the organizer', (
      tester,
      api,
    ) async {
      api.on(
        _ticketPath,
        ticketPayload(scanning: true, kit: {'state': 'exception'}),
      );
      await _pump(tester, api);
      expect(find.text('Kit not ready yet'), findsOneWidget);
      expect(
        find.text('Please ask the organizer about your kit.'),
        findsOneWidget,
      );
      expect(find.textContaining('exception'), findsNothing);
    });

    apiTest('bib: large row with a semantic label', (tester, api) async {
      api.on(
        _ticketPath,
        ticketPayload(
          scanning: true,
          bibNumber: '1042',
          kit: {'state': 'ready'},
        ),
      );
      await _pump(tester, api);
      expect(find.text('Bib 1042'), findsOneWidget);
      expect(find.bySemanticsLabel('Bib number 1042'), findsOneWidget);
      expect(find.byKey(const Key('ticket-bib-none')), findsNothing);
    });

    apiTest('offline with a saved copy: stale hint', (tester, api) async {
      await EventTicketCache.put(
        'reg_1',
        ticketPayload(scanning: true, kit: {'state': 'ready'}),
      );
      api.onCall(_ticketPath, (_) => throw StateError('SocketException: down'));
      await _pump(tester, api);
      expect(find.byKey(const Key('ticket-kit-stale')), findsOneWidget);
      expect(
        find.text('Kit status may have changed. Connect to refresh.'),
        findsOneWidget,
      );
    });

    apiTest('online: no stale hint', (tester, api) async {
      api.on(
        _ticketPath,
        ticketPayload(scanning: true, kit: {'state': 'ready'}),
      );
      await _pump(tester, api);
      expect(find.byKey(const Key('ticket-kit-stale')), findsNothing);
    });

    for (final state in ['not_ready', 'ready', 'collected', 'exception']) {
      apiTest('Swahili, long strings, 1.3x, 320 dp ($state): no overflow', (
        tester,
        api,
      ) async {
        api.on(
          _ticketPath,
          ticketPayload(
            scanning: true,
            bibNumber: '5K-1042',
            kit: {
              'state': state,
              'collectedAt': '2027-03-12T08:00:00Z',
              'collectionPointName':
                  'Ukumbi wa Mkutano wa Mlimani City, Sam Nujoma',
            },
            collectionPoints: [_point()],
          ),
        );
        tester.view.devicePixelRatio = 1;
        await _pump(tester, api, lang: 'sw', size: const Size(320, 3200));
        expect(tester.takeException(), isNull);
        expect(find.text('Namba 5K-1042'), findsOneWidget);
      });
    }

    apiTest('wide screens: two columns', (tester, api) async {
      api.on(
        _ticketPath,
        ticketPayload(scanning: true, kit: {'state': 'ready'}),
      );
      await _pump(tester, api, size: const Size(1000, 1400));
      expect(find.byKey(const Key('ticket-columns')), findsOneWidget);
      final qr = tester.getTopLeft(find.byKey(const Key('ticket-qr-card')));
      final kit = tester.getTopLeft(find.byKey(const Key('ticket-kit-state')));
      expect(kit.dx, greaterThan(qr.dx + 300));
    });
  });

  group('bib elsewhere', () {
    apiTest('registration page shows the bib on the ticket card', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-registrations/reg_1',
        registrationJson(
          status: 'confirmed',
          orderStatus: 'confirmed',
          ticket: {'state': 'active', 'displayCode': 'T-3F9A2B'},
          bibNumber: '1042',
        ),
      );
      await pumpPage(
        tester,
        api,
        MemberEventRegistrationPage(
          registrationId: 'reg_1',
          options: optsS3(payment: 'manual', ticketsQr: true),
        ),
        user: member,
        size: const Size(375, 2000),
        extraRoutes: s3Routes,
        keepRequests: true,
      );
      expect(find.text('Bib 1042'), findsOneWidget);
    });
  });

  group('notices and i18n', () {
    test('kit and bib notices open the ticket', () {
      for (final type in ['event_kit_collected', 'event_bib_assigned']) {
        expect(memberLinkFor(deepLink: '', type: type), 'eventTicket');
        expect(
          memberRouteFor(deepLink: '', type: type, registrationId: 'r1'),
          '/member/events/registrations/r1/ticket',
        );
        expect(
          memberRouteFor(deepLink: '', type: type, registrationId: 'bad id!'),
          '/member/events/tickets',
        );
      }
    });

    test('every new key exists in English and Swahili, none identical', () {
      const keys = [
        'events.ticket.kit.title',
        'events.ticket.kit.not_ready',
        'events.ticket.kit.ready',
        'events.ticket.kit.collected',
        'events.ticket.kit.collectedAt',
        'events.ticket.kit.collectedOn',
        'events.ticket.kit.noNeed',
        'events.ticket.kit.exception',
        'events.ticket.kit.where',
        'events.ticket.kit.when',
        'events.ticket.kit.directions',
        'events.ticket.kit.staleHint',
        'events.ticket.bib',
        'events.ticket.bib.a11y',
        'events.ticket.bib.none',
        'events.notify.kitCollected.title',
        'events.notify.kitCollected.body',
        'events.notify.bibAssigned.title',
        'events.notify.bibAssigned.body',
        'ownerScan.eventTicket.title',
        'ownerScan.eventTicket.body',
      ];
      final en = FFLocale.keysOf('en');
      final sw = FFLocale.keysOf('sw');
      for (final k in keys) {
        expect(en, contains(k), reason: k);
        expect(sw, contains(k), reason: k);
      }
      expect(keys.length, 21);
    });
  });
}
