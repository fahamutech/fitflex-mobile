// Pay by mobile money: the number check, the stages, and the panel against a
// fake server (input → waiting → success / failed / held / slow / ended).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/widgets/mobile_money_pay.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0');

  final sent = <List<String>>[];
  final states = <String>[];
  Object? payError;

  /// The `reason` sent with a `held` state.
  String? heldReason;

  @override
  Future<Map<String, dynamic>> payByMobileMoney(
    String paymentRequestId,
    String phone, {
    String? network,
  }) async {
    if (payError != null) throw payError!;
    sent.add([paymentRequestId, phone]);
    return {'state': 'in_progress'};
  }

  @override
  Future<Map<String, dynamic>> refreshMobileMoney(
    String paymentRequestId,
  ) async => {
    'state': states.isEmpty ? 'in_progress' : states.removeAt(0),
    'reason': ?heldReason,
  };
}

Widget _app(_FakeApi api, Widget child) => AppScope(
  api: api,
  auth: AuthState(api),
  child: FFLocaleScope(
    notifier: FFLocale(),
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  ),
);

Widget _panel(
  _FakeApi api, {
  String? phone = '0712345678',
  bool testMode = false,
  Duration giveUpAfter = const Duration(minutes: 2),
}) => _app(
  api,
  MobileMoneyPayPanel(
    paymentRequestId: 'pay_1',
    amountTzs: 60000,
    defaultPhone: phone,
    testMode: testMode,
    pollEvery: const Duration(seconds: 1),
    giveUpAfter: giveUpAfter,
  ),
);

