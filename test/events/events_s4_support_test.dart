// Events S4: the pieces around the screens. Every spec §5.12 key in both
// languages, error reasons for the new codes (none falls to humanised
// English), the routes and inbox links, the options keys and how the mode
// switches, the wire shapes, the late-payment rule, and the payment label.
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/events/event_order.dart';
import 'package:fitflexmobile/shared/events/event_payment.dart';
import 'package:fitflexmobile/shared/events/event_payment_rules.dart';
import 'package:fitflexmobile/shared/events/event_refund.dart';
import 'package:fitflexmobile/shared/events/event_ticket.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/payment_labels.dart';
import 'package:fitflexmobile/shared/shop_checkout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

const _specKeys = <String>[
  'events.pay.title',
  'events.pay.cta',
  'events.pay.cta.a11y',
  'events.pay.manual.badge',
  'events.pay.manual.banner.title',
  'events.pay.manual.banner.body',
  'events.pay.recap.title',
  'events.pay.exact',
  'events.pay.confirmCheck',
  'events.pay.submit',
  'events.pay.sending',
  'events.pay.sent.snack',
  'events.pay.late.banner.title',
  'events.pay.late.banner.body',
  'events.pay.late.cta',
  'events.pay.alreadyPaid',
  'events.pay.uncertain.title',
  'events.pay.uncertain.body',
  'events.pay.uncertain.open',
  'events.pay.provider.cta',
  'events.pay.provider.unavailable',
  'events.pay.free.cta',
  'events.pay.free.done',
  'events.pay.submitted.title',
  'events.pay.submitted.body',
  'events.pay.submitted.sent',
  'events.pay.submitted.noCancel',
  'events.pay.processing.title',
  'events.pay.processing.body',
  'events.pay.rejected.title',
  'events.pay.rejected.reference_not_found',
  'events.pay.rejected.amount_mismatch',
  'events.pay.rejected.wrong_account',
  'events.pay.rejected.duplicate_reference',
  'events.pay.rejected.other',
  'events.pay.rejected.retry',
  'events.pay.rejected.noHold',
  'events.pay.failed.title',
  'events.pay.failed.body',
  'events.pay.confirmed.title',
  'events.pay.confirmed.body',
  'events.pay.confirmed.open',
  'events.pay.expiredPending.title',
  'events.pay.expiredPending.body',
  'events.pay.refundDue.title',
  'events.pay.refundDue.body',
  'events.order.status.partiallyCancelled',
  'events.order.status.refundPending',
  'events.order.status.refunded',
  'events.payment.status.submitted',
  'events.payment.status.processing',
  'events.payment.status.rejected',
  'events.payment.status.failed',
  'events.payment.status.needs_attention',
  'events.tickets.title',
  'events.tickets.section.upcoming',
  'events.tickets.section.past',
  'events.tickets.empty.title',
  'events.tickets.empty.body',
  'events.ticket.ready',
  'events.ticket.show',
  'events.ticket.number',
  'events.ticket.copy',
  'events.ticket.qr.a11y',
  'events.ticket.scan.soon',
  'events.ticket.scan.live',
  'events.ticket.cached',
  'events.ticket.offline',
  'events.ticket.handover',
  'events.ticket.claimedElsewhere',
  'events.ticket.revoked.cancelled',
  'events.ticket.revoked.event_cancelled',
  'events.ticket.revoked.refunded',
  'events.ticket.revoked.body',
  'events.ticket.rotate',
  'events.ticket.rotate.title',
  'events.ticket.rotate.body',
  'events.ticket.rotate.done',
  'events.cancelpaid.title',
  'events.cancelpaid.policy',
  'events.cancelpaid.refund.full',
  'events.cancelpaid.refund.partial',
  'events.cancelpaid.refund.until',
  'events.cancelpaid.refund.none',
  'events.cancelpaid.refund.review',
  'events.cancelpaid.ack',
  'events.cancelpaid.reason',
  'events.cancelpaid.cta.refund',
  'events.cancelpaid.cta.none',
  'events.cancelpaid.cta.review',
  'events.cancelpaid.warn',
  'events.cancelpaid.changed',
  'events.cancelpaid.done.refund',
  'events.cancelpaid.done.none',
  'events.cancelpaid.done.review',
  'events.cancelpaid.blocked.payment_submitted',
  'events.cancelpaid.blocked.refund_in_progress',
  'events.cancelpaid.blocked.cancellation_window_closed',
  'events.cancelpaid.blocked.event_cancelled',
  'events.cancelpaid.blocked.purchaser_only',
  'events.cancelpaid.blocked.kit_collected',
  'events.refund.title',
  'events.refund.status.requested',
  'events.refund.status.approved',
  'events.refund.status.paid',
  'events.refund.status.rejected',
  'events.refund.eta',
  'events.refund.sentTo',
  'events.refund.rejected.help',
  'events.refund.scope.registration',
  'events.refund.scope.order',
  'events.refund.scope.event_cancelled',
  'events.refund.scope.unfulfilled_payment',
  'events.invite.sent',
  'events.invite.notSent',
  'events.invite.resend',
  'events.invite.resend.body',
  'events.invite.resent',
  'events.invite.limit',
  'events.claim.paid',
  'error.reason.payment_in_progress',
  'error.reason.order_not_payable',
  'error.reason.hold_expired',
  'error.reason.payment_submitted',
  'error.reason.tickets_unavailable',
  'error.reason.unsupported_currency',
  'error.reason.payment_mode_mismatch',
  'error.reason.ticket_revoked',
  'error.reason.ticket_not_issued',
  'error.reason.refund_changed',
  'error.reason.refund_in_progress',
  'error.reason.cancellation_window_closed',
  'error.reason.purchaser_only',
  'error.reason.resend_limit_reached',
];

