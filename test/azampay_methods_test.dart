// Three ways to pay through AzamPay (fitflex-functions#361, PAYMENTS_AZAMPAY.md
// "Three ways to pay"): GET /payments/options lists `methods`; with more than
// one usable here the pay sheet lets the member choose mobile money, bank
// checkout (CRDB / NMB with the bank's one-time code) or AzamPay's payment
// page. Without `methods` (an older server), or with mobile money only, the
// sheet is the mobile-money one exactly as before. Nothing is "paid" until
// the server's refresh says `completed`.
import 'package:fitflexmobile/screens/member/widgets/mobile_money_pay.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/rest_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_api.dart';

const _base = '/me/payments/pay_1';
const _pageUrl = 'https://checkout.azampay.example/pay/abc';

Map<String, dynamic> _options({
  List<String>? methods = const ['mobile_money', 'bank', 'page'],
  int maxAmountTzs = 5000000,
  List<String> banks = const ['CRDB', 'NMB'],
  List<String> returnTo = const ['app', 'web'],
  List<String> languages = const ['en', 'sw'],
}) => {
  'enabled': true,
  'provider': 'azampay',
  'environment': 'live',
  'methods': ?methods,
  if (methods?.contains('bank') ?? false)
    'bank': {'providers': banks, 'maxAmountTzs': maxAmountTzs},
  if (methods?.contains('page') ?? false)
    'page': {'returnTo': returnTo, 'languages': languages},
};

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic>? options,
  num amount = 60000,
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  SingleChildScrollView(
    child: MobileMoneyPayPanel(
      paymentRequestId: 'pay_1',
      amountTzs: amount,
      defaultPhone: '0754123456',
      provider: 'azampay',
      options: options,
      pollEvery: const Duration(seconds: 1),
    ),
  ),
  user: const {'id': 'm1', 'userType': 'member'},
  lang: lang,
  size: const Size(390, 1600),
);

Finder _key(String k) => find.byKey(Key(k));

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
  await tester.pump();
}

