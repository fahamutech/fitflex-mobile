import 'package:fitflexmobile/screens/owner/members/widgets/member_format.dart';
import 'package:fitflexmobile/screens/owner/widgets/invoice_utils.dart';
import 'package:fitflexmobile/screens/owner/widgets/statement_models.dart';
import 'package:fitflexmobile/shared/ff_datetime.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  final when = DateTime(2026, 10, 5, 17, 30); // a Monday

  group('dates follow the app language', () {
    test('English stays as it was', () {
      FFLocale();
      expect(DateFormat('EEE d MMM').format(when), 'Mon 5 Oct');
      expect(formatDate(when), '5 Oct 2026');
      expect(monthAndYear(2026, 3), 'March 2026');
      expect(statementDay('2026-10-03'), '3 Oct');
      expect(TrainerAvailability(day: 'monday', slots: []).dayLabel, 'Monday');
    });

    test('Swahili names for days and months', () {
      FFLocale().set(const Locale('sw'));
      expect(DateFormat('EEE d MMM').format(when), 'Jumatatu 5 Okt');
      expect(DateFormat('d MMM yyyy').format(when), '5 Okt 2026');
      expect(formatDate(when), '5 Okt 2026');
      expect(monthAndYear(2026, 3), 'Machi 2026');
      // Not the first three letters of "Oktoba"/"Machi".
      expect(statementDay('2026-10-03'), '3 Okt');
      expect(statementDay('2026-03-09'), '9 Mac');
      expect(statementDay('soon'), 'soon');
      expect(
        OwnerInvoice.fromJson(const {
          'id': 'i1',
          'periodStart': '2026-08-01',
        }).monthLabel,
        'Agosti 2026',
      );
      expect(
        OwnerStatement.fromJson(const {
          'id': 's1',
          'periodStartDate': '2026-12-01',
        }).monthLabel,
        'Desemba 2026',
      );
      expect(TrainerAvailability(day: 'Friday', slots: []).dayLabel, 'Ijumaa');
      expect(
        TrainerAvailability(day: '2026-10-05', slots: []).dayLabel,
        '2026-10-05',
      );
    });

    test('a new FFLocale goes back to English', () {
      FFLocale().set(const Locale('sw'));
      FFLocale();
      expect(DateFormat('MMMM').format(when), 'October');
    });
  });

  group('time of day', () {
    test('English keeps AM/PM, or the 24-hour clock where it was used', () {
      FFLocale();
      expect(formatClock(when), '5:30 PM');
      expect(formatClock(when, english24h: true), '17:30');
      expect(formatClockTime(0, 5), '12:05 AM');
      expect(formatClockText('09:00'), '09:00');
      expect(formatTime(DateTime(2026, 1, 1, 8, 30)), '8:30 AM');
    });

    test('Swahili uses the period word on the same 12-hour digits', () {
      FFLocale().set(const Locale('sw'));
      expect(formatClock(when), '5:30 jioni');
      expect(formatClock(when, english24h: true), '5:30 jioni');
      expect(formatClockTime(5, 0), '5:00 asubuhi');
      expect(formatClockTime(11, 59), '11:59 asubuhi');
      expect(formatClockTime(12, 0), '12:00 mchana');
      expect(formatClockTime(15, 59), '3:59 mchana');
      expect(formatClockTime(16, 0), '4:00 jioni');
      expect(formatClockTime(18, 59), '6:59 jioni');
      expect(formatClockTime(19, 0), '7:00 usiku');
      expect(formatClockTime(0, 0), '12:00 usiku');
      expect(formatClockTime(4, 59), '4:59 usiku');
      expect(formatClockText('09:00'), '9:00 asubuhi');
      expect(formatClockText('soon'), 'soon');
      expect(formatTime(DateTime(2026, 1, 1, 8, 30)), '8:30 asubuhi');
    });
  });
}
