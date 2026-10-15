// Pay by mobile money: the number check, the stages, and the panel against a
// fake server (input → waiting → success / failed / held / slow).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/widgets/mobile_money_pay.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0');

  final sent = <List<String>>[];
  final states = <String>[];
  Object? payError;

  @override
  Future<Map<String, dynamic>> payByMobileMoney(
    String paymentRequestId,
    String phone,
  ) async {
    if (payError != null) throw payError!;
    sent.add([paymentRequestId, phone]);
    return {'state': 'in_progress'};
  }

  @override
  Future<Map<String, dynamic>> refreshMobileMoney(
    String paymentRequestId,
  ) async => {'state': states.isEmpty ? 'in_progress' : states.removeAt(0)};
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
    expect(momoStageFor('none'), MomoStage.waiting);
    expect(momoStageFor(null), MomoStage.waiting);
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
