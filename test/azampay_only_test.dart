// AzamPay is FitFlex's only payment method (owner decision 2026-11-17,
// fitflex-functions#360): members no longer pay a Lipa Namba by hand and type
// a transaction ID. GET /payments/options has no `manual` block, and
// POST /me/subscribe, /me/upgrade and /me/gym-pass-purchases ignore
// `reference` / `payerPhone`, so the app never asks for or sends them. A
// request paid by hand before the change still shows its transaction ID.
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_plans_sheet.dart';
import 'package:fitflexmobile/screens/member/widgets/mobile_money_pay.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_api.dart';

/// What a server from before the change may still send: a `manual` block
/// that is switched on. The app must not act on it.
const _oldManualBlock = {
  'enabled': false,
  'manual': {
    'enabled': true,
    'lipaNamba': '5123456',
    'accountName': 'FitFlex Africa Ltd',
    'network': 'M-Pesa',
    'referenceRequired': true,
    'payerPhoneRequired': true,
  },
};

const _azampayOn = {
  'enabled': true,
  'provider': 'azampay',
  'environment': 'live',
};

MemberData _data() => MemberData()
  ..selectedTier = 'pro'
  ..passes = [PassTier(id: 'pro', price: 120000, visitCap: 12)]
  ..me = MemberMeResponse.fromJson({
    'user': {
      'id': 'm1',
      'displayName': 'Amina',
      'onboardingCompleted': true,
      'phone': '0754123456',
    },
  });

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

void _expectNoPayByHand() {
  expect(_key('manual-pay-steps'), findsNothing);
  expect(_key('manual-pay-transaction-id'), findsNothing);
  expect(_key('manual-pay-payer-phone'), findsNothing);
}

