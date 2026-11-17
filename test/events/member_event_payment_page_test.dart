// Events S4 (spec §5.2, §5.3, §5.14 member_event_payment_page_test), after
// AzamPay became the only payment method (fitflex-functions#360): the recap
// with the exact amount and one mobile-money button; the body is `{}` with
// an idempotency key (kept on a retry); no Lipa Namba, transaction ID or
// paying number is asked for or sent; an unknown outcome keeps the page;
// each server refusal in its place; an order whose hold ended is not paid.
import 'package:fitflexmobile/screens/member/events/pay/member_event_payment_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

final _now = DateTime.utc(2027, 3, 10, 12);

const _payPath = '/me/event-orders/ord_1/payment';
const _cta = Key('pay-provider-cta');

/// `GET /payments/options` while a member may pay an event order.
const _momoOn = {
  'enabled': true,
  'provider': 'azampay',
  'environment': 'production',
  'mobileMoney': {
    'products': ['EVENT_ORDER'],
  },
};

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  EventsOptions? options,
}) => pumpPage(
  tester,
  api,
  MemberEventPaymentPage(
    orderId: 'ord_1',
    options: options ?? optsS3(payment: 'provider'),
    now: _now,
  ),
  user: member,
  lang: lang,
  size: const Size(375, 2200),
  extraRoutes: s3Routes,
  keepRequests: true,
);

