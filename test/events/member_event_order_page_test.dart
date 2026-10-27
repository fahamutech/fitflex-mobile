// Events S3 (spec §5.14 member_event_order_page_test): awaiting state with
// the countdown, the labelled placeholder (no ManualPaymentSteps), cancel
// with reason → cancelled view, expired with "Register again", per-place
// removal incl. remove_whole_line, polling on resume, 404.
import 'package:fitflexmobile/screens/member/events/member_event_order_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events/registration_draft.dart';
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
  Duration pollEvery = const Duration(seconds: 60),
}) => pumpPage(
  tester,
  api,
  MemberEventOrderPage(
    orderId: 'ord_1',
    options: optsS3(),
    now: _now,
    pollEvery: pollEvery,
  ),
  user: member,
  lang: lang,
  size: const Size(375, 1800),
  extraRoutes: s3Routes,
  keepRequests: true,
);

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsAnalytics.debugSink = [];
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    EventsAnalytics.debugSink = null;
  });

  apiTest(
    'awaiting payment: countdown, reference, placeholder, no Lipa Namba',
    (tester, api) async {
      api.on('GET /me/event-orders/ord_1', orderJson());
      final host = await _pump(tester, api);
      expect(api.only('GET', '/me/event-orders/ord_1'), isNotNull);
      expect(find.text('Order EV-3F9A2B7C1D'), findsOneWidget);
      expect(
        tester.widget<FFBadge>(find.byKey(const Key('order-status'))).label,
        'Awaiting payment',
      );
      expect(find.text('Held until 15:27 EAT'), findsOneWidget);
      expect(find.text('27 min left'), findsOneWidget);
      final sem = tester.getSemantics(find.byKey(const Key('ff-countdown')));
      expect(sem.flagsCollection.isLiveRegion, isTrue);
      expect(
        find.byKey(const Key('order-payment-placeholder')),
        findsOneWidget,
      );
      expect(
        find.text(host.tr('events.order.payment.soon.title')),
        findsOneWidget,
      );
      expect(find.byType(ManualPaymentSteps), findsNothing);
      expect(find.textContaining('Lipa'), findsNothing);
      expect(find.byKey(const Key('order-quote')), findsOneWidget);
      expect(find.byKey(const Key('order-participant-reg_1')), findsOneWidget);
      expect(find.text('You'), findsOneWidget);
      expect(find.byKey(const Key('order-cancel')), findsOneWidget);
      expect(find.byKey(const Key('order-copy-ref')), findsOneWidget);
    },
  );

  apiTest('the countdown ticks and turns urgent under 5 minutes', (
    tester,
    api,
  ) async {
    var now = DateTime.utc(2027, 3, 10, 12);
    await pumpPage(
      tester,
      api,
      FFCountdownText(
        until: DateTime.utc(2027, 3, 10, 12, 6),
        now: () => now,
        minutesLabel: '{n} min left',
        secondsLabel: '{n} s left',
        style: const TextStyle(color: Colors.black),
        urgentStyle: const TextStyle(color: Colors.red),
      ),
      user: member,
      settle: false,
    );
    await tester.pump();
    expect(find.text('6 min left'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('ff-countdown'))).style?.color,
      Colors.black,
    );
    now = now.add(const Duration(minutes: 2));
    await tester.pump(const Duration(minutes: 2, seconds: 1));
    expect(find.text('4 min left'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('ff-countdown'))).style?.color,
      Colors.red,
    );
    now = now.add(const Duration(minutes: 3, seconds: 30));
    await tester.pump(const Duration(minutes: 3, seconds: 31));
    expect(find.text('30 s left'), findsOneWidget);
    now = now.add(const Duration(seconds: 40));
    await tester.pump(const Duration(seconds: 40));
    expect(find.text('0 s left'), findsOneWidget);
  });

  apiTest('cancel asks a reason, sends { reason } and shows cancelled', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-orders/ord_1', orderJson());
    api.on('POST /me/event-orders/ord_1/cancel', {
      'order': orderJson(
        status: 'cancelled',
        closeReason: 'cancelled',
        closedAt: '2027-03-10T12:10:00Z',
      )['order'],
      'registrations': [
        registrationJson(status: 'cancelled', orderStatus: 'cancelled'),
      ],
    });
    final host = await _pump(tester, api);
    await tapVisible(tester, find.byKey(const Key('order-cancel')));
    expect(find.byKey(const Key('event-cancel-dialog')), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel-reason-wrong_details')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('event-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(api.only('POST', '/me/event-orders/ord_1/cancel').body, {
      'reason': 'wrong_details',
    });
    expect(host.snack(host.tr('events.order.cancelled.snack')), findsOneWidget);
    expect(find.byKey(const Key('order-cancelled')), findsOneWidget);
    expect(
      find.text('You cancelled this order on 10 Mar 2027.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('order-cancel')), findsNothing);
    expect(find.byKey(const Key('order-payment-placeholder')), findsNothing);
    expect(find.byKey(const Key('order-register-again')), findsOneWidget);
    expect(EventsAnalytics.debugSink!.single.name, 'order_cancelled');
  });

  apiTest(
    'expired: notice + "Register again" writes a draft and opens register',
    (tester, api) async {
      api.on(
        'GET /me/event-orders/ord_1',
        orderJson(
          status: 'expired',
          closeReason: 'expired',
          allowedActions: [],
        ),
      );
      await _pump(tester, api);
      expect(find.byKey(const Key('order-expired')), findsOneWidget);
      expect(
        find.text('The hold ended before payment. Places were released.'),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(const Key('order-register-again')));
      expect(find.text('ROUTE-REGISTER-evt_1-'), findsOneWidget);
      final draft = await RegistrationDraftStore.load('evt_1');
      expect(draft?.lines, {'tt_std': 1});
      expect(draft?.participants.single.firstName, 'Asha');
    },
  );

  apiTest('"Register again" is disabled once the event is closed', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-orders/ord_1',
      orderJson(
        status: 'expired',
        allowedActions: [],
        event: detail('evt_1', availability: 'closed'),
      ),
    );
    await _pump(tester, api);
    expect(
      isEnabled(tester, find.byKey(const Key('order-register-again'))),
      isFalse,
    );
    expect(find.text('Closed'), findsWidgets);
  });

  apiTest('an admin cancel reads "cancelled by FitFlex"', (tester, api) async {
    api.on(
      'GET /me/event-orders/ord_1',
      orderJson(status: 'cancelled', closeReason: 'admin', allowedActions: []),
    );
    await _pump(tester, api);
    expect(find.text('This order was cancelled by FitFlex.'), findsOneWidget);
  });

  apiTest('removing one place of two posts the registration cancel', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-orders/ord_1',
      orderJson(
        lines: [quoteLine(quantity: 2)],
        total: 50000,
        registrations: [
          registrationJson(),
          registrationJson(
            id: 'reg_2',
            firstName: 'Juma',
            lastName: 'Kessy',
            isSelf: false,
            claimState: 'unclaimed',
            consentBasis: 'purchaser_authorised',
          ),
        ],
      ),
    );
    await _pump(tester, api);
    expect(find.text('Awaiting claim'), findsOneWidget);
    await tapVisible(
      tester,
      find.byKey(const Key('order-participant-menu-reg_2')),
    );
    await tester.tap(find.byKey(const Key('order-participant-remove-reg_2')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Juma Kessy?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('event-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(api.only('POST', '/me/event-registrations/reg_2/cancel').body, {
      'reason': 'changed_mind',
    });
    expect(api.where('GET', '/me/event-orders/ord_1'), hasLength(2));
  });

  apiTest('remove_whole_line offers to cancel the whole order', (
    tester,
    api,
  ) async {
    api.on(
      'GET /me/event-orders/ord_1',
      orderJson(
        lines: [
          quoteLine(),
          quoteLine(ticketTypeId: 'tt_free', name: 'Free entry', unit: 0),
        ],
        registrations: [
          registrationJson(),
          registrationJson(
            id: 'reg_2',
            ticketTypeId: 'tt_free',
            ticketTypeName: 'Free entry',
            firstName: 'Juma',
            isSelf: false,
            claimState: 'unclaimed',
          ),
        ],
      ),
    );
    api.fail('POST /me/event-registrations/reg_2/cancel', 409, {
      'error': 'remove_whole_line',
    });
    await _pump(tester, api);
    await tapVisible(
      tester,
      find.byKey(const Key('order-participant-menu-reg_2')),
    );
    await tester.tap(find.byKey(const Key('order-participant-remove-reg_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('event-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This is the last Free entry place in the order. Cancel the whole order and register again.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('remove-whole-line-cancel')), findsOneWidget);
  });

  apiTest('polls while awaiting and refreshes on resume', (tester, api) async {
    api.on('GET /me/event-orders/ord_1', orderJson());
    await _pump(tester, api, pollEvery: const Duration(seconds: 5));
    expect(api.where('GET', '/me/event-orders/ord_1'), hasLength(1));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(api.where('GET', '/me/event-orders/ord_1'), hasLength(2));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(api.where('GET', '/me/event-orders/ord_1'), hasLength(3));
  });

  apiTest('a 404 shows the "isn\'t available" state', (tester, api) async {
    api.fail('GET /me/event-orders/ord_1', 404, {'error': 'order_not_found'});
    await _pump(tester, api);
    expect(find.byKey(const Key('order-gone')), findsOneWidget);
    expect(find.text('This order isn\'t available'), findsOneWidget);
  });

  apiTest('Swahili: status pill and hold copy', (tester, api) async {
    api.on('GET /me/event-orders/ord_1', orderJson());
    await _pump(tester, api, lang: 'sw');
    expect(find.text('Inasubiri malipo'), findsNWidgets(2)); // order + its place
    expect(find.text('zimebaki dakika 27'), findsOneWidget);
    expect(find.text('Inakuja kwenye toleo lijalo la app'), findsOneWidget);
  });
}
