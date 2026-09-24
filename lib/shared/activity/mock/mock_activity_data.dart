/// Generated demo activity history. Mock-only — nothing here is read from or
/// written to the FitFlex backend, and every id is prefixed `mock_` so it can
/// never be mistaken for production data.
library;

import 'dart:math';

import '../activity.dart';

const mockGymId = 'mock_gym_downtown';
const mockTrainerId = 'mock_trainer_amani';

/// Every 30 days the member is ill for three days and logs nothing — a
/// realistic gap for streak logic to deal with. Anchored to calendar dates
/// (not to "today") so past history doesn't shift as the clock moves.
bool _isSickDay(DateTime date) =>
    DateTime.utc(
          date.year,
          date.month,
          date.day,
        ).difference(DateTime.utc(1970)).inDays %
        30 <
    3;

/// Builds [days] days of history ending on [today], oldest to newest.
///
/// Each calendar day is seeded from its own date, so a given day always has
/// the same activities no matter when the history is generated — the history
/// stays stable as the clock moves forward.
List<Activity> generateMockActivities({
  required String userId,
  required DateTime today,
  int days = 42,
}) {
  final out = <Activity>[];
  for (var back = days - 1; back >= 0; back--) {
    final date = DateTime(today.year, today.month, today.day - back);
    out.addAll(_activitiesForDay(userId, date, sick: _isSickDay(date)));
  }
  return out;
}

List<Activity> _activitiesForDay(
  String userId,
  DateTime date, {
  required bool sick,
}) {
  final rng = Random(date.year * 10000 + date.month * 100 + date.day);
  if (sick) return const [];
  // Most Sundays are full rest days.
  if (date.weekday == DateTime.sunday && rng.nextDouble() < 0.7) {
    return const [];
  }

  final day = _DayBuilder(userId, date);

  // Background walking, as a step count would arrive from a phone or watch.
  final steps = 3000 + rng.nextInt(8500);
  final walkMinutes = steps ~/ 110;
  day.add(
    ActivityType.walking,
    ActivitySource.device,
    hour: 7,
    minutes: walkMinutes,
    steps: steps,
    activeMinutes: walkMinutes,
    distanceKm: steps * 0.00075,
    intensity: ActivityIntensity.low,
    notes: 'Daily steps',
  );

  // Structured sessions are skipped about one time in five.
  final skipped = rng.nextDouble() < 0.2;
  if (skipped) return day.activities;
  final evenWeek = _weekOfYear(date).isEven;

  switch (date.weekday) {
    case DateTime.monday:
    case DateTime.thursday:
      day.add(
        ActivityType.strength,
        ActivitySource.fitflex,
        hour: 18,
        minutes: 45 + rng.nextInt(26),
        intensity: rng.nextBool()
            ? ActivityIntensity.moderate
            : ActivityIntensity.high,
        gymId: mockGymId,
      );
    case DateTime.tuesday:
      final km = 5 + rng.nextInt(4) + rng.nextDouble();
      day.add(
        ActivityType.running,
        ActivitySource.fitflex,
        hour: 6,
        minutes: (km * 6).round(),
        distanceKm: km,
        steps: (km * 1300).round(),
        intensity: ActivityIntensity.high,
      );
    case DateTime.wednesday:
      if (evenWeek) {
        day.add(
          ActivityType.personalTraining,
          ActivitySource.trainer,
          hour: 17,
          minutes: 60,
          intensity: ActivityIntensity.high,
          gymId: mockGymId,
          trainerId: mockTrainerId,
          notes: 'Lower body + core',
        );
      } else {
        final km = 2.5 + rng.nextDouble() * 1.5;
        day.add(
          ActivityType.jogging,
          ActivitySource.manual,
          hour: 6,
          minutes: (km * 7.5).round(),
          distanceKm: km,
          intensity: ActivityIntensity.moderate,
        );
      }
    case DateTime.friday:
      if (evenWeek) {
        day.add(
          ActivityType.hiit,
          ActivitySource.manual,
          hour: 19,
          minutes: 20 + rng.nextInt(11),
          intensity: ActivityIntensity.high,
        );
      } else {
        day.add(
          ActivityType.stretching,
          ActivitySource.manual,
          hour: 21,
          minutes: 15 + rng.nextInt(11),
          intensity: ActivityIntensity.low,
        );
      }
    case DateTime.saturday:
      if (evenWeek) {
        final km = 10 + rng.nextInt(5) + rng.nextDouble();
        day.add(
          ActivityType.running,
          ActivitySource.fitflex,
          hour: 6,
          minutes: (km * 6.5).round(),
          distanceKm: km,
          steps: (km * 1300).round(),
          intensity: ActivityIntensity.moderate,
          notes: 'Long run',
        );
      } else {
        day.add(
          ActivityType.groupClass,
          ActivitySource.gym,
          hour: 9,
          minutes: 50,
          intensity: ActivityIntensity.moderate,
          gymId: mockGymId,
          notes: 'Saturday circuit class',
        );
      }
    case DateTime.sunday:
      final km = 6 + rng.nextDouble() * 4;
      day.add(
        ActivityType.hiking,
        ActivitySource.manual,
        hour: 8,
        minutes: (km * 18).round(),
        distanceKm: km,
        intensity: ActivityIntensity.moderate,
      );
  }
  return day.activities;
}

class _DayBuilder {
  _DayBuilder(this.userId, this.date);

  final String userId;
  final DateTime date;
  final List<Activity> activities = [];

  void add(
    ActivityType type,
    ActivitySource source, {
    required int hour,
    required int minutes,
    required ActivityIntensity intensity,
    int? steps,
    int? activeMinutes,
    double? distanceKm,
    String? gymId,
    String? trainerId,
    String? notes,
  }) {
    final ymd = '${date.year}${_two(date.month)}${_two(date.day)}';
    activities.add(
      Activity(
        id: 'mock_act_${ymd}_${activities.length}',
        isSample: true,
        userId: userId,
        type: type,
        source: source,
        startedAt: DateTime(date.year, date.month, date.day, hour),
        durationMinutes: minutes,
        distanceKm: distanceKm == null
            ? null
            : double.parse(distanceKm.toStringAsFixed(2)),
        steps: steps,
        activeMinutes: activeMinutes ?? minutes,
        calories: minutes * _kcalPerMinute[intensity]!,
        intensity: intensity,
        gymId: gymId,
        trainerId: trainerId,
        notes: notes,
      ),
    );
  }
}

const _kcalPerMinute = {
  ActivityIntensity.low: 4,
  ActivityIntensity.moderate: 7,
  ActivityIntensity.high: 10,
};

String _two(int n) => n.toString().padLeft(2, '0');

int _weekOfYear(DateTime date) {
  final firstDay = DateTime(date.year, 1, 1);
  return date.difference(firstDay).inDays ~/ 7;
}