void main() {
  test('Tanzanian mobile numbers are recognised in the usual spellings', () {
    for (final ok in [
      '0712345678',
      '712345678',
      '+255712345678',
      '255 712-345-678',
      '0654 321 098',
    ]) {
      expect(looksLikeTzMobile(ok), isTrue, reason: ok);
    }
    for (final bad in ['', '12345', '0812345678', '+254712345678', 'abc']) {
      expect(looksLikeTzMobile(bad), isFalse, reason: bad);
    }
  });

  test('server states map to stages; anything unknown keeps waiting', () {
    expect(momoStageFor('completed'), MomoStage.success);
    expect(momoStageFor('failed'), MomoStage.failed);
    expect(momoStageFor('held'), MomoStage.held);
    expect(momoStageFor('in_progress'), MomoStage.waiting);
    expect(momoStageFor(null), MomoStage.waiting);
    expect(momoStageFor('something_new'), MomoStage.waiting);
  });

  test('none (the prompt is no longer open) is its own stage', () {
    expect(momoStageFor('none'), MomoStage.ended);
  });

  testWidgets('an ended prompt offers to send it again, and sends a new one', (
    t,
  ) async {
    final api = _FakeApi()..states.addAll(['in_progress', 'none']);
    await t.pumpWidget(_panel(api));
    await t.tap(find.textContaining('Send payment request to'));
    await t.pump();
    await t.pump(const Duration(seconds: 1)); // in_progress
    await t.pump(const Duration(seconds: 1)); // none
    expect(find.text('The payment request has ended'), findsOneWidget);
    expect(find.text('Still waiting'), findsNothing);
    expect(find.text('Done'), findsOneWidget);

    await t.tap(find.byKey(const Key('momo-send-again')));
    await t.pump();
    await t.tap(find.textContaining('Send payment request to 0712345678'));
    await t.pump();
    expect(api.sent, hasLength(2));
    expect(find.text('Check your phone'), findsOneWidget);
    // Stop the poll timer before the test ends.
    api.states.add('completed');
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Payment received'), findsOneWidget);
  });

  testWidgets('still waiting can be checked again; an ended prompt then '
      'offers to send again', (t) async {
    final api = _FakeApi();
    await t.pumpWidget(_panel(api, giveUpAfter: const Duration(seconds: 2)));
    await t.tap(find.textContaining('Send payment request'));
    await t.pump();
    for (var i = 0; i < 3; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.text('Still waiting'), findsOneWidget);
    expect(find.byKey(const Key('momo-send-again')), findsNothing);

    // Still out: nothing changes.
    await t.tap(find.byKey(const Key('momo-check-again')));
    await t.pump();
    await t.pump();
    expect(find.text('Still waiting'), findsOneWidget);

    // Ten minutes on, the server has given the prompt up.
    api.states.add('none');
    await t.tap(find.byKey(const Key('momo-check-again')));
    await t.pump();
    await t.pump();
    expect(find.text('The payment request has ended'), findsOneWidget);
    expect(find.byKey(const Key('momo-send-again')), findsOneWidget);
  });

  testWidgets('money that came after the prompt ended has its own wording', (
    t,
  ) async {
    final api = _FakeApi()
      ..states.add('held')
      ..heldReason = 'no_open_attempt';
    await t.pumpWidget(_panel(api));
    await t.tap(find.textContaining('Send payment request'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('We received your payment'), findsOneWidget);
    expect(
      find.text(FFLocale.textOf('en', 'momo.held.noOpenAttempt')!),
      findsOneWidget,
    );
    expect(find.byKey(const Key('momo-send-again')), findsNothing);
  });

  test('held reasons the server names each have wording', () {
    for (final reason in [
      'no_open_attempt',
      'amount_mismatch',
      'transaction_mismatch',
    ]) {
      final key = momoHeldBodyKey(reason);
      expect(key, isNot('momo.heldBody'), reason: reason);
      expect(FFLocale.textOf('en', key), isNotNull, reason: reason);
      expect(FFLocale.textOf('sw', key), isNotNull, reason: reason);
    }
    expect(momoHeldBodyKey('sandbox_not_settled'), 'momo.heldBody');
  });

  group('shop orders (AZAMPAY_SHOP_ORDERS)', () {
    const listed = {
      'enabled': true,
      'provider': 'azampay',
      'mobileMoney': {
        'products': ['FITFLEX_PASS', 'GYM_SUBSCRIPTION', 'SHOP_ORDER'],
      },
    };

    test('offered to a member only when the server lists SHOP_ORDER', () {
      expect(momoOffers(listed, MomoProduct.shopOrder, role: 'member'), isTrue);
      expect(
        momoOffers(listed, MomoProduct.shopOrder, role: 'trainer'),
        isFalse,
      );
      // No list (switches off), or a list without it: never.
      expect(
        momoOffers(
          const {'enabled': true, 'provider': 'azampay'},
          MomoProduct.shopOrder,
          role: 'member',
        ),
        isFalse,
      );
      expect(
        momoOffers(
          const {
            'enabled': true,
            'mobileMoney': {
              'products': ['FITFLEX_PASS'],
            },
          },
          MomoProduct.shopOrder,
          role: 'member',
        ),
        isFalse,
      );
      expect(
        momoOffers(
          {...listed, 'enabled': false},
          MomoProduct.shopOrder,
          role: 'member',
        ),
        isFalse,
      );
    });

    test('a paid order says the vendor has it, not that a plan is active', () {
      expect(
        momoSuccessBodyKey(MomoProduct.shopOrder),
        'shop.paymentConfirmed',
      );
    });

    for (final code in [
      'order_not_found',
      'order_buyer_mismatch',
      'order_amount_mismatch',
      'order_not_payable',
    ]) {
      test('409 $code is explained in English and Swahili', () {
        final e = ApiException(409, {'error': code});
        final en = apiErrorMessage(FFLocale(), e);
        final sw = apiErrorMessage(FFLocale()..set(const Locale('sw')), e);
        expect(en, isNot(contains(code)));
        expect(sw, isNot(contains(code)));
        expect(sw, isNot(en));
      });
    }
  });

  test('new Swahili is a marked placeholder until a native review', () {
    for (final key in [
      'momo.endedTitle',
      'momo.endedBody',
      'momo.sendAgain',
      'momo.held.noOpenAttempt',
      'error.reason.orderBuyerMismatch',
      'error.reason.orderAmountMismatch',
      'shop.payNothingOpen',
    ]) {
      expect(FFLocale.textOf('en', key), isNotNull, reason: key);
      expect(
        FFLocale.textOf('sw', key),
        '[SW-PENDING] ${FFLocale.textOf('en', key)}',
        reason: key,
      );
    }
  });

  testWidgets('a bad number is caught before anything is sent', (t) async {
    final api = _FakeApi();
    await t.pumpWidget(_panel(api, phone: ''));
    await t.enterText(find.byType(TextField), '123');
    await t.tap(find.textContaining('Send payment request'));
    await t.pump();
    expect(find.textContaining('Tanzanian mobile number'), findsOneWidget);
    expect(api.sent, isEmpty);
  });

  testWidgets('send, wait, then success', (t) async {
    final api = _FakeApi()..states.addAll(['in_progress', 'completed']);
    await t.pumpWidget(_panel(api, testMode: true));
    expect(find.textContaining('Test mode'), findsOneWidget);
    await t.tap(find.textContaining('Send payment request to 0712345678'));
    await t.pump();
    expect(api.sent, [
      ['pay_1', '0712345678'],
    ]);
    expect(find.text('Check your phone'), findsOneWidget);

    await t.pump(const Duration(seconds: 1)); // in_progress
    expect(find.text('Check your phone'), findsOneWidget);
    await t.pump(const Duration(seconds: 1)); // completed
    expect(find.text('Payment received'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('a failed payment offers try again, back to the number', (
    t,
  ) async {
    final api = _FakeApi()..states.add('failed');
    await t.pumpWidget(_panel(api));
    await t.tap(find.textContaining('Send payment request'));
    await t.pump();
    await t.pump(const Duration(seconds: 1));
    expect(find.text('Payment did not go through'), findsOneWidget);
    await t.tap(find.text('Try again'));
    await t.pump();
    expect(find.textContaining('Send payment request'), findsOneWidget);
  });

  testWidgets(
    'a payment needing a check says so and does not ask to pay again',
    (t) async {
      final api = _FakeApi()..states.add('held');
      await t.pumpWidget(_panel(api));
      await t.tap(find.textContaining('Send payment request'));
      await t.pump();
      await t.pump(const Duration(seconds: 1));
      expect(find.text('We received your payment'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets('waiting too long ends calmly, not as a failure', (t) async {
    final api = _FakeApi();
    await t.pumpWidget(_panel(api, giveUpAfter: const Duration(seconds: 2)));
    await t.tap(find.textContaining('Send payment request'));
    await t.pump();
    for (var i = 0; i < 4; i++) {
      await t.pump(const Duration(seconds: 1));
    }
    expect(find.text('Still waiting'), findsOneWidget);
    expect(find.text('Payment did not go through'), findsNothing);
  });

  testWidgets('a server refusal is shown and the number can be fixed', (
    t,
  ) async {
    final api = _FakeApi()
      ..payError = ApiException(503, {'error': 'provider_unavailable'});
    await t.pumpWidget(_panel(api));
    await t.tap(find.textContaining('Send payment request'));
    await t.pump();
    await t.pump();
    expect(find.textContaining('not reachable right now'), findsOneWidget);
    expect(find.textContaining('Send payment request'), findsOneWidget);
  });
}
