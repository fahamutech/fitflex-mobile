// Dates and times in the app's selected language.
//
// [FFLocale] calls [useDateLanguage] whenever the language changes, so a
// plain `DateFormat('d MMM')` anywhere in the app follows the app language
// rather than always printing English names.

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

bool _symbolsLoaded = false;

/// Makes `intl` format dates in [languageCode] ('en' or 'sw') by default.
void useDateLanguage(String languageCode) {
  if (!_symbolsLoaded) {
    // Loads the bundled symbols synchronously; the returned future is done.
    initializeDateFormatting();
    _symbolsLoaded = true;
  }
  Intl.defaultLocale = languageCode;
}

/// Whether dates and times are currently shown in Swahili.
bool get datesInSwahili => (Intl.defaultLocale ?? 'en').startsWith('sw');

/// The Swahili word for the part of the day [hour] (0–23) falls in.
String swahiliDayPeriod(int hour) {
  if (hour >= 5 && hour < 12) return 'asubuhi';
  if (hour >= 12 && hour < 16) return 'mchana';
  if (hour >= 16 && hour < 19) return 'jioni';
  return 'usiku';
}

/// A time of day for display.
///
/// Swahili: a 12-hour clock with the period word, "5:30 jioni". The digits are
/// the ones an English 12-hour clock shows, not the traditional Swahili
/// six-hour offset.
///
/// English: "5:30 PM", or "17:30" when [english24h] is set (for the places
/// that have always shown a 24-hour clock).
String formatClockTime(int hour, int minute, {bool english24h = false}) {
  final mm = minute.toString().padLeft(2, '0');
  final h12 = hour % 12 == 0 ? 12 : hour % 12;
  if (datesInSwahili) return '$h12:$mm ${swahiliDayPeriod(hour)}';
  if (english24h) return '${hour.toString().padLeft(2, '0')}:$mm';
  return '$h12:$mm ${hour < 12 ? 'AM' : 'PM'}';
}

/// [formatClockTime] for the time of day of [at], as given (not converted).
String formatClock(DateTime at, {bool english24h = false}) =>
    formatClockTime(at.hour, at.minute, english24h: english24h);

/// [formatClockTime] for an "HH:mm" string such as a session slot. Anything
/// that is not a time is returned unchanged.
String formatClockText(String hhmm, {bool english24h = true}) {
  final parts = hhmm.split(':');
  if (parts.length < 2) return hhmm;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) return hhmm;
  return formatClockTime(h, m, english24h: english24h);
}

/// "Oct" / "Okt" for [month] 1–12.
String shortMonthName(int month) =>
    DateFormat('MMM').format(DateTime(2000, month));

/// "October 2026" / "Oktoba 2026".
String monthAndYear(int year, int month) =>
    DateFormat('MMMM y').format(DateTime(year, month));

/// The full day name for an English weekday name as the server sends it
/// ("monday"), or null when [day] is not a weekday name.
String? weekdayName(String day) {
  const days = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  final i = days.indexOf(day.toLowerCase());
  if (i < 0) return null;
  // 1 January 2024 was a Monday.
  return DateFormat('EEEE').format(DateTime(2024, 1, 1 + i));
}
