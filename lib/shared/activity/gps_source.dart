import 'run_metrics.dart';

enum GpsAccess { granted, denied, deniedForever, serviceOff }

/// Where a run's GPS fixes come from. The concrete one lives under
/// `providers/` and is picked in `activity_config.dart`.
abstract interface class GpsSource {
  /// Whether runs can be recorded on this platform.
  bool get isSupported;

  /// Asks for location permission (while in use) if needed.
  Future<GpsAccess> ensureAccess();

  /// Fixes while recording. Keeps going with the screen off (Android shows
  /// [notificationTitle] as an ongoing notification). Cancel to stop.
  Stream<TrackPoint> track({
    required String notificationTitle,
    required String notificationText,
  });

  Future<void> openAppSettings();
  Future<void> openLocationSettings();
}
