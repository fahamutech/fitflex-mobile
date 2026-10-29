// Events S4 (spec §5.6): the registration page's ticket card (state, number,
// "Show ticket"; never a QR thumbnail), Cancel and refund for the purchaser
// of a paid place, the refund card, and the claim invitation.
import 'package:fitflexmobile/screens/member/events/member_event_registration_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

Future<PageHost> _pump(WidgetTester tester, RecordingApi api) => pumpPage(
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

Map<String, dynamic> _paid({
  Map<String, dynamic>? ticket = const {
    'state': 'active',
    'displayCode': 'T-3F9A2B',
  },
  List<String> actions = const ['cancel_refund'],
  String relation = 'self',
  String claimState = 'self',
  bool isSelf = true,
  List<Map<String, dynamic>>? refunds,
  String? invitedAt,
  String status = 'confirmed',
}) => registrationJson(
  status: status,
  orderStatus: 'confirmed',
  relation: relation,
  claimState: claimState,
  isSelf: isSelf,
  allowedActions: actions,
  ticket: ticket,
  refunds: refunds,
  claimInvitedAt: invitedAt,
  purchaser: relation == 'claimed' ? {'nameMasked': 'N**** A*******'} : null,
);

void main() {
  setUp(() => debugEventsDiscoveryOverride = true);
  tearDown(() => debugEventsDiscoveryOverride = null);

  apiTest('an active ticket: state, number and Show ticket, no QR picture', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-registrations/reg_1', _paid());
    await _pump(tester, api);
    expect(find.byKey(const Key('reg-ticket')), findsOneWidget);
    expect(find.text('Ticket ready'), findsOneWidget);
    expect(find.text('Ticket number T-3F9A2B'), findsOneWidget);
    expect(find.byType(FFQrCode), findsNothing);
    expect(find.byKey(const Key('reg-ticket-placeholder')), findsNothing);
    expect(
      tester.widget<FFBadge>(find.byKey(const Key('reg-status'))).tone,
      FFBadgeTone.success,
    );
    await tapVisible(tester, find.byKey(const Key('reg-show-ticket')));
    expect(find.text('ROUTE-TICKET-reg_1'), findsOneWidget);
  });

  apiTest('a revoked ticket says so and offers nothing to show', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-registrations/reg_1',
      _paid(ticket: {'state': 'revoked'}, actions: [], status: 'cancelled'),
    );
    await _pump(tester, api);
    expect(find.byKey(const Key('reg-ticket-revoked')), findsOneWidget);
    expect(find.text('Ticket cancelled'), findsOneWidget);
    expect(find.text('This code no longer works.'), findsOneWidget);
    expect(find.byKey(const Key('reg-show-ticket')), findsNothing);
  });

  apiTest('paid but no ticket row yet: being prepared, with a refresh', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-registrations/reg_1', _paid(ticket: null));
    await _pump(tester, api);
    expect(find.text('Your ticket is being prepared'), findsOneWidget);
    api.clear();
    await tapVisible(tester, find.byKey(const Key('reg-ticket-refresh')));
    expect(api.only('GET', '/me/event-registrations/reg_1'), isNotNull);
  });

  apiTest('reserved keeps the S3 sentence', (tester, api) async {
    api.on('GET /me/event-registrations/reg_1', registrationJson());
    await _pump(tester, api);
    expect(find.byKey(const Key('reg-ticket-placeholder')), findsOneWidget);
    expect(
      find.text('Your ticket appears here once your payment is confirmed'),
      findsOneWidget,
    );
  });

  apiTest('the purchaser can cancel and refund a paid place', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-registrations/reg_1', _paid());
    await _pump(tester, api);
    expect(find.byKey(const Key('reg-remove')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('reg-cancel-refund')));
    expect(find.text('ROUTE-REG-CANCEL-reg_1-ord_1'), findsOneWidget);
  });

  apiTest('a place with a refund shows its refund card', (tester, api) async {
    api.on(
      'GET /me/event-registrations/reg_1',
      _paid(
        ticket: {'state': 'revoked'},
        actions: [],
        status: 'cancelled',
        refunds: [refundView(status: 'approved')],
      ),
    );
    await _pump(tester, api);
    expect(find.byKey(const Key('refund-card-rf_1')), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
    expect(find.byKey(const Key('reg-cancel-refund')), findsNothing);
  });

  apiTest('a claimed participant has the ticket, and no cancel', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-registrations/reg_1',
      _paid(
        relation: 'claimed',
        claimState: 'claimed',
        isSelf: false,
        actions: [],
      ),
    );
    await _pump(tester, api);
    expect(find.byKey(const Key('reg-show-ticket')), findsOneWidget);
    expect(find.byKey(const Key('reg-cancel-refund')), findsNothing);
    expect(find.byKey(const Key('reg-ask-purchaser')), findsOneWidget);
  });

  apiTest('unclaimed place: invitation status and send again', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-registrations/reg_1',
      _paid(
        relation: 'purchased',
        claimState: 'unclaimed',
        isSelf: false,
        invitedAt: '2027-03-10T12:31:00Z',
      ),
    );
    api.on('POST /me/event-orders/ord_1/claim-invitations', {'sent': true});
    final host = await _pump(tester, api);
    expect(find.text('Invitation sent 10 Mar 2027'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('reg-invite-resend')));
    expect(
      find.text('This creates a new link. The old link stops working.'),
      findsOneWidget,
    );
    await tapVisible(tester, find.byKey(const Key('invite-confirm')));
    expect(api.only('POST', '/me/event-orders/ord_1/claim-invitations').body, {
      'registrationId': 'reg_1',
    });
    expect(host.snack('Invitation sent'), findsOneWidget);
  });

  apiTest('after a claim the purchaser has no ticket card at all', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-registrations/reg_1',
      _paid(
        ticket: null,
        relation: 'purchased',
        claimState: 'claimed',
        isSelf: false,
        actions: [],
      ),
    );
    await _pump(tester, api);
    expect(find.byKey(const Key('reg-ticket')), findsNothing);
    expect(find.byKey(const Key('reg-ticket-preparing')), findsNothing);
    expect(find.byKey(const Key('reg-show-ticket')), findsNothing);
  });
}
