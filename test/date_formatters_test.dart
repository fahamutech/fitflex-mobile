import 'package:fitflexmobile/screens/member/widgets/checkin_list.dart';
import 'package:fitflexmobile/shared/formatters.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Tanzania is EAT, UTC+3 all year (no daylight saving).
const _eat = Duration(hours: 3);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugLocalOffsetOverride = _eat;
  });
  tearDown(() => debugLocalOffsetOverride = null);

  group('formatDate / formatDateTime', () {
    test('a late-evening UTC instant is the next day in EAT', () {
      const iso = '2026-10-18T22:30:00Z';
      expect(formatDate(iso), '19 Oct 2026');
      expect(formatDateTime(iso), '19 Oct 2026, 01:30');
    });

    test('Swahili month names', () {
      const iso = '2026-10-18T22:30:00.000Z';
      expect(formatDate(iso, locale: 'sw'), '19 Okt 2026');
      expect(formatDateTime(iso, locale: 'sw'), '19 Okt 2026, 1:30 usiku');
      expect(formatDate('2026-08-01T09:00:00Z', locale: 'sw'), '1 Ago 2026');
      expect(formatDate('2026-12-31T12:00:00Z', locale: 'sw'), '31 Des 2026');
    });

    test('Swahili time of day: 12-hour clock with the part of the day', () {
      // Glossary (owner, 2026-10-04): "5:30 jioni"; no six-hour offset.
      String sw(int h, int m) =>
          formatTimeOfDay(DateTime(2026, 10, 19, h, m), locale: 'sw');
      expect(sw(0, 5), '12:05 usiku');
      expect(sw(4, 59), '4:59 usiku');
      expect(sw(5, 0), '5:00 asubuhi');
      expect(sw(11, 30), '11:30 asubuhi');
      expect(sw(12, 0), '12:00 mchana');
      expect(sw(15, 45), '3:45 mchana');
      expect(sw(17, 30), '5:30 jioni');
      expect(sw(19, 0), '7:00 usiku');
      expect(sw(23, 10), '11:10 usiku');
      // English stays 24-hour.
      expect(formatTimeOfDay(DateTime(2026, 10, 19, 17, 30)), '17:30');
    });

    test('an instant with an explicit offset is read correctly', () {
      // 23:30 at UTC-2 is 01:30Z, so 04:30 EAT.
      expect(formatDateTime('2026-10-18T23:30:00-02:00'), '19 Oct 2026, 04:30');
    });

    test('a calendar date with no time stays the same day', () {
      expect(formatDate('2026-10-30'), '30 Oct 2026');
      expect(formatDate(DateTime(2026, 1, 5)), '5 Jan 2026');
    });

    test('a UTC DateTime is converted too', () {
      expect(formatDate(DateTime.utc(2026, 3, 31, 21, 15)), '1 Apr 2026');
    });

    test('missing or unreadable values use the fallback', () {
      expect(formatDate(null), '-');
      expect(formatDate(''), '-');
      expect(formatDate('not a date', fallback: ''), '');
      expect(formatDateTime(42), '-');
    });

    test('without the test hook it follows the device clock', () {
      debugLocalOffsetOverride = null;
      final utc = DateTime.utc(2026, 10, 18, 22, 30);
      final local = utc.toLocal();
      expect(localDateTime(utc.toIso8601String()), local);
    });
  });

  testWidgets('member check-in list shows the local date and time, not ISO', (
    tester,
  ) async {
    await tester.pumpWidget(
      FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp(
          home: Scaffold(
            body: CheckinList(
              checkins: [
                CheckIn.fromJson({
                  'id': 'c1',
                  'memberId': 'm1',
                  'gymId': 'g1',
                  'gym': {'id': 'g1', 'name': 'Mikocheni Fitness'},
                  'timestamp': '2026-10-18T22:30:00.000Z',
                }),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('19 Oct 2026, 01:30'), findsOneWidget);
    expect(find.textContaining('2026-10-18T'), findsNothing);
  });

  testWidgets('…and in Swahili when the member chose it', (tester) async {
    final locale = FFLocale()..set(const Locale('sw'));
    await tester.pumpWidget(
      FFLocaleScope(
        notifier: locale,
        child: MaterialApp(
          home: Scaffold(
            body: CheckinList(
              checkins: [
                CheckIn.fromJson({
                  'id': 'c1',
                  'memberId': 'm1',
                  'gymId': 'g1',
                  'timestamp': '2026-10-18T22:30:00.000Z',
                }),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.text('19 Okt 2026, 1:30 usiku'), findsOneWidget);
  });
}
