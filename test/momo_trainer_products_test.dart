// Mobile money for trainer products (B6b, against fitflex-functions#240):
// "Pay now" for a member's trainer sessions and a trainer's gym pass, shown
// only while `GET /payments/options` lists the product for the role; the new
// refusals and held reasons in English and Swahili; and the lists re-fetched
// once a payment completes.

import 'package:fitflexmobile/screens/member/member_sessions_page.dart';
import 'package:fitflexmobile/screens/member/widgets/mobile_money_pay.dart';
import 'package:fitflexmobile/screens/member/widgets/trainer_actions_sheet.dart';
import 'package:fitflexmobile/screens/trainer/trainer_gyms_tab.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/screens/trainer/trainer_passes_page.dart';
import 'package:fitflexmobile/screens/trainer/widgets/trainer_sheets.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_api.dart';

const _member = {'id': 'm1', 'userType': 'member', 'phone': '+255712345678'};
const _trainer = {'id': 't1', 'userType': 'trainer', 'phone': '+255754000111'};

/// Options as the server sends them with the trainer-products flag on.
Map<String, dynamic> _on(List<String> products) => {
  'enabled': true,
  'environment': 'production',
  'mobileMoney': {'products': products},
};

/// Options from a server without the flag (or before #240): no key.
const _legacyOn = {'enabled': true, 'environment': 'production'};

const _memberProducts = ['FITFLEX_PASS', 'GYM_SUBSCRIPTION', 'TRAINER_SERVICE'];
const _trainerProducts = ['TRAINER_GYM_PASS'];

Map<String, dynamic> _booking(
  String id, {
  String status = 'payment_pending',
  String? paymentRequestId = 'pay_g1',
  num amount = 20000,
  String slot = '07:00',
}) => {
  'id': id,
  'groupId': 'tbg_1',
  'status': status,
  'date': '2099-05-05',
  'slot': slot,
  'amountTzs': amount,
  'paymentRequestId': paymentRequestId,
  'trainer': {'id': 'trn_1', 'displayName': 'Coach Asha'},
  'gym': {'id': 'gym_1', 'name': 'Gym Tu'},
  'cancellation': {'canCancel': true, 'refundable': false},
};

Map<String, dynamic> _pass(
  String id, {
  String kind = 'trainer_pass',
  String status = 'payment_pending',
  String? memberReference,
}) => {
  'id': id,
  'status': status,
  'kind': kind,
  'plan': 'weekly',
  'gym': {'id': 'gym_1', 'name': 'Gym Tu'},
  'paymentRequest': status == 'payment_pending'
      ? {
          'id': 'pay_$id',
          'subscriptionId': id,
          'amountTzs': 40000,
          'status': 'pending',
          'memberReference': ?memberReference,
        }
      : null,
};

void _seedSessions(RecordingApi api, List<Map<String, dynamic>> bookings) {
  api.on('GET /me/trainer-bookings', bookings);
  api.on('GET /me/refunds', {'refunds': []});
}

Future<PageHost> _sessions(
  WidgetTester t,
  RecordingApi api, {
  String lang = 'en',
  Size size = const Size(400, 1200),
  bool keepRequests = false,
}) => pumpPage(
  t,
  api,
  const MemberSessionsPage(),
  user: _member,
  lang: lang,
  size: size,
  keepRequests: keepRequests,
);

Future<PageHost> _passes(
  WidgetTester t,
  RecordingApi api, {
  String lang = 'en',
  Size size = const Size(400, 1200),
}) => pumpPage(
  t,
  api,
  const TrainerPassesPage(),
  user: _trainer,
  lang: lang,
  size: size,
);

Finder _payNow(String paymentRequestId) =>
    find.byKey(Key('pay-now-$paymentRequestId'));

