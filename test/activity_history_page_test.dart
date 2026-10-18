import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_activity_history_page.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/mock/mock_activity_provider.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 9, 23, 20);

Activity _act(String id, DateTime at, {String? gymId}) => Activity(
  id: id,
  userId: 'u1',
  type: ActivityType.strength,
  source: ActivitySource.manual,
  startedAt: at,
  durationMinutes: 40,
  gymId: gymId,
);

/// Serves [older] for any window, and records the windows asked for.
class _OlderProvider extends MockActivityProvider {
  _OlderProvider(this.batches);

  final List<List<Activity>> batches;
  final windows = <(DateTime, DateTime)>[];

  @override
  Future<List<Activity>> getActivities({
    required DateTime from,
    required DateTime to,
    String userId = '',
  }) async {
    windows.add((from, to));
    return batches.isEmpty ? const [] : batches.removeAt(0);
  }
}

Future<void> _pump(
  WidgetTester tester,
  MemberData data,
  _OlderProvider provider,
) async {
  tester.view.physicalSize = const Size(1080, 6000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'http://x');
  await tester.pumpWidget(
    AppScope(
      api: api,
      auth: AuthState(api),
      activityProvider: provider,
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
            body: MemberDataScope(
              data: data,
              child: MemberActivityHistoryPage(now: _now),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('weeks of the month, newest first, with dates', (tester) async {
    final data = MemberData()
      ..activityLoaded = true
      ..activities = [
        _act('sep23', DateTime(2026, 9, 23, 7)),
        _act('sep10', DateTime(2026, 9, 10, 7)),
        _act('aug30', DateTime(2026, 8, 30, 7)),
      ]
      ..checkins = [
        CheckIn(
          id: 'v1',
          memberId: 'u1',
          timestamp: DateTime(2026, 9, 9, 18).toUtc().toIso8601String(),
          gymTier: 'gold',
          gymId: 'gym_1',
          gym: Gym.fromJson({'id': 'gym_1', 'name': 'Iron House'}),
        ),
      ];
    await _pump(tester, data, _OlderProvider([]));

    expect(find.text('W4 · Sep 2026'), findsOneWidget);
    expect(find.text('22–30 Sep'), findsOneWidget);
    expect(find.text('W2 · Sep 2026'), findsOneWidget);
    expect(find.text('8–14 Sep'), findsOneWidget);
    expect(find.text('W4 · Aug 2026'), findsOneWidget);
    expect(find.text('22–31 Aug'), findsOneWidget);
    expect(find.text('Gym visit · Iron House'), findsOneWidget);

    double y(String key) => tester.getTopLeft(find.byKey(Key(key))).dy;
    expect(y('history-week-2026-9-4'), lessThan(y('history-week-2026-9-2')));
    expect(y('history-week-2026-9-2'), lessThan(y('history-week-2026-8-4')));
    // The visit (9 Sep 18:00) comes after 10 Sep within W2.
    expect(y('activity-sep10'), lessThan(y('visit-v1')));
  });

  testWidgets('Show older loads the window before, until one is empty', (
    tester,
  ) async {
    final data = MemberData()
      ..activityLoaded = true
      ..activities = [_act('sep23', DateTime(2026, 9, 23, 7))];
    final provider = _OlderProvider([
      [_act('may5', DateTime(2026, 5, 5, 7))],
    ]);
    await _pump(tester, data, provider);
    expect(find.text('W1 · May 2026'), findsNothing);

    await tester.tap(find.byKey(const Key('history-older')));
    await tester.pumpAndSettle();
    expect(find.text('W1 · May 2026'), findsOneWidget);
    expect(provider.windows.single.$2, DateTime(2026, 6, 25));

    await tester.tap(find.byKey(const Key('history-older')));
    await tester.pumpAndSettle();
    expect(provider.windows.length, 2);
    expect(find.byKey(const Key('history-older')), findsNothing);
    expect(find.byKey(const Key('history-end')), findsOneWidget);
  });
}