void main() {
  tearDown(() => debugEventsDiscoveryOverride = null);

  group('i18n', () {
    test('every spec §5.12 key is in both languages', () {
      final en = FFLocale.keysOf('en');
      final sw = FFLocale.keysOf('sw');
      expect(_specKeys.length, greaterThan(120));
      for (final k in _specKeys) {
        expect(en, contains(k), reason: 'en $k');
        expect(sw, contains(k), reason: 'sw $k');
      }
      expect(en, sw);
    });

    test('Swahili differs from English for every S4 key', () {
      // Shared words that are the same in both languages by design.
      const same = <String>{};
      for (final k in _specKeys) {
        if (same.contains(k)) continue;
        expect(
          FFLocale.textOf('sw', k),
          isNot(FFLocale.textOf('en', k)),
          reason: k,
        );
      }
    });

    test('Swahili uses the glossary: app, oda, tiketi, never "programu"', () {
      for (final k in FFLocale.keysOf('sw')) {
        if (!k.startsWith('events.')) continue;
        final t = (FFLocale.textOf('sw', k) ?? '').toLowerCase();
        expect(t.contains('programu'), isFalse, reason: k);
      }
      expect(
        FFLocale.textOf('sw', 'events.order.status.refunded'),
        'Imerejeshwa',
      );
      expect(
        FFLocale.textOf('sw', 'events.payment.status.failed'),
        'Imeshindikana',
      );
      expect(FFLocale.textOf('sw', 'events.status.order.paid'), 'Imelipwa');
      expect(
        FFLocale.textOf('sw', 'events.status.order.awaiting'),
        'Inasubiri malipo',
      );
      expect(
        FFLocale.textOf('sw', 'events.status.order.cancelled'),
        'Imeghairiwa',
      );
      expect(
        FFLocale.textOf('sw', 'events.status.order.expired'),
        'Imeisha muda',
      );
    });

    test('the order pills use the i-class forms of the spec', () {
      expect(
        eventOrderStatusKey(EventOrderStatus.awaitingPayment),
        'events.status.order.awaiting',
      );
      expect(
        eventOrderStatusKey(EventOrderStatus.confirmed),
        'events.status.order.paid',
      );
      expect(
        eventOrderStatusKey(EventOrderStatus.cancelled),
        'events.status.order.cancelled',
      );
      expect(
        eventOrderStatusKey(EventOrderStatus.expired),
        'events.status.order.expired',
      );
      expect(
        eventOrderStatusKey(EventOrderStatus.partiallyCancelled),
        'events.order.status.partiallyCancelled',
      );
      expect(
        eventOrderStatusKey(EventOrderStatus.refundPending),
        'events.order.status.refundPending',
      );
      expect(
        eventOrderStatusKey(EventOrderStatus.refunded),
        'events.order.status.refunded',
      );
    });

    test('new product label key exists in both languages', () {
      expect(FFLocale.keysOf('en'), contains('pay.product.eventOrder'));
      expect(FFLocale.keysOf('sw'), contains('pay.product.eventOrder'));
      expect(FFLocale.keysOf('en'), contains('momo.successBody.eventOrder'));
      expect(FFLocale.keysOf('sw'), contains('momo.successBody.eventOrder'));
    });
  });

  group('error reasons (spec §3.17)', () {
    const codes = [
      'order_not_payable',
      'hold_expired',
      'payment_submitted',
      'tickets_unavailable',
      'payment_mode_mismatch',
      'ticket_revoked',
      'ticket_not_issued',
      'refund_changed',
      'refund_in_progress',
      'cancellation_window_closed',
      'purchaser_only',
      'resend_limit_reached',
      'event_cancelled',
      'kit_collected',
      'order_not_confirmed',
      'event_unavailable',
    ];
    for (final lang in ['en', 'sw']) {
      test('$lang: each new code has its own words, not a humanised code', () {
        final locale = FFLocale()..set(Locale(lang));
        for (final code in codes) {
          final msg = errorMessage(locale, ApiException(409, {'error': code}));
          final own = locale.t('error.reason.$code');
          expect(own, isNot('error.reason.$code'), reason: code);
          expect(msg, contains(own), reason: code);
          // The humanised English fallback would read like "Hold expired".
          expect(
            msg.toLowerCase().contains(code.replaceAll('_', ' ')),
            isFalse,
            reason: '$code fell to humanised text: $msg',
          );
        }
      });

      test('$lang: events pages word payment_in_progress and '
          'unsupported_currency for tickets', () {
        final locale = FFLocale()..set(Locale(lang));
        for (final code in ['payment_in_progress', 'unsupported_currency']) {
          final msg = eventsErrorMessage(
            locale,
            ApiException(409, {'error': code}),
          );
          expect(msg, contains(locale.t('error.reason.$code')), reason: code);
        }
        // The shared map keeps its trainer-booking wording for everyone else.
        expect(
          errorMessage(
            locale,
            ApiException(409, {'error': 'payment_in_progress'}),
          ),
          contains(locale.t('error.reason.paymentInProgress')),
        );
      });
    }

    test('reasons that already existed are untouched', () {
      final locale = FFLocale()..set(const Locale('en'));
      expect(
        errorMessage(
          locale,
          ApiException(409, {'error': 'payment_reference_duplicate'}),
        ),
        contains(locale.t('error.reason.paymentReferenceDuplicate')),
      );
      expect(
        errorMessage(locale, ApiException(429, {'error': 'too_many_attempts'})),
        contains(locale.t('error.reason.tooManyAttempts')),
      );
    });
  });

  group('routes', () {
    test(
      'flag on: every S4 route matches its page, static before :eventId',
      () {
        debugEventsDiscoveryOverride = true;
        final router = buildRouter(AuthState(ApiClient(baseUrl: 'http://x')));
        addTearDown(router.dispose);
        String nameOf(String path) =>
            router.configuration.findMatch(Uri.parse(path)).last.route.name ??
            '';
        expect(nameOf('/member/events/tickets'), 'memberEventTickets');
        expect(
          nameOf('/member/events/orders/ord_1/pay'),
          'memberEventOrderPay',
        );
        expect(
          nameOf('/member/events/orders/ord_1/cancel'),
          'memberEventOrderCancel',
        );
        expect(
          nameOf('/member/events/registrations/reg_1/ticket'),
          'memberEventTicket',
        );
        expect(
          nameOf('/member/events/registrations/reg_1/cancel'),
          'memberEventRegistrationCancel',
        );
        // S3 routes still resolve as before.
        expect(nameOf('/member/events/orders/ord_1'), 'memberEventOrder');
        expect(nameOf('/member/events/evt_1'), 'memberEventDetail');
        expect(
          AppRoutes.memberEventOrderPayPath('o1'),
          '/member/events/orders/o1/pay',
        );
        expect(
          AppRoutes.memberEventTicketPath('r1'),
          '/member/events/registrations/r1/ticket',
        );
        expect(
          AppRoutes.memberEventRegistrationCancelPath('r1', orderId: 'o1'),
          '/member/events/registrations/r1/cancel?order=o1',
        );
      },
    );

    test('flag off: the S4 routes are gone', () {
      debugEventsDiscoveryOverride = false;
      final router = buildRouter(AuthState(ApiClient(baseUrl: 'http://x')));
      addTearDown(router.dispose);
      for (final p in [
        '/member/events/tickets',
        '/member/events/orders/ord_1/pay',
        '/member/events/registrations/reg_1/ticket',
      ]) {
        expect(
          router.configuration.findMatch(Uri.parse(p)).isError,
          isTrue,
          reason: p,
        );
      }
    });
  });

  group('inbox deep links', () {
    String? route(String type, {String? orderId, String? registrationId}) =>
        memberRouteFor(
          deepLink: '',
          type: type,
          orderId: orderId,
          registrationId: registrationId,
        );

    test('payment and refund notices open the order', () {
      for (final t in [
        'event_payment_submitted',
        'event_payment_refund_due',
        'event_payment_late_received',
        'event_cancelled_refund',
        'event_refund_requested',
        'event_refund_approved',
        'event_refund_paid',
        'event_refund_rejected',
      ]) {
        expect(route(t, orderId: 'o1'), '/member/events/orders/o1', reason: t);
        expect(route(t), '/member/events/orders', reason: t);
      }
    });

    test('rejected opens the pay page; confirmed the tickets', () {
      expect(
        route('event_payment_rejected', orderId: 'o1'),
        '/member/events/orders/o1/pay',
      );
      expect(route('event_payment_rejected'), '/member/events/orders');
      expect(
        route('event_payment_confirmed', orderId: 'o1'),
        '/member/events/tickets',
      );
    });

    test(
      'a ticket for a participant opens the ticket; a cancelled place the list',
      () {
        expect(
          route('event_ticket_ready', registrationId: 'r1'),
          '/member/events/registrations/r1/ticket',
        );
        expect(route('event_ticket_ready'), '/member/events/tickets');
        expect(
          route('event_place_cancelled_by_purchaser', registrationId: 'r1'),
          '/member/events/orders?tab=registrations',
        );
      },
    );

    test('an unsafe id never builds a path', () {
      expect(
        route('event_payment_rejected', orderId: 'a/../b'),
        '/member/events/orders',
      );
      expect(
        route('event_ticket_ready', registrationId: 'x y'),
        '/member/events/tickets',
      );
    });

    test('each new link has a button label in both languages', () {
      for (final link in [
        'eventTickets',
        'eventPay',
        'eventTicket',
        'eventRegistrations',
      ]) {
        expect(FFLocale.keysOf('en'), contains('inbox.open.$link'));
        expect(FFLocale.keysOf('sw'), contains('inbox.open.$link'));
      }
    });
  });

  group('options', () {
    test('S3 shape: no payment keys means none, defaults, no tickets', () {
      final o = EventsOptions.fromJson(optionsS3);
      expect(o.payment, 'none');
      expect(o.paymentsOn, isFalse);
      expect(o.tickets.qr, isFalse);
      expect(o.tickets.scanning, isFalse);
      expect(o.manualConfirmHours, 24);
      expect(o.refundDays, 5);
      expect(o.hold.lateGraceHours, 24);
    });

    test('manual and provider read their keys', () {
      final m = EventsOptions.fromJson({
        ...optionsS3,
        'payment': 'manual',
        'manualConfirmHours': 12,
        'refundDays': 7,
        'hold': {
          'manualExtendHours': 24,
          'manualMaxHours': 48,
          'providerExtendMinutes': 10,
          'lateGraceHours': 6,
        },
        'tickets': {'qr': true, 'scanning': true},
      });
      expect(m.payment, 'manual');
      expect(m.paymentsOn, isTrue);
      expect(m.manualConfirmHours, 12);
      expect(m.refundDays, 7);
      expect(m.hold.lateGraceHours, 6);
      expect(m.tickets.qr, isTrue);
      expect(m.tickets.scanning, isTrue);
      expect(
        EventsOptions.fromJson({
          ...optionsS3,
          'payment': 'provider',
        }).paymentsOn,
        isTrue,
      );
    });

    test('an unknown mode is not "on"', () {
      expect(
        EventsOptions.fromJson({...optionsS3, 'payment': 'cash'}).paymentsOn,
        isFalse,
      );
      expect(EventsOptions.off.payment, 'none');
    });
  });

  group('wire shapes', () {
    test('PaymentView reads every field and tolerates gaps', () {
      final p = EventPaymentView.fromJson(
        paymentView(
          state: 'rejected',
          rejectCode: 'wrong_account',
          memberNote: 'Use the number shown.',
          canRetry: true,
          late: true,
        ),
      )!;
      expect(p.state, EventPaymentState.rejected);
      expect(p.method, 'manual');
      expect(p.amountTzs, 25000);
      expect(p.reference, 'QGH7XK2L9P');
      expect(p.payerPhoneMasked, '+255 7•• ••• 678');
      expect(p.submittedAt, DateTime.utc(2027, 3, 10, 12));
      expect(p.confirmTargetAt, DateTime.utc(2027, 3, 11, 12));
      expect(p.rejectCode, 'wrong_account');
      expect(p.memberNote, 'Use the number shown.');
      expect(p.canRetry, isTrue);
      expect(p.late, isTrue);
      expect(EventPaymentView.fromJson(null), isNull);
      expect(
        EventPaymentView.fromJson({'id': 'x'})!.state,
        EventPaymentState.other,
      );
    });

    test('state words', () {
      for (final w in [
        'submitted',
        'processing',
        'confirmed',
        'rejected',
        'failed',
        'expired',
        'needs_attention',
      ]) {
        expect(EventPaymentState.parse(w).wire, w);
      }
      expect(EventPaymentState.submitted.isLive, isTrue);
      expect(EventPaymentState.processing.isLive, isTrue);
      expect(EventPaymentState.rejected.isLive, isFalse);
    });

    test('order detail carries the payment, the instructions and refunds', () {
      final d = EventOrderDetail.fromJson(
        manualOrderJson(paymentView: paymentView(), refunds: [refundView()]),
      );
      expect(d.payment, 'manual');
      expect(d.paymentView!.state, EventPaymentState.submitted);
      expect(d.manualInstructions!.manual.lipaNamba, '5123456');
      expect(d.manualInstructions!.manual.payerPhoneRequired, isTrue);
      expect(d.manualInstructions!.amountTzs, 25000);
      expect(d.refunds.single.status, 'requested');
    });

    test('instructions without the Lipa Namba are unusable (fail closed)', () {
      expect(EventManualInstructions.fromJson({'accountName': 'x'}), isNull);
      expect(EventManualInstructions.fromJson(null), isNull);
    });

    test('a registration reads its ticket state, refunds and invitation', () {
      final r = EventRegistration.fromJson(
        registrationJson(
          status: 'confirmed',
          ticket: {'state': 'active', 'displayCode': 'T-3F9A2B'},
          refunds: [refundView()],
          claimInvitedAt: '2027-03-10T12:31:00Z',
          claimInviteCount: 2,
        ),
      );
      expect(r.ticket!.isActive, isTrue);
      expect(r.ticket!.displayCode, 'T-3F9A2B');
      expect(r.refunds, hasLength(1));
      expect(r.invitedAt, DateTime.utc(2027, 3, 10, 12, 31));
      expect(r.inviteCount, 2);
      // The ticket survives the names being filled in.
      expect(r.withNamesFrom(const []).ticket, isNotNull);
    });

    test('order and registration statuses of S4', () {
      expect(
        EventOrderStatus.parse('partially_cancelled'),
        EventOrderStatus.partiallyCancelled,
      );
      expect(
        EventOrderStatus.parse('refund_pending'),
        EventOrderStatus.refundPending,
      );
      expect(EventOrderStatus.parse('refunded'), EventOrderStatus.refunded);
      expect(
        EventRegistrationStatus.parse('refunded'),
        EventRegistrationStatus.refunded,
      );
      expect(
        registrationIsLive(
          EventRegistrationStatus.refunded,
          EventOrderStatus.refunded,
        ),
        isFalse,
      );
      expect(
        registrationIsLive(
          EventRegistrationStatus.confirmed,
          EventOrderStatus.confirmed,
        ),
        isTrue,
      );
    });

    test('ticket rows and payloads', () {
      final row = EventTicketRow.fromJson(ticketRow(state: 'revoked'));
      expect(row.isActive, isFalse);
      expect(row.participantName, 'Asha Mollel');
      expect(row.displayCode, 'T-3F9A2B');
      final t = EventTicketPayload.fromJson(ticketPayload());
      expect(t.drawn, startsWith('FFEV1:'));
      expect(t.isActive, isTrue);
      // Falls back to the token when no payload is named; never invents one.
      expect(
        EventTicketPayload.fromJson({
          'ticket': {'id': 'x'},
          'token': 'tok',
        }).drawn,
        'tok',
      );
      expect(
        EventTicketPayload.fromJson({
          'ticket': {'id': 'x'},
        }).drawn,
        '',
      );
    });

    test('cancel preview reads every mode', () {
      final p = CancelPreview.fromJson(cancelPreview(percent: 50));
      expect(p.mode, CancelMode.auto);
      expect(p.refundTzs, 12500);
      expect(p.places.single.name, 'Asha Mollel');
      expect(p.policyText.of('sw'), 'Marejesho hadi usajili ufungwe.');
      expect(p.isBlocked, isFalse);
      expect(
        CancelPreview.fromJson(cancelPreview(mode: 'manual_review')).mode,
        CancelMode.manualReview,
      );
      expect(
        CancelPreview.fromJson(cancelPreview(mode: 'none')).mode,
        CancelMode.none,
      );
      expect(
        CancelPreview.fromJson(
          cancelPreview(blocked: 'payment_submitted'),
        ).isBlocked,
        isTrue,
      );
      expect(CancelPreview.fromJson({}).isBlocked, isTrue);
    });
  });

  group('late payment rule', () {
    final opts = optsS3(payment: 'manual');
    EventOrder order({
      String status = 'expired',
      String? reason = 'expired',
      String? closedAt = '2027-03-10T11:00:00Z',
    }) => EventOrder.fromJson(
      (orderJson(status: status, closeReason: reason, closedAt: closedAt)
              as Map)['order']
          as Map,
    );

    test('payable inside the window, only after a natural expiry', () {
      final now = DateTime.utc(2027, 3, 10, 12);
      expect(eventOrderLatePayable(order(), opts, now), isTrue);
      expect(
        eventOrderLatePayable(order(reason: 'cancelled'), opts, now),
        isFalse,
      );
      expect(eventOrderLatePayable(order(reason: 'admin'), opts, now), isFalse);
      expect(
        eventOrderLatePayable(order(), opts, DateTime.utc(2027, 3, 11, 11, 1)),
        isFalse,
      );
      expect(
        eventOrderLatePayable(order(), opts, DateTime.utc(2027, 3, 11, 10, 59)),
        isTrue,
      );
      expect(
        eventOrderLatePayable(order(status: 'awaiting_payment'), opts, now),
        isFalse,
      );
    });

    test('not in provider mode, and not when payment is off', () {
      final now = DateTime.utc(2027, 3, 10, 12);
      expect(
        eventOrderLatePayable(order(), optsS3(payment: 'provider'), now),
        isFalse,
      );
      expect(eventOrderLatePayable(order(), optsS3(), now), isFalse);
    });
  });

  group('payment label', () {
    Future<String> label(WidgetTester tester, Map<String, dynamic> json) async {
      late String out;
      await tester.pumpWidget(
        FFLocaleScope(
          notifier: FFLocale()..set(const Locale('en')),
          child: MaterialApp(
            home: Builder(
              builder: (context) {
                out = paymentProductLabel(
                  context,
                  PaymentRequest.fromJson(json),
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return out;
    }

    testWidgets('event tickets, with the event when the server names it', (
      tester,
    ) async {
      expect(
        await label(tester, {
          'id': 'p1',
          'productType': 'EVENT_ORDER',
          'amountTzs': 25000,
          'status': 'pending',
          'eventTitle': 'Dar Half Marathon',
        }),
        'Event tickets · Dar Half Marathon',
      );
      expect(
        await label(tester, {
          'id': 'p1',
          'productType': 'EVENT_ORDER',
          'status': 'pending',
          'eventOrderReference': 'EV-3F9A2B7C1D',
        }),
        'Event tickets · EV-3F9A2B7C1D',
      );
      expect(
        await label(tester, {
          'id': 'p1',
          'productType': 'EVENT_ORDER',
          'status': 'pending',
        }),
        'Event tickets',
      );
    });
  });

  test(
    'a pending event payment never counts as the member\'s pass payment',
    () {
      final d = MemberData()
        ..me = MemberMeResponse.fromJson({
          'user': {'id': 'u1', 'userType': 'member'},
          'pendingPayments': [
            {
              'id': 'p1',
              'productType': 'EVENT_ORDER',
              'amountTzs': 25000,
              'status': 'pending',
            },
          ],
        });
      expect(d.pendingPass, isNull);
    },
  );

  test(
    'the idempotency key is kept for the same entries, renewed for new ones',
    () {
      var n = 0;
      String make() => 'chk_${++n}';
      final a = CheckoutAttempt.forPurchase(null, 'o|QGH|0712', makeKey: make);
      final same = CheckoutAttempt.forPurchase(a, 'o|QGH|0712', makeKey: make);
      final changed = CheckoutAttempt.forPurchase(
        a,
        'o|QGX|0712',
        makeKey: make,
      );
      expect(same.key, a.key);
      expect(changed.key, isNot(a.key));
      expect(newCheckoutKey(), matches(RegExp(r'^[A-Za-z0-9._:-]{8,100}$')));
    },
  );
}
