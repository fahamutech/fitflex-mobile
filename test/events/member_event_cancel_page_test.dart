// Events S4 (spec §5.7 member_event_cancel_page_test): the preview by mode
// (full, partial, none with an acknowledgement, review), the policy text and
// deadline, blocked reasons, `expectedRefundTzs` sent as an equality check,
// `refund_changed` asking again, and where a finished cancel lands.
import 'package:fitflexmobile/screens/member/events/cancel/member_event_cancel_page.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

Future<PageHost> _pumpReg(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  String? orderId = 'ord_1',
}) => pumpPage(
  tester,
  api,
  MemberEventCancelPage.registration(
    registrationId: 'reg_1',
    orderId: orderId,
    options: optsS3(payment: 'manual', ticketsQr: true),
  ),
  user: member,
  lang: lang,
  size: const Size(375, 1800),
  extraRoutes: s3Routes,
  keepRequests: true,
);

Future<PageHost> _pumpOrder(WidgetTester tester, RecordingApi api) => pumpPage(
  tester,
  api,
  MemberEventCancelPage.order(
    orderId: 'ord_1',
    options: optsS3(payment: 'manual', ticketsQr: true),
  ),
  user: member,
  size: const Size(375, 1800),
  extraRoutes: s3Routes,
  keepRequests: true,
);

