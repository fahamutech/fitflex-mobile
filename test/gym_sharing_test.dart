import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_privacy_page.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/owner/widgets/gym_engagement_widgets.dart';
import 'package:fitflexmobile/shared/activity/gym_sharing.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _app(ApiClient api, Widget child, {MemberData? data}) => AppScope(
  api: api,
  auth: AuthState(api),
  child: FFLocaleScope(
    notifier: FFLocale(),
    child: MaterialApp(
      theme: buildTheme(),
      supportedLocales: const [Locale('en'), Locale('sw')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(
        body: data == null
            ? ListView(children: [child])
            : MemberDataScope(data: data, child: child),
      ),
    ),
  ),
);

class _FakeApi extends ApiClient {
  final calls = <(String, Object?)>[];
  bool fail = false;
  List<Map<String, dynamic>> memberActivity = [];
  Map<String, dynamic> engagement = {};
  String? engagementGym;

  @override
  Future<Map<String, dynamic>> updateGymSharing(
    String gymId,
    Map<String, bool> permissions,
  ) async {
    calls.add((gymId, permissions));
    if (fail) throw Exception('offline');
    return {};
  }

  @override
  Future<List<dynamic>> ownerMemberActivity(String memberId) async =>
      memberActivity;

  @override
  Future<Map<String, dynamic>> ownerEngagement({String? gymId}) async {
    engagementGym = gymId;
    return engagement;
  }
}

GymSharing _gym({Map<String, bool> permissions = const {}}) =>
    GymSharing.tryParse({
      'gym': {'id': 'g1', 'name': 'Mikocheni Fitness'},
      'reasons': ['member', 'visited'],
      'permissions': permissions,
    })!;

Map<String, dynamic> _activity({
  Map<String, bool> permissions = const {},
  List<Map<String, dynamic>>? classes,
  List<Map<String, dynamic>>? workouts,
}) => {
  'gym': {'id': 'g1', 'name': 'Mikocheni Fitness'},
  'permissions': permissions,
  'engagement': {
    'visits30': 9,
    'previous30': 6,
    'lastVisit': '2026-09-22',
    'daysSinceLastVisit': 2,
    'weekStreak': 5,
    'avgVisitsPerWeek': 2.1,
    'status': 'active',
  },
  'classAttendance': ?classes,
  'gymWorkouts': ?workouts,
};

