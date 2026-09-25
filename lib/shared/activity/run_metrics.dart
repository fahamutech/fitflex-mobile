/// Run metrics from a GPS track, for the live numbers while recording.
///
/// Same rules as the server (fitflex-functions src/shared/run-metrics.mjs),
/// which works out the numbers that are saved — keep the two in step.
/// A track is a list of segments (a new one after each pause); points the
/// phone wasn't sure about are dropped, and time and distance only count
/// inside segments.
library;

import 'dart:math' as math;

/// One GPS fix.
class TrackPoint {
  const TrackPoint(this.lat, this.lng, this.altitude, this.time, this.accuracy);

  final double lat;
  final double lng;
  final double? altitude;
  final DateTime time;
  final double? accuracy;

  /// `[lat, lng, altitudeM, timeMs, accuracyM]`, as the server takes it.
  List<Object?> toWire() => [
    lat,
    lng,
    altitude,
    time.millisecondsSinceEpoch,
    accuracy,
  ];

  static TrackPoint? fromWire(Object? v) {
    if (v is! List || v.length < 4) return null;
    final lat = v[0], lng = v[1], t = v[3];
    if (lat is! num || lng is! num || t is! num) return null;
    return TrackPoint(
      lat.toDouble(),
      lng.toDouble(),
      (v[2] as num?)?.toDouble(),
      DateTime.fromMillisecondsSinceEpoch(t.toInt()),
      v.length > 4 ? (v[4] as num?)?.toDouble() : null,
    );
  }
}

const maxAccuracyM = 30.0;
const maxPointSpeedMs = 12.0;
const climbThresholdM = 3.0;
const _smoothWindow = 3;
const _earthM = 6371000.0;

double haversineM(TrackPoint a, TrackPoint b) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat);
  final dLng = rad(b.lng - a.lng);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(a.lat)) *
          math.cos(rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * _earthM * math.asin(math.min(1, math.sqrt(h)));
}

/// Whether [p] can follow [prev] in a clean track.
bool acceptPoint(TrackPoint? prev, TrackPoint p) {
  if (p.lat.abs() > 90 || p.lng.abs() > 180) return false;
  if (p.accuracy != null && p.accuracy! > maxAccuracyM) return false;
  if (prev == null) return true;
  final dt = p.time.difference(prev.time).inMilliseconds / 1000;
  if (dt <= 0) return false;
  return haversineM(prev, p) / dt <= maxPointSpeedMs;
}

List<List<TrackPoint>> cleanTrack(List<List<TrackPoint>> segments) => [
  for (final seg in segments)
    if (_clean(seg) case final kept when kept.isNotEmpty) kept,
];

List<TrackPoint> _clean(List<TrackPoint> seg) {
  final kept = <TrackPoint>[];
  for (final p in seg) {
    if (acceptPoint(kept.lastOrNull, p)) kept.add(p);
  }
  return kept;
}

double elevationGainM(List<TrackPoint> points) {
  final alts = [
    for (final p in points)
      if (p.altitude != null) p.altitude!,
  ];
  if (alts.length < 2) return 0;
  const half = _smoothWindow ~/ 2;
  final smooth = [
    for (var i = 0; i < alts.length; i++)
      () {
        final w = alts.sublist(
          math.max(0, i - half),
          math.min(alts.length, i + half + 1),
        );
        return w.reduce((a, b) => a + b) / w.length;
      }(),
  ];
  var gain = 0.0;
  var low = smooth.first;
  for (final a in smooth) {
    if (a < low) {
      low = a;
    } else if (a - low >= climbThresholdM) {
      gain += a - low;
      low = a;
    }
  }
  return gain;
}

class RunMetrics {
  const RunMetrics({
    this.distanceKm = 0,
    this.movingSeconds = 0,
    this.elevationGainM = 0,
    this.splits = const [],
  });

  final double distanceKm;
  final int movingSeconds;
  final int elevationGainM;

  /// Seconds for each whole km.
  final List<int> splits;

  /// Seconds per km, or null before there's any distance.
  int? get paceSecPerKm =>
      distanceKm < 0.01 ? null : (movingSeconds / distanceKm).round();

  double get speedKmh =>
      movingSeconds <= 0 ? 0 : distanceKm / (movingSeconds / 3600);
}

RunMetrics trackMetrics(List<List<TrackPoint>> segments) {
  var meters = 0.0, moving = 0.0, gain = 0.0;
  final splits = <int>[];
  var nextKm = 1000.0, splitStart = 0.0;
  for (final seg in segments) {
    gain += elevationGainM(seg);
    for (var i = 1; i < seg.length; i++) {
      final d = haversineM(seg[i - 1], seg[i]);
      final dt = seg[i].time.difference(seg[i - 1].time).inMilliseconds / 1000;
      while (d > 0 && meters + d >= nextKm) {
        final at = moving + dt * ((nextKm - meters) / d);
        splits.add((at - splitStart).round());
        splitStart = at;
        nextKm += 1000;
      }
      meters += d;
      moving += dt;
    }
  }
  return RunMetrics(
    distanceKm: (meters / 10).round() / 100,
    movingSeconds: moving.round(),
    elevationGainM: gain.round(),
    splits: splits,
  );
}

/// Estimated calories (ACSM running above 8 km/h, walking below), from
/// body weight. No weight, no estimate.
int? runCalories({
  required double distanceKm,
  required int movingSeconds,
  num? weightKg,
}) {
  final w = weightKg?.toDouble();
  if (w == null || w < 25 || w > 300 || movingSeconds <= 0) return null;
  final minutes = movingSeconds / 60;
  final mPerMin = distanceKm * 1000 / minutes;
  final vo2 = mPerMin >= 134 ? 0.2 * mPerMin + 3.5 : 0.1 * mPerMin + 3.5;
  return (vo2 * w / 1000 * 5 * minutes).round();
}

/// "5:12" (minutes:seconds) per km.
String formatPace(int? secPerKm) {
  if (secPerKm == null || secPerKm <= 0 || secPerKm > 59 * 60) return '–:––';
  return '${secPerKm ~/ 60}:${(secPerKm % 60).toString().padLeft(2, '0')}';
}

/// "1:02:05" or "32:10".
String formatDuration(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
