/// The phone's own step counter (Android's hardware step sensor).
///
/// It only reads: the number of steps since the phone last started. Turning
/// that into daily totals is `StepLedger`'s job. iPhone isn't supported yet.
abstract interface class PhoneStepCounter {
  /// Whether this platform has a step counter FitFlex can read.
  bool get isSupported;

  Future<bool> hasPermission();

  /// Asks for the "Physical activity" permission. Returns whether it's granted.
  Future<bool> requestPermission();

  /// Whether the member said "don't ask again", so only Settings can grant it.
  Future<bool> isPermanentlyDenied();

  Future<void> openSettings();

  /// Steps since the phone last started, or null when there's no reading
  /// (no sensor, no permission, or it didn't answer in time).
  Future<int?> readSinceBoot();
}
