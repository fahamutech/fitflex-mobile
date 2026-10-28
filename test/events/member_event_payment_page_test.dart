// Events S4 (spec §5.2, §5.3, §5.14 member_event_payment_page_test): the
// labelled-manual alert first, the steps from `next.instructions`, a submit
// that waits for valid entries and the confirmation box, the idempotency key
// (kept on a retry, renewed on a change), no amount / currency / provider in
// the body, an unknown outcome that keeps the form, each server refusal in
// its place, late mode, the provider variant and the mode switch.
import 'package:fitflexmobile/screens/member/events/pay/member_event_payment_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/manual_payment.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

final _now = DateTime.utc(2027, 3, 10, 12);

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
    options: options ?? optsS3(payment: 'manual'),
    now: _now,
  ),
  user: member,
  lang: lang,
  size: const Size(375, 2200),
  extraRoutes: s3Routes,
  keepRequests: true,
);

const _idField = Key('manual-pay-transaction-id');
const _phoneField = Key('manual-pay-payer-phone');
const _submit = Key('pay-submit');
const _check = Key('pay-confirm-check');

Future<void> _fill(
  WidgetTester tester, {
  String id = 'QGH7XK2L9P',
  String phone = '0712345678',
  bool check = true,
}) async {
  await typeInto(tester, find.byKey(_idField), id);
  await typeInto(tester, find.byKey(_phoneField), phone);
  if (check) await tapVisible(tester, find.byKey(_check));
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

  apiTest('manual: the alert comes first, then recap, steps, fields', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-orders/ord_1', manualOrderJson());
    await _pump(tester, api);
    expect(find.byKey(const Key('pay-manual-banner')), findsOneWidget);
    expect(
      find.textContaining('Manual confirmation: FitFlex checks your payment'),
      findsOneWidget,
    );
    expect(find.textContaining('within 24 hours'), findsOneWidget);
    // Amount comes from the server order.
    expect(find.text('Pay exactly TSh 25,000'), findsOneWidget);
    expect(find.text('EV-3F9A2B7C1D · 1 places'), findsOneWidget);
    // The steps are the shared widget, filled from next.instructions.
    expect(find.byType(ManualPaymentSteps), findsOneWidget);
    expect(find.byKey(const Key('manual-pay-number')), findsOneWidget);
    expect(find.text('5123456'), findsOneWidget);
    expect(
      find.text('Pay from M-Pesa, Tigo Pesa or Airtel Money.'),
      findsOneWidget,
    );
    expect(find.byKey(_idField), findsOneWidget);
    expect(find.byKey(_phoneField), findsOneWidget);
    expect(
      find.text('I paid TSh 25,000 to FitFlex Africa from this number'),
      findsOneWidget,
    );
    // The alert is the first block under the heading.
    final alertY = tester
        .getTopLeft(find.byKey(const Key('pay-manual-banner')))
        .dy;
    final recapY = tester.getTopLeft(find.byKey(const Key('pay-recap'))).dy;
    final stepsY = tester
        .getTopLeft(find.byKey(const Key('manual-pay-steps')))
        .dy;
    final fieldY = tester.getTopLeft(find.byKey(_idField)).dy;
    expect(alertY < recapY && recapY < stepsY && stepsY < fieldY, isTrue);
    // No provider wording or instant claims on the manual page.
    expect(find.byKey(const Key('pay-provider-cta')), findsNothing);
    expect(find.textContaining('instant'), findsNothing);
    expect(EventsAnalytics.debugSink!.map((e) => e.name), ['payment_started']);
  });

  apiTest('submit waits for a valid ID, a valid number and the tick', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-orders/ord_1', manualOrderJson());
    await _pump(tester, api);
    expect(isEnabled(tester, find.byKey(_submit)), isFalse);
    await typeInto(tester, find.byKey(_idField), 'QGH7XK2L9P');
    expect(isEnabled(tester, find.byKey(_submit)), isFalse);
    await typeInto(tester, find.byKey(_phoneField), '12345');
    await tapVisible(tester, find.byKey(_check));
    // Number is not a valid mobile number yet.
    expect(isEnabled(tester, find.byKey(_submit)), isFalse);
    await typeInto(tester, find.byKey(_phoneField), '0712345678');
    expect(isEnabled(tester, find.byKey(_submit)), isTrue);
    await tapVisible(tester, find.byKey(_check));
    expect(isEnabled(tester, find.byKey(_submit)), isFalse);
    await typeInto(tester, find.byKey(_idField), 'ab1');
    await tapVisible(tester, find.byKey(_check));
    expect(isEnabled(tester, find.byKey(_submit)), isFalse);
  });

  apiTest(
    'submit: key sent, body is the entries only, then back to the order',
    (tester, api) async {
      api.on('GET /me/event-orders/ord_1', manualOrderJson());
      api.on('POST /me/event-orders/ord_1/payment', paymentAccepted());
      final host = await _pump(tester, api);
      await _fill(tester);
      await tapVisible(tester, find.byKey(_submit));
      final req = api.only('POST', '/me/event-orders/ord_1/payment');
      expect(req.headers['idempotency-key'], isNotEmpty);
      expect(req.headers['idempotency-key'], startsWith('chk_'));
      expect(req.body, {'reference': 'QGH7XK2L9P', 'payerPhone': '0712345678'});
      final body = req.body as Map;
      for (final k in ['amountTzs', 'amount', 'currency', 'provider']) {
        expect(body.containsKey(k), isFalse, reason: k);
      }
      expect(host.snack(host.tr('events.pay.sent.snack')), findsOneWidget);
      expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
      expect(
        EventsAnalytics.debugSink!.map((e) => e.name),
        containsAll(['payment_started', 'payment_submitted']),
      );
      // Never a green "paid" visual on this page.
      expect(find.textContaining('Payment confirmed'), findsNothing);
    },
  );

  apiTest('an unknown outcome keeps the form; the same entries reuse the key, '
      'a changed one renews it', (tester, api) async {
    api.on('GET /me/event-orders/ord_1', manualOrderJson());
    api.fail('POST /me/event-orders/ord_1/payment', 503, {'error': 'down'});
    final host = await _pump(tester, api);
    await _fill(tester);
    await tapVisible(tester, find.byKey(_submit));
    expect(find.text(host.tr('events.pay.uncertain.title')), findsOneWidget);
    expect(find.text(host.tr('events.pay.uncertain.body')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pay-uncertain-close')));
    // The form is not cleared.
    expect(textOf(tester, find.byKey(_idField)), 'QGH7XK2L9P');
    expect(textOf(tester, find.byKey(_phoneField)), '0712345678');
    await tapVisible(tester, find.byKey(_submit));
    await tapVisible(tester, find.byKey(const Key('pay-uncertain-close')));
    final both = api.where('POST', '/me/event-orders/ord_1/payment');
    expect(both, hasLength(2));
    expect(
      both[0].headers['idempotency-key'],
      both[1].headers['idempotency-key'],
    );
    // A corrected ID is a new purchase: a new key.
    await typeInto(tester, find.byKey(_idField), 'QGH7XK2L9Q');
    await tapVisible(tester, find.byKey(_submit));
    await tapVisible(tester, find.byKey(const Key('pay-uncertain-close')));
    final three = api.where('POST', '/me/event-orders/ord_1/payment');
    expect(
      three[2].headers['idempotency-key'],
      isNot(three[0].headers['idempotency-key']),
    );
    // "Open my order" goes to the order page.
    await tapVisible(tester, find.byKey(_submit));
    await tapVisible(tester, find.byKey(const Key('pay-uncertain-open')));
    expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
  });

  apiTest('a replayed answer is treated as sent', (tester, api) async {
    api.on('GET /me/event-orders/ord_1', manualOrderJson());
    api.on(
      'POST /me/event-orders/ord_1/payment',
      paymentAccepted(replayed: true),
    );
    final host = await _pump(tester, api);
    await _fill(tester);
    await tapVisible(tester, find.byKey(_submit));
    expect(host.snack(host.tr('events.pay.sent.snack')), findsOneWidget);
    expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
  });

  group('server refusals', () {
    apiTest('a duplicate ID lands under the ID field', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', manualOrderJson());
      api.fail('POST /me/event-orders/ord_1/payment', 409, {
        'error': 'payment_reference_duplicate',
      });
      final host = await _pump(tester, api);
      await _fill(tester);
      await tapVisible(tester, find.byKey(_submit));
      expect(find.text(host.tr('manualPay.idDuplicate')), findsOneWidget);
      // Editing clears it.
      await typeInto(tester, find.byKey(_idField), 'QGH7XK2L9R');
      expect(find.text(host.tr('manualPay.idDuplicate')), findsNothing);
    });

    apiTest('an invalid number lands under the number field', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', manualOrderJson());
      api.fail('POST /me/event-orders/ord_1/payment', 400, {
        'error': 'payer_phone_invalid',
      });
      final host = await _pump(tester, api);
      await _fill(tester);
      await tapVisible(tester, find.byKey(_submit));
      expect(find.text(host.tr('manualPay.phoneInvalid')), findsOneWidget);
    });

    apiTest('too many attempts is an alert with the wait', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', manualOrderJson());
      api.fail('POST /me/event-orders/ord_1/payment', 429, {
        'error': 'too_many_attempts',
      });
      final host = await _pump(tester, api);
      await _fill(tester);
      await tapVisible(tester, find.byKey(_submit));
      expect(find.byKey(const Key('pay-inline-error')), findsOneWidget);
      expect(
        find.textContaining(host.tr('error.reason.tooManyAttempts')),
        findsOneWidget,
      );
    });

    apiTest('payment_in_progress goes to the order page', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', manualOrderJson());
      api.fail('POST /me/event-orders/ord_1/payment', 409, {
        'error': 'payment_in_progress',
      });
      await _pump(tester, api);
      await _fill(tester);
      await tapVisible(tester, find.byKey(_submit));
      expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
    });

    apiTest('hold_expired shows the expired view', (tester, api) async {
      var calls = 0;
      api.onCall('GET /me/event-orders/ord_1', (_) {
        calls++;
        return calls == 1
            ? manualOrderJson()
            : manualOrderJson(
                status: 'expired',
                closeReason: 'expired',
                closedAt: '2027-03-09T12:00:00Z', // beyond the 24 h grace
                holdExpiresAt: null,
              );
      });
      api.fail('POST /me/event-orders/ord_1/payment', 409, {
        'error': 'hold_expired',
      });
      await _pump(tester, api);
      await _fill(tester);
      await tapVisible(tester, find.byKey(_submit));
      expect(find.byKey(const Key('pay-expired')), findsOneWidget);
      expect(find.byKey(_submit), findsNothing);
    });

    apiTest('unsupported currency / tickets unavailable submits nothing', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', manualOrderJson());
      api.fail('POST /me/event-orders/ord_1/payment', 503, {
        'error': 'tickets_unavailable',
      });
      final host = await _pump(tester, api);
      await _fill(tester);
      await tapVisible(tester, find.byKey(_submit));
      // A 5xx is an unknown outcome; dismiss, then a definite refusal.
      await tapVisible(tester, find.byKey(const Key('pay-uncertain-close')));
      api.fail('POST /me/event-orders/ord_1/payment', 409, {
        'error': 'unsupported_currency',
      });
      await typeInto(tester, find.byKey(_idField), 'QGH7XK2L9Z');
      await tapVisible(tester, find.byKey(_submit));
      expect(find.byKey(const Key('pay-unavailable')), findsOneWidget);
      expect(find.text(host.tr('events.pay.unavailable')), findsOneWidget);
      expect(isEnabled(tester, find.byKey(_submit)), isFalse);
    });

    apiTest('payment_mode_mismatch re-reads the options and the mode', (
      tester,
      api,
    ) async {
      var orders = 0;
      api.onCall('GET /me/event-orders/ord_1', (_) {
        orders++;
        return orders == 1 ? manualOrderJson() : orderJson(payment: 'provider');
      });
      api.on('GET /events/options', {...optionsS3, 'payment': 'provider'});
      api.on('GET /payments/options', {
        'enabled': true,
        'mobileMoney': {
          'products': ['EVENT_ORDER'],
        },
      });
      api.fail('POST /me/event-orders/ord_1/payment', 409, {
        'error': 'payment_mode_mismatch',
        'mode': 'provider',
      });
      await _pump(tester, api);
      await _fill(tester);
      await tapVisible(tester, find.byKey(_submit));
      expect(api.sent('GET', '/events/options'), isTrue);
      // Re-rendered as the provider page: no Lipa Namba, no ID field.
      expect(find.byKey(const Key('pay-provider-cta')), findsOneWidget);
      expect(find.byKey(_idField), findsNothing);
      expect(find.byType(ManualPaymentSteps), findsNothing);
    });
  });

  apiTest('rejected: back here with the old ID put back to correct', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-orders/ord_1',
      manualOrderJson(
        paymentView: paymentView(
          state: 'rejected',
          rejectCode: 'reference_not_found',
          canRetry: true,
        ),
      ),
    );
    await _pump(tester, api);
    expect(textOf(tester, find.byKey(_idField)), 'QGH7XK2L9P');
    expect(find.byKey(const Key('pay-manual-banner')), findsOneWidget);
  });

  apiTest('a live payment sends the member to the order page', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-orders/ord_1',
      manualOrderJson(paymentView: paymentView()),
    );
    await _pump(tester, api);
    expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
  });

  apiTest('options mode none redirects to the order page', (tester, api) async {
    api.on('GET /me/event-orders/ord_1', orderJson());
    await _pump(tester, api, options: optsS3());
    expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
    expect(find.byKey(_submit), findsNothing);
  });

  group('late mode', () {
    apiTest('inside the grace window: warning, steps, late label', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        manualOrderJson(
          status: 'expired',
          closeReason: 'expired',
          closedAt: '2027-03-10T11:00:00Z',
          holdExpiresAt: null,
          allowedActions: [],
        ),
      );
      api.on(
        'POST /me/event-orders/ord_1/payment',
        paymentAccepted(late: true),
      );
      final host = await _pump(tester, api);
      expect(find.byKey(const Key('pay-late-banner')), findsOneWidget);
      expect(find.textContaining('only if you already paid'), findsOneWidget);
      expect(find.byType(ManualPaymentSteps), findsOneWidget);
      expect(find.byKey(const Key('pay-countdown')), findsNothing);
      expect(buttonLabelled(host.tr('events.pay.late.cta')), findsOneWidget);
      await _fill(tester);
      await tapVisible(tester, find.byKey(_submit));
      expect(api.only('POST', '/me/event-orders/ord_1/payment'), isNotNull);
      expect(
        EventsAnalytics.debugSink!
            .firstWhere((e) => e.name == 'payment_submitted')
            .props['late'],
        isTrue,
      );
    });

    apiTest('beyond the grace window it is the expired view', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        manualOrderJson(
          status: 'expired',
          closeReason: 'expired',
          closedAt: '2027-03-09T10:00:00Z',
          holdExpiresAt: null,
          allowedActions: [],
        ),
      );
      await _pump(tester, api);
      expect(find.byKey(const Key('pay-expired')), findsOneWidget);
      expect(find.byType(ManualPaymentSteps), findsNothing);
    });

    apiTest('an order the member cancelled is never payable late', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        manualOrderJson(
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

  group('provider mode', () {
    final providerOrder = orderJson(payment: 'provider');

    apiTest('one button, no Lipa Namba, no ID field, no manual alert', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', providerOrder);
      api.on('GET /payments/options', {
        'enabled': true,
        'environment': 'production',
        'mobileMoney': {
          'products': ['EVENT_ORDER'],
        },
      });
      final host = await _pump(
        tester,
        api,
        options: optsS3(payment: 'provider'),
      );
      expect(find.byKey(const Key('pay-provider-cta')), findsOneWidget);
      expect(
        buttonLabelled(
          host
              .tr('events.pay.provider.cta')
              .replaceFirst('{amount}', 'TSh 25,000'),
        ),
        findsOneWidget,
      );
      expect(find.byType(ManualPaymentSteps), findsNothing);
      expect(find.byKey(_idField), findsNothing);
      expect(find.byKey(const Key('pay-manual-banner')), findsNothing);
      expect(find.textContaining('Lipa Namba'), findsNothing);
      expect(find.byKey(const Key('pay-recap')), findsOneWidget);
    });

    apiTest('tap: empty body, key, then the existing mobile-money sheet', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', providerOrder);
      api.on('GET /payments/options', {
        'enabled': true,
        'environment': 'production',
        'mobileMoney': {
          'products': ['EVENT_ORDER'],
        },
      });
      api.on(
        'POST /me/event-orders/ord_1/payment',
        paymentAccepted(mode: 'provider'),
      );
      final host = await _pump(
        tester,
        api,
        options: optsS3(payment: 'provider'),
      );
      await tapVisible(tester, find.byKey(const Key('pay-provider-cta')));
      final req = api.only('POST', '/me/event-orders/ord_1/payment');
      expect(req.body, <String, dynamic>{});
      expect(req.headers['idempotency-key'], startsWith('chk_'));
      // The shared sheet opens for the server's payment request.
      expect(find.text(host.tr('momo.title')), findsOneWidget);
      expect(find.byKey(const Key('manual-pay-steps')), findsNothing);
    });

    apiTest('momo not offered: says so, and no other way to pay', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', providerOrder);
      api.on('GET /payments/options', {
        'enabled': true,
        'mobileMoney': {
          'products': ['FITFLEX_PASS'],
        },
      });
      final host = await _pump(
        tester,
        api,
        options: optsS3(payment: 'provider'),
      );
      expect(find.byKey(const Key('pay-provider-unavailable')), findsOneWidget);
      expect(
        find.text(host.tr('events.pay.provider.unavailable')),
        findsOneWidget,
      );
      expect(
        isEnabled(tester, find.byKey(const Key('pay-provider-cta'))),
        isFalse,
      );
      expect(find.byType(ManualPaymentSteps), findsNothing);
      expect(api.sent('POST', '/me/event-orders/ord_1/payment'), isFalse);
    });
  });

  apiTest('Swahili: the banner, amount and submit label', (tester, api) async {
    api.on('GET /me/event-orders/ord_1', manualOrderJson());
    await _pump(tester, api, lang: 'sw');
    expect(
      find.textContaining('Uthibitisho wa mkono: FitFlex inakagua malipo yako'),
      findsOneWidget,
    );
    expect(find.text('Lipa kiasi kamili: TSh 25,000'), findsOneWidget);
    expect(find.text('Nimelipa · Tuma ikaguliwe'), findsOneWidget);
  });

  apiTest('a failed load is an error state with retry', (tester, api) async {
    api.fail('GET /me/event-orders/ord_1', 500);
    await _pump(tester, api);
    expect(find.byKey(const Key('pay-error')), findsOneWidget);
    api.heal('GET /me/event-orders/ord_1');
    api.on('GET /me/event-orders/ord_1', manualOrderJson());
    await tapVisible(tester, find.byType(FFButton).first);
    expect(find.byKey(_submit), findsOneWidget);
  });

  apiTest('404 is the gone view', (tester, api) async {
    await _pump(tester, api);
    expect(find.byKey(const Key('pay-gone')), findsOneWidget);
  });
}
