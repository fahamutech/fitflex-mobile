/// Turns readings of the phone's step counter into daily step totals.
///
/// Android's step counter reports the steps taken since the phone last
/// started, as one ever-growing number. FitFlex reads it every so often (while
/// the app is open, and every ~15 minutes in the background) and credits the
/// difference between two readings to the day of the later reading.
///
/// Rules — nothing is estimated:
/// - The first reading after turning counting on is only a starting point;
///   steps from before it aren't credited (we can't know when they happened).
/// - A reading lower than the last one means the phone restarted: the new
///   reading is the steps since the restart, all taken after the last
///   reading, so it is credited as is.
/// - Steps between two readings that span midnight go to the later day. With
///   background readings every ~15 minutes that's a few minutes' worth at
///   most; it can be more if the phone was off or the app couldn't run.
/// - A day never goes above [maxDailySteps], the server's plausibility limit.
library;

import 'activity_summary.dart' show dayOf;

/// The most steps one day can hold (matches the server's limit).
const maxDailySteps = 100000;

/// Days kept on the phone (the server accepts up to 35 days back).
const ledgerDays = 34;

/// A jump bigger than this between two readings is treated as a sensor
/// glitch and not credited.
const _maxJump = maxDailySteps;

/// Walking distance from a step count — an estimate, for sources that
/// count steps only (the phone's step sensor). A walking step is about 41%
/// of height; without a height, 0.70 m. Same rule as the server
/// (`estimateWalkKm` in fitflex-functions activity-service.mjs).
double stepLengthM(num? heightCm) {
  final h = heightCm?.toDouble();
  return h != null && h >= 100 && h <= 230 ? (h * 0.414).round() / 100 : 0.7;
}

double estimateWalkKm(int steps, num? heightCm) =>
    (steps * stepLengthM(heightCm) / 10).round() / 100;

String dayKey(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

DateTime dayFromKey(String key) {
  final p = key.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

class StepLedger {
  StepLedger({
    this.lastCount,
    this.lastAt,
    Map<String, int>? days,
    Map<String, int>? uploaded,
  }) : days = days ?? {},
       uploaded = uploaded ?? {};

  /// The counter value and time of the last reading.
  int? lastCount;
  DateTime? lastAt;

  /// Steps credited per local day (`yyyy-mm-dd`).
  final Map<String, int> days;

  /// What the server already has per day.
  final Map<String, int> uploaded;

  bool get hasBaseline => lastCount != null;

  /// Applies a reading of [sinceBoot] steps taken at [at]. Returns the steps
  /// credited (0 for a starting point or a glitch).
  int record(int sinceBoot, DateTime at) {
    if (sinceBoot < 0) return 0;
    final last = lastCount;
    lastCount = sinceBoot;
    lastAt = at;
    if (last == null) return 0;
    final delta = sinceBoot >= last ? sinceBoot - last : sinceBoot;
    if (delta == 0 || delta > _maxJump) return 0;
    final key = dayKey(at);
    final before = days[key] ?? 0;
    final after = (before + delta).clamp(0, maxDailySteps);
    days[key] = after;
    _prune(at);
    return after - before;
  }

  /// Days the server already has (e.g. counted before turning it off):
  /// counting continues from the higher of the two.
  void seed(Map<String, int> known) {
    for (final e in known.entries) {
      final v = e.value.clamp(0, maxDailySteps);
      if (v > (days[e.key] ?? 0)) days[e.key] = v;
      if (v > (uploaded[e.key] ?? 0)) uploaded[e.key] = v;
    }
  }

  /// Forget the starting point (counting was turned off). Days already
  /// counted stay.
  void resetBaseline() {
    lastCount = null;
    lastAt = null;
  }

  /// Days whose total the server doesn't have yet, oldest first.
  List<({String key, DateTime day, int steps})> pending() {
    final keys =
        days.keys.where((k) => (days[k] ?? 0) > (uploaded[k] ?? 0)).toList()
          ..sort();
    return [
      for (final k in keys) (key: k, day: dayFromKey(k), steps: days[k]!),
    ];
  }

  void markUploaded(Map<String, int> sent) {
    for (final e in sent.entries) {
      if (e.value > (uploaded[e.key] ?? 0)) uploaded[e.key] = e.value;
    }
  }

  /// Steps counted on this phone today.
  int stepsOn(DateTime day) => days[dayKey(day)] ?? 0;

  void _prune(DateTime now) {
    final oldest = dayKey(
      dayOf(now).subtract(const Duration(days: ledgerDays)),
    );
    days.removeWhere((k, _) => k.compareTo(oldest) < 0);
    uploaded.removeWhere((k, _) => k.compareTo(oldest) < 0);
  }

  Map<String, dynamic> toJson() => {
    'lastCount': lastCount,
    'lastAt': lastAt?.toIso8601String(),
    'days': days,
    'uploaded': uploaded,
  };

  factory StepLedger.fromJson(Map<String, dynamic> json) {
    Map<String, int> ints(Object? v) => {
      if (v is Map)
        for (final e in v.entries)
          if (e.value is num) e.key.toString(): (e.value as num).toInt(),
    };
    return StepLedger(
      lastCount: (json['lastCount'] as num?)?.toInt(),
      lastAt: DateTime.tryParse(json['lastAt'] as String? ?? ''),
      days: ints(json['days']),
      uploaded: ints(json['uploaded']),
    );
  }
}