const _previewReg = 'GET /me/event-registrations/reg_1/cancel-preview';
const _cancelReg = 'POST /me/event-registrations/reg_1/cancel';
const _action = Key('cancel-action');

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsAnalytics.debugSink = [];
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    EventsAnalytics.debugSink = null;
  });

  group('refund shown by mode', () {
    apiTest('full: the policy, the amount, the deadline, the button', (
      tester,
      api,
    ) async {
      api.on(_previewReg, cancelPreview());
      await _pumpReg(tester, api);
      expect(find.text('Refunds until registration closes.'), findsOneWidget);
      expect(
        find.text('Full refund until registration closes'),
        findsOneWidget,
      );
      expect(find.text("You'll get back TSh 25,000."), findsOneWidget);
      expect(find.byKey(const Key('cancel-deadline')), findsOneWidget);
      expect(
        find.text('This refund is available until 12 Mar 2027.'),
        findsOneWidget,
      );
      expect(find.text('Asha Mollel'), findsOneWidget);
      expect(buttonLabelled('Cancel · refund TSh 25,000'), findsOneWidget);
      expect(isEnabled(tester, find.byKey(_action)), isTrue);
      expect(find.byKey(const Key('cancel-ack')), findsNothing);
      expect(EventsAnalytics.debugSink!.single.name, 'cancel_preview_viewed');
    });

    apiTest('partial: the amount, the percent and what was paid', (
      tester,
      api,
    ) async {
      api.on(
        _previewReg,
        cancelPreview(percent: 50, preset: 'full_until_days'),
      );
      await _pumpReg(tester, api);
      expect(
        find.text("You'll get back TSh 12,500 (50% of TSh 25,000)."),
        findsOneWidget,
      );
      expect(find.text('50% refund until 12 Mar 2027'), findsOneWidget);
      expect(buttonLabelled('Cancel · refund TSh 12,500'), findsOneWidget);
    });

    apiTest('none: needs the acknowledgement before the button works', (
      tester,
      api,
    ) async {
      api.on(
        _previewReg,
        cancelPreview(mode: 'none', percent: 0, deadlineAt: null),
      );
      await _pumpReg(tester, api);
      expect(
        find.text(
          "No refund. The organizer's policy gives no refund at this time.",
        ),
        findsOneWidget,
      );
      expect(buttonLabelled('Cancel ticket · no refund'), findsOneWidget);
      expect(isEnabled(tester, find.byKey(_action)), isFalse);
      await tapVisible(tester, find.byKey(const Key('cancel-ack')));
      expect(isEnabled(tester, find.byKey(_action)), isTrue);
      expect(find.text("I understand I won't get money back"), findsOneWidget);
    });

    apiTest('review: only a request is made, worded that way', (
      tester,
      api,
    ) async {
      api.on(
        _previewReg,
        cancelPreview(
          mode: 'manual_review',
          percent: 0,
          refundTzs: 25000,
          preset: 'custom',
          deadlineAt: null,
        ),
      );
      api.on(_cancelReg, {'requested': true});
      final host = await _pumpReg(tester, api);
      expect(buttonLabelled('Ask for a refund'), findsOneWidget);
      expect(find.textContaining('needs a person to review'), findsOneWidget);
      await tapVisible(tester, find.byKey(_action));
      // The dialog does not say the place is gone.
      expect(find.textContaining("can't be undone"), findsNothing);
      await tapVisible(tester, find.byKey(const Key('cancel-confirm')));
      expect(host.snack("Request sent. We'll reply soon."), findsOneWidget);
    });
  });

  group('confirm', () {
    apiTest('sends the reason and the expected refund, never an amount', (
      tester,
      api,
    ) async {
      api.on(_previewReg, cancelPreview());
      api.on(_cancelReg, {
        'order': {'id': 'ord_1'},
        'registration': {'id': 'reg_1', 'orderId': 'ord_1'},
      });
      final host = await _pumpReg(tester, api);
      await tapVisible(
        tester,
        find.byKey(const Key('cancel-reason-wrong_details')),
      );
      await tapVisible(tester, find.byKey(_action));
      // The destructive confirmation warns before anything is sent.
      expect(
        find.text(
          "This can't be undone. Your place may be given to someone else.",
        ),
        findsOneWidget,
      );
      expect(api.sent('POST', '/me/event-registrations/reg_1/cancel'), isFalse);
      await tapVisible(tester, find.byKey(const Key('cancel-confirm')));
      expect(api.only('POST', '/me/event-registrations/reg_1/cancel').body, {
        'reason': 'wrong_details',
        'expectedRefundTzs': 25000,
      });
      expect(
        host.snack('Ticket cancelled. Refund of TSh 25,000 requested.'),
        findsOneWidget,
      );
      // Lands on the order page, where the refund card is.
      expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
      expect(EventsAnalytics.debugSink!.map((e) => e.name), [
        'cancel_preview_viewed',
        'cancel_confirmed',
      ]);
    });

    apiTest('keep my ticket sends nothing', (tester, api) async {
      api.on(_previewReg, cancelPreview());
      await _pumpReg(tester, api);
      await tapVisible(tester, find.byKey(_action));
      await tapVisible(tester, find.byKey(const Key('cancel-keep')));
      expect(api.sent('POST', '/me/event-registrations/reg_1/cancel'), isFalse);
    });

    apiTest('no refund: expectedRefundTzs is 0', (tester, api) async {
      api.on(
        _previewReg,
        cancelPreview(mode: 'none', percent: 0, deadlineAt: null),
      );
      api.on(_cancelReg, {
        'order': {'id': 'ord_1'},
      });
      await _pumpReg(tester, api);
      await tapVisible(tester, find.byKey(const Key('cancel-ack')));
      await tapVisible(tester, find.byKey(_action));
      await tapVisible(tester, find.byKey(const Key('cancel-confirm')));
      expect(
        (api.only('POST', '/me/event-registrations/reg_1/cancel').body
            as Map)['expectedRefundTzs'],
        0,
      );
    });

    apiTest('refund_changed shows the new number and asks again', (
      tester,
      api,
    ) async {
      var previews = 0;
      api.onCall(_previewReg, (_) {
        previews++;
        return previews == 1
            ? cancelPreview()
            : cancelPreview(percent: 50, preset: 'full_until_days');
      });
      api.fail(_cancelReg, 409, {
        'error': 'refund_changed',
        'refundTzs': 12500,
      });
      await _pumpReg(tester, api);
      await tapVisible(tester, find.byKey(_action));
      await tapVisible(tester, find.byKey(const Key('cancel-confirm')));
      expect(find.byKey(const Key('cancel-changed')), findsOneWidget);
      expect(
        find.text('The refund amount changed. Check it and confirm again.'),
        findsOneWidget,
      );
      expect(
        find.text("You'll get back TSh 12,500 (50% of TSh 25,000)."),
        findsOneWidget,
      );
      // A second confirmation, with the new number.
      api.heal(_cancelReg);
      api.on(_cancelReg, {
        'order': {'id': 'ord_1'},
      });
      await tapVisible(tester, find.byKey(_action));
      await tapVisible(tester, find.byKey(const Key('cancel-confirm')));
      final posts = api.where('POST', '/me/event-registrations/reg_1/cancel');
      expect((posts.first.body as Map)['expectedRefundTzs'], 25000);
      expect((posts.last.body as Map)['expectedRefundTzs'], 12500);
    });

    apiTest('a refusal at confirm closes the action with its reason', (
      tester,
      api,
    ) async {
      api.on(_previewReg, cancelPreview());
      api.fail(_cancelReg, 409, {'error': 'refund_in_progress'});
      await _pumpReg(tester, api);
      await tapVisible(tester, find.byKey(_action));
      await tapVisible(tester, find.byKey(const Key('cancel-confirm')));
      expect(
        find.byKey(const Key('cancel-blocked-refund_in_progress')),
        findsOneWidget,
      );
      expect(find.byKey(_action), findsNothing);
    });

    apiTest('without an order id in the answer it goes back to the list', (
      tester,
      api,
    ) async {
      api.on(_previewReg, cancelPreview());
      api.on(_cancelReg, {});
      await _pumpReg(tester, api, orderId: null);
      await tapVisible(tester, find.byKey(_action));
      await tapVisible(tester, find.byKey(const Key('cancel-confirm')));
      expect(find.text('ROUTE-ORDERS'), findsOneWidget);
    });
  });

  group('blocked', () {
    const texts = {
      'payment_submitted':
          "We're still checking your payment. You can cancel once it's confirmed.",
      'refund_in_progress': 'A refund for this ticket is already in progress.',
      'cancellation_window_closed': 'Cancellations have closed for this event.',
      'event_cancelled':
          'This event was cancelled. FitFlex will refund what you paid.',
      'purchaser_only':
          'Only the person who registered you, who paid, can cancel this ticket.',
      'kit_collected': 'The kit for this ticket has been collected.',
    };
    for (final e in texts.entries) {
      apiTest('${e.key}: the specific text and no action', (tester, api) async {
        api.on(
          _previewReg,
          cancelPreview(
            mode: 'closed',
            eligible: false,
            blocked: e.key,
            refundTzs: 0,
          ),
        );
        await _pumpReg(tester, api);
        expect(find.byKey(Key('cancel-blocked-${e.key}')), findsOneWidget);
        expect(find.text(e.value), findsOneWidget);
        expect(find.byKey(_action), findsNothing);
        expect(
          find.byKey(const Key('cancel-reason-changed_mind')),
          findsNothing,
        );
      });
    }

    apiTest('ineligible with no named reason reads as the window closed', (
      tester,
      api,
    ) async {
      api.on(_previewReg, cancelPreview(mode: 'closed', eligible: false));
      await _pumpReg(tester, api);
      expect(
        find.byKey(const Key('cancel-blocked-cancellation_window_closed')),
        findsOneWidget,
      );
    });
  });

  apiTest('a whole order: its own preview, all the places, its own cancel', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-orders/ord_1/cancel-preview', {
      ...cancelPreview(paidTzs: 50000),
      'places': [
        {
          'registrationId': 'reg_1',
          'name': 'Asha Mollel',
          'paidTzs': 25000,
          'refundTzs': 25000,
        },
        {
          'registrationId': 'reg_2',
          'name': 'Juma Kessy',
          'paidTzs': 25000,
          'refundTzs': 25000,
        },
      ],
    });
    api.on('POST /me/event-orders/ord_1/cancel', {
      'order': {'id': 'ord_1'},
    });
    await _pumpOrder(tester, api);
    expect(find.text('Asha Mollel'), findsOneWidget);
    expect(find.text('Juma Kessy'), findsOneWidget);
    expect(find.text("You'll get back TSh 50,000."), findsOneWidget);
    await tapVisible(tester, find.byKey(_action));
    expect(find.text('Cancel this whole order?'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('cancel-confirm')));
    expect(api.only('POST', '/me/event-orders/ord_1/cancel').body, {
      'reason': 'changed_mind',
      'expectedRefundTzs': 50000,
    });
    expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
  });

  apiTest('a failed preview is an error state with retry', (tester, api) async {
    api.fail(_previewReg, 500);
    await _pumpReg(tester, api);
    expect(find.byKey(const Key('cancel-error')), findsOneWidget);
    expect(find.byKey(_action), findsNothing);
    api.heal(_previewReg);
    api.on(_previewReg, cancelPreview());
    await tapVisible(tester, find.text('Try again').first);
    expect(find.byKey(_action), findsOneWidget);
  });

  apiTest('Swahili: the amount, the button and the warning', (
    tester,
    api,
  ) async {
    api.on(_previewReg, cancelPreview());
    await _pumpReg(tester, api, lang: 'sw');
    expect(find.text('Utarejeshewa TSh 25,000.'), findsOneWidget);
    expect(find.text('Ghairi · rejesha TSh 25,000'), findsOneWidget);
    expect(find.text('Marejesho kamili hadi usajili ufungwe'), findsOneWidget);
  });
}
