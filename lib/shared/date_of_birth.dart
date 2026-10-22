// Member date of birth: the one client-side rule, matching the backend's
// src/shared/date-of-birth.mjs (POST /me/profile). Strict "YYYY-MM-DD", a real
// calendar day, from 1901-01-01 to today in East Africa (Dar es Salaam, UTC+3);
// "" clears it. The server answers anything else with
// 400 { error: 'invalid_field', field: 'dateOfBirth' }.
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'i18n.dart';

/// The earliest date of birth the server takes.
final DateTime firstDateOfBirth = DateTime(1901);

/// Today's calendar day in East Africa (UTC+3), the server's "today" for a
/// date of birth, whatever the device's own time zone.
DateTime eastAfricaToday({DateTime? now}) {
  final eat = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 3));
  return DateTime(eat.year, eat.month, eat.day);
}

/// YYYY-MM-DD as a real calendar day, else null ("2026-02-30" is null).
DateTime? parseDateOfBirth(String text) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final date = DateTime(y, mo, d);
  if (date.year != y || date.month != mo || date.day != d) return null;
  return date;
}

String formatDateOfBirth(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// A stored date of birth for the field: only a plain YYYY-MM-DD is a
/// date. Anything else, timestamps included, is left as it is so the field
/// says it is not valid and the member picks again. A timestamp is not cut
/// to its first 10 characters: "1990-05-09T21:00:00Z" is 10 May in Dar.
String normaliseDateOfBirth(String stored) => stored.trim();

/// The i18n key for what is wrong with a typed or stored date of birth, or
/// null when it is fine or empty (empty clears it).
String? dateOfBirthProblemKey(String? value, {DateTime? now}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final date = parseDateOfBirth(text);
  if (date == null || date.isBefore(firstDateOfBirth)) {
    return 'member.dobInvalid';
  }
  if (date.isAfter(eastAfricaToday(now: now))) return 'member.dobFuture';
  return null;
}

/// True for the server's refusal of a date of birth.
bool isDateOfBirthError(Object error) =>
    error is ApiException &&
    error.code == 'invalid_field' &&
    error.body is Map &&
    (error.body as Map)['field'] == 'dateOfBirth';

/// The translated line for the server's date-of-birth refusal, else null.
String? dateOfBirthErrorMessage(FFLocale locale, Object error) =>
    isDateOfBirthError(error) ? locale.t('member.dobInvalid') : null;

/// The date picker for a date of birth: 1901-01-01 to today (East Africa).
/// [current] is kept as the starting day when it is in range.
Future<DateTime?> showDateOfBirthPicker(
  BuildContext context, {
  DateTime? current,
  String? helpText,
}) {
  final today = eastAfricaToday();
  final initial =
      current != null &&
          !current.isAfter(today) &&
          !current.isBefore(firstDateOfBirth)
      ? current
      : DateTime(today.year - 25, today.month);
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: firstDateOfBirth,
    lastDate: today,
    initialEntryMode: DatePickerEntryMode.calendar,
    helpText: helpText,
  );
}
