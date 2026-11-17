// AzamPay (fitflex-functions#357), dormant on the server: the wallet choice
// in the shared pay sheet (only when GET /payments/options says
// provider=azampay) and the "your next plan" card for renewals paid early
// (GET /me.scheduledRenewals, SCHEDULED_RENEWALS).
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/mobile_money_pay.dart';
import 'package:fitflexmobile/screens/member/widgets/scheduled_renewals_card.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/formatters.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_api.dart';

const _payPath = '/me/payments/pay_1/mobile-money';

Widget _panel({String? provider, String phone = '0754123456'}) =>
    SingleChildScrollView(
      child: MobileMoneyPayPanel(
        paymentRequestId: 'pay_1',
        amountTzs: 60000,
        defaultPhone: phone,
        provider: provider,
        pollEvery: const Duration(seconds: 1),
      ),
    );

Future<PageHost> _pumpPanel(
  WidgetTester tester,
  RecordingApi api, {
  String? provider,
  String phone = '0754123456',
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  _panel(provider: provider, phone: phone),
  user: const {'id': 'm1', 'userType': 'member'},
  lang: lang,
  size: const Size(390, 900),
);

Future<void> _send(WidgetTester tester) async {
  await tester.tap(find.textContaining('Send payment request'));
  await tester.pump();
  await tester.pump();
}

bool _chosen(WidgetTester tester, String wallet) => tester
    .widget<FFFilterChip>(find.byKey(Key('momo-wallet-$wallet')))
    .selected;

void main() {
  group('wallet guess from the number (ASSUMPTION: TCRA prefixes)', () {
    test('known prefixes, in every usual spelling', () {
      const cases = {
        '0754123456': 'Mpesa',
        '0745 123 456': 'Mpesa',
        '+255 762 123 456': 'Mpesa',
        '0712345678': 'Tigo',
        '0652345678': 'Tigo',
        '0672345678': 'Tigo',
        '255772345678': 'Tigo',
        '0682345678': 'Airtel',
        '0692345678': 'Airtel',
        '782345678': 'Airtel',
        '0612345678': 'Halopesa',
        '0622345678': 'Halopesa',
      };
      cases.forEach((phone, wallet) {
        expect(momoWalletGuess(phone), wallet, reason: phone);
      });
    });

    test('no guess for unknown ranges, short input or AzamPesa', () {
      for (final phone in ['', '0', '07', '0792345678', '0732345678']) {
        expect(momoWalletGuess(phone), isNull, reason: phone);
      }
      // AzamPesa is a wallet, not a number range: it is only ever picked.
      expect(momoWallets, contains('Azampesa'));
    });
  });

  group('pay sheet', () {
    apiTest('another provider name: no wallet choice, the body is {phone}', (
      tester,
      api,
    ) async {
      await _pumpPanel(tester, api, provider: 'other');
      expect(find.text(FFLocale.textOf('en', 'momo.wallet')!), findsNothing);
      expect(find.byKey(const Key('momo-wallet-Mpesa')), findsNothing);
      await _send(tester);
      expect(api.only('POST', _payPath).body, {'phone': '0754123456'});
    });

    apiTest('no provider named (older server): unchanged as well', (
      tester,
      api,
    ) async {
      await _pumpPanel(tester, api);
      expect(find.byKey(const Key('momo-wallet-Mpesa')), findsNothing);
      await _send(tester);
      expect(api.only('POST', _payPath).body, {'phone': '0754123456'});
    });

    apiTest('AzamPay: the guessed wallet is chosen and sent', (
      tester,
      api,
    ) async {
      await _pumpPanel(tester, api, provider: 'azampay');
      for (final w in momoWallets) {
        expect(find.byKey(Key('momo-wallet-$w')), findsOneWidget, reason: w);
      }
      expect(find.text('M-Pesa'), findsOneWidget);
      expect(find.text('AzamPesa'), findsOneWidget);
      expect(_chosen(tester, 'Mpesa'), isTrue);
      await _send(tester);
      expect(api.only('POST', _payPath).body, {
        'phone': '0754123456',
        'network': 'Mpesa',
      });
    });

    apiTest('AzamPay: typing re-guesses until the member picks', (
      tester,
      api,
    ) async {
      await _pumpPanel(tester, api, provider: 'azampay');
      await tester.enterText(find.byType(TextField), '0682345678');
      await tester.pump();
      expect(_chosen(tester, 'Airtel'), isTrue);
      expect(_chosen(tester, 'Mpesa'), isFalse);

      // The member's own choice wins and later typing leaves it alone.
      await tester.tap(find.byKey(const Key('momo-wallet-Azampesa')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '0712345678');
      await tester.pump();
      expect(_chosen(tester, 'Azampesa'), isTrue);
      expect(_chosen(tester, 'Tigo'), isFalse);
      await _send(tester);
      expect(api.only('POST', _payPath).body, {
        'phone': '0712345678',
        'network': 'Azampesa',
      });
    });

    apiTest('AzamPay: no wallet known asks for one before sending', (
      tester,
      api,
    ) async {
      final host = await _pumpPanel(
        tester,
        api,
        provider: 'azampay',
        phone: '0792345678',
      );
      for (final w in momoWallets) {
        expect(_chosen(tester, w), isFalse, reason: w);
      }
      await _send(tester);
      expect(api.sent('POST', _payPath), isFalse);
      expect(
        find.text(host.tr('error.reason.networkRequired')),
        findsOneWidget,
      );
    });

    apiTest('AzamPay: 400 network_required asks to pick the wallet', (
      tester,
      api,
    ) async {
      api.fail('POST $_payPath', 400, {'error': 'network_required'});
      final host = await _pumpPanel(tester, api, provider: 'azampay');
      await _send(tester);
      expect(api.where('POST', _payPath), hasLength(1));
      expect(
        find.text(host.tr('error.reason.networkRequired')),
        findsOneWidget,
      );
      // Back on the number step, ready to try again.
      expect(find.textContaining('Send payment request'), findsOneWidget);
    });
  });

  group('error reasons', () {
    final en = FFLocale();
    test('renewal_already_scheduled and network_required have wording', () {
      expect(
        apiErrorMessage(
          en,
          ApiException(409, {'error': 'renewal_already_scheduled'}),
        ),
        contains(
          'You already have a renewal waiting. It starts when your current '
          'plan ends.',
        ),
      );
      expect(
        apiErrorMessage(en, ApiException(400, {'error': 'network_required'})),
        contains('Choose the mobile money wallet you are paying from'),
      );
    });
  });

  group('GET /me scheduledRenewals', () {
    Map<String, dynamic> me([Object? renewals, bool include = true]) => {
      'user': {'id': 'm1'},
      'visitsUsed': 0,
      'scheduledRenewals': ?(include ? renewals : null),
    };

    test('parsed when present, soonest first as sent', () {
      final out = MemberMeResponse.fromJson(
        me([
          {
            'id': 'sub_a',
            'type': 'platform_pass',
            'tier': 'premium',
            'plan': null,
            'homeGymId': null,
            'startsAt': '2026-12-01T09:00:00.000Z',
            'expiresAt': '2026-12-31T09:00:00.000Z',
          },
          {
            'id': 'sub_b',
            'type': 'direct_sub',
            'tier': null,
            'plan': 'monthly',
            'homeGymId': 'g1',
            'startsAt': '2026-12-10T09:00:00.000Z',
            'expiresAt': '2027-01-09T09:00:00.000Z',
          },
          'not a map',
        ]),
      );
      expect(out.scheduledRenewals, hasLength(2));
      final a = out.scheduledRenewals.first;
      expect(a.id, 'sub_a');
      expect(a.type, 'platform_pass');
      expect(a.tier, 'premium');
      expect(a.isGymPlan, isFalse);
      expect(a.startsAt, '2026-12-01T09:00:00.000Z');
      final b = out.scheduledRenewals.last;
      expect(b.isGymPlan, isTrue);
      expect(b.homeGymId, 'g1');
      expect(b.plan, 'monthly');
    });

    test('absent, null or not a list: empty', () {
      expect(MemberMeResponse.fromJson(me()).scheduledRenewals, isEmpty);
      expect(
        MemberMeResponse.fromJson(me(null, false)).scheduledRenewals,
        isEmpty,
      );
      expect(MemberMeResponse.fromJson(me('x')).scheduledRenewals, isEmpty);
      expect(
        MemberMeResponse.fromJson(me(const [])).scheduledRenewals,
        isEmpty,
      );
    });
  });

  group('next plan card', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    final gym = Gym.fromJson({
      'id': 'g1',
      'name': 'Iron Paradise',
      'tier': 'standard',
      'status': 'active',
    });
    ScheduledRenewal pass() => ScheduledRenewal(
      id: 'sub_a',
      type: 'platform_pass',
      tier: 'premium',
      startsAt: '2026-12-01T09:00:00.000Z',
    );
    ScheduledRenewal gymPlan(String gymId) => ScheduledRenewal(
      id: 'sub_$gymId',
      type: 'direct_sub',
      homeGymId: gymId,
      startsAt: '2026-12-10T09:00:00.000Z',
    );
    String date(String iso) => formatDate(iso);

    Widget host(Widget child) => FFLocaleScope(
      notifier: FFLocale(),
      child: MaterialApp(home: Scaffold(body: child)),
    );

    testWidgets('one card per renewal: pass tier, gym name, or generic', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          ScheduledRenewalsCards(
            renewals: [pass(), gymPlan('g1'), gymPlan('unknown')],
            gyms: [gym],
          ),
        ),
      );
      expect(
        find.text(
          'Your next pass (Premium) starts on '
          '${date('2026-12-01T09:00:00.000Z')}',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Your next plan at Iron Paradise starts on '
          '${date('2026-12-10T09:00:00.000Z')}',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Your next gym plan starts on ${date('2026-12-10T09:00:00.000Z')}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('nothing at all when there are none', (tester) async {
      await tester.pumpWidget(host(const ScheduledRenewalsCards(renewals: [])));
      expect(find.byType(FFCard), findsNothing);
      expect(find.textContaining('starts on'), findsNothing);
    });

    MemberData data(List<Object> renewals) => MemberData()
      ..me = MemberMeResponse.fromJson({
        'user': {'id': 'm1', 'onboardingCompleted': true},
        'scheduledRenewals': renewals,
      })
      ..passes = [
        PassTier.fromJson({'id': 'basic', 'price': 30000, 'visitCap': 12}),
      ]
      ..passesLoaded = true
      ..gyms = [gym];

    apiTest('passes page shows the card when /me lists a renewal', (
      tester,
      api,
    ) async {
      await pumpPage(
        tester,
        api,
        MemberDataScope(
          data: data([
            {
              'id': 'sub_b',
              'type': 'direct_sub',
              'homeGymId': 'g1',
              'startsAt': '2026-12-10T09:00:00.000Z',
            },
          ]),
          child: const MemberPassesPage(),
        ),
        user: const {'id': 'm1', 'userType': 'member'},
        size: const Size(390, 1600),
      );
      expect(find.byKey(const Key('scheduled-renewal-sub_b')), findsOneWidget);
      expect(
        find.textContaining('Your next plan at Iron Paradise'),
        findsOneWidget,
      );
    });

    apiTest('passes page is unchanged without renewals', (tester, api) async {
      await pumpPage(
        tester,
        api,
        MemberDataScope(data: data(const []), child: const MemberPassesPage()),
        user: const {'id': 'm1', 'userType': 'member'},
        size: const Size(390, 1600),
      );
      expect(find.byType(ScheduledRenewalsCards), findsOneWidget);
      expect(find.textContaining('starts on'), findsNothing);
    });
  });

  test('new strings exist in both languages; Swahili awaits review', () {
    const keys = [
      'momo.wallet',
      'error.reason.networkRequired',
      'error.reason.renewalAlreadyScheduled',
      'renewal.nextPass',
      'renewal.nextGymPlan',
      'renewal.nextGymPlanGeneric',
    ];
    for (final k in keys) {
      expect(FFLocale.textOf('en', k), isNotNull, reason: k);
      // Placeholder until a native speaker translates it (no new Swahili).
      expect(FFLocale.textOf('sw', k), startsWith('[SW-PENDING] '), reason: k);
    }
    // Wallet names are brand names, the same in both languages.
    for (final w in momoWallets) {
      final k = 'momo.wallet.$w';
      expect(FFLocale.textOf('en', k), isNotNull, reason: k);
      expect(FFLocale.textOf('sw', k), FFLocale.textOf('en', k), reason: k);
    }
  });
}
