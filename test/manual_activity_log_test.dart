import 'dart:convert';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/activity_widgets.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/activity_summary.dart';
import 'package:fitflexmobile/shared/activity/goal.dart';
import 'package:fitflexmobile/shared/activity/manual_activity_log.dart';
import 'package:fitflexmobile/shared/activity/progress_engine.dart';
import 'package:fitflexmobile/shared/activity/sample_activity_log.dart';
import 'package:fitflexmobile/shared/activity/streaks.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Thursday 24 Sep 2026, 18:00.
final _now = DateTime(2026, 9, 24, 18);

ManualActivityDraft _walk({
  int? minutes = 45,
  double? km = 4.2,
  int? steps = 6100,
  DateTime? at,
  String? notes,
}) => ManualActivityDraft(
  type: ActivityType.walking,
  startedAt: at ?? DateTime(2026, 9, 24, 7, 30),
  durationMinutes: minutes,
  distanceKm: km,
  steps: steps,
  notes: notes,
);

/// Records drafts; succeeds, or throws [error].
class _FakeLog implements ManualActivityLog {
  final drafts = <ManualActivityDraft>[];
  Object? error;

  @override
  Future<Activity> log(ManualActivityDraft d) async {
    drafts.add(d);
    if (error != null) throw error!;
    return Activity(
      id: 'act_new',
      userId: 'u1',
      type: d.type,
      source: ActivitySource.manual,
      startedAt: d.startedAt,
      durationMinutes: d.durationMinutes,
      distanceKm: d.distanceKm,
      steps: d.steps,
      notes: d.notesForBackend,
    );
  }
}