void main() {
  group('FitFlex Pass payment page', () {
    apiTest('a leftover manual block is ignored: no steps, no ID, the body '
        'is just the tier', (tester, api) async {
      api.on('GET /payments/options', _oldManualBlock);
      api.on('POST /me/subscribe', {
        'subscription': {'id': 's1'},
        'paymentRequest': {'id': 'p1', 'amountTzs': 120000},
      });
      final host = await _pumpPayment(tester, api);
      _expectNoPayByHand();
      expect(find.text(host.tr('member.paymentBody')), findsOneWidget);
      expect(buttonLabelled(host.tr('member.requestPayment')), findsOneWidget);
      await tapVisible(tester, _key('payment-submit'));
      expect(api.only('POST', '/me/subscribe').body, {
        'tier': 'pro',
        'type': 'platform_pass',
      });
    });

    apiTest('AzamPay on: Pay now, then the wallet sheet for the request', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', _azampayOn);
      api.on('POST /me/subscribe', {
        'subscription': {'id': 's1'},
        'paymentRequest': {'id': 'p1', 'amountTzs': 120000},
      });
      final host = await _pumpPayment(tester, api);
      _expectNoPayByHand();
      expect(buttonLabelled(host.tr('momo.payNow')), findsOneWidget);
      expect(find.text(host.tr('momo.pageBody')), findsOneWidget);
      // The button keeps its spinner while the sheet is open: pump by hand.
      await tester.ensureVisible(_key('payment-submit'));
      await tester.tap(_key('payment-submit'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(api.only('POST', '/me/subscribe').body, {
        'tier': 'pro',
        'type': 'platform_pass',
      });
      expect(find.text(host.tr('momo.title')), findsOneWidget);
      expect(_key('momo-wallet-Mpesa'), findsOneWidget);
    });

    apiTest('mobile money off: the request staff approve, as before', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', {'enabled': false});
      final host = await _pumpPayment(tester, api);
      _expectNoPayByHand();
      expect(buttonLabelled(host.tr('member.requestPayment')), findsOneWidget);
    });

    apiTest('options unreachable: the same', (tester, api) async {
      api.fail('GET /payments/options', 500);
      final host = await _pumpPayment(tester, api);
      _expectNoPayByHand();
      expect(buttonLabelled(host.tr('member.requestPayment')), findsOneWidget);
    });
  });

  group('upgrade', () {
    apiTest('a leftover manual block is ignored: the body is just the tier', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', _oldManualBlock);
      api.on('GET /me/upgrade-options', {
        'current': {'tier': 'basic', 'priceTzs': 50000},
        'options': [
          {'tier': 'pro', 'differenceTzs': 40000, 'gymAccess': 'standard'},
        ],
      });
      api.on('POST /me/upgrade', {
        'paymentRequest': {'id': 'p1', 'amountTzs': 40000},
      });
      final data = MemberData()
        ..passes = [PassTier(id: 'pro', price: 120000, visitCap: 12)]
        ..passesLoaded = true
        ..me = MemberMeResponse.fromJson({
          'user': {'id': 'm1', 'displayName': 'Amina'},
          'subscription': {
            'id': 's1',
            'type': 'platform_pass',
            'tier': 'basic',
            'status': 'active',
            'expiresAt': DateTime.now()
                .add(const Duration(days: 20))
                .toUtc()
                .toIso8601String(),
          },
        });
      final host = await pumpPage(
        tester,
        api,
        MemberDataScope(data: data, child: const MemberPassesPage()),
        user: const {'id': 'm1', 'userType': 'member'},
        size: const Size(400, 1600),
      );
      await tapVisible(tester, find.text(host.tr('pass.pro')));
      expect(_key('upgrade-manual-pay'), findsNothing);
      _expectNoPayByHand();
      // The button names the difference, not "Submit transaction ID".
      expect(
        buttonLabelled(
          host.tr('upgrade.pay').replaceFirst('{amount}', 'TSh 40,000'),
        ),
        findsOneWidget,
      );
      await tapVisible(tester, _key('upgrade-submit'));
      expect(api.only('POST', '/me/upgrade').body, {'tier': 'pro'});
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

    apiTest('a leftover manual block is ignored: no ID, no reference', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', _oldManualBlock);
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
      _expectNoPayByHand();
      expect(buttonLabelled(host.tr('member.subscribe')), findsOneWidget);
      await tapVisible(tester, _key('gym-plan-subscribe'));
      expect(api.only('POST', '/me/subscribe').body, {
        'type': 'direct_sub',
        'homeGymId': 'g1',
        'plan': 'monthly',
      });
    });
  });

  group('a request paid by hand before the change', () {
    test('its transaction ID and paying number are still read', () {
      final p = PaymentRequest.fromJson({
        'id': 'p1',
        'memberReference': 'QJK3H7XY2P',
        'payerPhone': '+255754111222',
      });
      expect(p.memberReference, 'QJK3H7XY2P');
      expect(p.payerPhone, '+255754111222');
      expect(PaymentRequest.fromJson({'id': 'p2'}).memberReference, isNull);
    });

    apiTest('My QR shows the transaction ID and the paying number', (
      tester,
      api,
    ) async {
      final data = MemberData()
        ..me = MemberMeResponse.fromJson({
          'user': {'id': 'm1', 'displayName': 'Amina'},
          'pendingPayment': {
            'id': 'p1',
            'tier': 'pro',
            'status': 'pending',
            'amountTzs': 120000,
            'memberReference': 'QJK3H7XY2P',
            'payerPhone': '+255754111222',
          },
        });
      final host = await pumpPage(
        tester,
        api,
        MemberDataScope(data: data, child: const MemberQrTab()),
        user: const {'id': 'm1', 'userType': 'member'},
        size: const Size(400, 1600),
      );
      expect(
        find.text(
          host.tr('manualPay.idShown').replaceAll('{id}', 'QJK3H7XY2P'),
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          host
              .tr('manualPay.paidFromShown')
              .replaceAll('{phone}', '+255754111222'),
        ),
        findsOneWidget,
      );
    });

    apiTest('it gets no Pay now (409 manual_payment_submitted otherwise)', (
      tester,
      api,
    ) async {
      api.on('GET /payments/options', _azampayOn);
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

    apiTest('a request without one keeps Pay now', (tester, api) async {
      api.on('GET /payments/options', _azampayOn);
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

    test('the labels that show it keep their Swahili', () {
      for (final k in [
        'manualPay.idLabel',
        'manualPay.idShown',
        'manualPay.paidFrom',
        'manualPay.paidFromShown',
      ]) {
        expect(FFLocale.textOf('en', k), isNotNull, reason: k);
        expect(FFLocale.textOf('sw', k), isNotNull, reason: k);
        expect(
          FFLocale.textOf('sw', k),
          isNot(FFLocale.textOf('en', k)),
          reason: k,
        );
      }
    });
  });

  group('wording', () {
    test('no pay-by-hand instructions are left in either language', () {
      const kept = {
        'manualPay.idLabel',
        'manualPay.idShown',
        'manualPay.paidFrom',
        'manualPay.paidFromShown',
      };
      for (final lang in ['en', 'sw']) {
        final keys = FFLocale.keysOf(lang);
        expect(
          keys.where((k) => k.startsWith('manualPay.')).toSet(),
          kept,
          reason: lang,
        );
        expect(
          keys.where((k) => k.startsWith('events.pay.manual.')),
          isEmpty,
          reason: lang,
        );
      }
    });

    for (final (status, code) in const [
      (409, 'manual_payment_submitted'),
      (429, 'too_many_attempts'),
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

    test('Swahili says mobile money the glossary way (mtandao wa simu)', () {
      for (final k in FFLocale.keysOf('sw')) {
        expect(
          FFLocale.textOf('sw', k),
          isNot(contains('pesa ya simu')),
          reason: k,
        );
      }
      expect(
        FFLocale.textOf('sw', 'momo.pageBody'),
        contains('mtandao wa simu'),
      );
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
