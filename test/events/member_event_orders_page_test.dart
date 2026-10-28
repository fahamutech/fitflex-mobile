// Events S3 (spec §5.14 member_event_orders_page_test): both tabs, empty
// states, claimable cards with persisted "Not me", card semantics, error,
// offline cached copy, flag off.
import 'package:fitflexmobile/screens/member/events/member_event_orders_page.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  String tab = '',
  bool registration = true,
}) => pumpPage(
  tester,
  api,
  MemberEventOrdersPage(
    initialTab: tab,
    options: optsS3(registration: registration),
    now: DateTime.utc(2027, 3, 10, 12),
  ),
  user: member,
  size: const Size(375, 1400),
  extraRoutes: s3Routes,
  keepRequests: true,
);

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsCache.reset();
  });
  tearDown(() => debugEventsDiscoveryOverride = null);

  apiTest('registrations: self, purchased and claimed rows with chips', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-registrations',
      page([
        registrationJson(),
        registrationJson(
          id: 'reg_2',
          firstName: 'Juma',
          lastName: 'Kessy',
          isSelf: false,
          relation: 'purchased',
          claimState: 'unclaimed',
          team: {'name': 'Coco Runners'},
        ),
        registrationJson(
          id: 'reg_3',
          relation: 'claimed',
          isSelf: false,
          claimState: 'claimed',
          status: 'reserved',
          orderStatus: 'expired',
          purchaser: {'nameMasked': 'N**** A*******'},
        ),
      ]),
    );
    api.on('GET /me/event-registrations/claimable', {'items': []});
    await _pump(tester, api);
    expect(api.only('GET', '/me/event-registrations').query, 'limit=20');
    expect(find.byKey(const Key('reg-card-reg_1')), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Juma Kessy · Registered by you'), findsOneWidget);
    expect(find.textContaining('Registered by N**** A*******'), findsWidgets);
    expect(find.text('Awaiting payment'), findsNWidgets(2));
    expect(find.text('Expired'), findsOneWidget);
    expect(find.text('EV-3F9A2B7C1D · Coco Runners'), findsOneWidget);
    final sem = tester.getSemantics(find.byKey(const Key('reg-card-reg_1')));
    expect(sem.label, contains('Dar Half Marathon'));
    expect(sem.label, contains('Awaiting payment'));
    expect(sem.flagsCollection.isButton, isTrue);
    await tapVisible(tester, find.byKey(const Key('reg-card-reg_2')));
    expect(find.text('ROUTE-REG-reg_2'), findsOneWidget);
  });

  apiTest('"Is this you?" cards: That\'s me opens claim; Not me persists', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-registrations', page([]));
    api.on('GET /me/event-registrations/claimable', {
      'items': [claimableJson(), claimableJson(id: 'reg_10')],
    });
    await _pump(tester, api);
    expect(find.text('Is this you?'), findsOneWidget);
    expect(find.byKey(const Key('claim-card-reg_9')), findsOneWidget);
    expect(
      find.text(
        'N**** A******* registered A*** M. for Dar Half Marathon · 10K',
      ),
      findsNWidgets(2),
    );
    expect(find.text('Matches your number ending ••• 678'), findsNWidgets(2));
    await tapVisible(tester, find.byKey(const Key('claim-no-reg_9')));
    expect(find.byKey(const Key('claim-card-reg_9')), findsNothing);
    final p = await SharedPreferences.getInstance();
    expect(p.getStringList(kDismissedClaimsKey), ['reg_9']);
    await tapVisible(tester, find.byKey(const Key('claim-yes-reg_10')));
    expect(find.text('ROUTE-CLAIM-reg_10'), findsOneWidget);
  });

  apiTest('a dismissed card stays hidden on the next visit', (
    tester,
    api,
  ) async {
    SharedPreferences.setMockInitialValues({
      kDismissedClaimsKey: ['reg_9'],
    });
    api.on('GET /me/event-registrations', page([]));
    api.on('GET /me/event-registrations/claimable', {
      'items': [claimableJson()],
    });
    await _pump(tester, api);
    expect(find.byKey(const Key('claim-card-reg_9')), findsNothing);
    expect(find.byKey(const Key('mine-regs-empty')), findsOneWidget);
    expect(find.text('No registrations yet'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('mine-browse')));
    expect(find.text('ROUTE-EVENTS'), findsOneWidget);
  });

  apiTest('orders tab: cards with countdown, empty state', (tester, api) async {
    api.on('GET /me/event-registrations', page([]));
    api.on('GET /me/event-registrations/claimable', {'items': []});
    api.on(
      'GET /me/event-orders',
      page([
        orderRow(),
        orderRow(
          id: 'ord_2',
          reference: 'EV-2',
          status: 'cancelled',
          holdExpiresAt: null,
        ),
      ]),
    );
    await _pump(tester, api, tab: 'orders');
    expect(find.byKey(const Key('order-card-ord_1')), findsOneWidget);
    expect(find.text('1 places · TSh 25,000'), findsNWidgets(2));
    expect(find.text('27 min left'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('order-card-ord_1')));
    expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    api.on('GET /me/event-orders', page([]));
    await _pump(tester, api, tab: 'orders');
    expect(find.byKey(const Key('mine-orders-empty')), findsOneWidget);
    expect(find.text('No orders yet'), findsOneWidget);
  });

  apiTest('switching tabs; error state with retry', (tester, api) async {
    api.on('GET /me/event-registrations/claimable', {'items': []});
    api.fail('GET /me/event-registrations', 500);
    api.on('GET /me/event-orders', page([orderRow()]));
    await _pump(tester, api);
    expect(find.byKey(const Key('mine-regs-error')), findsOneWidget);
    api.heal('GET /me/event-registrations');
    api.on('GET /me/event-registrations', page([registrationJson()]));
    await tapVisible(tester, find.text('Try again'));
    expect(find.byKey(const Key('reg-card-reg_1')), findsOneWidget);
    await tapVisible(tester, find.text('Orders'));
    expect(find.byKey(const Key('order-card-ord_1')), findsOneWidget);
  });

  apiTest('offline: the last cached page with a notice', (tester, api) async {
    await EventsCache.putMine('registrations', page([registrationJson()]));
    api.onCall(
      'GET /me/event-registrations',
      (_) => throw StateError('SocketException: down'),
    );
    api.on('GET /me/event-registrations/claimable', {'items': []});
    await _pump(tester, api);
    expect(find.byKey(const Key('mine-offline')), findsOneWidget);
    expect(find.byKey(const Key('reg-card-reg_1')), findsOneWidget);
  });

  apiTest('registration:false redirects to Activity with the snack', (
    tester,
    api,
  ) async {
    final host = await _pump(tester, api, registration: false);
    expect(find.text('ROUTE-ACTIVITY'), findsOneWidget);
    expect(host.snack(host.tr('events.register.unavailable')), findsOneWidget);
    expect(api.requests, isEmpty);
  });
}
