import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_plans_sheet.dart';
import 'package:fitflexmobile/screens/member/widgets/mobile_money_pay.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/manual_payment.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_api.dart';

// Contract: fitflex-functions#188 (GET /payments/options `manual` block,
// `reference` on POST /me/subscribe and POST /me/upgrade).
const _manualOn = {
  'enabled': false,
  'manual': {
    'enabled': true,
    'lipaNamba': '5123456',
    'accountName': 'FitFlex Africa Ltd',
    'network': 'M-Pesa',
    'instructions': {
      'en': 'Use the Lipa kwa M-Pesa menu.',
      'sw': 'Tumia menyu ya Lipa kwa M-Pesa.',
    },
    'referenceRequired': true,
  },
};

const _manualOff = {
  'enabled': false,
  'manual': {
    'enabled': false,
    'lipaNamba': null,
    'accountName': null,
    'network': null,
    'instructions': null,
    'referenceRequired': false,
  },
};

MemberData _data() => MemberData()
  ..selectedTier = 'pro'
  ..passes = [PassTier(id: 'pro', price: 120000, visitCap: 12)];

Future<PageHost> _pumpPayment(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  MemberDataScope(data: _data(), child: const MemberPaymentPage()),
  user: const {'id': 'm1', 'userType': 'member'},
  lang: lang,
  size: const Size(400, 1600),
);

Finder _key(String k) => find.byKey(Key(k));

Finder get _idField => find.descendant(
  of: _key('manual-pay-transaction-id'),
  matching: find.byType(EditableText),
);

