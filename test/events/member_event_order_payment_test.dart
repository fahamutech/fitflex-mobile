// Events S4 (spec §5.1, §5.14 member_event_order_page_test, extended): the
// order page's payment slot by state. The placeholder only while the server
// takes no payment; a status card from `payment.state` otherwise; the sticky
// Pay bar; polling at 30 s while a payment is live; confirmed with tickets,
// invitation chips and refunds; no green before the server says confirmed.
import 'package:fitflexmobile/screens/member/events/member_event_order_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

final _now = DateTime.utc(2027, 3, 10, 12, 10);

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  EventsOptions? options,
}) => pumpPage(
  tester,
  api,
  MemberEventOrderPage(
    orderId: 'ord_1',
    options: options ?? optsS3(payment: 'manual', ticketsQr: true),
    now: _now,
  ),
  user: member,
  lang: lang,
  size: const Size(375, 2400),
  extraRoutes: s3Routes,
  keepRequests: true,
);

Map<String, dynamic> _confirmedReg({
  String id = 'reg_1',
  String claimState = 'self',
  String relation = 'self',
  bool isSelf = true,
  String? invitedAt,
  Map<String, dynamic>? ticket = const {
    'state': 'active',
    'displayCode': 'T-3F9A2B',
  },
  List<String> actions = const [],
}) => registrationJson(
  id: id,
  status: 'confirmed',
  orderStatus: 'confirmed',
  claimState: claimState,
  relation: relation,
  isSelf: isSelf,
  claimInvitedAt: invitedAt,
  ticket: ticket,
  allowedActions: actions,
  firstName: isSelf ? 'Asha' : 'Juma',
);

