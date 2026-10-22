import 'package:flutter/foundation.dart';

import '../formatters.dart';

// Event times are shown in the event's own zone (spec §12): the API gives
// `utcOffsetMinutes` (at `startsAt`) and `timezoneAbbr`, so no timezone
// database is needed. The shifted clock reading is built as a plain (non-UTC)
// DateTime so the shared formatters never move it to the device's zone.

/// [utc] read on a clock [offsetMinutes] east of UTC.
DateTime eventClock(DateTime utc, int offsetMinutes) {
  final shifted = utc.toUtc().add(Duration(minutes: offsetMinutes));
  return DateTime(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
  );
}

const _weekdaysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Jumatatu … Jumapili, shortened as in the spec (§12).
// TODO(sw-review): weekday abbreviations Jtt, Jnn, Jtn, Alh, Iju, Jmsi, Jpl
// are a draft awaiting native review.
const _weekdaysSw = ['Jtt', 'Jnn', 'Jtn', 'Alh', 'Iju', 'Jmsi', 'Jpl'];

/// "Sat" / "Jmsi" for [d]'s weekday.
String eventWeekdayShort(DateTime d, {String locale = 'en'}) =>
    (locale == 'sw' ? _weekdaysSw : _weekdaysEn)[d.weekday - 1];

/// "Sat 14 Mar" (sw "Jmsi 14 Mac"): the card's date chip.
String eventDayChip(DateTime utc, int offsetMinutes, {String locale = 'en'}) {
  final d = eventClock(utc, offsetMinutes);
  return '${eventWeekdayShort(d, locale: locale)} '
      '${formatDayMonth(d, locale: locale)}';
}

/// "14 Mar 2027" in the event's zone.
String eventDate(DateTime utc, int offsetMinutes, {String locale = 'en'}) =>
    formatDate(eventClock(utc, offsetMinutes), locale: locale);

/// "Sat 14 Mar 2027" in the event's zone.
String eventDayDate(DateTime utc, int offsetMinutes, {String locale = 'en'}) {
  final d = eventClock(utc, offsetMinutes);
  return '${eventWeekdayShort(d, locale: locale)} '
      '${formatDate(d, locale: locale)}';
}

/// "06:30 EAT" (sw "6:30 asubuhi EAT"): a time with the zone's abbreviation.
String eventTime(
  DateTime utc,
  int offsetMinutes,
  String abbr, {
  String locale = 'en',
}) {
  final t = formatTimeOfDay(eventClock(utc, offsetMinutes), locale: locale);
  return abbr.isEmpty ? t : '$t $abbr';
}

/// "Sat 14 Mar 2027, 06:30 EAT".
String eventDateTime(
  DateTime utc,
  int offsetMinutes,
  String abbr, {
  String locale = 'en',
}) =>
    '${eventDayDate(utc, offsetMinutes, locale: locale)}, '
    '${eventTime(utc, offsetMinutes, abbr, locale: locale)}';

/// "Fri 12 Mar, 09:00–18:00 EAT" for a window on one day; two full
/// date-times joined by " – " when it spans days.
String eventWindowText(
  DateTime opens,
  DateTime closes,
  int offsetMinutes,
  String abbr, {
  String locale = 'en',
}) {
  final o = eventClock(opens, offsetMinutes);
  final c = eventClock(closes, offsetMinutes);
  final sameDay = o.year == c.year && o.month == c.month && o.day == c.day;
  if (sameDay) {
    final range =
        '${formatTimeOfDay(o, locale: locale)}–'
        '${formatTimeOfDay(c, locale: locale)}';
    return '${eventWeekdayShort(o, locale: locale)} '
        '${formatDayMonth(o, locale: locale)}, '
        '${abbr.isEmpty ? range : '$range $abbr'}';
  }
  return '${eventDateTime(opens, offsetMinutes, abbr, locale: locale)} – '
      '${eventDateTime(closes, offsetMinutes, abbr, locale: locale)}';
}

/// Test hook: when set, the device is taken to be this many minutes east of
/// UTC, so tests can pin a zone on any computer.
@visibleForTesting
int? debugDeviceOffsetMinutesOverride;

/// The device's offset from UTC at [utc], in minutes.
int deviceOffsetMinutes(DateTime utc) =>
    debugDeviceOffsetMinutesOverride ??
    utc.toUtc().toLocal().timeZoneOffset.inMinutes;

/// "06:30" on the device's own clock when it differs from the event's zone,
/// or null when the two zones agree at [utc] (no line to show).
String? deviceTimeIfDifferent(
  DateTime utc,
  int eventOffsetMinutes, {
  String locale = 'en',
}) {
  final device = deviceOffsetMinutes(utc);
  if (device == eventOffsetMinutes) return null;
  final local = eventClock(utc, device);
  return '${formatDayMonth(local, locale: locale)}, '
      '${formatTimeOfDay(local, locale: locale)}';
}

/// Whole days from [now] until [until], never negative.
int daysUntil(DateTime until, DateTime now) {
  final diff = until.toUtc().difference(now.toUtc());
  if (diff.isNegative) return 0;
  return (diff.inHours / 24).ceil();
}