/// Taps "Pay now", sends the prompt, and lets the panel poll once.
Future<void> _payAndPoll(WidgetTester t, PageHost host, String id) async {
  await t.ensureVisible(_payNow(id));
  await t.tap(_payNow(id));
  // Options, then the sheet opening (no settle: the sheet has a spinner later).
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  await t.tap(find.textContaining(host.tr('momo.send').split('{').first));
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pump(const Duration(seconds: 4)); // the first status check
  for (var i = 0; i < 3; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('which products get "Pay now"', () {
    test('options key absent: the old behaviour', () {
      // Members: passes and gym plans only.
      expect(momoOffers(_legacyOn, 'FITFLEX_PASS', role: 'member'), isTrue);
      expect(momoOffers(_legacyOn, 'GYM_SUBSCRIPTION', role: 'member'), isTrue);
      expect(momoOffers(_legacyOn, 'TRAINER_SERVICE', role: 'member'), isFalse);
      // Trainers: nothing.
      for (final p in [..._memberProducts, ..._trainerProducts]) {
        expect(momoOffers(_legacyOn, p, role: 'trainer'), isFalse, reason: p);
      }
    });

    test('with the key, only the listed products', () {
      final member = _on(_memberProducts);
      expect(momoOffers(member, 'TRAINER_SERVICE', role: 'member'), isTrue);
      expect(momoOffers(member, 'TRAINER_GYM_PASS', role: 'member'), isFalse);
      expect(momoOffers(member, 'SHOP_ORDER', role: 'member'), isFalse);
      final trainer = _on(_trainerProducts);
      expect(momoOffers(trainer, 'TRAINER_GYM_PASS', role: 'trainer'), isTrue);
      for (final p in _memberProducts) {
        expect(momoOffers(trainer, p, role: 'trainer'), isFalse, reason: p);
        // A list naming member products still never offers them to a trainer.
        expect(
          momoOffers(_on(_memberProducts), p, role: 'trainer'),
          isFalse,
          reason: p,
        );
      }
      // Paying not offered to this role: an empty list wins over the old rule.
      expect(momoOffers(_on([]), 'FITFLEX_PASS', role: 'member'), isFalse);
    });

    test('never while mobile money is off, whatever the list says', () {
      final off = {..._on(_memberProducts), 'enabled': false};
      expect(momoOffers(off, 'TRAINER_SERVICE', role: 'member'), isFalse);
      expect(momoOffers(off, 'FITFLEX_PASS', role: 'member'), isFalse);
      expect(momoOffers(_on(_memberProducts), null, role: 'member'), isFalse);
    });
  });

  group('member: trainer sessions', () {
    apiTest('options key absent: no "Pay now" on an unpaid session', (
      t,
      api,
    ) async {
      api.on('GET /payments/options', _legacyOn);
      _seedSessions(api, [_booking('tbk_1')]);
      await _sessions(t, api);
      expect(find.byKey(const Key('session-tbk_1')), findsOneWidget);
      expect(_payNow('pay_g1'), findsNothing);
    });

    apiTest('one "Pay now" per booking, for the whole booking', (t, api) async {
      api.on('GET /payments/options', _on(_memberProducts));
      _seedSessions(api, [
        _booking('tbk_1', slot: '07:00'),
        _booking('tbk_2', slot: '13:00'),
        _booking('tbk_3', status: 'confirmed', paymentRequestId: 'pay_old'),
      ]);
      final host = await _sessions(t, api, keepRequests: true);
      expect(_payNow('pay_g1'), findsOneWidget);
      expect(_payNow('pay_old'), findsNothing);
      // Asked once for the page, not once per button.
      expect(api.where('GET', '/payments/options'), hasLength(1));

      await t.tap(_payNow('pay_g1'));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      // The sheet asks for both sessions together.
      expect(find.textContaining('TSh 40,000'), findsOneWidget);
      expect(
        find.textContaining(host.tr('momo.send').split('{').first),
        findsOneWidget,
      );
    });

    apiTest('pay now → completed: the sessions are re-fetched', (t, api) async {
      api.on('GET /payments/options', _on(_memberProducts));
      _seedSessions(api, [_booking('tbk_1')]);
      api.on('POST /me/payments/pay_g1/mobile-money', {'state': 'in_progress'});
      api.on('POST /me/payments/pay_g1/mobile-money/refresh', {
        'state': 'completed',
      });
      final host = await _sessions(t, api);
      await _payAndPoll(t, host, 'pay_g1');

      final sent = api.only('POST', '/me/payments/pay_g1/mobile-money');
      expect(sent.body, {'phone': '+255712345678'});
      expect(find.text(host.tr('momo.successTitle')), findsOneWidget);
      expect(find.text(host.tr('momo.successBody.session')), findsOneWidget);
      expect(api.sent('GET', '/me/trainer-bookings'), isTrue);
    });

    apiTest('group_slot_rebooked before a prompt: explained, nothing sent', (
      t,
      api,
    ) async {
      api.on('GET /payments/options', _on(_memberProducts));
      _seedSessions(api, [_booking('tbk_1')]);
      api.fail('POST /me/payments/pay_g1/mobile-money', 409, {
        'error': 'group_slot_rebooked',
        'bookingIds': ['tbk_1'],
      });
      final host = await _sessions(t, api);
      await _payAndPoll(t, host, 'pay_g1');
      expect(
        find.textContaining(host.tr('error.reason.groupSlotRebooked')),
        findsOneWidget,
      );
      expect(
        api.sent('POST', '/me/payments/pay_g1/mobile-money/refresh'),
        isFalse,
      );
    });

    apiTest('a session in Swahili fits 360 with "Pay now"', (t, api) async {
      api.on('GET /payments/options', _on(_memberProducts));
      _seedSessions(api, [_booking('tbk_1'), _booking('tbk_2', slot: '13:00')]);
      final host = await _sessions(
        t,
        api,
        lang: 'sw',
        size: const Size(360, 740),
      );
      expect(host.tr('momo.payNow'), 'Lipa sasa');
      expect(buttonLabelled('Lipa sasa'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('trainer: gym passes', () {
    apiTest('options key absent: no "Pay now" for a trainer', (t, api) async {
      api.on('GET /payments/options', _legacyOn);
      api.on('GET /trainer/passes', [_pass('sub_1')]);
      await _passes(t, api);
      expect(find.byKey(const Key('trainer-pass-sub_1')), findsOneWidget);
      expect(_payNow('pay_sub_1'), findsNothing);
    });

    apiTest('a trainer pass gets "Pay now"; a member plan does not', (
      t,
      api,
    ) async {
      api.on('GET /payments/options', _on(_trainerProducts));
      api.on('GET /trainer/passes', [
        _pass('sub_1'),
        _pass('sub_2', kind: 'member_plan'),
        _pass('sub_3', memberReference: 'QJK3H7XY2P'),
      ]);
      await _passes(t, api);
      expect(_payNow('pay_sub_1'), findsOneWidget);
      expect(_payNow('pay_sub_2'), findsNothing);
      // Paid by hand with a transaction ID already.
      expect(_payNow('pay_sub_3'), findsNothing);
    });

    apiTest('member products are never offered to a trainer', (t, api) async {
      // Even if a list named them, a trainer's member plan stays manual.
      api.on('GET /payments/options', _on(_memberProducts));
      api.on('GET /trainer/passes', [
        _pass('sub_1'),
        _pass('sub_2', kind: 'member_plan'),
      ]);
      await _passes(t, api);
      expect(_payNow('pay_sub_1'), findsNothing);
      expect(_payNow('pay_sub_2'), findsNothing);
    });

    apiTest('pay now → completed: the passes are re-fetched', (t, api) async {
      api.on('GET /payments/options', _on(_trainerProducts));
      var round = 0;
      api.onCall('GET /trainer/passes', (_) {
        round += 1;
        return [
          _pass('sub_1', status: round == 1 ? 'payment_pending' : 'active'),
        ];
      });
      api.on('POST /me/payments/pay_sub_1/mobile-money', {
        'state': 'in_progress',
      });
      api.on('POST /me/payments/pay_sub_1/mobile-money/refresh', {
        'state': 'completed',
      });
      final host = await _passes(t, api);
      await _payAndPoll(t, host, 'pay_sub_1');
      expect(api.only('POST', '/me/payments/pay_sub_1/mobile-money').body, {
        'phone': '+255754000111',
      });
      expect(
        find.text(host.tr('momo.successBody.trainerPass')),
        findsOneWidget,
      );
      expect(api.sent('GET', '/trainer/passes'), isTrue);
      await t.tap(find.text(host.tr('momo.done')));
      await t.pumpAndSettle();
      expect(_payNow('pay_sub_1'), findsNothing);
      expect(find.text(host.tr('trainerPass.active')), findsOneWidget);
    });

    apiTest('not_payable_by_role is explained', (t, api) async {
      api.on('GET /payments/options', _on(_trainerProducts));
      api.on('GET /trainer/passes', [_pass('sub_1')]);
      api.fail('POST /me/payments/pay_sub_1/mobile-money', 403, {
        'error': 'not_payable_by_role',
        'product': 'GYM_SUBSCRIPTION',
      });
      final host = await _passes(t, api);
      await _payAndPoll(t, host, 'pay_sub_1');
      expect(
        find.textContaining(host.tr('error.reason.notPayableByRoleMember')),
        findsOneWidget,
      );
    });

    apiTest('a pending pass in Swahili fits 360 with "Pay now"', (
      t,
      api,
    ) async {
      api.on('GET /payments/options', _on(_trainerProducts));
      api.on('GET /trainer/passes', [_pass('sub_1')]);
      await _passes(t, api, lang: 'sw', size: const Size(360, 740));
      expect(buttonLabelled('Lipa sasa'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('offered straight after the request is made', () {
    final trainer = TrainerProfile(
      id: 'trn_1',
      displayName: 'Coach Asha',
      hourlyRateTzs: 20000,
      gymIds: const ['gym_1'],
      status: 'active',
    );

    void seedBooking(RecordingApi api) {
      api.onCall(
        'POST /me/trainer-bookings/quote',
        (r) => {
          'summary': {
            'slots': (r.body as Map)['slots'],
            'currency': 'TZS',
            'pricePerSession': 20000,
            'subtotal': 20000,
            'discount': 0,
            'discountPct': 0,
            'total': 20000,
          },
        },
      );
      api.on('POST /me/trainer-bookings', {
        'bookingGroupId': 'tbg_1',
        'bookings': [_booking('tbk_1')],
        'paymentRequest': {
          'id': 'pay_g1',
          'bookingGroupId': 'tbg_1',
          'amountTzs': 20000,
          'status': 'pending',
        },
      });
    }

    for (final (label, options, offered) in [
      ('flag on', _on(_memberProducts), true),
      ('key absent', _legacyOn, false),
    ]) {
      apiTest('booking a trainer ($label)', (t, api) async {
        api.on('GET /payments/options', options);
        seedBooking(api);
        final host = await pumpPage(
          t,
          api,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showTrainerBookingSheet(
                context,
                trainer,
                gymId: 'gym_1',
                slots: const [(date: '2099-05-05', slot: '07:00')],
              ),
              child: const Text('open'),
            ),
          ),
          user: _member,
          size: const Size(400, 1200),
        );
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('trainer-book-confirm')));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(api.sent('POST', '/me/trainer-bookings'), isTrue);
        expect(
          find.textContaining(host.tr('momo.send').split('{').first),
          offered ? findsOneWidget : findsNothing,
        );
      });
    }

    for (final (label, options, offered) in [
      ('flag on', _on(_trainerProducts), true),
      ('key absent', _legacyOn, false),
    ]) {
      apiTest('a trainer buying a gym pass ($label)', (t, api) async {
        api.on('GET /payments/options', options);
        api.on('POST /trainer/gyms/gym_1/trainer-pass', {
          'subscription': {'id': 'sub_1', 'status': 'payment_pending'},
          'paymentRequest': {
            'id': 'pay_sub_1',
            'subscriptionId': 'sub_1',
            'amountTzs': 40000,
            'status': 'pending',
          },
        });
        final host = await pumpPage(
          t,
          api,
          SingleChildScrollView(
            child: TrainerGymSheet(
              gym: const {
                'id': 'gym_1',
                'name': 'Gym Tu',
                'trainerAccess': {
                  'access': 'trainer_pass',
                  'options': [
                    {
                      'kind': 'trainer_pass',
                      'period': 'weekly',
                      'feeTzs': 40000,
                    },
                  ],
                },
              },
              onChanged: () {},
            ),
          ),
          user: _trainer,
          size: const Size(400, 1200),
        );
        await t.tap(find.byKey(const Key('trainer-pass-buy')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('trainer-pass-confirm')));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(api.sent('POST', '/trainer/gyms/gym_1/trainer-pass'), isTrue);
        expect(
          find.textContaining(host.tr('momo.send').split('{').first),
          offered ? findsOneWidget : findsNothing,
        );
      });
    }
  });

  group('cancelling while a prompt is out (409 payment_in_progress)', () {
    const busy = {'error': 'payment_in_progress'};

    for (final lang in ['en', 'sw']) {
      test('the booking wording, not the generic one ($lang)', () {
        final locale = FFLocale()..set(Locale(lang));
        final msg = bookingCancelErrorMessage(locale, ApiException(409, busy));
        expect(msg, locale.t('error.reason.bookingPaymentInProgress'));
        expect(msg, isNot(contains('payment_in_progress')));
        // Anything else reads as before.
        final other = ApiException(409, {'error': 'booking_not_cancellable'});
        expect(
          bookingCancelErrorMessage(locale, other),
          errorMessage(locale, other),
        );
      });
    }

    test('English as agreed; Swahili its own, saying mtandao wa simu', () {
      expect(
        FFLocale.textOf('en', 'error.reason.bookingPaymentInProgress'),
        'A mobile money payment is in progress for this booking. Wait for the '
        'phone prompt to finish, then try again.',
      );
      final sw = FFLocale.textOf('sw', 'error.reason.bookingPaymentInProgress');
      expect(sw, contains('mtandao wa simu'));
      expect(FFLocale.textOf('sw', 'momo.held.transactionMismatch'), isNotNull);
      expect(
        FFLocale.textOf('sw', 'momo.held.transactionMismatch'),
        isNot(FFLocale.textOf('en', 'momo.held.transactionMismatch')),
      );
    });

    for (final lang in ['en', 'sw']) {
      apiTest('member cancel is told to wait ($lang)', (t, api) async {
        api.on('GET /payments/options', _legacyOn);
        _seedSessions(api, [_booking('tbk_1')]);
        api.fail('POST /me/trainer-bookings/tbk_1/cancel', 409, busy);
        final host = await _sessions(
          t,
          api,
          lang: lang,
          size: const Size(360, 740),
        );
        await tapVisible(t, find.byKey(const Key('session-cancel-tbk_1')));
        await t.tap(find.byKey(const Key('session-cancel-confirm')));
        await t.pumpAndSettle();
        expect(api.sent('POST', '/me/trainer-bookings/tbk_1/cancel'), isTrue);
        expect(
          find.text(host.tr('error.reason.bookingPaymentInProgress')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      });

      apiTest('trainer cancel is told to wait ($lang)', (t, api) async {
        api.on('GET /trainer/sessions', {
          'sessions': [
            {
              'id': 'tbk_1',
              'source': 'booking',
              'status': 'payment_pending',
              'date': '2099-05-05',
              'slot': '07:00',
              'amountTzs': 20000,
              'member': {'displayName': 'Amina'},
            },
          ],
        });
        api.fail('POST /trainer/bookings/tbk_1/cancel', 409, busy);
        final host = await pumpPage(
          t,
          api,
          const TrainerSessionsSheet(),
          user: _trainer,
          lang: lang,
          size: const Size(360, 740),
        );
        await tapVisible(t, find.byKey(const Key('trainer-cancel-tbk_1')));
        await t.tap(find.byKey(const Key('trainer-cancel-confirm')));
        await t.pumpAndSettle();
        expect(api.sent('POST', '/trainer/bookings/tbk_1/cancel'), isTrue);
        expect(
          find.text(host.tr('error.reason.bookingPaymentInProgress')),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
      });
    }
  });

  group('held reasons', () {
    for (final lang in ['en', 'sw']) {
      for (final (reason, key) in const [
        ('group_slot_rebooked', 'momo.held.groupSlotRebooked'),
        // Can be held with every flag off too (fitflex-functions#240):
        // the mapping does not depend on any flag.
        ('reference_already_used', 'momo.held.referenceAlreadyUsed'),
        ('amount_mismatch', 'momo.held.amountMismatch'),
        ('transaction_mismatch', 'momo.held.transactionMismatch'),
        ('something_new', 'momo.heldBody'),
        (null, 'momo.heldBody'),
      ]) {
        apiTest('held ($reason) says why, at 360 ($lang)', (t, api) async {
          api.on('POST /me/payments/pay_1/mobile-money', {
            'state': 'in_progress',
          });
          api.on('POST /me/payments/pay_1/mobile-money/refresh', {
            'state': 'held',
            'reason': ?reason,
          });
          final host = await pumpPage(
            t,
            api,
            const SingleChildScrollView(
              child: MobileMoneyPayPanel(
                paymentRequestId: 'pay_1',
                amountTzs: 40000,
                defaultPhone: '0712345678',
                productType: 'TRAINER_SERVICE',
                pollEvery: Duration(seconds: 1),
              ),
            ),
            user: _member,
            lang: lang,
            size: const Size(360, 740),
          );
          await t.tap(
            find.textContaining(host.tr('momo.send').split('{').first),
          );
          await t.pump();
          await t.pump(const Duration(milliseconds: 50));
          await t.pump(const Duration(seconds: 1));
          await t.pump(const Duration(milliseconds: 50));
          expect(find.text(host.tr('momo.heldTitle')), findsOneWidget);
          expect(find.text(host.tr(key)), findsOneWidget);
          // Held money is never asked for again.
          expect(find.text(host.tr('momo.tryAgain')), findsNothing);
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('refusals', () {
    final codes = <(int, Map<String, dynamic>, String)>[
      (403, {'error': 'not_payable_by_role'}, 'error.reason.notPayableByRole'),
      (
        403,
        {'error': 'not_payable_by_role', 'product': 'TRAINER_GYM_PASS'},
        'error.reason.notPayableByRoleTrainer',
      ),
      (
        403,
        {'error': 'not_payable_by_role', 'product': 'TRAINER_SERVICE'},
        'error.reason.notPayableByRoleMember',
      ),
      (
        409,
        {
          'error': 'group_slot_rebooked',
          'bookingIds': ['tbk_1'],
        },
        'error.reason.groupSlotRebooked',
      ),
      (
        409,
        {'error': 'unsupported_currency'},
        'error.reason.unsupportedCurrency',
      ),
    ];
    for (final (status, body, key) in codes) {
      test(
        '${body['error']} ${body['product'] ?? ''} in English and Swahili',
        () {
          final e = ApiException(status, body);
          final en = apiErrorMessage(FFLocale(), e);
          final sw = apiErrorMessage(FFLocale()..set(const Locale('sw')), e);
          expect(en, contains(FFLocale.textOf('en', key)));
          expect(sw, contains(FFLocale.textOf('sw', key)));
          expect(sw, isNot(en));
          expect(en, isNot(contains(body['error'] as String)));
          expect(sw, isNot(contains(body['error'] as String)));
        },
      );
    }

    test('tier_not_available names the tier when the server sends it', () {
      final e = ApiException(409, {
        'error': 'tier_not_available',
        'tier': 'pro',
      });
      expect(
        apiErrorMessage(FFLocale(), e),
        contains('the Pro pass is not on sale right now'),
      );
      expect(
        apiErrorMessage(FFLocale()..set(const Locale('sw')), e),
        contains('pasi ya Pro haiuzwi kwa sasa'),
      );
      // Without it, the plain wording as before.
      expect(
        apiErrorMessage(
          FFLocale(),
          ApiException(409, {'error': 'tier_not_available'}),
        ),
        contains('this pass is not on sale right now'),
      );
    });

    test('every new line has its own Swahili, saying mtandao wa simu', () {
      const keys = [
        'error.reason.notPayableByRole',
        'error.reason.notPayableByRoleTrainer',
        'error.reason.notPayableByRoleMember',
        'error.reason.groupSlotRebooked',
        'error.reason.unsupportedCurrency',
        'error.reason.tierNotAvailableNamed',
        'momo.successBody.session',
        'momo.successBody.trainerPass',
        'momo.held.groupSlotRebooked',
        'momo.held.referenceAlreadyUsed',
        'momo.held.amountMismatch',
        'member.bookingPaid',
        'trainerPass.paidNow',
      ];
      for (final k in keys) {
        expect(FFLocale.textOf('en', k), isNotNull, reason: k);
        expect(FFLocale.textOf('sw', k), isNotNull, reason: k);
        expect(FFLocale.textOf('sw', k), isNot(FFLocale.textOf('en', k)));
      }
      expect(
        FFLocale.textOf('sw', 'error.reason.unsupportedCurrency'),
        contains('mtandao wa simu'),
      );
      expect(
        FFLocale.textOf('sw', 'error.reason.providerUnavailable'),
        startsWith('Mtandao wa simu'),
      );
    });
  });
}
