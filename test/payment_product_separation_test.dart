// Subscription & payment audit: FitFlex Pass, a gym's own plans and trainer
// purchases stay distinct in what the member is shown and told.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_plans_sheet.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/payment_labels.dart';

Widget _wrap(Widget child) => FFLocaleScope(
  notifier: FFLocale(),
  child: MaterialApp(
    theme: buildTheme(),
    supportedLocales: const [Locale('en'), Locale('sw')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  ),
);

Gym _gym(String id, String name, {num? day, num? week, num? month}) =>
    Gym.fromJson({
      'id': id,
      'name': name,
      'tier': 'standard',
      'location': 'Dar es Salaam',
      'perVisitRate': 5000,
      'ratePerDay': day,
      'ratePerWeek': week,
      'ratePerMonth': month,
      'commissionRate': 12,
      'status': 'active',
    });

PaymentRequest _pay(Map<String, dynamic> extra) => PaymentRequest.fromJson({
  'id': 'pay_1',
  'memberId': 'u1',
  'amountTzs': 1000,
  'status': 'pending',
  'provider': 'admin_approved',
  'requestedAt': '2026-10-09T10:00:00Z',
  ...extra,
});

MemberMeResponse _me(List<Map<String, dynamic>> pending) =>
    MemberMeResponse.fromJson({
      'user': {'id': 'u1', 'userType': 'member'},
      'visitsUsed': 0,
      'pendingPayments': pending,
      'pendingPayment': pending
          .where(
            (p) =>
                p['productType'] == 'FITFLEX_PASS' ||
                p['productType'] == 'GYM_SUBSCRIPTION',
          )
          .firstOrNull,
    });

void main() {
  group('direct gym plans never show FitFlex Pass tiers', () {
    for (final tier in ['Basic', 'Pro', 'Premium', 'Executive']) {
      testWidgets('no "$tier" option on a gym with all three periods', (
        tester,
      ) async {
        await tester.pumpWidget(
          _wrap(
            GymPlansSheet(
              gym: _gym('g1', 'Alpha', day: 5000, week: 25000, month: 80000),
            ),
          ),
        );
        expect(find.text(tier), findsNothing);
      });
    }

    testWidgets('a gym with no pricing shows the unavailable state, not pass tiers', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(GymPlansSheet(gym: _gym('g2', 'Bare'))));
      expect(
        find.text('No plans configured for this gym yet.'),
        findsOneWidget,
      );
      expect(find.text('Pro'), findsNothing);
      expect(find.byKey(const Key('gym-plan-subscribe')), findsNothing);
    });

    testWidgets('only the periods the gym sells are purchasable', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(GymPlansSheet(gym: _gym('g3', 'Monthly Only', month: 90000))),
      );
      expect(find.byKey(const Key('gym-plan-monthly')), findsOneWidget);
      expect(find.byKey(const Key('gym-plan-daily')), findsNothing);
      expect(find.byKey(const Key('gym-plan-weekly')), findsNothing);
    });

    testWidgets('changing the gym replaces the offers and drops the selection', (
      tester,
    ) async {
      final a = _gym('g1', 'Alpha', day: 5000, month: 80000);
      final b = _gym('g3', 'Monthly Only', month: 90000);
      await tester.pumpWidget(_wrap(GymPlansSheet(key: ValueKey(a.id), gym: a)));
      await tester.tap(find.byKey(const Key('gym-plan-daily')));
      await tester.pump();
      await tester.pumpWidget(_wrap(GymPlansSheet(key: ValueKey(b.id), gym: b)));
      expect(find.byKey(const Key('gym-plan-daily')), findsNothing);
      expect(find.text('Monthly Only'), findsOneWidget);
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('gym-plan-subscribe')),
      );
      expect(button.onPressed, isNull, reason: 'no stale selection');
    });

    testWidgets('the sheet says these plans are for this gym only', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(GymPlansSheet(gym: _gym('g1', 'Alpha', day: 5000))),
      );
      expect(find.textContaining('separate from a FitFlex Pass'), findsOneWidget);
    });
  });

  group('pending payments are held per product', () {
    final passPending = {
      'id': 'pay_pass',
      'productType': 'FITFLEX_PASS',
      'tier': 'pro',
    };
    final gymPending = {
      'id': 'pay_gym',
      'productType': 'GYM_SUBSCRIPTION',
      'gymId': 'g1',
      'gym': {'id': 'g1', 'name': 'Alpha'},
      'plan': 'monthly',
      'tier': null,
    };
    final sessionPending = {
      'id': 'pay_bk',
      'productType': 'TRAINER_SERVICE',
      'plan': 'trainer_session',
    };

    test('a gym plan payment does not block the FitFlex Pass', () {
      final d = MemberData()..me = _me([gymPending]);
      expect(d.pendingPass, isNull);
      expect(d.pendingGymPlan('g1'), isNotNull);
    });

    test('a pass payment does not block a gym plan', () {
      final d = MemberData()..me = _me([passPending]);
      expect(d.pendingPass, isNotNull);
      expect(d.pendingGymPlan('g1'), isNull);
    });

    test('a gym plan payment blocks only its own gym', () {
      final d = MemberData()..me = _me([gymPending]);
      expect(d.pendingGymPlan('g1'), isNotNull);
      expect(d.pendingGymPlan('g2'), isNull);
    });

    test('a pending trainer session blocks neither', () {
      final d = MemberData()..me = _me([sessionPending]);
      expect(d.pendingPass, isNull);
      expect(d.pendingGymPlan('g1'), isNull);
      expect(d.me!.pendingPayment, isNull);
    });

    test('an older server (no product types) still reads a tiered request as a pass', () {
      final d = MemberData()
        ..me = MemberMeResponse.fromJson({
          'user': {'id': 'u1', 'userType': 'member'},
          'visitsUsed': 0,
          'pendingPayment': {
            'id': 'p',
            'tier': 'pro',
            'amountTzs': 120000,
            'status': 'pending',
          },
        });
      expect(d.pendingPass, isNotNull);
    });
  });

  group('payment labels say what was bought', () {
    Future<String> label(WidgetTester tester, PaymentRequest p) async {
      late String out;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              out = paymentProductLabel(context, p);
              return const SizedBox();
            },
          ),
        ),
      );
      return out;
    }

    testWidgets('FitFlex Pass names the tier', (tester) async {
      expect(
        await label(tester, _pay({'productType': 'FITFLEX_PASS', 'tier': 'pro'})),
        'FitFlex Pass · Pro',
      );
    });

    testWidgets('gym plan names the gym and period, with no tier', (tester) async {
      final text = await label(
        tester,
        _pay({
          'productType': 'GYM_SUBSCRIPTION',
          'tier': null,
          'plan': 'monthly',
          'gymId': 'g1',
          'gym': {'id': 'g1', 'name': 'Alpha Gym'},
        }),
      );
      expect(text, startsWith('Alpha Gym'));
      expect(text, contains('Monthly'));
      expect(text, isNot(contains('FitFlex Pass')));
    });

    testWidgets('trainer session and order are not called a pass', (tester) async {
      expect(
        await label(tester, _pay({'productType': 'TRAINER_SERVICE'})),
        'Trainer session',
      );
      expect(
        await label(tester, _pay({'productType': 'SHOP_ORDER'})),
        'Shop order',
      );
    });

    testWidgets('trainer gym pass names the gym', (tester) async {
      final text = await label(
        tester,
        _pay({
          'productType': 'TRAINER_GYM_PASS',
          'gym': {'id': 'g1', 'name': 'Alpha Gym'},
        }),
      );
      expect(text, contains('Trainer gym pass'));
      expect(text, contains('Alpha Gym'));
    });
  });
}
