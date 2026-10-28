// Events S4 review fixes: the refund-policy line for all five presets from
// the server's `generated` text, refunds on the registration page (own or
// from the order), invitation fallbacks, 429 back-off on payment-status,
// payment state `none`, the organisation payment line, the admin note in
// Swahili, plural ticket wording, and the Swahili wording changes.
import 'package:fitflexmobile/screens/member/events/cancel/member_event_cancel_page.dart';
import 'package:fitflexmobile/screens/member/events/tickets/member_event_ticket_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/screens/member/events/member_event_detail_page.dart';
import 'package:fitflexmobile/screens/member/events/member_event_order_page.dart';
import 'package:fitflexmobile/screens/member/events/member_event_registration_page.dart';
import 'package:fitflexmobile/shared/events/event_detail.dart';
import 'package:fitflexmobile/shared/events/event_order.dart';
import 'package:fitflexmobile/shared/events/event_payment.dart';
import 'package:fitflexmobile/shared/events/event_ticket.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

final _now = DateTime.utc(2027, 3, 10, 12, 10);

/// The five presets as the server sends them (spec §3.12.1).
final _presets = <String, Map<String, dynamic>>{
  'no_refund': {
    'preset': 'no_refund',
    'text': {'en': '', 'sw': ''},
    'generated': {'en': 'No refunds', 'sw': 'Hakuna marejesho'},
  },
  'refund_until_close': {
    'preset': 'refund_until_close',
    'text': {'en': '', 'sw': ''},
    'generated': {
      'en': 'Full refund until registration closes on 12 Mar 2027',
      'sw': 'Marejesho kamili hadi usajili ufungwe tarehe 12 Mac 2027',
    },
  },
  'full_until_days': {
    'preset': 'full_until_days',
    'days': 14,
    'text': {'en': '', 'sw': ''},
    'generated': {
      'en': 'Full refund until 14 days before the start',
      'sw': 'Marejesho kamili hadi siku 14 kabla ya kuanza',
    },
  },
  'tiered': {
    'preset': 'tiered',
    'tiers': [
      {'daysBefore': 30, 'percent': 100},
      {'daysBefore': 14, 'percent': 50},
    ],
    'text': {'en': '', 'sw': ''},
    'generated': {
      'en': '100% until 30 days before, then 50% until 14 days before',
      'sw': '100% hadi siku 30 kabla, kisha 50% hadi siku 14 kabla',
    },
  },
  'custom': {
    'preset': 'custom',
    'text': {'en': 'Ask us on WhatsApp.', 'sw': 'Tuulize kwa WhatsApp.'},
    'generated': {
      'en': 'Refunds are decided case by case',
      'sw': 'Marejesho huamuliwa kila kesi',
    },
  },
};

Future<PageHost> _pumpDetail(
  WidgetTester tester,
  RecordingApi api,
  String lang,
) => pumpPage(
  tester,
  api,
  MemberEventDetailPage(eventId: 'evt_1', options: opts(), now: _now),
  user: member,
  lang: lang,
  size: const Size(375, 4000),
  keepRequests: true,
);

Future<PageHost> _pumpOrder(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  Duration livePollEvery = const Duration(seconds: 30),
}) => pumpPage(
  tester,
  api,
  MemberEventOrderPage(
    orderId: 'ord_1',
    options: optsS3(payment: 'manual', ticketsQr: true),
    now: _now,
    livePollEvery: livePollEvery,
  ),
  user: member,
  lang: lang,
  size: const Size(375, 2400),
  extraRoutes: s3Routes,
  keepRequests: true,
);

