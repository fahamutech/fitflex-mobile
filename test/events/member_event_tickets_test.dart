// Events S4 (spec §5.4 member_event_tickets_test): the Tickets segment
// (there with `tickets.qr`, first when a ticket is active), the sections,
// the card states and semantics, empty / error / offline, and that the list
// never carries a token.
import 'dart:convert';

import 'package:fitflexmobile/screens/member/events/member_event_orders_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  String tab = '',
  bool qr = true,
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  MemberEventOrdersPage(
    initialTab: tab,
    options: optsS3(payment: 'manual', ticketsQr: qr),
    now: DateTime.utc(2027, 3, 10, 12),
  ),
  user: member,
  lang: lang,
  size: const Size(375, 1600),
  extraRoutes: s3Routes,
  keepRequests: true,
);

void _seedOthers(RecordingApi api) {
  api.on('GET /me/event-registrations', page([registrationJson()]));
  api.on('GET /me/event-registrations/claimable', {'items': []});
  api.on('GET /me/event-orders', page([]));
}

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsCache.reset();
  });
  tearDown(() => debugEventsDiscoveryOverride = null);

  apiTest('the segment is there with tickets.qr and Tickets is first', (
    tester,
    api,
  ) async {
    _seedOthers(api);
    api.on('GET /me/event-tickets', page([ticketRow()]));
    await _pump(tester, api);
    final seg = tester.widget<FFSegmented>(find.byKey(const Key('mine-tabs')));
    expect(seg.options.map((o) => o.$1), [
      'tickets',
      'registrations',
      'orders',
    ]);
    expect(seg.options.first.$2, 'Tickets');
    expect(seg.value, 'tickets');
    expect(api.only('GET', '/me/event-tickets').query, 'limit=20');
    expect(find.byKey(const Key('ticket-card-reg_1')), findsOneWidget);
  });

  apiTest('no active ticket: the Registrations tab stays the default', (
    tester,
    api,
  ) async {
    _seedOthers(api);
    api.on('GET /me/event-tickets', page([]));
    await _pump(tester, api);
    expect(
      tester.widget<FFSegmented>(find.byKey(const Key('mine-tabs'))).value,
      'registrations',
    );
  });

  apiTest('without tickets.qr there is no Tickets segment and no request', (
    tester,
    api,
  ) async {
    _seedOthers(api);
    await _pump(tester, api, qr: false);
    final seg = tester.widget<FFSegmented>(find.byKey(const Key('mine-tabs')));
    expect(seg.options.map((o) => o.$1), ['registrations', 'orders']);
    expect(api.sent('GET', '/me/event-tickets'), isFalse);
  });

  apiTest('the /tickets route opens on Tickets even when empty', (
    tester,
    api,
  ) async {
    _seedOthers(api);
    api.on('GET /me/event-tickets', page([]));
    await _pump(tester, api, tab: 'tickets');
    expect(
      tester.widget<FFSegmented>(find.byKey(const Key('mine-tabs'))).value,
      'tickets',
    );
    expect(find.byKey(const Key('tickets-empty')), findsOneWidget);
    expect(find.text('No tickets yet'), findsOneWidget);
    expect(
      find.text('Your tickets appear here once your payment is confirmed.'),
      findsOneWidget,
    );
    await tapVisible(tester, find.byKey(const Key('tickets-browse')));
    expect(find.text('ROUTE-EVENTS'), findsOneWidget);
  });

  apiTest('sections, states and what is on a card', (tester, api) async {
    _seedOthers(api);
    api.on(
      'GET /me/event-tickets',
      page([
        ticketRow(),
        ticketRow(
          registrationId: 'reg_2',
          relation: 'purchased',
          first: 'Juma',
          last: 'Kessy',
          displayCode: 'T-AAAA11',
        ),
        ticketRow(
          registrationId: 'reg_3',
          state: 'revoked',
          title: 'Arusha 10K',
          displayCode: 'T-BBBB22',
        ),
        ticketRow(
          registrationId: 'reg_4',
          state: 'revoked',
          availability: 'cancelled',
          title: 'Moshi Run',
          displayCode: 'T-CCCC33',
        ),
        ticketRow(
          registrationId: 'reg_5',
          title: 'Old Run',
          displayCode: 'T-DDDD44',
          startsAt: '2027-02-01T03:30:00Z',
        ),
      ]),
    );
    await _pump(tester, api);
    expect(find.text('Upcoming'), findsOneWidget);
    expect(find.text('Past and cancelled'), findsOneWidget);
    // Order on screen: upcoming first, then the rest.
    double y(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
    expect(y('ticket-card-reg_1') < y('ticket-card-reg_3'), isTrue);
    expect(y('ticket-card-reg_2') < y('ticket-card-reg_5'), isTrue);
    expect(find.text('Ticket ready'), findsNWidgets(3)); // reg_1, reg_2, reg_5
    expect(find.text('Ticket cancelled'), findsOneWidget);
    expect(find.text('Event cancelled'), findsOneWidget);
    expect(find.text('T-3F9A2B'), findsOneWidget);
    expect(find.text('You'), findsAtLeastNWidgets(1));
    expect(find.text('Registered by you'), findsOneWidget);
    expect(find.text('Asha Mollel'), findsAtLeastNWidgets(1));
    final sem = tester.getSemantics(find.byKey(const Key('ticket-card-reg_1')));
    expect(
      sem.label,
      'Dar Half Marathon, 21K Half Marathon, Asha Mollel, Ticket ready',
    );
    await tapVisible(tester, find.byKey(const Key('ticket-card-reg_1')));
    expect(find.text('ROUTE-TICKET-reg_1'), findsOneWidget);
  });

  apiTest('a cancelled ticket still opens (its page explains)', (
    tester,
    api,
  ) async {
    _seedOthers(api);
    api.on(
      'GET /me/event-tickets',
      page([ticketRow(registrationId: 'reg_3', state: 'revoked')]),
    );
    await _pump(tester, api, tab: 'tickets');
    await tapVisible(tester, find.byKey(const Key('ticket-card-reg_3')));
    expect(find.text('ROUTE-TICKET-reg_3'), findsOneWidget);
  });

  apiTest('the list never carries a token and is cached without one', (
    tester,
    api,
  ) async {
    _seedOthers(api);
    api.on('GET /me/event-tickets', page([ticketRow()]));
    await _pump(tester, api);
    final cached = await EventsCache.getMine('tickets');
    expect(cached, isNotNull);
    final text = jsonEncode(cached!.$2);
    expect(text.contains('token'), isFalse);
    expect(text.contains('qrPayload'), isFalse);
  });

  apiTest('an error with nothing cached is an error state with retry', (
    tester,
    api,
  ) async {
    _seedOthers(api);
    api.fail('GET /me/event-tickets', 500);
    await _pump(tester, api, tab: 'tickets');
    expect(find.byKey(const Key('tickets-error')), findsOneWidget);
    api.heal('GET /me/event-tickets');
    api.on('GET /me/event-tickets', page([ticketRow()]));
    await tapVisible(tester, find.text('Try again').first);
    expect(find.byKey(const Key('ticket-card-reg_1')), findsOneWidget);
  });

  apiTest('Swahili: segment, sections and empty state', (tester, api) async {
    _seedOthers(api);
    api.on('GET /me/event-tickets', page([ticketRow()]));
    await _pump(tester, api, lang: 'sw');
    expect(find.text('Tiketi'), findsOneWidget);
    expect(find.text('Zijazo'), findsOneWidget);
    expect(find.text('Tiketi iko tayari'), findsOneWidget);
  });
}
