// Events S4 (spec §5.13): the long Swahili labels fit the bar at 375 px and
// 1.3x text, and the pages do not overflow at that size.
import 'package:fitflexmobile/screens/member/events/cancel/member_event_cancel_page.dart';
import 'package:fitflexmobile/screens/member/events/member_event_order_page.dart';
import 'package:fitflexmobile/screens/member/events/pay/member_event_payment_page.dart';
import 'package:fitflexmobile/screens/member/events/tickets/member_event_ticket_page.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

Future<void> _pump(
  WidgetTester tester,
  RecordingApi api,
  Widget page, {
  String lang = 'sw',
}) => pumpPage(
  tester,
  api,
  page,
  user: member,
  lang: lang,
  textScale: 1.3,
  size: const Size(375, 812),
  extraRoutes: s3Routes,
  keepRequests: true,
);

void main() {
  setUp(() => debugEventsDiscoveryOverride = true);
  tearDown(() => debugEventsDiscoveryOverride = null);

  final opts = optsS3(payment: 'manual', ticketsQr: true);

  for (final lang in ['sw', 'en']) {
    apiTest('pay page at 1.3x ($lang): no overflow, the bar holds both', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', manualOrderJson(total: 1250000));
      await _pump(
        tester,
        api,
        MemberEventPaymentPage(orderId: 'ord_1', options: opts),
        lang: lang,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('pay-submit')), findsOneWidget);
      expect(find.byKey(const Key('pay-back')), findsOneWidget);
      final bar = tester.getRect(find.byKey(const Key('pay-submit')));
      expect(bar.right, lessThanOrEqualTo(375));
    });

    apiTest('order page at 1.3x ($lang): Pay bar and submitted card fit', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', manualOrderJson(total: 1250000));
      await _pump(
        tester,
        api,
        MemberEventOrderPage(
          orderId: 'ord_1',
          options: opts,
          now: DateTime.utc(2027, 3, 10, 12, 10),
        ),
        lang: lang,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('order-pay')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('order-pay'))).right,
        lessThanOrEqualTo(375),
      );
    });

    apiTest('cancel bar at 1.3x ($lang): "cancel · refund TSh 1,250,000"', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-registrations/reg_1/cancel-preview',
        cancelPreview(paidTzs: 1250000),
      );
      await _pump(
        tester,
        api,
        MemberEventCancelPage.registration(
          registrationId: 'reg_1',
          options: opts,
        ),
        lang: lang,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text(
          lang == 'sw'
              ? 'Ghairi · rejesha TSh 1,250,000'
              : 'Cancel · refund TSh 1,250,000',
        ),
        findsOneWidget,
      );
      expect(
        tester.getRect(find.byKey(const Key('cancel-action'))).right,
        lessThanOrEqualTo(375),
      );
    });

    apiTest('ticket page at 1.3x ($lang): no overflow', (tester, api) async {
      api.on('GET /me/event-registrations/reg_1/ticket', ticketPayload());
      await _pump(
        tester,
        api,
        MemberEventTicketPage(registrationId: 'reg_1', options: opts),
        lang: lang,
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('ticket-qr')), findsOneWidget);
    });
  }

  // The state cards, in the longest language, at 1.3x.
  final states = <String, Map<String, dynamic>>{
    'submitted': manualOrderJson(paymentView: paymentView()),
    'rejected': manualOrderJson(
      paymentView: paymentView(
        state: 'rejected',
        rejectCode: 'wrong_account',
        memberNote: 'Tumia namba iliyoonyeshwa kwenye ukurasa wa malipo.',
        canRetry: true,
      ),
    ),
    'confirmed with invitation and refund': orderJson(
      status: 'partially_cancelled',
      payment: 'manual',
      paymentView: paymentView(state: 'confirmed'),
      registrations: [
        registrationJson(
          status: 'confirmed',
          orderStatus: 'partially_cancelled',
          ticket: {'state': 'active', 'displayCode': 'T-3F9A2B'},
          allowedActions: [],
        ),
        registrationJson(
          id: 'reg_2',
          status: 'confirmed',
          orderStatus: 'partially_cancelled',
          isSelf: false,
          relation: 'purchased',
          claimState: 'unclaimed',
          firstName: 'Juma',
          allowedActions: [],
        ),
      ],
      allowedActions: ['cancel_refund'],
      refunds: [
        refundView(
          status: 'paid',
          amountTzs: 1250000,
          paidTo: '+255 7•• ••• 678',
          paymentReference: 'MPX1234567890',
        ),
      ],
    ),
    'unfulfilled': manualOrderJson(
      status: 'expired',
      closeReason: 'expired',
      closedAt: '2027-03-10T11:50:00Z',
      holdExpiresAt: null,
      paymentView: paymentView(state: 'needs_attention', refundId: 'rf_1'),
      refunds: [refundView(scope: 'unfulfilled_payment', status: 'approved')],
      allowedActions: [],
    ),
  };
  for (final e in states.entries) {
    apiTest('order page at 1.3x (sw): ${e.key}', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', e.value);
      await _pump(
        tester,
        api,
        MemberEventOrderPage(
          orderId: 'ord_1',
          options: opts,
          now: DateTime.utc(2027, 3, 10, 12, 10),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