Future<PageHost> _pumpReg(WidgetTester tester, RecordingApi api) => pumpPage(
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

void main() {
  setUp(() => debugEventsDiscoveryOverride = true);
  tearDown(() => debugEventsDiscoveryOverride = null);
  rotateAndRejectionTests();

  group('refund policy line (all five presets)', () {
    test('the model reads generated, days, tiers and text', () {
      final full = EventRefundPolicy.fromJson(_presets['full_until_days']);
      expect(full.days, 14);
      expect(full.generatedLine('en'), contains('14 days'));
      expect(full.generatedLine('sw'), contains('siku 14'));
      final tiered = EventRefundPolicy.fromJson(_presets['tiered']);
      expect(tiered.tiers.map((t) => (t.daysBefore, t.percent)), [
        (30, 100),
        (14, 50),
      ]);
      final custom = EventRefundPolicy.fromJson(_presets['custom']);
      expect(custom.text.of('en'), 'Ask us on WhatsApp.');
      expect(EventRefundPolicy.fromJson(null).generatedLine('en'), '');
    });

    for (final lang in ['en', 'sw']) {
      for (final e in _presets.entries) {
        apiTest('detail page ($lang) prints the line for ${e.key}', (
          tester,
          api,
        ) async {
          api.on('GET /events/evt_1', detail('evt_1', refundPolicy: e.value));
          await _pumpDetail(tester, api, lang);
          final line = (e.value['generated'] as Map)[lang] as String;
          expect(find.byKey(const Key('event-refund-summary')), findsOneWidget);
          expect(find.text(line), findsOneWidget);
          if (e.key == 'custom') {
            expect(
              find.text((e.value['text'] as Map)[lang] as String),
              findsOneWidget,
            );
          }
        });
      }
    }

    apiTest(
      'an older server without `generated` keeps the two originals only',
      (tester, api) async {
        api.on(
          'GET /events/evt_1',
          detail(
            'evt_1',
            refundPolicy: {
              'preset': 'tiered',
              'text': {'en': '', 'sw': ''},
            },
          ),
        );
        await _pumpDetail(tester, api, 'en');
        expect(find.byKey(const Key('event-refund-summary')), findsNothing);
        await tester.pumpWidget(const SizedBox());
        api.on(
          'GET /events/evt_1',
          detail(
            'evt_1',
            refundPolicy: {
              'preset': 'no_refund',
              'text': {'en': '', 'sw': ''},
            },
          ),
        );
        await _pumpDetail(tester, api, 'en');
        expect(find.text('No refunds'), findsOneWidget);
      },
    );

    apiTest('the order page prints the server line too', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(event: detail('evt_1', refundPolicy: _presets['tiered'])),
      );
      await _pumpOrder(tester, api);
      expect(
        find.text('100% until 30 days before, then 50% until 14 days before'),
        findsOneWidget,
      );
    });

    apiTest(
      'the cancel page shows the server line and builds none of its own',
      (tester, api) async {
        api.on(
          'GET /me/event-registrations/reg_1/cancel-preview',
          cancelPreview(
            percent: 50,
            preset: 'tiered',
            generatedEn: '100% until 30 days before, then 50%',
          ),
        );
        await pumpPage(
          tester,
          api,
          MemberEventCancelPage.registration(
            registrationId: 'reg_1',
            options: optsS3(payment: 'manual'),
          ),
          user: member,
          size: const Size(375, 1800),
          extraRoutes: s3Routes,
          keepRequests: true,
        );
        expect(find.byKey(const Key('cancel-policy-line')), findsOneWidget);
        expect(
          find.text('100% until 30 days before, then 50%'),
          findsOneWidget,
        );
        expect(find.textContaining('refund until'), findsNothing);
        // No server line: nothing is invented from percent and deadline.
        await tester.pumpWidget(const SizedBox());
        api.on(
          'GET /me/event-registrations/reg_1/cancel-preview',
          cancelPreview(percent: 50, preset: 'tiered', generatedEn: ''),
        );
        await pumpPage(
          tester,
          api,
          MemberEventCancelPage.registration(
            registrationId: 'reg_1',
            options: optsS3(payment: 'manual'),
          ),
          user: member,
          size: const Size(375, 1800),
          extraRoutes: s3Routes,
          keepRequests: true,
        );
        expect(find.byKey(const Key('cancel-policy-line')), findsNothing);
      },
    );
  });

  group('registration page refunds', () {
    Map<String, dynamic> paidReg() => registrationJson(
      status: 'cancelled',
      orderStatus: 'partially_cancelled',
      allowedActions: [],
    );

    apiTest('its own refunds win', (tester, api) async {
      api.on('GET /me/event-registrations/reg_1', {
        ...paidReg(),
        'refunds': [refundView(id: 'rf_own')],
      });
      await _pumpReg(tester, api);
      expect(find.byKey(const Key('refund-card-rf_own')), findsOneWidget);
      expect(api.sent('GET', '/me/event-orders/ord_1'), isFalse);
    });

    apiTest('none of its own: the order\'s refunds for this place', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-registrations/reg_1', paidReg());
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'partially_cancelled',
          payment: 'manual',
          refunds: [
            {...refundView(id: 'rf_this'), 'registrationId': 'reg_1'},
            {...refundView(id: 'rf_other'), 'registrationId': 'reg_2'},
            refundView(id: 'rf_order', scope: 'event_cancelled'),
            refundView(id: 'rf_unknown'),
          ],
        ),
      );
      await _pumpReg(tester, api);
      expect(find.byKey(const Key('refund-card-rf_this')), findsOneWidget);
      expect(find.byKey(const Key('refund-card-rf_order')), findsOneWidget);
      expect(find.byKey(const Key('refund-card-rf_other')), findsNothing);
      expect(find.byKey(const Key('refund-card-rf_unknown')), findsNothing);
    });

    apiTest('an unpaid place never reads the order', (tester, api) async {
      api.on('GET /me/event-registrations/reg_1', registrationJson());
      await _pumpReg(tester, api);
      expect(api.sent('GET', '/me/event-orders/ord_1'), isFalse);
    });
  });

  group('invitation fields', () {
    test('flat fields first, nested invitation as the fallback', () {
      final nested = EventRegistration.fromJson({
        'id': 'r',
        'invitation': {'sentAt': '2027-03-10T12:31:00Z', 'count': 3},
      });
      expect(nested.invitedAt, DateTime.utc(2027, 3, 10, 12, 31));
      expect(nested.inviteCount, 3);
      final both = EventRegistration.fromJson({
        'id': 'r',
        'claimInvitedAt': '2027-03-11T08:00:00Z',
        'claimInviteCount': 1,
        'invitation': {'sentAt': '2027-03-10T12:31:00Z', 'count': 3},
      });
      expect(both.invitedAt, DateTime.utc(2027, 3, 11, 8));
      expect(both.inviteCount, 1);
    });
  });

  test('ticket body: ticketType name read, no purchaser name relied on', () {
    final t = EventTicketPayload.fromJson({
      ...ticketPayload(),
      'ticketType': {'id': 'tt_std', 'name': 'Standard'},
      'purchaserFirstName': 'Zed',
    });
    expect(t.ticketTypeName, 'Standard');
    expect(t.toString(), isNot(contains('Zed')));
  });

  group('payment-status polling', () {
    Map<String, dynamic> orderWithPayment() =>
        manualOrderJson(paymentView: paymentView());

    apiTest('429 backs off to 60 s with no error shown', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', orderWithPayment());
      api.fail('GET /me/event-orders/ord_1/payment-status', 429, {
        'error': 'rate_limited',
        'retryAfterSeconds': 30,
      });
      await _pumpOrder(tester, api);
      api.clear();
      await tester.pump(const Duration(seconds: 31));
      expect(
        api.where('GET', '/me/event-orders/ord_1/payment-status'),
        hasLength(1),
      );
      // No banner, no snack, no error state.
      expect(find.byType(SnackBar), findsNothing);
      expect(find.byKey(const Key('order-error')), findsNothing);
      expect(find.textContaining('Too many'), findsNothing);
      // Not at 30 s again; at 60 s.
      await tester.pump(const Duration(seconds: 31));
      expect(
        api.where('GET', '/me/event-orders/ord_1/payment-status'),
        hasLength(1),
      );
      await tester.pump(const Duration(seconds: 31));
      expect(
        api.where('GET', '/me/event-orders/ord_1/payment-status'),
        hasLength(2),
      );
    });

    apiTest('a good answer returns to 30 s', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', orderWithPayment());
      var n = 0;
      api.onCall('GET /me/event-orders/ord_1/payment-status', (_) {
        n++;
        if (n == 1) throw StateError('SocketException: x');
        return {
          'order': {
            'id': 'ord_1',
            'status': 'awaiting_payment',
            'holdExpiresAt': '2027-03-10T12:27:00Z',
            'totalTzs': 25000,
            'currency': 'TZS',
          },
          'payment': paymentView(),
        };
      });
      await _pumpOrder(tester, api);
      api.clear();
      await tester.pump(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 31));
      expect(
        api.where('GET', '/me/event-orders/ord_1/payment-status'),
        hasLength(2),
      );
    });
  });

  group('payment state none', () {
    test('parses as "not yet paid", not other', () {
      final p = EventPaymentView.fromJson(paymentView(state: 'none'))!;
      expect(p.state, EventPaymentState.none);
      expect(p.state.wire, 'none');
      expect(p.state.isLive, isFalse);
      expect(
        EventOrderDetail.fromJson(
          manualOrderJson(paymentView: paymentView(state: 'none')),
        ).hasPayment,
        isFalse,
      );
    });

    apiTest('the order is still payable and says not yet paid', (
      tester,
      api,
    ) async {
      api.on(
        'GET /me/event-orders/ord_1',
        manualOrderJson(paymentView: paymentView(state: 'none')),
      );
      await _pumpOrder(tester, api);
      expect(find.byKey(const Key('pay-not-yet-paid')), findsOneWidget);
      expect(find.text('Not yet paid'), findsOneWidget);
      expect(find.byKey(const Key('order-pay')), findsOneWidget);
      expect(find.text('Payment sent for checking'), findsNothing);
    });
  });

  apiTest('an organisation payment shows how and when it was recorded', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-orders/ord_1',
      manualOrderJson(
        paymentView: {
          ...paymentView(),
          'payerMethod': 'bank_transfer',
          'paidOn': '2027-03-09T00:00:00Z',
        },
      ),
    );
    await _pumpOrder(tester, api);
    expect(
      find.text('Sent as bank transfer, dated 9 Mar 2027'),
      findsOneWidget,
    );
  });

  group('the admin note', () {
    Map<String, dynamic> rejected({String? sw}) => manualOrderJson(
      paymentView: {
        ...paymentView(
          state: 'rejected',
          rejectCode: 'other',
          memberNote: 'Check the last digit.',
          canRetry: true,
        ),
        'memberNoteSw': ?sw,
      },
    );

    apiTest('Swahili with a Swahili note: that note', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        rejected(sw: 'Angalia tarakimu ya mwisho.'),
      );
      await _pumpOrder(tester, api, lang: 'sw');
      expect(
        find.text('Maelezo kutoka FitFlex: Angalia tarakimu ya mwisho.'),
        findsOneWidget,
      );
    });

    apiTest('Swahili without one: the English note, labelled as English', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', rejected());
      await _pumpOrder(tester, api, lang: 'sw');
      expect(
        find.text(
          'Maelezo kutoka FitFlex (kwa Kiingereza): Check the last digit.',
        ),
        findsOneWidget,
      );
    });

    apiTest('English shows the English note', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', rejected(sw: 'Angalia.'));
      await _pumpOrder(tester, api);
      expect(
        find.text('Note from FitFlex: Check the last digit.'),
        findsOneWidget,
      );
    });
  });

  group('plural tickets', () {
    Map<String, dynamic> confirmed(int n) => orderJson(
      status: 'confirmed',
      payment: 'manual',
      paymentView: paymentView(state: 'confirmed'),
      registrations: [
        for (var i = 1; i <= n; i++)
          registrationJson(
            id: 'reg_$i',
            status: 'confirmed',
            orderStatus: 'confirmed',
            ticket: {'state': 'active', 'displayCode': 'T-$i'},
            allowedActions: [],
          ),
      ],
      allowedActions: [],
    );

    apiTest('one', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', confirmed(1));
      await _pumpOrder(tester, api);
      expect(
        find.text('1 ticket for Dar Half Marathon is ready.'),
        findsOneWidget,
      );
    });

    apiTest('many', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', confirmed(3));
      await _pumpOrder(tester, api);
      expect(
        find.text('3 tickets for Dar Half Marathon are ready.'),
        findsOneWidget,
      );
    });

    test('the announcement has both forms in both languages', () {
      expect(
        FFLocale.textOf('en', 'events.pay.announce.confirmed'),
        'Payment confirmed. {n} tickets ready.',
      );
      expect(
        FFLocale.textOf('en', 'events.pay.announce.confirmed.one'),
        'Payment confirmed. 1 ticket ready.',
      );
      expect(
        FFLocale.keysOf('sw'),
        contains('events.pay.announce.confirmed.one'),
      );
      expect(FFLocale.keysOf('sw'), contains('events.pay.confirmed.body.one'));
    });
  });

  test('Swahili wording from the review', () {
    String sw(String k) => FFLocale.textOf('sw', k) ?? '';
    expect(sw('events.ticket.offline'), startsWith('Hakuna intaneti'));
    expect(sw('events.pay.offline'), startsWith('Hakuna intaneti'));
    expect(sw('events.pay.slowWait'), startsWith('Bado tunasubiri intaneti'));
    expect(
      sw('events.pay.provider.cta'),
      startsWith('Lipa kwa mtandao wa simu'),
    );
    expect(sw('events.pay.provider.unavailable'), contains('mtandao wa simu'));
    expect(
      sw('events.pay.processing.title'),
      'Idhinisha malipo kwenye simu yako',
    );
    expect(
      sw('events.ticket.scan.soon'),
      startsWith('Skani ya kuchukua vifaa vya mbio'),
    );
    expect(sw('events.ticket.scan.soon'), isNot(contains('Uskanaji')));
    expect(
      sw('events.refund.scope.unfulfilled_payment'),
      'Malipo yatarejeshwa',
    );
    expect(sw('events.order.status.refundPending'), 'Inasubiri marejesho');
    expect(sw('events.pay.rejected.retry'), contains('zimeshikiliwa'));
    expect(sw('events.refund.sentTo'), contains('namba ya muamala {ref}'));
    expect(sw('events.payment.status.needs_attention'), 'Inakaguliwa');
    expect(sw('events.payment.status.rejected'), 'Imekataliwa');
    expect(
      sw('events.pay.rejected.wrong_account'),
      isNot(contains('Lipa Lipa')),
    );
    expect(
      sw('error.reason.event_unavailable'),
      isNot(equals(FFLocale.textOf('en', 'error.reason.event_unavailable'))),
    );
    // Refund wording stays per the glossary.
    expect(sw('events.refund.status.rejected'), 'Hayajaidhinishwa');
  });
}

