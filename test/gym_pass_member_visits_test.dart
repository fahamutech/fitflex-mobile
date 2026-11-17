import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/checkin_list.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/gym_passes/gym_pass.dart';
import 'package:fitflexmobile/shared/gym_passes/gym_passes_flag.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _sub(
  String id,
  String status, {
  String type = 'direct_sub',
  String? plan,
  String? passPurchaseId,
}) => {
  'id': id,
  'type': type,
  'status': status,
  'plan': ?plan,
  'passPurchaseId': ?passPurchaseId,
};

MemberData _data({
  Map<String, dynamic>? subscription,
  Map<String, dynamic>? entitlements,
}) => MemberData()
  ..me = MemberMeResponse.fromJson({
    'user': {'id': 'm1', 'onboardingCompleted': true},
    'subscription': ?subscription,
    'entitlements': ?entitlements,
  });

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
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

CheckIn _checkin(String id, {String? passPurchaseId}) => CheckIn(
  id: id,
  memberId: 'm1',
  timestamp: '2026-11-10T08:00:00.000Z',
  gymTier: 'standard',
  gymId: 'g1',
  passPurchaseId: passPurchaseId,
);

void main() {
  tearDown(() => debugGymCustomPassesOverride = null);

  group('canCheckIn', () {
    test(
      'FitFlex Pass active + newer expired gym-pass child: QR available',
      () {
        final d = _data(
          subscription: _sub('s_child', 'expired', passPurchaseId: 'p1'),
          entitlements: {
            'fitflexPass': {
              'id': 's_pass',
              'type': 'platform_pass',
              'status': 'active',
            },
            'gymSubscriptions': [],
          },
        );
        expect(d.hasActivePass, isFalse);
        expect(d.canCheckIn, isTrue);
      },
    );

    test('active gym subscription in entitlements: QR available', () {
      final d = _data(
        subscription: _sub('s_child', 'suspended', passPurchaseId: 'p1'),
        entitlements: {
          'fitflexPass': null,
          'gymSubscriptions': [_sub('s_other', 'active', plan: 'monthly')],
        },
      );
      expect(d.canCheckIn, isTrue);
    });

    test('only an expired child: locked', () {
      final d = _data(
        subscription: _sub('s_child', 'expired', passPurchaseId: 'p1'),
        entitlements: {
          'fitflexPass': {'id': 's_pass', 'status': 'expired'},
          'gymSubscriptions': [],
        },
      );
      expect(d.canCheckIn, isFalse);
    });

    test('no pass at all, with or without entitlements: locked', () {
      expect(_data().canCheckIn, isFalse);
      expect(
        _data(
          entitlements: {'fitflexPass': null, 'gymSubscriptions': []},
        ).canCheckIn,
        isFalse,
      );
    });

    test('legacy plan behaves as before', () {
      expect(
        _data(
          subscription: _sub('s1', 'active', type: 'platform_pass'),
        ).canCheckIn,
        isTrue,
      );
      expect(
        _data(
          subscription: _sub('s1', 'expired', type: 'platform_pass'),
        ).canCheckIn,
        isFalse,
      );
      expect(
        _data(subscription: _sub('s2', 'active', plan: 'monthly')).canCheckIn,
        isTrue,
      );
      final sponsored = _data()..sponsoredGymAccess = true;
      expect(sponsored.canCheckIn, isTrue);
    });
  });

  group('visit label', () {
    final names = {'p1': 'Morning Pass'};

    test('name when known, generic when not, null for other visits', () {
      final en = FFLocale();
      expect(
        gymPassVisitLabel(
          en,
          passPurchaseId: 'p1',
          names: names,
          enabled: true,
        ),
        'Morning Pass',
      );
      expect(
        gymPassVisitLabel(
          en,
          passPurchaseId: 'p9',
          names: names,
          enabled: true,
        ),
        'Gym pass',
      );
      expect(
        gymPassVisitLabel(
          en,
          passPurchaseId: null,
          names: names,
          enabled: true,
        ),
        isNull,
      );
      expect(
        gymPassVisitLabel(
          en,
          passPurchaseId: 'p1',
          names: names,
          enabled: false,
        ),
        isNull,
      );
    });

    test('names come from memberships with a plan name', () {
      final mine = GymPassesMine.fromJson({
        'memberships': [
          {
            'purchaseId': 'p1',
            'plan': {'name': ' Morning Pass '},
          },
          {'purchaseId': 'p2'},
        ],
      });
      expect(gymPassNamesById(mine), {'p1': 'Morning Pass'});
    });

    testWidgets('history shows the pass name, then generic, flag on', (
      tester,
    ) async {
      debugGymCustomPassesOverride = true;
      await tester.pumpWidget(
        _wrap(
          CheckinList(
            checkins: [
              _checkin('c1', passPurchaseId: 'p1'),
              _checkin('c2', passPurchaseId: 'p9'),
              _checkin('c3'),
            ],
            passNames: const {'p1': 'Morning Pass'},
          ),
        ),
      );
      expect(find.textContaining('Morning Pass'), findsOneWidget);
      expect(find.textContaining('Gym pass'), findsOneWidget);
    });

    testWidgets('flag off: history unchanged', (tester) async {
      debugGymCustomPassesOverride = false;
      await tester.pumpWidget(
        _wrap(
          CheckinList(
            checkins: [_checkin('c1', passPurchaseId: 'p1')],
            passNames: const {'p1': 'Morning Pass'},
          ),
        ),
      );
      expect(find.textContaining('Morning Pass'), findsNothing);
      expect(find.textContaining('Gym pass'), findsNothing);
    });
  });
}