void main() {
  group('options', () {
    test('a missing or switched-off block means no manual payment', () {
      expect(ManualPayment.fromOptions(null), isNull);
      expect(ManualPayment.fromOptions({'enabled': true}), isNull);
      expect(ManualPayment.fromOptions(_manualOff), isNull);
      expect(
        ManualPayment.fromOptions({
          'manual': {'enabled': true, 'lipaNamba': '', 'accountName': 'X'},
        }),
        isNull,
      );
    });

    test('an enabled block is read in full', () {
      final m = ManualPayment.fromOptions(_manualOn)!;
      expect(m.lipaNamba, '5123456');
      expect(m.accountName, 'FitFlex Africa Ltd');
      expect(m.network, 'M-Pesa');
      expect(m.instructionsFor('sw'), 'Tumia menyu ya Lipa kwa M-Pesa.');
      expect(m.instructionsFor('en'), 'Use the Lipa kwa M-Pesa menu.');
      final noText = ManualPayment.fromOptions({
        'manual': {
          'enabled': true,
          'lipaNamba': '5123456',
          'accountName': 'FitFlex',
          'network': null,
          'instructions': null,
        },
      })!;
      expect(noText.network, isNull);
      expect(noText.instructionsFor('en'), isNull);
    });
  });

  group('transaction ID check (same rule as the server)', () {
    test('accepts real-looking IDs, trimmed, any case', () {
      for (final ok in [
        'QJK3H7XY2P',
        '  qjk3h7xy2p  ',
        'MP241019.1234',
        'A1_b-2.c',
        '123456',
        '9${'A' * 39}',
      ]) {
        expect(transactionIdError(ok), isNull, reason: ok);
      }
    });

    test('refuses empty, short, long, odd characters, no digit, bad start', () {
      expect(transactionIdError(''), 'manualPay.idRequired');
      expect(transactionIdError('   '), 'manualPay.idRequired');
      for (final bad in [
        'AB12C', // 5 characters
        '1${'A' * 40}', // 41 characters
        'QJK3H7 XY2P', // space inside
        'QJK3H7#XY2P', // symbol
        'ABCDEFGH', // no digit
        '-ABC123', // starts with a dash
        '.ABC123',
      ]) {
        expect(transactionIdError(bad), 'manualPay.idInvalid', reason: bad);
      }
    });
  });

  group('payment page', () {
    apiTest('manual on: steps, copy button, required ID sent as reference', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', _manualOn);
      api.on('POST /me/subscribe', {
        'subscription': {'id': 's1'},
        'paymentRequest': {
          'id': 'p1',
          'amountTzs': 120000,
          'memberReference': 'QJK3H7XY2P',
        },
      });
      final host = await _pumpPayment(tester, api);

      expect(_key('manual-pay-steps'), findsOneWidget);
      expect(
        find.text(
          'Pay TZS 120,000 to Lipa Namba 5123456 '
          '(account name FitFlex Africa Ltd, network M-Pesa).',
        ),
        findsOneWidget,
      );
      expect(_key('manual-pay-copy'), findsOneWidget);
      expect(find.text('Use the Lipa kwa M-Pesa menu.'), findsOneWidget);
      expect(find.text(host.tr('manualPay.pageBody')), findsOneWidget);
      expect(buttonLabelled('Submit transaction ID'), findsOneWidget);

      // Empty: refused on the phone, nothing sent.
      await tapVisible(tester, _key('payment-submit'));
      expect(find.text(host.tr('manualPay.idRequired')), findsOneWidget);
      expect(api.sent('POST', '/me/subscribe'), isFalse);

      // Not an ID: refused on the phone too.
      await tester.enterText(_idField, 'ABCDEFGH');
      await tapVisible(tester, _key('payment-submit'));
      expect(find.text(host.tr('manualPay.idInvalid')), findsOneWidget);
      expect(api.sent('POST', '/me/subscribe'), isFalse);

      await tester.enterText(_idField, '  QJK3H7XY2P ');
      await tapVisible(tester, _key('payment-submit'));
      expect(api.only('POST', '/me/subscribe').body, {
        'tier': 'pro',
        'type': 'platform_pass',
        'reference': 'QJK3H7XY2P',
      });
      // Paid by hand: no mobile-money sheet is offered afterwards.
      expect(find.text(host.tr('momo.title')), findsNothing);
    });

    apiTest('manual on, Swahili: instructions and steps in Swahili', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', _manualOn);
      final host = await _pumpPayment(tester, api, lang: 'sw');
      expect(find.text('Tumia menyu ya Lipa kwa M-Pesa.'), findsOneWidget);
      expect(find.text(host.tr('manualPay.submit')), findsOneWidget);
      expect(host.tr('manualPay.submit'), isNot('Submit transaction ID'));
    });

    apiTest('a duplicate ID from the server shows under the field', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', _manualOn);
      api.fail('POST /me/subscribe', 409, {
        'error': 'payment_reference_duplicate',
      });
      final host = await _pumpPayment(tester, api);
      await tester.enterText(_idField, 'QJK3H7XY2P');
      await tapVisible(tester, _key('payment-submit'));
      expect(find.text(host.tr('manualPay.idDuplicate')), findsOneWidget);
    });

    apiTest('manual off: unchanged flow, no reference sent', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', _manualOff);
      api.on('POST /me/subscribe', {
        'subscription': {'id': 's1'},
        'paymentRequest': {'id': 'p1', 'amountTzs': 120000},
      });
      final host = await _pumpPayment(tester, api);
      expect(_key('manual-pay-steps'), findsNothing);
      expect(_key('manual-pay-transaction-id'), findsNothing);
      expect(find.text(host.tr('member.paymentBody')), findsOneWidget);
      expect(buttonLabelled(host.tr('member.requestPayment')), findsOneWidget);
      await tapVisible(tester, _key('payment-submit'));
      expect(api.only('POST', '/me/subscribe').body, {
        'tier': 'pro',
        'type': 'platform_pass',
      });
    });

    apiTest('no options block at all (older server): unchanged', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', {'enabled': false});
      final host = await _pumpPayment(tester, api);
      expect(_key('manual-pay-steps'), findsNothing);
      expect(buttonLabelled(host.tr('member.requestPayment')), findsOneWidget);
    });

    apiTest('options unreachable: unchanged', (tester, api) async {
      api.fail('GET /payments/options', 500);
      final host = await _pumpPayment(tester, api);
      expect(_key('manual-pay-steps'), findsNothing);
      expect(buttonLabelled(host.tr('member.requestPayment')), findsOneWidget);
    });

    apiTest('mobile money on (manual off): the button says Pay now', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', {'enabled': true, 'environment': 'live'});
      final host = await _pumpPayment(tester, api);
      expect(buttonLabelled(host.tr('momo.payNow')), findsOneWidget);
      expect(find.text(host.tr('momo.pageBody')), findsOneWidget);
    });
  });

  group('pending request', () {
    test('memberReference is read from the request', () {
      final p = PaymentRequest.fromJson({
        'id': 'p1',
        'memberReference': 'QJK3H7XY2P',
      });
      expect(p.memberReference, 'QJK3H7XY2P');
      expect(PaymentRequest.fromJson({'id': 'p2'}).memberReference, isNull);
    });

    apiTest('a request with a transaction ID gets no Pay now', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', {'enabled': true});
      final req = PaymentRequest.fromJson({
        'id': 'p1',
        'tier': 'pro',
        'productType': 'FITFLEX_PASS',
        'amountTzs': 120000,
        'memberReference': 'QJK3H7XY2P',
      });
      final host = await pumpPage(
        tester,
        api,
        PayNowButton(request: req),
        user: const {'id': 'm1', 'userType': 'member'},
      );
      expect(buttonLabelled(host.tr('momo.payNow')), findsNothing);
    });

    apiTest('without one, Pay now stays while mobile money is on', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', {'enabled': true});
      final req = PaymentRequest.fromJson({
        'id': 'p1',
        'tier': 'pro',
        'productType': 'FITFLEX_PASS',
        'amountTzs': 120000,
      });
      final host = await pumpPage(
        tester,
        api,
        PayNowButton(request: req),
        user: const {'id': 'm1', 'userType': 'member'},
      );
      expect(buttonLabelled(host.tr('momo.payNow')), findsOneWidget);
    });
  });

  group('errors', () {
    for (final (status, code) in const [
      (400, 'payment_reference_required'),
      (400, 'payment_reference_invalid'),
      (409, 'payment_reference_duplicate'),
      (409, 'manual_payment_submitted'),
    ]) {
      test('$code is explained in English and Swahili', () {
        final e = ApiException(status, {'error': code});
        final en = apiErrorMessage(FFLocale(), e);
        final sw = apiErrorMessage(FFLocale()..set(const Locale('sw')), e);
        expect(en, isNot(contains(code)));
        expect(sw, isNot(contains(code)));
        expect(sw, isNot(en));
      });
    }

    test('the three reference codes go under the field', () {
      expect(
        transactionIdServerErrorKey(
          ApiException(400, {'error': 'payment_reference_required'}),
        ),
        'manualPay.idRequired',
      );
      expect(
        transactionIdServerErrorKey(
          ApiException(400, {'error': 'payment_reference_invalid'}),
        ),
        'manualPay.idInvalid',
      );
      expect(
        transactionIdServerErrorKey(
          ApiException(409, {'error': 'payment_reference_duplicate'}),
        ),
        'manualPay.idDuplicate',
      );
      expect(
        transactionIdServerErrorKey(
          ApiException(409, {'error': 'payment_already_pending'}),
        ),
        isNull,
      );
    });

    test('every manualPay line has its own Swahili', () {
      final keys = FFLocale.keysOf(
        'en',
      ).where((k) => k.startsWith('manualPay.'));
      expect(keys.length, greaterThanOrEqualTo(15));
      for (final k in keys) {
        expect(FFLocale.textOf('sw', k), isNotNull, reason: k);
        if (k == 'manualPay.idHint') continue; // an example ID
        expect(
          FFLocale.textOf('sw', k),
          isNot(FFLocale.textOf('en', k)),
          reason: k,
        );
      }
    });
  });

  group('gym plan (direct_sub)', () {
    final gym = Gym.fromJson({
      'id': 'g1',
      'name': 'Mikocheni Fitness',
      'tier': 'standard',
      'location': 'Mikocheni',
      'perVisitRate': 5000,
      'commissionRate': 10,
      'status': 'active',
      'ratePerMonth': 90000,
    });

    apiTest('manual on: the ID is required and sent as reference', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', _manualOn);
      api.on('POST /me/subscribe', {
        'subscription': {'id': 's1'},
        'paymentRequest': {'id': 'p1', 'amountTzs': 90000},
      });
      final host = await pumpPage(
        tester,
        api,
        _SheetLauncher(gym),
        user: const {'id': 'm1', 'userType': 'member'},
        size: const Size(400, 1600),
      );
      await tapVisible(tester, _key('open-gym-plans'));
      expect(_key('gym-plan-manual-pay'), findsNothing); // no plan chosen yet
      await tapVisible(tester, _key('gym-plan-monthly'));
      expect(_key('gym-plan-manual-pay'), findsOneWidget);
      expect(buttonLabelled(host.tr('manualPay.submit')), findsOneWidget);
      await tapVisible(tester, _key('gym-plan-subscribe'));
      expect(find.text(host.tr('manualPay.idRequired')), findsOneWidget);
      expect(api.sent('POST', '/me/subscribe'), isFalse);
      await tester.enterText(_idField, 'MP241019.1234');
      await tapVisible(tester, _key('gym-plan-subscribe'));
      expect(api.only('POST', '/me/subscribe').body, {
        'type': 'direct_sub',
        'homeGymId': 'g1',
        'plan': 'monthly',
        'reference': 'MP241019.1234',
      });
    });

    apiTest('manual off: unchanged, no reference', (tester, api) async {
      api.on('GET /payments/options', _manualOff);
      api.on('POST /me/subscribe', {
        'subscription': {'id': 's1'},
        'paymentRequest': {'id': 'p1', 'amountTzs': 90000},
      });
      final host = await pumpPage(
        tester,
        api,
        _SheetLauncher(gym),
        user: const {'id': 'm1', 'userType': 'member'},
        size: const Size(400, 1600),
      );
      await tapVisible(tester, _key('open-gym-plans'));
      await tapVisible(tester, _key('gym-plan-monthly'));
      expect(_key('gym-plan-manual-pay'), findsNothing);
      expect(buttonLabelled(host.tr('member.subscribe')), findsOneWidget);
      await tapVisible(tester, _key('gym-plan-subscribe'));
      expect(api.only('POST', '/me/subscribe').body, {
        'type': 'direct_sub',
        'homeGymId': 'g1',
        'plan': 'monthly',
      });
    });
  });
}

/// Opens the gym plans sheet the way the app does, so it can close itself.
class _SheetLauncher extends StatelessWidget {
  const _SheetLauncher(this.gym);
  final Gym gym;

  @override
  Widget build(BuildContext context) => TextButton(
    key: const Key('open-gym-plans'),
    onPressed: () => showGymPlansSheet(context, gym),
    child: const Text('open'),
  );
}
