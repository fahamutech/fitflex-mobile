// Events S3 (spec §5.14 member_event_registration_page_test): sections by
// relation (purchaser vs claimed participant), the QR placeholder, the
// remove flow incl. remove_whole_line, 404.
import 'package:fitflexmobile/screens/member/events/member_event_order_page.dart';
import 'package:fitflexmobile/screens/member/events/member_event_registration_page.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

Future<PageHost> _pump(WidgetTester tester, RecordingApi api) => pumpPage(
  tester,
  api,
  MemberEventRegistrationPage(registrationId: 'reg_1', options: optsS3()),
  user: member,
  size: const Size(375, 1600),
  extraRoutes: s3Routes,
  keepRequests: true,
);

void main() {
  setUp(() => debugEventsDiscoveryOverride = true);
  tearDown(() => debugEventsDiscoveryOverride = null);

  apiTest('purchaser view: status, QR placeholder, details, remove action', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-registrations/reg_1',
      registrationJson(
        emergencyContact: {'name': 'Mama', 'phone': '0712000000'},
        team: {'id': 'team_1', 'name': 'Coco Runners'},
      ),
    );
    await _pump(tester, api);
    expect(api.only('GET', '/me/event-registrations/reg_1'), isNotNull);
    expect(find.text('Asha Mollel'), findsOneWidget);
    expect(find.byKey(const Key('reg-awaiting')), findsOneWidget);
    expect(
      find.text('Awaiting payment · held until 15:27 EAT'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('reg-ticket-placeholder')), findsOneWidget);
    expect(
      find.text('Your entry QR appears here once payment is confirmed'),
      findsOneWidget,
    );
    expect(find.text('+255712345678'), findsOneWidget);
    expect(find.text('9 May 1990'), findsOneWidget);
    expect(find.text('M'), findsOneWidget);
    expect(find.byKey(const Key('reg-emergency')), findsOneWidget);
    expect(find.text('Mama · 0712000000'), findsOneWidget);
    expect(find.text('Registered by you on 10 Mar 2027'), findsOneWidget);
    expect(find.byKey(const Key('reg-remove')), findsOneWidget);
    expect(find.byKey(const Key('reg-ask-purchaser')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('reg-team')));
    expect(find.text('ROUTE-TEAM-team_1'), findsOneWidget);
  });

  apiTest('claimed participant: own details, no remove, "Ask {name}"', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-registrations/reg_1',
      registrationJson(
        relation: 'claimed',
        isSelf: false,
        claimState: 'claimed',
        consentBasis: 'purchaser_authorised',
        allowedActions: [],
        purchaser: {'nameMasked': 'Neema A*******'},
        emergencyContact: {'name': 'Mama', 'phone': '0712000000'},
      ),
    );
    await _pump(tester, api);
    expect(find.byKey(const Key('reg-emergency')), findsOneWidget);
    expect(find.byKey(const Key('reg-remove')), findsNothing);
    expect(
      find.text('Ask Neema to change or cancel this registration'),
      findsOneWidget,
    );
    expect(
      find.text('Registered by Neema A******* on 10 Mar 2027'),
      findsOneWidget,
    );
  });

  apiTest('remove posts the reason and reloads', (tester, api) async {
    api.on('GET /me/event-registrations/reg_1', registrationJson());
    await _pump(tester, api);
    await tapVisible(tester, find.byKey(const Key('reg-remove')));
    expect(find.text('Remove Asha Mollel?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-reason-duplicate')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('event-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(api.only('POST', '/me/event-registrations/reg_1/cancel').body, {
      'reason': 'duplicate',
    });
    expect(api.where('GET', '/me/event-registrations/reg_1'), hasLength(2));
  });

  apiTest('remove_whole_line explains and offers the order', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-registrations/reg_1', registrationJson());
    api.fail('POST /me/event-registrations/reg_1/cancel', 409, {
      'error': 'remove_whole_line',
    });
    await _pump(tester, api);
    await tapVisible(tester, find.byKey(const Key('reg-remove')));
    await tester.tap(find.byKey(const Key('event-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This is the last Standard place in the order. Cancel the whole order and register again.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('remove-whole-line-open')));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
  });

  apiTest('cancelled rows show the pill and no actions', (tester, api) async {
    api.on(
      'GET /me/event-registrations/reg_1',
      registrationJson(
        status: 'cancelled',
        orderStatus: 'cancelled',
        allowedActions: [],
      ),
    );
    await _pump(tester, api);
    expect(find.byKey(const Key('reg-status')), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.byKey(const Key('reg-remove')), findsNothing);
  });

  maskedTests();

  apiTest('404 shows the gone state', (tester, api) async {
    api.fail('GET /me/event-registrations/reg_1', 404, {
      'error': 'registration_not_found',
    });
    await _pump(tester, api);
    expect(find.byKey(const Key('reg-gone')), findsOneWidget);
  });
}

void maskedTests() {
  apiTest('masked purchaser view (claimed place): no blank rows, no crash', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-registrations/reg_1',
      registrationJson(
        isSelf: false,
        claimState: 'claimed',
        consentBasis: 'purchaser_authorised',
        phone: null,
        email: null,
        dateOfBirth: null,
        gender: null,
        kitSize: null,
        emergencyContact: null,
      ),
    );
    await _pump(tester, api);
    expect(tester.takeException(), isNull);
    expect(find.text('Asha Mollel'), findsOneWidget);
    expect(find.byKey(const Key('reg-participant')), findsNothing);
    expect(find.text('Participant'), findsNothing);
    expect(find.byKey(const Key('reg-emergency')), findsNothing);
    expect(find.text('Mobile number'), findsNothing);
    expect(find.text('Date of birth'), findsNothing);
    // The rest of the page still renders, and the purchaser can still act.
    expect(find.byKey(const Key('reg-ticket-placeholder')), findsOneWidget);
    expect(find.byKey(const Key('reg-event')), findsOneWidget);
    expect(find.byKey(const Key('reg-remove')), findsOneWidget);
  });

  apiTest('partly masked: only the rows that came back show', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-registrations/reg_1',
      registrationJson(
        email: null,
        dateOfBirth: null,
        gender: null,
        kitSize: 'l',
        emergencyContact: null,
      ),
    );
    await _pump(tester, api);
    expect(find.byKey(const Key('reg-participant')), findsOneWidget);
    expect(find.text('+255712345678'), findsOneWidget);
    expect(find.text('L'), findsOneWidget);
    expect(find.text('Email'), findsNothing);
    expect(find.text('Date of birth'), findsNothing);
  });

  apiTest('the order page copes with a masked participant row', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-orders/ord_1',
      orderJson(
        registrations: [
          registrationJson(
            isSelf: false,
            claimState: 'claimed',
            phone: null,
            email: null,
            dateOfBirth: null,
            gender: null,
            kitSize: null,
            emergencyContact: null,
          ),
        ],
      ),
    );
    await pumpPage(
      tester,
      api,
      MemberEventOrderPage(
        orderId: 'ord_1',
        options: optsS3(),
        now: DateTime.utc(2027, 3, 10, 12),
      ),
      user: member,
      size: const Size(375, 1800),
      extraRoutes: s3Routes,
      keepRequests: true,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('order-participant-reg_1')), findsOneWidget);
    expect(find.text('Asha Mollel'), findsOneWidget);
    expect(find.text('Claimed'), findsOneWidget);
  });
}