Future<void> _pumpPage(
  WidgetTester tester, {
  required ManualActivityLog log,
  required MemberData data,
}) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: '/member/activity/log',
    routes: [
      GoRoute(
        path: '/member/activity',
        builder: (_, _) => const Scaffold(body: Text('activity-home')),
        routes: [
          GoRoute(
            path: 'log',
            builder: (_, _) => Scaffold(body: MemberLogActivityPage(now: _now)),
          ),
        ],
      ),
    ],
  );
  final api = ApiClient(baseUrl: 'http://x');
  await tester.pumpWidget(
    AppScope(
      api: api,
      auth: AuthState(api),
      manualActivityLog: log,
      child: FFLocaleScope(
        notifier: FFLocale(),
        child: MemberDataScope(
          data: data,
          child: MaterialApp.router(
            theme: buildTheme(),
            routerConfig: router,
            supportedLocales: const [Locale('en'), Locale('sw')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('fields per type', () {
    test('walking-like types take distance and steps', () {
      for (final t in [
        ActivityType.walking,
        ActivityType.running,
        ActivityType.jogging,
        ActivityType.hiking,
      ]) {
        final f = manualFieldsFor(t);
        expect(
          [f.distance, f.steps, f.name],
          [true, true, false],
          reason: '$t',
        );
      }
      final bike = manualFieldsFor(ActivityType.cycling);
      expect([bike.distance, bike.steps], [true, false]);
    });

    test('workouts take a name and intensity, never steps', () {
      for (final t in [
        ActivityType.strength,
        ActivityType.hiit,
        ActivityType.functional,
        ActivityType.sports,
      ]) {
        final f = manualFieldsFor(t);
        expect(
          [f.name, f.intensity, f.steps, f.distance],
          [true, true, false, false],
          reason: '$t',
        );
      }
      final m = manualFieldsFor(ActivityType.mobility);
      expect([m.name, m.distance, m.steps], [false, false, false]);
    });

    test('the picker offers exactly the brief\'s 13 types', () {
      expect(manualActivityTypes, hasLength(13));
      expect(manualActivityTypes, isNot(contains(ActivityType.groupClass)));
      expect(
        manualActivityTypes,
        isNot(contains(ActivityType.personalTraining)),
      );
    });
  });

  group('validation (mirrors the backend limits)', () {
    String? err(ManualActivityDraft d, String field) =>
        validateManualActivity(d, _now)[field];

    test('duration is required and bounded', () {
      expect(err(_walk(minutes: null), 'duration'), contains('Required'));
      expect(err(_walk(minutes: 0), 'duration'), contains('Range'));
      expect(err(_walk(minutes: 1441), 'duration'), contains('Range'));
      expect(validateManualActivity(_walk(), _now), isEmpty);
    });

    test('no future starts, nothing older than 90 days', () {
      expect(
        err(_walk(at: DateTime(2026, 9, 24, 19)), 'startedAt'),
        contains('future'),
      );
      expect(
        err(_walk(at: DateTime(2026, 9, 24, 18, 4)), 'startedAt'),
        isNull,
        reason: 'clock-skew allowance, as on the server',
      );
      expect(
        err(_walk(at: DateTime(2026, 6, 1)), 'startedAt'),
        contains('tooOld'),
      );
    });

    test('distance and steps ranges', () {
      expect(err(_walk(km: 0), 'distance'), isNotNull);
      expect(err(_walk(km: 500.1), 'distance'), isNotNull);
      expect(err(_walk(steps: 0), 'steps'), isNotNull);
      expect(err(_walk(steps: 200001), 'steps'), isNotNull);
      expect(err(_walk(km: null, steps: null), 'distance'), isNull);
    });

    test('name and notes lengths', () {
      final long = ManualActivityDraft(
        type: ActivityType.strength,
        startedAt: DateTime(2026, 9, 24, 7),
        durationMinutes: 40,
        name: 'x' * 81,
      );
      expect(validateManualActivity(long, _now)['name'], isNotNull);
      final notes = ManualActivityDraft(
        type: ActivityType.strength,
        startedAt: DateTime(2026, 9, 24, 7),
        durationMinutes: 40,
        name: 'Legs',
        notes: 'y' * 496,
      );
      expect(
        validateManualActivity(notes, _now)['notes'],
        isNotNull,
        reason: 'name + newline + notes over 500',
      );
    });
  });

  group('backend contract', () {
    test('walking: type, start, duration, distance, steps, notes', () {
      expect(_walk(notes: '  Morning loop ').toJson(), {
        'type': 'walking',
        'startedAt': DateTime(2026, 9, 24, 7, 30).toUtc().toIso8601String(),
        'durationMinutes': 45,
        'distanceKm': 4.2,
        'steps': 6100,
        'notes': 'Morning loop',
      });
    });

    test('strength: the name leads the notes; no steps or distance', () {
      final d = ManualActivityDraft(
        type: ActivityType.strength,
        startedAt: DateTime(2026, 9, 24, 17),
        durationMinutes: 50,
        distanceKm: 3,
        steps: 999,
        intensity: ActivityIntensity.high,
        name: ' Upper body ',
        notes: 'Felt strong',
      );
      final body = d.toJson();
      expect(body['notes'], 'Upper body\nFelt strong');
      expect(body['intensity'], 'high');
      expect(body.containsKey('distanceKm'), isFalse);
      expect(body.containsKey('steps'), isFalse);
      expect(
        body.containsKey('source'),
        isFalse,
        reason: 'the server stamps manual; members can\'t pick a source',
      );
    });

    test('the logged name shows back in history', () {
      final a = Activity(
        id: 'a',
        userId: 'u',
        type: ActivityType.strength,
        source: ActivitySource.manual,
        startedAt: _now,
        notes: 'Upper body\nFelt strong',
      );
      expect(manualActivityName(a), 'Upper body');
      final walk = Activity(
        id: 'w',
        userId: 'u',
        type: ActivityType.walking,
        source: ActivitySource.manual,
        startedAt: _now,
        notes: 'Nice day',
      );
      expect(manualActivityName(walk), isNull);
    });

    test('API log posts to /me/activities and parses the saved row', () async {
      late http.Request sent;
      final client = MockClient((req) async {
        sent = req;
        return http.Response(
          jsonEncode({
            'activity': {
              'id': 'act_123',
              'userId': 'u1',
              'type': 'walking',
              'source': 'manual',
              'startedAt': '2026-09-24T04:30:00.000Z',
              'durationMinutes': 45,
              'distanceKm': 4.2,
              'steps': 6100,
            },
          }),
          201,
        );
      });
      final saved = await http.runWithClient(
        () =>
            ApiManualActivityLog(ApiClient(baseUrl: 'http://api')).log(_walk()),
        () => client,
      );
      expect(sent.method, 'POST');
      expect(sent.url.path, '/me/activities');
      expect(jsonDecode(sent.body), _walk().toJson());
      expect(saved.id, 'act_123');
      expect(saved.origin, DataOrigin.manual);
    });

    test('a rejected entry surfaces as an ApiException', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'error': 'invalid_steps'}), 400),
      );
      await expectLater(
        http.runWithClient(
          () => ApiManualActivityLog(
            ApiClient(baseUrl: 'http://api'),
          ).log(_walk()),
          () => client,
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test(
      'sample mode keeps entries in the session log, marked sample',
      () async {
        final log = SampleActivityLog();
        final a = await LocalManualActivityLog(sampleLog: log).log(_walk());
        expect(log.items.single.id, a.id);
        expect(a.source, ActivitySource.manual);
        expect(a.isSample, isTrue);
      },
    );
  });

  group('Log activity page', () {
    testWidgets('fields follow the activity type', (tester) async {
      await _pumpPage(tester, log: _FakeLog(), data: MemberData());
      expect(find.byKey(const Key('log-distance')), findsOneWidget);
      expect(find.byKey(const Key('log-steps')), findsOneWidget);
      expect(find.byKey(const Key('log-name')), findsNothing);

      await tester.tap(find.byKey(const Key('log-type-strength')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('log-name')), findsOneWidget);
      expect(find.byKey(const Key('log-intensity-high')), findsOneWidget);
      expect(find.byKey(const Key('log-steps')), findsNothing);
      expect(find.byKey(const Key('log-distance')), findsNothing);
      expect(find.text('e.g. Upper body'), findsOneWidget);

      await tester.tap(find.byKey(const Key('log-type-cycling')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('log-distance')), findsOneWidget);
      expect(find.byKey(const Key('log-steps')), findsNothing);
    });

    testWidgets('required duration is checked before anything is sent', (
      tester,
    ) async {
      final log = _FakeLog();
      await _pumpPage(tester, log: log, data: MemberData());
      await tester.tap(find.byKey(const Key('log-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter how long it lasted, in minutes.'),
        findsOneWidget,
      );
      expect(log.drafts, isEmpty);

      await tester.enterText(find.byKey(const Key('log-duration')), '45');
      await tester.enterText(find.byKey(const Key('log-steps')), '300000');
      await tester.tap(find.byKey(const Key('log-save')));
      await tester.pumpAndSettle();
      expect(find.text('Steps must be between 1 and 200,000.'), findsOneWidget);
      expect(log.drafts, isEmpty);
    });

    testWidgets(
      'saving updates history, totals, goals and streaks, then goes back',
      (tester) async {
        final log = _FakeLog();
        final stepGoal = Goal(
          id: 'g',
          userId: 'u1',
          type: GoalType.steps,
          target: 8000,
          period: GoalPeriod.day,
          startDate: DateTime(2026, 9, 1),
        );
        final data = MemberData()
          ..activityLoaded = true
          ..goals = [stepGoal];
        await _pumpPage(tester, log: log, data: data);

        await tester.enterText(find.byKey(const Key('log-duration')), '45');
        await tester.enterText(find.byKey(const Key('log-distance')), '4,2');
        await tester.enterText(find.byKey(const Key('log-steps')), '6100');
        await tester.tap(find.byKey(const Key('log-save')));
        await tester.pumpAndSettle();

        final d = log.drafts.single;
        expect(d.type, ActivityType.walking);
        expect(d.durationMinutes, 45);
        expect(d.distanceKm, 4.2, reason: 'comma decimals accepted');
        expect(d.startedAt, DateTime(2026, 9, 24, 17, 0));

        // History
        expect(data.activities.single.id, 'act_new');
        // Daily metrics
        final today = summarizeDay(data.activities, _now);
        expect(today.steps, 6100);
        expect(today.activeMinutes, 45);
        // Goal progress
        expect(evaluateGoal(stepGoal, data.activities, _now).current, 6100);
        // Streak: 45 active minutes qualifies the day.
        expect(
          computeStreak(
            StreakKind.activity,
            today: _now,
            activities: data.activities,
          )!.current,
          1,
        );
        // Back on Activity with a confirmation.
        expect(find.text('activity-home'), findsOneWidget);
        expect(find.text('Activity logged'), findsOneWidget);
      },
    );

    testWidgets('server and network errors keep the form and explain', (
      tester,
    ) async {
      final log = _FakeLog()
        ..error = ApiException(400, {'error': 'invalid_steps'});
      final data = MemberData();
      await _pumpPage(tester, log: log, data: data);
      await tester.enterText(find.byKey(const Key('log-duration')), '30');
      await tester.tap(find.byKey(const Key('log-save')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('log-submit-error')), findsOneWidget);
      expect(find.byKey(const Key('log-activity')), findsOneWidget);
      expect(data.activities, isEmpty);

      log.error = http.ClientException('Failed host lookup');
      await tester.tap(find.byKey(const Key('log-save')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const Key('log-submit-error')),
          matching: find.textContaining(FFLocale().t('error.network')),
        ),
        findsOneWidget,
      );
      expect(log.drafts, hasLength(2));
    });
  });

  testWidgets('a logged strength session reads by its name, as Manual', (
    tester,
  ) async {
    await tester.pumpWidget(
      FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp(
          theme: buildTheme(),
          home: Scaffold(
            body: ActivityTimelineTile(
              activity: Activity(
                id: 'm1',
                userId: 'u1',
                type: ActivityType.strength,
                source: ActivitySource.manual,
                startedAt: _now,
                durationMinutes: 50,
                notes: 'Upper body\nFelt strong',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Upper body'), findsOneWidget);
    expect(find.text('Manual'), findsOneWidget);
  });
}
