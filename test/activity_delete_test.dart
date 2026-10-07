import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/activity_widgets.dart';
import 'package:fitflexmobile/screens/member/widgets/share_picker.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Api extends ApiClient {
  final deleted = <String>[];
  bool fail = false;

  @override
  Future<void> deleteActivity(String id) async {
    if (fail) throw Exception('offline');
    deleted.add(id);
  }

  @override
  Future<Map<String, dynamic>> myGroups() async => {'groups': []};
  @override
  Future<Map<String, dynamic>> socialSettings() async => {};
}

Activity _a(
  String id, {
  ActivitySource source = ActivitySource.manual,
  String? workoutId,
  int? movingSeconds,
  DevicePlatform? platform,
}) => Activity(
  id: id,
  userId: 'm1',
  type: ActivityType.running,
  source: source,
  startedAt: DateTime(2026, 9, 24, 7),
  durationMinutes: 30,
  distanceKm: 5,
  workoutId: workoutId,
  movingSeconds: movingSeconds,
  devicePlatform: platform,
  notes: 'Morning run',
);

Widget _app(ApiClient api, MemberData data, Widget child) => AppScope(
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
      home: MemberDataScope(
        data: data,
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  ),
);

void main() {
  test('only your own logged activities and recorded runs can be deleted', () {
    expect(canDeleteActivity(_a('manual')), isTrue);
    expect(
      canDeleteActivity(
        _a('run', source: ActivitySource.fitflex, movingSeconds: 1800),
      ),
      isTrue,
    );
    expect(
      canDeleteActivity(
        _a('workout', source: ActivitySource.fitflex, workoutId: 'w1'),
      ),
      isFalse,
      reason: 'a finished workout is deleted with its workout',
    );
    expect(
      canDeleteActivity(_a('trainer', source: ActivitySource.trainer)),
      isFalse,
    );
    expect(canDeleteActivity(_a('gym', source: ActivitySource.gym)), isFalse);
    expect(
      canDeleteActivity(
        _a(
          'steps',
          source: ActivitySource.device,
          platform: DevicePlatform.phoneSensor,
        ),
      ),
      isFalse,
    );
  });

  testWidgets('tap a logged activity → Delete → confirm removes it', (
    tester,
  ) async {
    final api = _Api();
    final a = _a('act_1');
    final data = MemberData()..activities = [a, _a('act_2')];
    await tester.pumpWidget(
      _app(
        api,
        data,
        ListenableBuilder(
          listenable: data,
          builder: (_, _) => Column(
            children: [
              for (final x in data.activities)
                ActivityTimelineTile(activity: x),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('activity-act_1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-action-share')), findsOneWidget);
    await tester.tap(find.byKey(const Key('activity-action-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this activity?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('activity-delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.deleted, ['act_1']);
    expect(data.activities.map((x) => x.id), ['act_2']);
    expect(find.text('Activity deleted.'), findsOneWidget);
    expect(find.byKey(const Key('activity-act_1')), findsNothing);
  });

  testWidgets('cancelling, or a failed delete, keeps the activity', (
    tester,
  ) async {
    final api = _Api()..fail = true;
    final a = _a('act_1');
    final data = MemberData()..activities = [a];
    await tester.pumpWidget(_app(api, data, ActivityTimelineTile(activity: a)));
    await tester.tap(find.byKey(const Key('activity-act_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activity-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(data.activities, hasLength(1));

    await tester.tap(find.byKey(const Key('activity-act_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activity-action-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('activity-delete-confirm')));
    await tester.pumpAndSettle();
    expect(data.activities, hasLength(1));
    expect(find.textContaining('Couldn\'t delete it'), findsOneWidget);
  });

  testWidgets('a trainer-logged activity offers sharing but not Delete', (
    tester,
  ) async {
    final a = _a('act_t', source: ActivitySource.trainer);
    final data = MemberData()..activities = [a];
    await tester.pumpWidget(
      _app(_Api(), data, ActivityTimelineTile(activity: a)),
    );
    await tester.tap(find.byKey(const Key('activity-act_t')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('activity-action-share')), findsOneWidget);
    expect(find.byKey(const Key('activity-action-delete')), findsNothing);
  });
}