Set<FFBadgeTone> _tones(WidgetTester tester) => {
  for (final b in tester.widgetList<FFBadge>(find.byType(FFBadge))) b.tone,
};

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsAnalytics.debugSink = [];
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    EventsAnalytics.debugSink = null;
  });

  group('payment not open (mode none)', () {
    apiTest('the placeholder with corrected wording, and no Pay bar', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', orderJson());
      final host = await _pump(tester, api, options: optsS3());
      expect(
        find.byKey(const Key('order-payment-placeholder')),
        findsOneWidget,
      );
      expect(find.text("Payment isn't available yet"), findsOneWidget);
      expect(find.textContaining('next update'), findsNothing);
      expect(find.textContaining('next app update'), findsNothing);
      expect(find.byKey(const Key('order-pay')), findsNothing);
      expect(find.byKey(const Key('order-payment-card')), findsNothing);
      expect(
        find.text(host.tr('events.order.payment.soon.body')),
        findsOneWidget,
      );
    });

    apiTest('with manual on, the placeholder never shows', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', manualOrderJson());
      await _pump(tester, api);
      expect(find.byKey(const Key('order-payment-placeholder')), findsNothing);
      expect(find.byKey(const Key('order-payment-card')), findsOneWidget);
    });
  });

  group('awaiting payment', () {
    apiTest('nothing sent: exact amount, manual badge, Pay bar opens pay', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', manualOrderJson());
      await _pump(tester, api);
      expect(find.text('Pay exactly TSh 25,000'), findsOneWidget);
      expect(find.text('Manual confirmation'), findsOneWidget);
      expect(find.byKey(const Key('order-pay')), findsOneWidget);
      expect(buttonLabelled('Pay · TSh 25,000'), findsOneWidget);
      // Labelled button for assistive tech.
      expect(
        find.bySemanticsLabel('Pay TSh 25,000 for order EV-3F9A2B7C1D'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('order-cancel')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('order-pay')));
      expect(find.text('ROUTE-PAY-ord_1'), findsOneWidget);
    });

    apiTest('submitted: under review, ID, target hours, extended hold, no '
        'cancel, no green', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        manualOrderJson(
          paymentView: paymentView(),
          holdExpiresAt: '2027-03-11T12:00:00Z',
          allowedActions: ['cancel'],
        ),
      );
      await _pump(tester, api);
      expect(find.text('Payment sent for checking'), findsOneWidget);
      expect(find.text('Under review'), findsOneWidget);
      expect(
        find.textContaining('We have your transaction ID QGH7XK2L9P'),
        findsOneWidget,
      );
      expect(find.textContaining('within 24 hours'), findsOneWidget);
      // Held until the extended time: 11 Mar 15:00 EAT.
      expect(find.textContaining('held until 15:00 EAT'), findsOneWidget);
      expect(find.textContaining('+255 7•• ••• 678'), findsOneWidget);
      expect(
        find.text("You can't cancel while we check your payment."),
        findsOneWidget,
      );
      expect(find.byKey(const Key('order-cancel')), findsNothing);
      expect(find.byKey(const Key('order-pay')), findsNothing);
      expect(find.byKey(const Key('pay-open-tickets')), findsNothing);
      expect(_tones(tester), isNot(contains(FFBadgeTone.success)));
      // The card title is a polite live region.
      expect(
        tester
            .getSemantics(find.byKey(const Key('pay-card-title')))
            .flagsCollection
            .isLiveRegion,
        isTrue,
      );
    });

    apiTest('submitted: polls payment-status every 30 s, not the order', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        manualOrderJson(paymentView: paymentView()),
      );
      api.on('GET /me/event-orders/ord_1/payment-status', {
        'order': {
          'id': 'ord_1',
          'status': 'awaiting_payment',
          'holdExpiresAt': '2027-03-10T12:27:00Z',
          'totalTzs': 25000,
          'currency': 'TZS',
        },
        'payment': paymentView(),
        'refund': null,
      });
      await _pump(tester, api);
      api.clear();
      await tester.pump(const Duration(seconds: 31));
      expect(
        api.where('GET', '/me/event-orders/ord_1/payment-status'),
        hasLength(1),
      );
      expect(api.where('GET', '/me/event-orders/ord_1'), isEmpty);
      // Nothing changed: it schedules the next look.
      await tester.pump(const Duration(seconds: 31));
      expect(
        api.where('GET', '/me/event-orders/ord_1/payment-status'),
        hasLength(2),
      );
    });

    apiTest('a change in status reads the order again and turns confirmed', (
      tester,
      api,
    ) async {
      var reads = 0;
      api.onCall('GET /me/event-orders/ord_1', (_) {
        reads++;
        return reads == 1
            ? manualOrderJson(paymentView: paymentView())
            : orderJson(
                status: 'confirmed',
                payment: 'manual',
                paymentView: paymentView(state: 'confirmed'),
                registrations: [_confirmedReg()],
                allowedActions: [],
              );
      });
      api.on('GET /me/event-orders/ord_1/payment-status', {
        'order': {
          'id': 'ord_1',
          'status': 'confirmed',
          'totalTzs': 25000,
          'currency': 'TZS',
        },
        'payment': paymentView(state: 'confirmed'),
      });
      await _pump(tester, api);
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(find.text('Payment confirmed'), findsOneWidget);
      expect(
        find.text('1 ticket for Dar Half Marathon is ready.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pay-open-tickets')), findsOneWidget);
      expect(
        EventsAnalytics.debugSink!
            .where((e) => e.name == 'payment_state_seen')
            .map((e) => e.props['state']),
        ['submitted', 'confirmed'],
      );
    });

    apiTest('no payment: the order is re-read at 60 s as in S3', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', manualOrderJson());
      await _pump(tester, api);
      api.clear();
      await tester.pump(const Duration(seconds: 61));
      expect(api.where('GET', '/me/event-orders/ord_1'), hasLength(1));
      expect(api.sent('GET', '/me/event-orders/ord_1/payment-status'), isFalse);
    });

    apiTest('processing (provider): waiting for the phone, Check status', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          payment: 'provider',
          paymentView: paymentView(
            state: 'processing',
            method: 'provider',
            reference: null,
          ),
        ),
      );
      await _pump(
        tester,
        api,
        options: optsS3(payment: 'provider', ticketsQr: true),
      );
      expect(find.text('Approve the payment on your phone'), findsOneWidget);
      expect(find.text('Waiting for your phone'), findsOneWidget);
      expect(find.byKey(const Key('pay-check-status')), findsOneWidget);
      expect(find.textContaining('+255 7•• ••• 678'), findsOneWidget);
      expect(find.textContaining('Resend'), findsNothing);
      api.clear();
      await tapVisible(tester, find.byKey(const Key('pay-check-status')));
      expect(api.where('GET', '/me/event-orders/ord_1'), hasLength(1));
    });

    apiTest('rejected: reason, the admin note verbatim, Try again to pay', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        manualOrderJson(
          paymentView: paymentView(
            state: 'rejected',
            rejectCode: 'reference_not_found',
            memberNote: 'Check the last digit.',
            canRetry: true,
          ),
        ),
      );
      await _pump(tester, api);
      expect(find.text("We couldn't confirm your payment"), findsOneWidget);
      expect(
        find.textContaining("couldn't find that transaction ID"),
        findsOneWidget,
      );
      expect(
        find.text('Note from FitFlex: Check the last digit.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Try again · held until 15:27 EAT'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('order-pay')), findsNothing);
      await tapVisible(tester, find.byKey(const Key('pay-try-again')));
      expect(find.text('ROUTE-PAY-ord_1'), findsOneWidget);
    });

    apiTest('rejected for amount shows the amount; no retry once the hold '
        'has ended', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        manualOrderJson(
          paymentView: paymentView(
            state: 'rejected',
            rejectCode: 'amount_mismatch',
            canRetry: false,
          ),
        ),
      );
      await _pump(tester, api);
      expect(
        find.text('The amount we received was different from TSh 25,000.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pay-try-again')), findsNothing);
      expect(
        find.text('Your hold has ended, so these places were released.'),
        findsOneWidget,
      );
    });

    apiTest('provider failed: the support line with the reference, retry', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          payment: 'provider',
          paymentView: paymentView(
            state: 'failed',
            method: 'provider',
            canRetry: true,
          ),
        ),
      );
      await _pump(
        tester,
        api,
        options: optsS3(payment: 'provider', ticketsQr: true),
      );
      expect(find.text("The payment didn't go through"), findsOneWidget);
      expect(
        find.text(
          'If money left your phone, contact support with EV-3F9A2B7C1D.',
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pay-try-again')), findsOneWidget);
    });
  });

  group('expired', () {
    apiTest('inside the grace window: "I already paid" opens the pay page', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        manualOrderJson(
          status: 'expired',
          closeReason: 'expired',
          closedAt: '2027-03-10T11:50:00Z',
          holdExpiresAt: null,
          allowedActions: [],
        ),
      );
      await _pump(tester, api);
      expect(find.byKey(const Key('order-expired')), findsOneWidget);
      expect(find.byKey(const Key('order-already-paid')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('order-already-paid')));
      expect(find.text('ROUTE-PAY-ord_1'), findsOneWidget);
    });

    apiTest('beyond the window there is no such link', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        manualOrderJson(
          status: 'expired',
          closeReason: 'expired',
          closedAt: '2027-03-08T11:50:00Z',
          holdExpiresAt: null,
          allowedActions: [],
        ),
      );
      await _pump(tester, api);
      expect(find.byKey(const Key('order-already-paid')), findsNothing);
    });

    apiTest('hold ended while we were checking: the refund-in-full promise', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        manualOrderJson(
          status: 'expired',
          closeReason: 'expired',
          closedAt: '2027-03-10T11:50:00Z',
          holdExpiresAt: null,
          paymentView: paymentView(),
          allowedActions: [],
        ),
      );
      await _pump(tester, api);
      expect(
        find.text('Your hold ended while we were checking'),
        findsOneWidget,
      );
      expect(find.textContaining('refund you in full'), findsOneWidget);
      expect(find.textContaining("Don't pay again"), findsOneWidget);
      expect(find.byKey(const Key('order-already-paid')), findsNothing);
      expect(_tones(tester), isNot(contains(FFBadgeTone.success)));
    });
  });

  apiTest('needs attention with a refund: places gone, refund card, no green', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-orders/ord_1',
      manualOrderJson(
        status: 'expired',
        closeReason: 'expired',
        closedAt: '2027-03-10T11:50:00Z',
        holdExpiresAt: null,
        paymentView: paymentView(state: 'needs_attention', refundId: 'rf_1'),
        refunds: [refundView(scope: 'unfulfilled_payment', status: 'approved')],
        allowedActions: [],
      ),
    );
    await _pump(tester, api);
    expect(find.text("Your places weren't available"), findsOneWidget);
    expect(
      find.text(
        "We received your payment but couldn't keep your places. "
        'A full refund of TSh 25,000 is being prepared.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('refund-card-rf_1')), findsOneWidget);
    expect(find.text('Payment returned'), findsOneWidget);
    expect(_tones(tester), isNot(contains(FFBadgeTone.success)));
  });

  group('confirmed', () {
    apiTest('success card, ticket buttons, wallet link', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'confirmed',
          payment: 'manual',
          paymentView: paymentView(state: 'confirmed'),
          registrations: [_confirmedReg()],
          allowedActions: ['cancel_refund'],
        ),
      );
      await _pump(tester, api);
      expect(find.text('Payment confirmed'), findsOneWidget);
      expect(find.text('Paid'), findsAtLeastNWidgets(1));
      expect(_tones(tester), contains(FFBadgeTone.success));
      await tapVisible(tester, find.byKey(const Key('pay-open-tickets')));
      expect(find.text('ROUTE-TICKETS'), findsOneWidget);
    });

    apiTest('Show ticket opens that place\'s ticket', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'confirmed',
          payment: 'manual',
          paymentView: paymentView(state: 'confirmed'),
          registrations: [_confirmedReg()],
          allowedActions: [],
        ),
      );
      await _pump(tester, api);
      await tapVisible(tester, find.byKey(const Key('order-ticket-reg_1')));
      expect(find.text('ROUTE-TICKET-reg_1'), findsOneWidget);
    });

    apiTest('a place claimed by someone else shows no ticket button', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'confirmed',
          payment: 'manual',
          paymentView: paymentView(state: 'confirmed'),
          registrations: [
            _confirmedReg(),
            _confirmedReg(
              id: 'reg_2',
              claimState: 'claimed',
              relation: 'purchased',
              isSelf: false,
            ),
          ],
          allowedActions: [],
        ),
      );
      await _pump(tester, api);
      expect(find.byKey(const Key('order-ticket-reg_1')), findsOneWidget);
      expect(find.byKey(const Key('order-ticket-reg_2')), findsNothing);
      expect(find.byKey(const Key('order-invite-reg_2')), findsNothing);
    });

    apiTest('unclaimed place: invitation status and "send again" warns the '
        'old link stops', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'confirmed',
          payment: 'manual',
          paymentView: paymentView(state: 'confirmed'),
          registrations: [
            _confirmedReg(
              id: 'reg_2',
              claimState: 'unclaimed',
              relation: 'purchased',
              isSelf: false,
              invitedAt: '2027-03-10T12:31:00Z',
            ),
            _confirmedReg(
              id: 'reg_3',
              claimState: 'unclaimed',
              relation: 'purchased',
              isSelf: false,
            ),
          ],
          allowedActions: [],
        ),
      );
      api.on('POST /me/event-orders/ord_1/claim-invitations', {
        'sent': true,
        'channel': 'sms',
      });
      final host = await _pump(tester, api);
      expect(find.text('Invitation sent 10 Mar 2027'), findsOneWidget);
      expect(find.text('No invitation sent yet'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('order-invite-reg_2')));
      expect(
        find.text('This creates a new link. The old link stops working.'),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(const Key('invite-confirm')));
      expect(
        api.only('POST', '/me/event-orders/ord_1/claim-invitations').body,
        {'registrationId': 'reg_2'},
      );
      expect(host.snack('Invitation sent'), findsOneWidget);
      expect(
        EventsAnalytics.debugSink!.map((e) => e.name),
        contains('invitation_resent'),
      );
    });

    apiTest('a resend over the limit shows the reason', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'confirmed',
          payment: 'manual',
          paymentView: paymentView(state: 'confirmed'),
          registrations: [
            _confirmedReg(
              id: 'reg_2',
              claimState: 'unclaimed',
              relation: 'purchased',
              isSelf: false,
            ),
          ],
          allowedActions: [],
        ),
      );
      api.fail('POST /me/event-orders/ord_1/claim-invitations', 409, {
        'error': 'resend_limit_reached',
      });
      final host = await _pump(tester, api);
      await tapVisible(tester, find.byKey(const Key('order-invite-reg_2')));
      await tapVisible(tester, find.byKey(const Key('invite-confirm')));
      expect(
        host.snack(
          'Request declined: You\'ve reached the limit for this invitation.',
        ),
        findsOneWidget,
        reason: 'the snack names the reason, not a humanised code',
      );
    });

    apiTest('Cancel and refund opens the cancel page', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'confirmed',
          payment: 'manual',
          paymentView: paymentView(state: 'confirmed'),
          registrations: [_confirmedReg()],
          allowedActions: ['cancel_refund'],
        ),
      );
      await _pump(tester, api);
      await tapVisible(tester, find.byKey(const Key('order-cancel-refund')));
      expect(find.text('ROUTE-ORDER-CANCEL-ord_1'), findsOneWidget);
    });

    apiTest('payment switched off later: tickets and cancel stay reachable', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'confirmed',
          payment: 'none',
          paymentView: paymentView(state: 'confirmed'),
          registrations: [_confirmedReg()],
          allowedActions: ['cancel_refund'],
        ),
      );
      await _pump(tester, api, options: optsS3(ticketsQr: true));
      expect(find.byKey(const Key('pay-open-tickets')), findsOneWidget);
      expect(find.byKey(const Key('order-ticket-reg_1')), findsOneWidget);
      expect(find.byKey(const Key('order-cancel-refund')), findsOneWidget);
      expect(find.byKey(const Key('order-payment-placeholder')), findsNothing);
    });
  });

  group('after a cancel', () {
    apiTest('partly cancelled with a requested refund', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'partially_cancelled',
          payment: 'manual',
          paymentView: paymentView(state: 'confirmed'),
          registrations: [_confirmedReg()],
          allowedActions: [],
          refunds: [refundView()],
        ),
      );
      await _pump(tester, api);
      expect(find.byKey(const Key('order-status')), findsOneWidget);
      expect(
        tester.widget<FFBadge>(find.byKey(const Key('order-status'))).label,
        'Partly cancelled',
      );
      expect(find.text('Requested'), findsOneWidget);
      expect(
        find.text(
          'FitFlex sends refunds by hand, usually within 5 working days.',
        ),
        findsOneWidget,
      );
      expect(find.text('One ticket'), findsOneWidget);
    });

    apiTest('refund sent: green, the payout reference and where to', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'refunded',
          payment: 'manual',
          paymentView: paymentView(state: 'confirmed'),
          registrations: [
            registrationJson(status: 'cancelled', orderStatus: 'refunded'),
          ],
          allowedActions: [],
          refunds: [
            refundView(
              status: 'paid',
              scope: 'order',
              paidTo: '+255 7•• ••• 678',
              paymentReference: 'MPX123',
            ),
          ],
        ),
      );
      await _pump(tester, api);
      expect(
        tester.widget<FFBadge>(find.byKey(const Key('order-status'))).label,
        'Refunded',
      );
      expect(
        tester
            .widget<FFBadge>(find.byKey(const Key('refund-status-rf_1')))
            .tone,
        FFBadgeTone.success,
      );
      expect(
        find.text('Sent to +255 7•• ••• 678 · reference MPX123'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('refund-eta')), findsNothing);
    });

    apiTest('refund not approved: the note and where to go', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'cancelled',
          payment: 'manual',
          paymentView: paymentView(state: 'confirmed'),
          registrations: [
            registrationJson(status: 'cancelled', orderStatus: 'cancelled'),
          ],
          allowedActions: [],
          refunds: [
            refundView(
              status: 'rejected',
              rejectionNote: 'Outside the window.',
            ),
          ],
        ),
      );
      await _pump(tester, api);
      expect(find.text('Not approved'), findsOneWidget);
      expect(find.text('Outside the window.'), findsOneWidget);
      expect(
        find.text('Contact support if you think this is wrong.'),
        findsOneWidget,
      );
    });
  });

  group('free order', () {
    apiTest('one tap confirms; "registered" shows only once the server says', (
      tester,
      api,
    ) async {
      var reads = 0;
      api.onCall('GET /me/event-orders/ord_1', (_) {
        reads++;
        return reads == 1
            ? orderJson(payment: 'manual', total: 0, instructions: null)
            : orderJson(
                status: 'confirmed',
                payment: 'none',
                total: 0,
                paymentView: paymentView(
                  state: 'confirmed',
                  method: 'free',
                  amountTzs: 0,
                  reference: null,
                ),
                registrations: [_confirmedReg()],
                allowedActions: [],
              );
      });
      api.on('POST /me/event-orders/ord_1/payment', {
        'payment': paymentView(state: 'confirmed', method: 'free'),
        'next': {'payment': 'none'},
      });
      final host = await _pump(tester, api);
      expect(buttonLabelled('Confirm free registration'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('order-pay')));
      final req = api.only('POST', '/me/event-orders/ord_1/payment');
      expect(req.body, <String, dynamic>{});
      expect(req.headers['idempotency-key'], startsWith('chk_'));
      expect(find.text('Payment confirmed'), findsOneWidget);
      expect(host.snack(host.tr('events.pay.free.done')), findsOneWidget);
    });
  });

  apiTest('Swahili: order pills and the submitted card', (tester, api) async {
    api.on(
      'GET /me/event-orders/ord_1',
      manualOrderJson(paymentView: paymentView()),
    );
    await _pump(tester, api, lang: 'sw');
    expect(find.text('Malipo yametumwa kukaguliwa'), findsOneWidget);
    expect(find.text('Inakaguliwa'), findsOneWidget);
    expect(
      find.textContaining('FitFlex huthibitisha malipo ndani ya saa 24'),
      findsOneWidget,
    );
  });
}
