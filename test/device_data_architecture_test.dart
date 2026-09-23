import 'dart:io';

import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/activity_provider.dart';
import 'package:fitflexmobile/shared/activity/activity_summary.dart';
import 'package:fitflexmobile/shared/activity/api_activity_provider.dart';
import 'package:fitflexmobile/shared/activity/mock/mock_activity_provider.dart';
import 'package:fitflexmobile/shared/activity/providers/apple_health_provider.dart';
import 'package:fitflexmobile/shared/activity/providers/health_connect_provider.dart';
import 'package:fitflexmobile/shared/activity/providers/wearable_provider.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(2026, 9, 23, 12);
final _from = DateTime(2026, 9, 17);
final _to = DateTime(2026, 9, 24);

Activity _a(
  String id,
  int day, {
  ActivityType type = ActivityType.walking,
  ActivitySource source = ActivitySource.device,
  int? steps,
  int? active,
  int? duration,
  double? km,
}) => Activity(
  id: id,
  userId: 'u1',
  type: type,
  source: source,
  startedAt: DateTime(2026, 9, day, 8),
  steps: steps,
  activeMinutes: active,
  durationMinutes: duration,
  distanceKm: km,
);

/// FitFlex API answering `/me/activities` from a fixed list.
class _Api extends ApiClient {
  _Api(this.rows);
  final List<Activity> rows;

  @override
  Future<List<dynamic>> myActivities({
    required DateTime from,
    required DateTime to,
  }) async => [
    for (final a in rows)
      if (!a.startedAt.isBefore(from) && a.startedAt.isBefore(to)) a.toJson(),
    {'id': 'broken'}, // one bad row must not hide the rest
  ];
}

final _rows = [
  _a('walk', 18, steps: 6000, km: 4.2),
  _a(
    'run',
    20,
    type: ActivityType.running,
    source: ActivitySource.fitflex,
    duration: 30,
    km: 5,
  ),
  _a(
    'lift',
    20,
    type: ActivityType.strength,
    source: ActivitySource.manual,
    active: 45,
  ),
  _a('walk2', 22, steps: 9000, active: 20, km: 6.1),
  _a('old', 10, steps: 99999),
];

