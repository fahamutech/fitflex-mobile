import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/pass_summary_card.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'direct member landing shows gym, plan, dates and days instead of pass.null visits',
    (tester) async {
      final data = MemberData()
        ..me = MemberMeResponse.fromJson({
          'user': {
            'id': 'member-1',
            'displayName': 'Amina Said',
            'onboardingCompleted': true,
          },
          'visitsUsed': 7,
          'visitCap': 12,
          'subscription': {
            'id': 'subscription-1',
            'type': 'direct_sub',
            'plan': 'monthly',
            'status': 'active',
            'startedAt': '2026-08-01T00:00:00.000Z',
            'expiresAt': '2026-09-01T00:00:00.000Z',
            'homeGymId': 'gym-1',
            'homeGym': {
              'id': 'gym-1',
              'name': 'Mikocheni Fitness',
              'tier': 'standard',
              'location': 'Mikocheni',
              'perVisitRate': 5000,
              'commissionRate': 10,
              'status': 'active',
            },
          },
        });
      final locale = FFLocale();

      await tester.pumpWidget(
        FFLocaleScope(
          notifier: locale,
          child: MaterialApp(
            theme: buildTheme(),
            supportedLocales: const [Locale('en'), Locale('sw')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: Scaffold(body: PassSummaryCard(data: data)),
          ),
        ),
      );

      expect(find.text('Mikocheni Fitness'), findsOneWidget);
      expect(find.text('Monthly plan'), findsOneWidget);
      expect(find.byKey(const Key('direct-membership-start')), findsOneWidget);
      expect(find.byKey(const Key('direct-membership-expiry')), findsOneWidget);
      expect(
        find.byKey(const Key('direct-membership-days-left')),
        findsOneWidget,
      );
      expect(find.textContaining('pass.null'), findsNothing);
      expect(find.text('Visits this cycle'), findsNothing);
    },
  );
}
