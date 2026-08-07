// Batch 2 (A2/A3/A7) — membership card, subscription expiry helpers and
// gym direct plans.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/screens/member/widgets/membership_card.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_plans_sheet.dart';

Widget _wrap(Widget child) {
  final locale = FFLocale();
  return FFLocaleScope(
    notifier: locale,
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
}

Gym _gym({num? day, num? week, num? month}) => Gym.fromJson({
  'id': 'gym_1',
  'name': 'Test Gym',
  'tier': 'standard',
  'location': 'Dar es Salaam',
  'perVisitRate': 5000,
  'ratePerDay': day,
  'ratePerWeek': week,
  'ratePerMonth': month,
  'commissionRate': 12,
  'status': 'active',
});

void main() {
  group('Subscription expiry helpers (A1/A2)', () {
    test('daysLeft is positive for a future expiry', () {
      final sub = Subscription.fromJson({
        'status': 'active',
        'expiresAt': DateTime.now()
            .add(const Duration(days: 10, hours: 1))
            .toIso8601String(),
      });
      expect(sub.daysLeft, 10);
      expect(sub.isExpired, isFalse);
    });

    test(
      'isExpired is true past expiry even when status still says active',
      () {
        final sub = Subscription.fromJson({
          'status': 'active',
          'expiresAt': DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        });
        expect(sub.isExpired, isTrue);
        expect(sub.daysLeft, isNegative);
      },
    );

    test('parses direct sub with plan and homeGym (A3)', () {
      final sub = Subscription.fromJson({
        'type': 'direct_sub',
        'plan': 'weekly',
        'status': 'active',
        'homeGymId': 'gym_1',
        'homeGym': {'id': 'gym_1', 'name': 'Test Gym', 'tier': 'standard'},
      });
      expect(sub.isDirect, isTrue);
      expect(sub.plan, 'weekly');
      expect(sub.homeGym?.name, 'Test Gym');
    });
  });

  group('MembershipCard (A2/A3)', () {
    testWidgets('shows expiry date and days left for an active membership', (
      tester,
    ) async {
      final expiry = DateTime.now().add(const Duration(days: 12, hours: 2));
      await tester.pumpWidget(
        _wrap(
          MembershipCard(
            subscription: Subscription.fromJson({
              'type': 'platform_pass',
              'tier': 'pro',
              'status': 'active',
              'startedAt': DateTime.now().toIso8601String(),
              'expiresAt': expiry.toIso8601String(),
            }),
          ),
        ),
      );
      expect(find.byKey(const Key('membership-expiry')), findsOneWidget);
      expect(find.byKey(const Key('membership-days-left')), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('shows Expired state past expiry', (tester) async {
      await tester.pumpWidget(
        _wrap(
          MembershipCard(
            subscription: Subscription.fromJson({
              'type': 'platform_pass',
              'tier': 'basic',
              'status': 'active',
              'expiresAt': DateTime.now()
                  .subtract(const Duration(days: 3))
                  .toIso8601String(),
            }),
          ),
        ),
      );
      expect(find.text('Expired'), findsOneWidget);
      expect(find.byKey(const Key('membership-days-left')), findsNothing);
    });

    testWidgets('shows the subscribed gym for a direct membership (A3)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          MembershipCard(
            subscription: Subscription.fromJson({
              'type': 'direct_sub',
              'plan': 'monthly',
              'status': 'active',
              'expiresAt': DateTime.now()
                  .add(const Duration(days: 20))
                  .toIso8601String(),
              'homeGymId': 'gym_1',
              'homeGym': {
                'id': 'gym_1',
                'name': 'Kijitonyama Fitness',
                'tier': 'standard',
                'location': 'Kijitonyama',
              },
            }),
          ),
        ),
      );
      expect(find.byKey(const Key('membership-gym')), findsOneWidget);
      expect(find.text('Kijitonyama Fitness'), findsOneWidget);
      expect(find.text('Monthly plan'), findsOneWidget);
    });

    testWidgets('renders empty state without a subscription', (tester) async {
      await tester.pumpWidget(_wrap(const MembershipCard(subscription: null)));
      expect(find.text('No active membership yet.'), findsOneWidget);
    });
  });

  group('gymPlansFor (A7)', () {
    test('builds daily/weekly/monthly plans from gym rates', () {
      final plans = gymPlansFor(_gym(day: 5000, week: 25000, month: 80000));
      expect(plans.map((p) => p.id), ['daily', 'weekly', 'monthly']);
      expect(plans.map((p) => p.days), [1, 7, 30]);
      expect(plans.map((p) => p.price), [5000, 25000, 80000]);
    });

    test('omits plans without a configured price', () {
      final plans = gymPlansFor(_gym(month: 80000));
      expect(plans.map((p) => p.id), ['monthly']);
    });

    test('returns empty when the gym has no rates', () {
      expect(gymPlansFor(_gym()), isEmpty);
    });
  });

  group('GymPlansSheet (A7)', () {
    testWidgets('lists plans and enables subscribe only after selection', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(GymPlansSheet(gym: _gym(day: 5000, week: 25000, month: 80000))),
      );
      expect(find.byKey(const Key('gym-plan-daily')), findsOneWidget);
      expect(find.byKey(const Key('gym-plan-weekly')), findsOneWidget);
      expect(find.byKey(const Key('gym-plan-monthly')), findsOneWidget);

      final button = tester.widget<FilledButton>(
        find.byKey(const Key('gym-plan-subscribe')),
      );
      expect(button.onPressed, isNull);

      await tester.tap(find.byKey(const Key('gym-plan-weekly')));
      await tester.pump();
      final afterSelect = tester.widget<FilledButton>(
        find.byKey(const Key('gym-plan-subscribe')),
      );
      expect(afterSelect.onPressed, isNotNull);
    });

    testWidgets('shows empty state when the gym has no plans', (tester) async {
      await tester.pumpWidget(_wrap(GymPlansSheet(gym: _gym())));
      expect(
        find.text('No plans configured for this gym yet.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('gym-plan-subscribe')), findsNothing);
    });
  });
}