String _text(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: _key(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _fillBank(
  WidgetTester tester, {
  String bank = 'CRDB',
  String account = '0150123456789',
  String otp = '123456',
}) async {
  await _tap(tester, _key('momo-method-bank'));
  await _tap(tester, _key('momo-bank-$bank'));
  await typeInto(tester, _key('momo-bank-account'), account);
  await typeInto(tester, _key('momo-bank-otp'), otp);
}

void main() {
  late List<Uri> opened;
  late bool openOk;
  final savedOpener = momoOpenExternal;

  setUp(() {
    opened = [];
    openOk = true;
    momoOpenExternal = (uri) async {
      opened.add(uri);
      return openOk;
    };
  });
  tearDown(() => momoOpenExternal = savedOpener);

  group('which ways are offered', () {
    test('no `methods` (older server), or only mobile money: mobile money', () {
      expect(momoMethodsFor(null, 60000), ['mobile_money']);
      expect(momoMethodsFor(_options(methods: null), 60000), ['mobile_money']);
      expect(momoMethodsFor(_options(methods: ['mobile_money']), 60000), [
        'mobile_money',
      ]);
      expect(momoListsMethods(_options(methods: null)), isFalse);
      expect(momoListsMethods(_options(methods: ['mobile_money'])), isTrue);
    });

    test('all three, in the server\'s order; unknown ones are ignored', () {
      expect(momoMethodsFor(_options(), 60000), [
        'mobile_money',
        'bank',
        'page',
      ]);
      expect(
        momoMethodsFor({
          ..._options(),
          'methods': ['mobile_money', 'card', 'page'],
        }, 60000),
        ['mobile_money', 'page'],
      );
    });

    test('bank is hidden above its limit, and without a bank to choose', () {
      expect(momoMethodsFor(_options(maxAmountTzs: 50000), 60000), [
        'mobile_money',
        'page',
      ]);
      // At the limit it is still offered.
      expect(
        momoMethodsFor(_options(maxAmountTzs: 60000), 60000),
        contains('bank'),
      );
      expect(
        momoMethodsFor(_options(banks: const []), 60000),
        isNot(contains('bank')),
      );
      // Listed without its block: nothing to choose from.
      expect(
        momoMethodsFor({
          'enabled': true,
          'methods': ['mobile_money', 'bank'],
        }, 60000),
        ['mobile_money'],
      );
    });

    test('the page needs the server\'s `app` return target', () {
      expect(momoMethodsFor(_options(returnTo: const ['web']), 60000), [
        'mobile_money',
        'bank',
      ]);
      expect(
        momoMethodsFor(_options(returnTo: const ['app']), 60000),
        contains('page'),
      );
    });

    test('nothing usable falls back to mobile money (always on)', () {
      expect(momoMethodsFor(_options(methods: const []), 60000), [
        'mobile_money',
      ]);
    });

    test('the page language is the app\'s only when the server lists it', () {
      expect(momoPageLanguage(_options(), 'sw'), 'sw');
      expect(momoPageLanguage(_options(), 'en'), 'en');
      expect(momoPageLanguage(_options(languages: const ['en']), 'sw'), isNull);
      expect(momoPageLanguage(_options(methods: null), 'en'), isNull);
    });

    test('the bank account and one-time code follow the server\'s rules', () {
      for (final ok in ['01501', '0150123456789', 'AC-12/34 56', 'a' * 30]) {
        expect(looksLikeBankAccount(ok), isTrue, reason: ok);
      }
      for (final bad in ['', '1234', 'a' * 31, '0150_123', '0150#123']) {
        expect(looksLikeBankAccount(bad), isFalse, reason: bad);
      }
      for (final ok in ['1234', '123456', 'AB12cd', '1' * 12]) {
        expect(looksLikeBankOtp(ok), isTrue, reason: ok);
      }
      for (final bad in ['', '123', '1' * 13, '12 34', '12-34']) {
        expect(looksLikeBankOtp(bad), isFalse, reason: bad);
      }
    });

    test('only an https payment page is opened', () {
      expect(momoCheckoutUri(_pageUrl), Uri.parse(_pageUrl));
      for (final bad in [
        null,
        '',
        42,
        'http://checkout.azampay.example/pay',
        'javascript:alert(1)',
        'fitflex://pay',
        'https://',
        '/pay/abc',
      ]) {
        expect(momoCheckoutUri(bad), isNull, reason: '$bad');
      }
    });
  });

  group('the sheet as before', () {
    apiTest('older server (no `methods`): no choice, {phone, network}, and '
        'the mobile-money refresh', (tester, api) async {
      await _pump(tester, api, options: _options(methods: null));
      expect(_key('momo-method-mobile_money'), findsNothing);
      expect(_key('momo-method-bank'), findsNothing);
      expect(_key('momo-method-page'), findsNothing);
      expect(_key('momo-wallet-Mpesa'), findsOneWidget);
      await _tap(tester, find.textContaining('Send payment request'));
      expect(api.only('POST', '$_base/mobile-money').body, {
        'phone': '0754123456',
        'network': 'Mpesa',
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(api.sent('POST', '$_base/mobile-money/refresh'), isTrue);
      expect(api.sent('POST', '$_base/refresh'), isFalse);
    });

    apiTest('no options at all (a caller that passes none): the same', (
      tester,
      api,
    ) async {
      await _pump(tester, api);
      expect(_key('momo-method-bank'), findsNothing);
      await _tap(tester, find.textContaining('Send payment request'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(api.sent('POST', '$_base/mobile-money/refresh'), isTrue);
    });

    apiTest('only mobile money listed: no choice; the refresh for every '
        'method is used', (tester, api) async {
      await _pump(tester, api, options: _options(methods: ['mobile_money']));
      expect(_key('momo-method-mobile_money'), findsNothing);
      expect(find.text(FFLocale.textOf('en', 'momo.method')!), findsNothing);
      await _tap(tester, find.textContaining('Send payment request'));
      expect(api.only('POST', '$_base/mobile-money').body, {
        'phone': '0754123456',
        'network': 'Mpesa',
      });
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(api.sent('POST', '$_base/refresh'), isTrue);
      expect(api.sent('POST', '$_base/mobile-money/refresh'), isFalse);
    });
  });

  group('choosing how to pay', () {
    apiTest('three ways listed: three choices, mobile money first', (
      tester,
      api,
    ) async {
      final host = await _pump(tester, api, options: _options());
      expect(find.text(host.tr('momo.method')), findsOneWidget);
      for (final m in ['mobile_money', 'bank', 'page']) {
        expect(_key('momo-method-$m'), findsOneWidget);
      }
      expect(
        tester.widget<FFFilterChip>(_key('momo-method-mobile_money')).selected,
        isTrue,
      );
      // Mobile money is what it was: the number and the wallet.
      expect(_key('momo-wallet-Mpesa'), findsOneWidget);
      expect(_key('momo-bank-account'), findsNothing);
      expect(_key('momo-page-open'), findsNothing);

      await _tap(tester, _key('momo-method-bank'));
      expect(_key('momo-wallet-Mpesa'), findsNothing);
      expect(_key('momo-bank-account'), findsOneWidget);

      await _tap(tester, _key('momo-method-page'));
      expect(_key('momo-bank-account'), findsNothing);
      expect(_key('momo-page-open'), findsOneWidget);
    });

    apiTest('an amount above the bank limit hides the bank', (
      tester,
      api,
    ) async {
      await _pump(tester, api, options: _options(), amount: 5000001);
      expect(_key('momo-method-bank'), findsNothing);
      expect(_key('momo-method-mobile_money'), findsOneWidget);
      expect(_key('momo-method-page'), findsOneWidget);
    });

    apiTest('a page that cannot return to the app is not offered', (
      tester,
      api,
    ) async {
      await _pump(tester, api, options: _options(returnTo: const ['web']));
      expect(_key('momo-method-page'), findsNothing);
      expect(_key('momo-method-bank'), findsOneWidget);
    });
  });

  group('bank checkout', () {
    apiTest('the steps for the chosen bank; nothing is sent until every '
        'entry is valid', (tester, api) async {
      final host = await _pump(tester, api, options: _options());
      await _tap(tester, _key('momo-method-bank'));
      expect(_key('momo-bank-CRDB'), findsOneWidget);
      expect(_key('momo-bank-NMB'), findsOneWidget);
      // No bank chosen yet: no steps.
      expect(_key('momo-bank-steps'), findsNothing);

      await _tap(tester, _key('momo-bank-pay'));
      expect(find.text(host.tr('momo.bank.chooseBank')), findsOneWidget);
      expect(
        find.text(host.tr('error.reason.invalidAccountNumber')),
        findsOneWidget,
      );
      expect(find.text(host.tr('error.reason.invalidOtp')), findsOneWidget);
      expect(api.sent('POST', '$_base/bank'), isFalse);

      await _tap(tester, _key('momo-bank-CRDB'));
      expect(find.text(host.tr('momo.bank.chooseBank')), findsNothing);
      expect(find.textContaining('*150*03#'), findsOneWidget);
      expect(find.textContaining('SIM Banking PIN'), findsOneWidget);
      expect(find.textContaining('7 Other services'), findsOneWidget);
      expect(find.textContaining('5 AzamPay'), findsOneWidget);
      expect(find.textContaining('Link AzamPay Account'), findsOneWidget);

      await _tap(tester, _key('momo-bank-NMB'));
      expect(find.textContaining('*150*03#'), findsNothing);
      expect(find.textContaining('*150*66#'), findsOneWidget);
      expect(find.textContaining('8 More'), findsOneWidget);
      expect(find.textContaining('5 Register Sarafu'), findsOneWidget);
      expect(find.textContaining('1 Select Account No'), findsOneWidget);

      // A code that is too short, and a number that is not a mobile number.
      await typeInto(tester, _key('momo-bank-account'), '0150123456789');
      await typeInto(tester, _key('momo-bank-otp'), '12');
      await typeInto(tester, _key('momo-bank-phone'), '12345');
      await _tap(tester, _key('momo-bank-pay'));
      expect(find.text(host.tr('error.reason.invalidOtp')), findsOneWidget);
      expect(find.text(host.tr('error.reason.invalidPhone')), findsOneWidget);
      expect(api.sent('POST', '$_base/bank'), isFalse);
    });

    apiTest('the code is hidden as it is typed', (tester, api) async {
      await _pump(tester, api, options: _options());
      await _tap(tester, _key('momo-method-bank'));
      final otp = tester.widget<EditableText>(
        find.descendant(
          of: _key('momo-bank-otp'),
          matching: find.byType(EditableText),
        ),
      );
      expect(otp.obscureText, isTrue);
    });

    apiTest('submit: the exact body, the code is cleared, then the refresh '
        'for every method until completed', (tester, api) async {
      var polls = 0;
      api.on('POST $_base/bank', {'state': 'in_progress', 'method': 'bank'});
      api.onCall(
        'POST $_base/refresh',
        (_) => {'state': ++polls < 2 ? 'in_progress' : 'completed'},
      );
      final host = await _pump(tester, api, options: _options());
      await _fillBank(tester);
      await _tap(tester, _key('momo-bank-pay'));
      expect(api.only('POST', '$_base/bank').body, {
        'bank': 'CRDB',
        'accountNumber': '0150123456789',
        'phone': '0754123456',
        'otp': '123456',
      });
      expect(find.text(host.tr('momo.bank.waitingTitle')), findsOneWidget);
      // Sending is not paying.
      expect(find.text(host.tr('momo.successTitle')), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text(host.tr('momo.bank.waitingTitle')), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text(host.tr('momo.successTitle')), findsOneWidget);
      expect(api.sent('POST', '$_base/mobile-money/refresh'), isFalse);
      expect(api.sent('POST', '$_base/mobile-money'), isFalse);
    });

    apiTest('a wrong code (422 provider_rejected): says what to check, the '
        'code is cleared, the rest is kept', (tester, api) async {
      api.fail('POST $_base/bank', 422, {'error': 'provider_rejected'});
      final host = await _pump(tester, api, options: _options());
      await _fillBank(tester, bank: 'NMB');
      await _tap(tester, _key('momo-bank-pay'));
      expect(api.only('POST', '$_base/bank').body, {
        'bank': 'NMB',
        'accountNumber': '0150123456789',
        'phone': '0754123456',
        'otp': '123456',
      });
      expect(find.text(host.tr('momo.bank.rejected')), findsOneWidget);
      expect(_text(tester, 'momo-bank-otp'), isEmpty);
      expect(_text(tester, 'momo-bank-account'), '0150123456789');
      expect(
        tester.widget<FFFilterChip>(_key('momo-bank-NMB')).selected,
        isTrue,
      );
      // A new code can be sent.
      api.heal('POST $_base/bank');
      api.on('POST $_base/bank', {'state': 'in_progress'});
      await typeInto(tester, _key('momo-bank-otp'), '654321');
      await _tap(tester, _key('momo-bank-pay'));
      expect(api.where('POST', '$_base/bank'), hasLength(2));
      expect(
        (api.where('POST', '$_base/bank')[1].body as Map)['otp'],
        '654321',
      );
      expect(find.text(host.tr('momo.bank.waitingTitle')), findsOneWidget);
    });

    for (final (status, code, where) in const [
      (400, 'invalid_otp', 'error.reason.invalidOtp'),
      (400, 'invalid_account_number', 'error.reason.invalidAccountNumber'),
      (400, 'invalid_bank', 'error.reason.invalidBank'),
      (400, 'invalid_phone', 'error.reason.invalidPhone'),
      (409, 'amount_over_bank_limit', 'error.reason.amountOverBankLimit'),
      (409, 'bank_attempts_exhausted', 'error.reason.bankAttemptsExhausted'),
      (429, 'too_many_attempts', 'error.reason.tooManyAttempts'),
      (503, 'provider_unavailable', 'error.reason.providerUnavailable'),
      (409, 'payment_not_pending', 'error.reason.paymentNotPending'),
    ]) {
      apiTest('$status $code is shown in words, and the code is cleared', (
        tester,
        api,
      ) async {
        api.fail('POST $_base/bank', status, {'error': code});
        final host = await _pump(tester, api, options: _options());
        await _fillBank(tester);
        await _tap(tester, _key('momo-bank-pay'));
        expect(find.textContaining(host.tr(where)), findsOneWidget);
        expect(find.textContaining(code), findsNothing);
        expect(_text(tester, 'momo-bank-otp'), isEmpty);
        // Back on the form, not waiting.
        expect(_key('momo-bank-pay'), findsOneWidget);
      });
    }

    apiTest('choosing another way drops a code that was typed', (
      tester,
      api,
    ) async {
      await _pump(tester, api, options: _options());
      await _fillBank(tester);
      await _tap(tester, _key('momo-method-mobile_money'));
      await _tap(tester, _key('momo-method-bank'));
      expect(_text(tester, 'momo-bank-otp'), isEmpty);
    });

    apiTest('a bank attempt that ended: its own words, and try again', (
      tester,
      api,
    ) async {
      api.on('POST $_base/bank', {'state': 'in_progress'});
      api.on('POST $_base/refresh', {'state': 'none'});
      final host = await _pump(tester, api, options: _options());
      await _fillBank(tester);
      await _tap(tester, _key('momo-bank-pay'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(find.text(host.tr('momo.bank.endedBody')), findsOneWidget);
      expect(find.text(host.tr('momo.endedBody')), findsNothing);
      await _tap(tester, _key('momo-send-again'));
      expect(_key('momo-bank-pay'), findsOneWidget);
      expect(_text(tester, 'momo-bank-otp'), isEmpty);
    });

    test('the code and the account number never reach the debug log', () {
      final line = redactBody(
        '{"bank":"CRDB","accountNumber":"0150123456789",'
        '"phone":"0712000000","otp":"123456"}',
        path: '/me/payments/pay_1/bank',
      );
      expect(line, isNot(contains('123456"')));
      expect(line, isNot(contains('0150123456789')));
      expect(line, contains('"otp":"<redacted>"'));
      expect(line, contains('"accountNumber":"<redacted>"'));
    });
  });

  group('AzamPay\'s payment page', () {
    Future<void> resume(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
    }

    apiTest('open: returnTo app and the app language, the page opens in '
        'the browser, and coming back is not paying', (tester, api) async {
      var state = 'in_progress';
      api.on('POST $_base/checkout-page', {
        'state': 'in_progress',
        'method': 'page',
        'checkoutUrl': _pageUrl,
      });
      api.onCall(
        'POST $_base/refresh',
        (_) => {
          'state': state,
          if (state == 'in_progress') 'checkoutUrl': _pageUrl,
        },
      );
      final host = await _pump(tester, api, options: _options());
      await _tap(tester, _key('momo-method-page'));
      await _tap(tester, _key('momo-page-open'));
      expect(api.only('POST', '$_base/checkout-page').body, {
        'returnTo': 'app',
        'language': 'en',
      });
      expect(opened, [Uri.parse(_pageUrl)]);
      expect(find.text(host.tr('momo.page.waitingTitle')), findsOneWidget);
      expect(find.text(host.tr('momo.successTitle')), findsNothing);

      // No timer for a page: nothing is asked until the app comes back.
      await tester.pump(const Duration(seconds: 5));
      expect(api.sent('POST', '$_base/refresh'), isFalse);

      // Back from the browser, not paid yet: still waiting.
      await resume(tester);
      expect(api.where('POST', '$_base/refresh'), hasLength(1));
      expect(find.text(host.tr('momo.page.waitingTitle')), findsOneWidget);
      expect(find.text(host.tr('momo.successTitle')), findsNothing);

      // The same page can be opened again; no second attempt is made.
      await _tap(tester, _key('momo-page-reopen'));
      expect(opened, [Uri.parse(_pageUrl), Uri.parse(_pageUrl)]);
      expect(api.where('POST', '$_base/checkout-page'), hasLength(1));

      // Only the server's `completed` is a payment.
      state = 'completed';
      await _tap(tester, _key('momo-check-now'));
      expect(find.text(host.tr('momo.successTitle')), findsOneWidget);
      expect(api.sent('POST', '$_base/mobile-money/refresh'), isFalse);
    });

    apiTest('coming back refreshes; completed then shows as paid', (
      tester,
      api,
    ) async {
      api.on('POST $_base/checkout-page', {'checkoutUrl': _pageUrl});
      api.on('POST $_base/refresh', {'state': 'completed'});
      final host = await _pump(tester, api, options: _options());
      await _tap(tester, _key('momo-method-page'));
      await _tap(tester, _key('momo-page-open'));
      expect(find.text(host.tr('momo.successTitle')), findsNothing);
      await resume(tester);
      expect(find.text(host.tr('momo.successTitle')), findsOneWidget);
    });

    apiTest('Swahili app: the page is asked for in Swahili', (
      tester,
      api,
    ) async {
      api.on('POST $_base/checkout-page', {'checkoutUrl': _pageUrl});
      await _pump(tester, api, options: _options(), lang: 'sw');
      await _tap(tester, _key('momo-method-page'));
      await _tap(tester, _key('momo-page-open'));
      expect(api.only('POST', '$_base/checkout-page').body, {
        'returnTo': 'app',
        'language': 'sw',
      });
    });

    apiTest('a language the server does not list is not sent', (
      tester,
      api,
    ) async {
      api.on('POST $_base/checkout-page', {'checkoutUrl': _pageUrl});
      await _pump(
        tester,
        api,
        options: _options(languages: const ['en']),
        lang: 'sw',
      );
      await _tap(tester, _key('momo-method-page'));
      await _tap(tester, _key('momo-page-open'));
      expect(api.only('POST', '$_base/checkout-page').body, {
        'returnTo': 'app',
      });
    });

    apiTest('an address that is not https is never opened', (
      tester,
      api,
    ) async {
      api.on('POST $_base/checkout-page', {
        'checkoutUrl': 'http://checkout.azampay.example/pay/abc',
      });
      final host = await _pump(tester, api, options: _options());
      await _tap(tester, _key('momo-method-page'));
      await _tap(tester, _key('momo-page-open'));
      expect(opened, isEmpty);
      expect(find.text(host.tr('momo.page.openFailed')), findsOneWidget);
      expect(_key('momo-page-open'), findsOneWidget);
    });

    apiTest('the browser could not be opened: says so, and can try again', (
      tester,
      api,
    ) async {
      api.on('POST $_base/checkout-page', {'checkoutUrl': _pageUrl});
      openOk = false;
      final host = await _pump(tester, api, options: _options());
      await _tap(tester, _key('momo-method-page'));
      await _tap(tester, _key('momo-page-open'));
      expect(find.text(host.tr('momo.page.openFailed')), findsOneWidget);
      openOk = true;
      await _tap(tester, _key('momo-page-reopen'));
      expect(opened, hasLength(2));
      expect(find.text(host.tr('momo.page.openFailed')), findsNothing);
    });

    for (final (status, code, where) in const [
      (409, 'return_not_configured', 'error.reason.pageUnavailable'),
      (400, 'invalid_return_to', 'error.reason.pageUnavailable'),
      (400, 'invalid_language', 'error.reason.pageUnavailable'),
      (422, 'provider_rejected', 'error.reason.providerRejected'),
      (429, 'too_many_attempts', 'error.reason.tooManyAttempts'),
      (409, 'not_payable_this_way', 'error.reason.notPayableThisWay'),
    ]) {
      apiTest('$status $code is shown in words; nothing is opened', (
        tester,
        api,
      ) async {
        api.fail('POST $_base/checkout-page', status, {'error': code});
        final host = await _pump(tester, api, options: _options());
        await _tap(tester, _key('momo-method-page'));
        await _tap(tester, _key('momo-page-open'));
        expect(find.textContaining(host.tr(where)), findsOneWidget);
        expect(opened, isEmpty);
        expect(_key('momo-page-open'), findsOneWidget);
      });
    }

    apiTest('a page that is no longer open: its own words, and open again', (
      tester,
      api,
    ) async {
      api.on('POST $_base/checkout-page', {'checkoutUrl': _pageUrl});
      api.on('POST $_base/refresh', {'state': 'none'});
      final host = await _pump(tester, api, options: _options());
      await _tap(tester, _key('momo-method-page'));
      await _tap(tester, _key('momo-page-open'));
      await _tap(tester, _key('momo-check-now'));
      expect(find.text(host.tr('momo.page.endedBody')), findsOneWidget);
      await _tap(tester, _key('momo-send-again'));
      expect(_key('momo-page-open'), findsOneWidget);
    });
  });

  group('wording', () {
    for (final code in [
      'invalid_bank',
      'invalid_account_number',
      'invalid_otp',
      'amount_over_bank_limit',
      'bank_attempts_exhausted',
      'return_not_configured',
      'invalid_return_to',
      'invalid_language',
      'provider_rejected',
      'provider_unavailable',
    ]) {
      test('$code is explained in English and Swahili', () {
        final e = ApiException(409, {'error': code});
        final en = apiErrorMessage(FFLocale(), e);
        final sw = apiErrorMessage(FFLocale()..set(const Locale('sw')), e);
        expect(en, isNot(contains(code)));
        expect(sw, isNot(contains(code)));
        expect(sw, isNot(en));
      });
    }

    test('new Swahili is a marked placeholder until a native review', () {
      final keys = FFLocale.keysOf('en').where(
        (k) =>
            k == 'momo.method' ||
            k.startsWith('momo.method.') ||
            k.startsWith('momo.bank.') ||
            k.startsWith('momo.page.') ||
            k == 'momo.checkNowPlain' ||
            const {
              'error.reason.invalidBank',
              'error.reason.invalidAccountNumber',
              'error.reason.invalidOtp',
              'error.reason.amountOverBankLimit',
              'error.reason.pageUnavailable',
            }.contains(k),
      );
      expect(keys.length, 32);
      for (final k in keys) {
        expect(
          FFLocale.textOf('sw', k),
          '[SW-PENDING] ${FFLocale.textOf('en', k)}',
          reason: k,
        );
      }
    });

    test('the bank steps are the documented ones', () {
      expect(
        FFLocale.textOf('en', 'momo.bank.steps.CRDB'),
        allOf(
          contains('*150*03#'),
          contains('SIM Banking PIN'),
          contains('7 Other services'),
          contains('5 AzamPay'),
          contains('Link AzamPay Account'),
        ),
      );
      expect(
        FFLocale.textOf('en', 'momo.bank.steps.NMB'),
        allOf(
          contains('*150*66#'),
          contains('8 More'),
          contains('5 Register Sarafu'),
          contains('1 Select Account No'),
        ),
      );
    });
  });
}