void main() {
  group('member: gym sharing', () {
    Future<(MemberData, _FakeApi)> pump(
      WidgetTester tester, {
      Map<String, bool> permissions = const {},
    }) async {
      tester.view.physicalSize = const Size(1080, 3000);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final api = _FakeApi();
      final data = MemberData()..gymSharing = [_gym(permissions: permissions)];
      await tester.pumpWidget(
        _app(api, const MemberActivitySharingPage(), data: data),
      );
      return (data, api);
    }

    bool on(WidgetTester tester, String p) =>
        tester.widget<Switch>(find.byKey(Key('gym-share-$p-g1'))).value;

    testWidgets('check-ins are always the gym\'s; everything else starts off', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Gyms'), findsOneWidget);
      expect(find.text('Mikocheni Fitness'), findsOneWidget);
      expect(find.text('Your gym'), findsOneWidget);
      expect(find.byKey(const Key('gym-always-g1')), findsOneWidget);
      expect(find.textContaining('your check-ins there'), findsOneWidget);
      for (final p in GymPermission.values) {
        expect(on(tester, p.wire), isFalse, reason: p.wire);
      }
      expect(
        find.text(
          'Gyms never see your steps, goals, streaks, or anything you do elsewhere.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a switch saves straight away for that gym', (tester) async {
      final (data, api) = await pump(tester);
      await tester.tap(find.byKey(const Key('gym-share-classAttendance-g1')));
      await tester.pumpAndSettle();
      expect(api.calls.single.$1, 'g1');
      expect(api.calls.single.$2, {
        'classAttendance': true,
        'gymWorkouts': false,
        'challenges': false,
      });
      expect(data.gymSharing.single.permissions, {
        GymPermission.classAttendance,
      });
      expect(on(tester, 'classAttendance'), isTrue);
      expect(
        find.text('Saved. Mikocheni Fitness sees this change right away.'),
        findsOneWidget,
      );
    });

    testWidgets('a failed save keeps the old setting', (tester) async {
      final (data, api) = await pump(
        tester,
        permissions: {'gymWorkouts': true},
      );
      api.fail = true;
      await tester.tap(find.byKey(const Key('gym-share-gymWorkouts-g1')));
      await tester.pumpAndSettle();
      expect(on(tester, 'gymWorkouts'), isTrue);
      expect(data.gymSharing.single.permissions, {GymPermission.gymWorkouts});
    });
  });

  group('gym owner', () {
    testWidgets(
      'member card shows visit patterns and says nothing else is shared',
      (tester) async {
        final api = _FakeApi()..memberActivity = [_activity()];
        await tester.pumpWidget(
          _app(api, const GymMemberActivityCard(memberId: 'm1')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Engagement'), findsOneWidget);
        expect(find.text('Active'), findsOneWidget);
        expect(
          find.text(
            '9 visits in 30 days · 2.1 a week · 5-week visit streak'
                .split(' · ')
                .map((f) => f.replaceAll(' ', '\u00A0'))
                .join(' · '),
          ),
          findsOneWidget,
        );
        expect(find.text('Last visit 2 days ago'), findsOneWidget);
        expect(find.byKey(const Key('gym-nothing-shared')), findsOneWidget);
      },
    );

    testWidgets('shared classes and workouts show when, what and how long', (
      tester,
    ) async {
      final api = _FakeApi()
        ..memberActivity = [
          _activity(
            permissions: {'classAttendance': true, 'gymWorkouts': true},
            classes: [
              {
                'date': '2026-09-20',
                'type': 'group_class',
                'durationMinutes': 50,
              },
            ],
            workouts: [
              {'date': '2026-09-22', 'type': 'strength', 'durationMinutes': 45},
            ],
          ),
        ];
      await tester.pumpWidget(
        _app(api, const GymMemberActivityCard(memberId: 'm1')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gym-nothing-shared')), findsNothing);
      expect(find.text('1 class attended'), findsOneWidget);
      expect(find.text('Sun 20 Sep · 50 min'), findsOneWidget);
      expect(find.text('1 workout at your gym'), findsOneWidget);
      expect(find.text('Tue 22 Sep · Strength · 45 min'), findsOneWidget);
    });

    testWidgets('card stays out of the way for members of other gyms', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(_FakeApi(), const GymMemberActivityCard(memberId: 'm1')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('gym-member-activity')), findsNothing);
    });

    testWidgets('dashboard: engagement bands and who to check in with', (
      tester,
    ) async {
      String? opened;
      final api = _FakeApi()
        ..engagement = {
          'members': 42,
          'active': 30,
          'slipping': 5,
          'at_risk': 4,
          'lapsed': 3,
          'newThisMonth': 6,
          'checkIn': [
            {
              'member': {'id': 'm2', 'displayName': 'Baraka'},
              'daysSinceLastVisit': 19,
              'status': 'at_risk',
            },
          ],
        };
      await tester.pumpWidget(
        _app(
          api,
          GymEngagementCard(gymId: 'g1', onOpenMember: (id) => opened = id),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.engagementGym, 'g1');
      expect(find.text('Member engagement'), findsOneWidget);
      expect(
        find.text('42 members visited in the last 90 days · 6 new this month'),
        findsOneWidget,
      );
      for (final n in ['30', '5', '4', '3']) {
        expect(find.text(n), findsOneWidget);
      }
      expect(find.text('Worth a check-in'), findsOneWidget);
      await tester.tap(find.byKey(const Key('engagement-member-m2')));
      expect(opened, 'm2');
    });
  });
}