void main() {
  group('provider contract', () {
    final providers = <String, ActivityProvider>{
      'mock': MockActivityProvider(clock: () => _today),
      'api': ApiActivityProvider(_Api(_rows)),
    };

    for (final MapEntry(key: name, value: p) in providers.entries) {
      group(name, () {
        test('totals agree with the progress engine\'s day rules', () async {
          final acts = await p.getActivities(
            from: _from,
            to: _to,
            userId: 'u1',
          );
          final days = [
            for (var d = 17; d < 24; d++)
              summarizeDay(acts, DateTime(2026, 9, d)),
          ];

          final steps = await p.getDailySteps(from: _from, to: _to);
          expect(
            steps.map((s) => s.day),
            [for (var d = 17; d < 24; d++) DateTime(2026, 9, d)],
            reason: 'every day, including empty ones, oldest first',
          );
          expect(steps.map((s) => s.value), days.map((d) => d.steps));

          expect(
            await p.getDistance(from: _from, to: _to),
            closeTo(days.fold<double>(0, (k, d) => k + d.distanceKm), 1e-9),
          );
          expect(
            await p.getActiveMinutes(from: _from, to: _to),
            days.fold<int>(0, (m, d) => m + d.activeMinutes),
          );
          final workouts = await p.getWorkouts(from: _from, to: _to);
          expect(workouts.every((w) => w.isWorkout), isTrue);
          expect(
            workouts.length,
            days.fold<int>(0, (n, d) => n + d.workoutCount),
          );
        });

        test('newest first, inside the window', () async {
          final acts = await p.getActivities(from: _from, to: _to);
          expect(acts, isNotEmpty);
          for (var i = 1; i < acts.length; i++) {
            expect(acts[i - 1].startedAt.isBefore(acts[i].startedAt), isFalse);
          }
          expect(
            acts.every(
              (a) => !a.startedAt.isBefore(_from) && a.startedAt.isBefore(_to),
            ),
            isTrue,
          );
        });

        test('describes itself', () async {
          expect(await p.isAvailable(), isTrue);
          expect(p.supports, ActivityDataType.values.toSet());
        });
      });
    }

    test(
      'API provider: sessions only, background walks aren\'t workouts',
      () async {
        final p = ApiActivityProvider(_Api(_rows));
        expect(p.kind, ActivityProviderKind.fitflex);
        expect(
          (await p.getWorkouts(from: _from, to: _to)).map((a) => a.id),
          unorderedEquals(['run', 'lift']),
        );
        expect(await p.getDistance(from: _from, to: _to), closeTo(15.3, 1e-9));
        expect(await p.getActiveMinutes(from: _from, to: _to), 30 + 45 + 20);
        expect(
          (await p.getDailySteps(from: _from, to: _to)).map((d) => d.value),
          [0, 6000, 0, 0, 0, 9000, 0],
        );
      },
    );

    test('mock provider is marked as sample data', () {
      expect(MockActivityProvider().kind, ActivityProviderKind.sample);
    });
  });

  group('planned providers', () {
    final planned = <ActivityProvider>[
      const AppleHealthProvider(),
      const HealthConnectProvider(),
      const WearableProvider(vendor: 'garmin'),
    ];
    test('are unavailable and return no data until built', () async {
      for (final p in planned) {
        expect(await p.isAvailable(), isFalse, reason: p.id);
        expect(await p.requestAccess(), isFalse, reason: p.id);
        expect(await p.getActivities(from: _from, to: _to), isEmpty);
        expect(await p.getDailySteps(from: _from, to: _to), isEmpty);
        expect(await p.getDistance(from: _from, to: _to), 0);
        expect(await p.getActiveMinutes(from: _from, to: _to), 0);
        expect(await p.getWorkouts(from: _from, to: _to), isEmpty);
      }
      expect(planned.map((p) => p.kind), [
        ActivityProviderKind.appleHealth,
        ActivityProviderKind.healthConnect,
        ActivityProviderKind.wearable,
      ]);
      expect(planned.map((p) => p.id), [
        'apple_health',
        'health_connect',
        'wearable_garmin',
      ]);
    });
  });

  group('architecture', () {
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    String rel(File f) => f.path.replaceAll('\\', '/');
    List<String> imports(File f) => [
      for (final m in RegExp(
        r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
        multiLine: true,
      ).allMatches(f.readAsStringSync()))
        m.group(1)!,
    ];

    // Health platform and wearable SDKs.
    const healthPackages = [
      'package:health/',
      'package:health_kit',
      'package:flutter_health',
      'package:health_connect',
      'package:flutter_health_connect',
      'package:fitbit',
      'package:garmin',
      'package:wear',
    ];

    test('only providers/ may use a health platform package', () {
      final offenders = [
        for (final f in files)
          if (!rel(f).startsWith('lib/shared/activity/providers/'))
            for (final i in imports(f))
              if (healthPackages.any(i.startsWith)) '${rel(f)} → $i',
      ];
      expect(offenders, isEmpty);
    });

    test('only activity_config.dart picks a concrete provider', () {
      final concrete = RegExp(
        r'(mock_activity_provider|api_activity_provider|providers/[a-z_]+)\.dart$',
      );
      final offenders = [
        for (final f in files)
          if (!rel(f).startsWith('lib/shared/activity/'))
            for (final i in imports(f))
              if (concrete.hasMatch(i)) '${rel(f)} → $i',
      ];
      expect(offenders, isEmpty);
      final inside = [
        for (final f in files)
          if (rel(f).startsWith('lib/shared/activity/') &&
              !rel(f).startsWith('lib/shared/activity/providers/') &&
              !rel(f).startsWith('lib/shared/activity/mock/') &&
              !rel(f).endsWith('/activity_config.dart'))
            for (final i in imports(f))
              if (concrete.hasMatch(i)) '${rel(f)} → $i',
      ];
      expect(inside, isEmpty);
    });

    test('the progress engine works on activities, not providers', () {
      const engine = [
        'activity_summary.dart',
        'progress_engine.dart',
        'streaks.dart',
        'challenge.dart',
        'goal.dart',
        'workout.dart',
        'workout_summary.dart',
      ];
      final offenders = [
        for (final f in files)
          if (engine.any((e) => rel(f) == 'lib/shared/activity/$e'))
            for (final i in imports(f))
              if (i.contains('provider') || i.contains('api_client'))
                '${rel(f)} → $i',
      ];
      expect(offenders, isEmpty);
      expect(
        files.where((f) => engine.any((e) => rel(f).endsWith('/$e'))),
        hasLength(engine.length),
        reason: 'engine files moved? update this list',
      );
    });
  });
}