// ── Final contract re-check ────────────────────────────────────────────────

void rotateAndRejectionTests() {
  group('rotate_required', () {
    const path = 'GET /me/event-registrations/reg_1/ticket';
    Future<PageHost> pump(WidgetTester tester, RecordingApi api, String lang) =>
        pumpPage(
          tester,
          api,
          MemberEventTicketPage(
            registrationId: 'reg_1',
            options: optsS3(payment: 'manual', ticketsQr: true),
          ),
          user: member,
          lang: lang,
          size: const Size(375, 1800),
          extraRoutes: s3Routes,
          keepRequests: true,
        );

    for (final lang in ['en', 'sw']) {
      apiTest('($lang) offers a new code, rotates and reloads', (
        tester,
        api,
      ) async {
        await EventTicketCache.put('reg_1', ticketPayload());
        var reads = 0;
        api.onCall(path, (_) {
          reads++;
          if (reads == 1) {
            throw ApiException(409, {'error': 'rotate_required'});
          }
          return ticketPayload(
            token: 'ev1.k2.etk_reg_1.2.CCCCCCCCCCCCCCCCCCCCCC',
          );
        });
        api.on(
          'POST /me/event-registrations/reg_1/ticket/rotate',
          ticketPayload(),
        );
        final host = await pump(tester, api, lang);
        expect(find.byType(FFQrCode), findsNothing);
        expect(find.byKey(const Key('ticket-rotate-required')), findsOneWidget);
        expect(
          find.text(host.tr('error.reason.rotate_required')),
          findsOneWidget,
        );
        expect(
          buttonLabelled(lang == 'sw' ? 'Pata msimbo mpya' : 'Get a new code'),
          findsOneWidget,
        );
        // The retired code is not kept on the phone.
        expect(await EventTicketCache.get('reg_1'), isNull);
        await tapVisible(tester, find.byKey(const Key('ticket-rotate-now')));
        expect(
          api.only('POST', '/me/event-registrations/reg_1/ticket/rotate'),
          isNotNull,
        );
        expect(reads, 2);
        expect(
          tester.widget<FFQrCode>(find.byKey(const Key('ticket-qr'))).data,
          'FFEV1:ev1.k2.etk_reg_1.2.CCCCCCCCCCCCCCCCCCCCCC',
        );
      });
    }

    test('the code has its own words in both languages', () {
      for (final lang in ['en', 'sw']) {
        final locale = FFLocale()..set(Locale(lang));
        final own = locale.t('error.reason.rotate_required');
        expect(own, isNot('error.reason.rotate_required'));
        expect(
          errorMessage(locale, ApiException(409, {'error': 'rotate_required'})),
          contains(own),
        );
      }
    });
  });

  group('refund rejection note', () {
    Map<String, dynamic> order({String? sw}) => orderJson(
      status: 'cancelled',
      payment: 'manual',
      paymentView: paymentView(state: 'confirmed'),
      registrations: [
        registrationJson(status: 'cancelled', orderStatus: 'cancelled'),
      ],
      allowedActions: [],
      refunds: [
        {
          ...refundView(
            status: 'rejected',
            rejectionNote: 'Outside the window.',
          ),
          'rejectionNoteSw': ?sw,
        },
      ],
    );

    apiTest('Swahili with a Swahili note shows it', (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        order(sw: 'Nje ya muda uliopangwa.'),
      );
      await _pumpOrder(tester, api, lang: 'sw');
      expect(find.text('Nje ya muda uliopangwa.'), findsOneWidget);
      expect(find.textContaining('Outside the window'), findsNothing);
    });

    apiTest('Swahili without one: the English note, labelled', (
      tester,
      api,
    ) async {
      api.on('GET /me/event-orders/ord_1', order());
      await _pumpOrder(tester, api, lang: 'sw');
      expect(
        find.text(
          'Maelezo kutoka FitFlex (kwa Kiingereza): Outside the window.',
        ),
        findsOneWidget,
      );
    });

    apiTest('English shows the English note, plain', (tester, api) async {
      api.on('GET /me/event-orders/ord_1', order(sw: 'Nje ya muda.'));
      await _pumpOrder(tester, api);
      expect(find.text('Outside the window.'), findsOneWidget);
      expect(find.text('Nje ya muda.'), findsNothing);
    });
  });
}
