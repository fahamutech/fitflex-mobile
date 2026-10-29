// The shop's view of the server clock (Shop home Phase 2 S4, flash
// sales). Kept free of other imports so the API client can feed it.
import 'package:flutter/foundation.dart';

/// The server's clock as the shop sees it (Phase 2 S4, flash sales): every
/// countdown and "is this sale still on" check uses [now], which is the
/// device time corrected by the last `serverNow` the shop received. A phone
/// set an hour wrong still ends a sale at the right moment (P1 AC-21).
class ShopClock {
  ShopClock._();

  /// Server time minus device time, from the last answer with `serverNow`.
  static Duration offset = Duration.zero;

  /// The device clock (tests replace it to fake a wrong phone clock and to
  /// follow the test's fake time).
  @visibleForTesting
  static DateTime Function()? debugDeviceNow;

  static DateTime deviceNow() => (debugDeviceNow ?? DateTime.now)().toUtc();

  /// The server's time now, as best the app knows it.
  static DateTime now() => deviceNow().add(offset);

  /// Records [serverNow] (received just now) against the device clock.
  static void sync(DateTime? serverNow) {
    if (serverNow == null) return;
    offset = serverNow.toUtc().difference(deviceNow());
  }

  /// Syncs from a shop answer: its `serverNow` when the body has one, else
  /// the HTTP `Date` header (whole seconds, so it never replaces a
  /// `serverNow` taken from the same kind of answer).
  static void syncFrom(Object? body, String? dateHeader) {
    final fromBody = body is Map
        ? DateTime.tryParse(body['serverNow']?.toString() ?? '')
        : null;
    sync(fromBody ?? parseHttpDate(dateHeader));
  }

  @visibleForTesting
  static void reset() {
    offset = Duration.zero;
    debugDeviceNow = null;
  }
}

const _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

/// An HTTP `Date` header (IMF-fixdate, "Wed, 29 Oct 2026 08:00:00 GMT") as
/// a UTC instant, or null when absent or not in that form.
DateTime? parseHttpDate(String? value) {
  final m = RegExp(
    r'^\s*[A-Za-z]{3},\s+(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})\s+GMT\s*$',
  ).firstMatch(value ?? '');
  if (m == null) return null;
  final month = _months[m.group(2)!.toLowerCase()];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(m.group(3)!),
    month,
    int.parse(m.group(1)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}
