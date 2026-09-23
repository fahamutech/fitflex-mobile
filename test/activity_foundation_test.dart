import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/activity/activity_provider.dart';
import 'package:fitflexmobile/shared/activity/mock/mock_activity_data.dart';
import 'package:fitflexmobile/shared/activity/mock/mock_activity_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Activity model', () {
    test('round-trips through JSON, omitting absent metrics', () {
      final activity = Activity(
        id: 'a1',
        userId: 'u1',
        type: ActivityType.personalTraining,
        source: ActivitySource.trainer,
        startedAt: DateTime.utc(2026, 9, 20, 17),
        durationMinutes: 60,
        intensity: ActivityIntensity.high,
        trainerId: 't1',
      );

      final json = activity.toJson();
      expect(json['type'], 'personal_training');
      expect(json['source'], 'trainer');
      expect(json.containsKey('distanceKm'), isFalse);
      expect(json.containsKey('steps'), isFalse);

      final back = Activity.fromJson(json);
      expect(back.type, ActivityType.personalTraining);
      expect(back.source, ActivitySource.trainer);
      expect(back.startedAt, DateTime.utc(2026, 9, 20, 17));
      expect(back.durationMinutes, 60);
      expect(back.trainerId, 't1');
      expect(back.distanceKm, isNull);
      expect(back.endedAt, DateTime.utc(2026, 9, 20, 18));
    });

    test('tolerates unknown type/source and numeric ints as doubles', () {
      final a = Activity.fromJson({
        'id': 'a2',
        'userId': 'u1',
        'type': 'underwater_basket_weaving',
        'source': 'smart_fridge',
        'startedAt': '2026-09-21T06:00:00Z',
        'distanceKm': 5,
        'steps': 6500.0,
      });
      expect(a.type, ActivityType.other);
      expect(a.source, ActivitySource.manual);
      expect(a.distanceKm, 5.0);
      expect(a.steps, 6500);
      expect(a.intensity, isNull);
    });

    test('rejects an activity without a start time', () {
      expect(
        () => Activity.fromJson({'id': 'a3', 'type': 'walking'}),
        throwsFormatException,
      );
    });

    test('supports every activity type and source in the spec', () {
      expect(ActivityType.values.map((t) => t.wire), [
        'walking',
        'running',
        'jogging',
        'cycling',
        'hiking',
        'swimming',
        'sports',
        'strength',
        'hiit',
        'functional',
        'group_class',
        'personal_training',
        'mobility',
        'stretching',
        'other',
      ]);
      expect(ActivitySource.values.map((s) => s.wire), [
        'device',
        'fitflex',
        'manual',
        'trainer',
        'gym',
      ]);
    });
  });

  group('MockActivityProvider', () {
    final today = DateTime(2026, 9, 23, 12);
    final ActivityProvider provider = MockActivityProvider(clock: () => today);

    Future<List<Activity>> history() => provider.getActivities(
      userId: 'u1',
      from: DateTime(2026, 1, 1),
      to: DateTime(2027, 1, 1),
    );

    test('covers several weeks with a realistic mix', () async {
      final acts = await history();
      final days = acts
          .map(
            (a) =>
                DateTime(a.startedAt.year, a.startedAt.month, a.startedAt.day),
          )
          .toSet();

      expect(acts.every((a) => a.userId == 'u1'), isTrue);
      expect(acts.every((a) => a.id.startsWith('mock_')), isTrue);
      // Active days and rest days both exist across 42 days.
      expect(days.length, greaterThan(21));
      expect(days.length, lessThan(42));

      final types = acts.map((a) => a.type).toSet();
      expect(
        types,
        containsAll([
          ActivityType.walking,
          ActivityType.running,
          ActivityType.strength,
        ]),
      );
      final steps = acts.map((a) => a.steps).whereType<int>().toSet();
      expect(steps.length, greaterThan(10));
      expect(acts.any((a) => a.gymId == mockGymId), isTrue);
    });

    test('is newest-first and respects the requested window', () async {
      final week = await provider.getActivities(
        userId: 'u1',
        from: DateTime(2026, 9, 17),
        to: DateTime(2026, 9, 24),
      );
      expect(week, isNotEmpty);
      for (var i = 1; i < week.length; i++) {
        expect(week[i - 1].startedAt.isBefore(week[i].startedAt), isFalse);
      }
      expect(
        week.every((a) => !a.startedAt.isBefore(DateTime(2026, 9, 17))),
        isTrue,
      );
    });

    test('keeps past days stable as the clock advances', () async {
      final later = MockActivityProvider(
        clock: () => today.add(const Duration(days: 3)),
      );
      final window = (from: DateTime(2026, 9, 1), to: DateTime(2026, 9, 10));
      final a = await provider.getActivities(
        userId: 'u1',
        from: window.from,
        to: window.to,
      );
      final b = await later.getActivities(
        userId: 'u1',
        from: window.from,
        to: window.to,
      );
      expect(b.map((x) => x.toJson()), a.map((x) => x.toJson()));
    });

    test('includes a multi-day inactive gap', () async {
      final active = (await history())
          .map(
            (a) =>
                DateTime(a.startedAt.year, a.startedAt.month, a.startedAt.day),
          )
          .toSet();
      var longest = 0, run = 0;
      for (var back = 41; back >= 0; back--) {
        final d = DateTime(today.year, today.month, today.day - back);
        run = active.contains(d) ? 0 : run + 1;
        if (run > longest) longest = run;
      }
      expect(longest, greaterThanOrEqualTo(3));
    });
  });
}