void _expectNoPayByHand() {
  expect(find.byKey(const Key('manual-pay-steps')), findsNothing);
  expect(find.byKey(const Key('manual-pay-transaction-id')), findsNothing);
  expect(find.byKey(const Key('manual-pay-payer-phone')), findsNothing);
  expect(find.byKey(const Key('pay-manual-banner')), findsNothing);
  expect(find.byKey(const Key('pay-confirm-check')), findsNothing);
  expect(find.byKey(const Key('pay-submit')), findsNothing);
  expect(find.textContaining('Lipa Namba'), findsNothing);
}

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsAnalytics.debugSink = [];
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    EventsAnalytics.debugSink = null;
  });

  apiTest('the recap and one mobile-money button; nothing to pay by hand', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-orders/ord_1', payableOrderJson());
    api.on('GET /payments/options', _momoOn);
    final host = await _pump(tester, api);
    // Amount comes from the server order.
    expect(find.text('Pay exactly TSh 25,000'), findsOneWidget);
    expect(find.text('EV-3F9A2B7C1D · 1 places'), findsOneWidget);
    expect(find.byKey(const Key('pay-recap')), findsOneWidget);
    expect(find.byKey(const Key('pay-countdown')), findsOneWidget);
    expect(
      buttonLabelled(
        host
            .tr('events.pay.provider.cta')
            .replaceFirst('{amount}', 'TSh 25,000'),
      ),
      findsOneWidget,
    );
    expect(isEnabled(tester, find.byKey(_cta)), isTrue);
    _expectNoPayByHand();
    expect(find.textContaining('instant'), findsNothing);
    final started = EventsAnalytics.debugSink!.single;
    expect(started.name, 'payment_started');
    expect(started.props['late'], isFalse);
  });

  apiTest('tap: empty body, key, then the existing mobile-money sheet', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-orders/ord_1', payableOrderJson());
    api.on('GET /payments/options', _momoOn);
    api.on('POST $_payPath', paymentAccepted());
    final host = await _pump(tester, api);
    await tapVisible(tester, find.byKey(_cta));
    final req = api.only('POST', _payPath);
    // Never an amount, currency, provider, transaction ID or paying number.
    expect(req.body, <String, dynamic>{});
    expect(req.headers['idempotency-key'], startsWith('chk_'));
    // The shared sheet opens for the server's payment request, and asks
    // which wallet pays.
    expect(find.text(host.tr('momo.title')), findsOneWidget);
    expect(find.byKey(const Key('momo-wallet-Mpesa')), findsOneWidget);
    _expectNoPayByHand();
    expect(
      EventsAnalytics.debugSink!
          .firstWhere((e) => e.name == 'payment_submitted')
          .props['late'],
      isFalse,
    );
  });

  apiTest('an unknown outcome keeps the page; the retry reuses the key', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-orders/ord_1', payableOrderJson());
    api.on('GET /payments/options', _momoOn);
    api.fail('POST $_payPath', 503);
    final host = await _pump(tester, api);
    await tapVisible(tester, find.byKey(_cta));
    expect(find.text(host.tr('events.pay.uncertain.title')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pay-uncertain-close')));
    expect(find.byKey(_cta), findsOneWidget);

    api.heal('POST $_payPath');
    api.on('POST $_payPath', paymentAccepted(replayed: true));
    await tapVisible(tester, find.byKey(_cta));
    final sent = api.where('POST', _payPath);
    expect(sent, hasLength(2));
    expect(
      sent[1].headers['idempotency-key'],
      sent[0].headers['idempotency-key'],
    );
    expect(sent[1].body, <String, dynamic>{});
    expect(find.text(host.tr('momo.title')), findsOneWidget);
  });

  group('server refusals', () {
    Future<PageHost> refused(
      WidgetTester tester,
      RecordingApi api,
      int status,
      Map<String, dynamic> body,
    ) async {
      api.on('GET /me/event-orders/ord_1', payableOrderJson());
      api.on('GET /payments/options', _momoOn);
      api.fail('POST $_payPath', status, body);
      final host = await _pump(tester, api);
      await tapVisible(tester, find.byKey(_cta));
      return host;
    }

    apiTest('too many attempts is an alert with the wait', (tester, api) async {
      await refused(tester, api, 429, {'error': 'too_many_attempts'});
      expect(find.byKey(const Key('pay-inline-error')), findsOneWidget);
      expect(find.byKey(_cta), findsOneWidget);
    });

    apiTest('payment_in_progress goes to the order page', (tester, api) async {
      await refused(tester, api, 409, {'error': 'payment_in_progress'});
      expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
    });

    apiTest('order_not_payable goes to the order page', (tester, api) async {
      await refused(tester, api, 409, {
        'error': 'order_not_payable',
        'status': 'cancelled',
      });
      expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
    });

    apiTest('hold_expired re-reads the order: the expired view', (
      tester,
      api,
    ) async {
      var orders = 0;
      api.onCall('GET /me/event-orders/ord_1', (_) {
        orders++;
        return orders == 1
            ? payableOrderJson()
            : orderJson(
                status: 'expired',
                closeReason: 'expired',
                closedAt: '2027-03-10T12:00:00Z',
                holdExpiresAt: null,
                allowedActions: [],
              );
      });
      api.on('GET /payments/options', _momoOn);
      api.fail('POST $_payPath', 409, {'error': 'hold_expired'});
      await _pump(tester, api);
      await tapVisible(tester, find.byKey(_cta));
      expect(find.byKey(const Key('pay-expired')), findsOneWidget);
      expect(find.byKey(_cta), findsNothing);
    });

    apiTest('tickets unavailable (5xx) is an unknown outcome; unsupported '
        'currency turns the button off', (tester, api) async {
      final host = await refused(tester, api, 503, {
        'error': 'tickets_unavailable',
      });
      // A 5xx is an unknown outcome; dismiss, then a definite refusal.
      await tapVisible(tester, find.byKey(const Key('pay-uncertain-close')));
      api.fail('POST $_payPath', 409, {'error': 'unsupported_currency'});
      await tapVisible(tester, find.byKey(_cta));
      expect(find.byKey(const Key('pay-unavailable')), findsOneWidget);
      expect(find.text(host.tr('events.pay.unavailable')), findsOneWidget);
      expect(isEnabled(tester, find.byKey(_cta)), isFalse);
    });

    apiTest('payment_mode_mismatch (paying was switched off) re-reads the '
        'options and goes back to the order', (tester, api) async {
      var orders = 0;
      api.onCall('GET /me/event-orders/ord_1', (_) {
        orders++;
        return orders == 1 ? payableOrderJson() : orderJson();
      });
      api.on('GET /events/options', {...optionsS3, 'payment': 'none'});
      api.on('GET /payments/options', _momoOn);
      api.fail('POST $_payPath', 409, {
        'error': 'payment_mode_mismatch',
        'mode': 'none',
      });
      await _pump(tester, api);
      await tapVisible(tester, find.byKey(_cta));
      expect(api.sent('GET', '/events/options'), isTrue);
      expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
    });
  });

  apiTest('a rejected transaction ID from before the change: the page is '
      'the mobile-money one, with no ID to correct', (tester, api) async {
    api.on(
      'GET /me/event-orders/ord_1',
      payableOrderJson(
        paymentView: paymentView(
          state: 'rejected',
          rejectCode: 'reference_not_found',
          canRetry: true,
        ),
      ),
    );
    api.on('GET /payments/options', _momoOn);
    await _pump(tester, api);
    expect(find.byKey(_cta), findsOneWidget);
    _expectNoPayByHand();
  });

  apiTest('a live payment sends the member to the order page', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-orders/ord_1',
      payableOrderJson(paymentView: paymentView()),
    );
    await _pump(tester, api);
    expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
  });

  apiTest('mode none redirects to the order page', (tester, api) async {
    api.on('GET /me/event-orders/ord_1', orderJson());
    await _pump(tester, api, options: optsS3());
    expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
    expect(find.byKey(_cta), findsNothing);
  });

  apiTest('a mode this release does not take (an older server\'s manual) '
      'redirects to the order page', (tester, api) async {
    api.on('GET /me/event-orders/ord_1', {
      ...orderJson(),
      'next': {
        'payment': 'manual',
        'instructions': {'lipaNamba': '5123456', 'accountName': 'FitFlex'},
      },
    });
    await _pump(tester, api);
    expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
    _expectNoPayByHand();
    expect(api.sent('POST', _payPath), isFalse);
  });

  group('an order whose hold ended', () {
    apiTest('is the expired view, also just after it ended (no late pay)', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        payableOrderJson(
          status: 'expired',
          closeReason: 'expired',
          closedAt: '2027-03-10T11:00:00Z',
          holdExpiresAt: null,
          allowedActions: [],
        ),
      );
      api.on('GET /payments/options', _momoOn);
      await _pump(tester, api);
      expect(find.byKey(const Key('pay-expired')), findsOneWidget);
      expect(find.byKey(const Key('pay-late-banner')), findsNothing);
      expect(find.byKey(_cta), findsNothing);
      _expectNoPayByHand();
    });

    apiTest('an order the member cancelled is the expired view too', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        payableOrderJson(
          status: 'expired',
          closeReason: 'cancelled',
          closedAt: '2027-03-10T11:00:00Z',
          holdExpiresAt: null,
          allowedActions: [],
        ),
      );
      await _pump(tester, api);
      expect(find.byKey(const Key('pay-expired')), findsOneWidget);
    });
  });

  apiTest('mobile money not offered: says so, and no other way to pay', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-orders/ord_1', payableOrderJson());
    api.on('GET /payments/options', {
      'enabled': true,
      'provider': 'azampay',
      'mobileMoney': {
        'products': ['FITFLEX_PASS'],
      },
    });
    final host = await _pump(tester, api);
    expect(find.byKey(const Key('pay-provider-unavailable')), findsOneWidget);
    expect(
      find.text(host.tr('events.pay.provider.unavailable')),
      findsOneWidget,
    );
    expect(isEnabled(tester, find.byKey(_cta)), isFalse);
    _expectNoPayByHand();
    expect(api.sent('POST', _payPath), isFalse);
  });

  apiTest('Swahili: the amount and the button', (tester, api) async {
    api.on('GET /me/event-orders/ord_1', payableOrderJson());
    api.on('GET /payments/options', _momoOn);
    await _pump(tester, api, lang: 'sw');
    expect(find.text('Lipa kiasi kamili: TSh 25,000'), findsOneWidget);
    expect(find.text('Lipa kwa mtandao wa simu · TSh 25,000'), findsOneWidget);
    expect(find.textContaining('Uthibitisho wa mkono'), findsNothing);
  });

  apiTest('a failed load is an error state with retry', (tester, api) async {
    api.fail('GET /me/event-orders/ord_1', 500);
    await _pump(tester, api);
    expect(find.byKey(const Key('pay-error')), findsOneWidget);
    api.heal('GET /me/event-orders/ord_1');
    api.on('GET /me/event-orders/ord_1', payableOrderJson());
    api.on('GET /payments/options', _momoOn);
    await tapVisible(tester, find.byType(FFButton).first);
    expect(find.byKey(_cta), findsOneWidget);
  });

  apiTest('404 is the gone view', (tester, api) async {
    await _pump(tester, api);
    expect(find.byKey(const Key('pay-gone')), findsOneWidget);
  });
}
