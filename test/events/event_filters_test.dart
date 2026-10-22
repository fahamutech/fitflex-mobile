// Events S2 (spec §11.12): the pure filter model and the event-zone time
// helpers.
import 'package:fitflexmobile/shared/events/event_filter.dart';
import 'package:fitflexmobile/shared/events/event_summary.dart';
import 'package:fitflexmobile/shared/events/event_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2027, 3, 5, 10);

  group('EventFilter.toQuery', () {
    test('sends nothing for the default filter', () {
      expect(EventFilter.none.toQuery(now: now), isEmpty);
      expect(EventFilter.none.activeCount, 0);
      expect(EventFilter.none.isNarrowing, isFalse);
    });

    test('search, availability, saved and sort', () {
      final f = const EventFilter(
        q: ' half ',
        openOnly: true,
        savedOnly: true,
        sort: EventSort.priceLow,
      ).toQuery(now: now);
      expect(f['q'], ['half']);
      expect(f['availability'], ['open']);
      expect(f['saved'], ['1']);
      expect(f['sort'], ['price_low']);
      expect(f.containsKey('from'), isFalse);
    });

    test('newest sort and the default sort key', () {
      expect(
        const EventFilter(sort: EventSort.newest).toQuery(now: now)['sort'],
        ['newest'],
      );
      expect(
        const EventFilter(sort: EventSort.soonest).toQuery(now: now),
        isNot(contains('sort')),
      );
    });

    test('this month and next 3 months resolve on the given day', () {
      final m = const EventFilter(
        dateRange: EventDateRange.thisMonth,
      ).toQuery(now: now);
      expect(m['from'], ['2027-03-05']);
      expect(m['to'], ['2027-03-31']);
      final n = const EventFilter(
        dateRange: EventDateRange.next3Months,
      ).toQuery(now: now);
      expect(n['from'], ['2027-03-05']);
      expect(n['to'], ['2027-06-05']);
    });

    test('custom dates are sent as days', () {
      final c = EventFilter(
        dateRange: EventDateRange.custom,
        from: DateTime(2027, 4, 1),
        to: DateTime(2027, 4, 30),
      ).toQuery(now: now);
      expect(c['from'], ['2027-04-01']);
      expect(c['to'], ['2027-04-30']);
    });

    test('distance and type buckets keep the server order', () {
      final q = const EventFilter(
        distances: {'other', '5k', '21k'},
        types: {'virtual', 'road'},
      ).toQuery(now: now);
      expect(q['distance'], ['5k', '21k', 'other']);
      expect(q['type'], ['road', 'virtual']);
    });

    test('region and each price bucket', () {
      expect(const EventFilter(region: 'dar').toQuery(now: now)['region'], [
        'dar',
      ]);
      expect(
        const EventFilter(
          price: EventPriceFilter.free,
        ).toQuery(now: now)['price'],
        ['free'],
      );
      expect(
        const EventFilter(
          price: EventPriceFilter.under20k,
        ).toQuery(now: now)['price'],
        ['under_20k'],
      );
      expect(
        const EventFilter(
          price: EventPriceFilter.under50k,
        ).toQuery(now: now)['price'],
        ['under_50k'],
      );
      expect(
        const EventFilter(price: EventPriceFilter.any).toQuery(now: now),
        isNot(contains('price')),
      );
    });
  });

  group('EventFilter.activeCount / copyWith / cleared', () {
    test('counts each sheet section once', () {
      const f = EventFilter(
        q: 'x',
        dateRange: EventDateRange.thisMonth,
        distances: {'5k', '10k'},
        types: {'road'},
        region: 'dar',
        price: EventPriceFilter.free,
        openOnly: true,
        savedOnly: true,
        sort: EventSort.newest,
      );
      expect(f.activeCount, 6);
      expect(f.cleared().activeCount, 0);
      expect(f.cleared().q, 'x');
      expect(f.cleared().sort, EventSort.newest);
    });

    test('copyWith keeps the rest and can clear dates and region', () {
      final f = EventFilter(
        dateRange: EventDateRange.custom,
        from: DateTime(2027, 4, 1),
        region: 'dar',
      );
      final g = f.copyWith(openOnly: true);
      expect(g.from, f.from);
      expect(g.region, 'dar');
      expect(g.openOnly, isTrue);
      final h = f.copyWith(clearDates: true, clearRegion: true);
      expect(h.from, isNull);
      expect(h.region, isNull);
    });

    test('signature is stable and order-free', () {
      const a = EventFilter(types: {'road', 'trail'}, openOnly: true);
      const b = EventFilter(openOnly: true, types: {'trail', 'road'});
      expect(a.signature, b.signature);
      expect(EventFilter.none.signature, '');
    });
  });

  group('event time (spec §12)', () {
    final starts = DateTime.utc(2027, 3, 14, 3, 30);

    test('formats in the event zone with the abbreviation', () {
      expect(eventDateTime(starts, 180, 'EAT'), 'Sun 14 Mar 2027, 06:30 EAT');
      expect(eventDayChip(starts, 180), 'Sun 14 Mar');
      expect(eventDate(starts, 180), '14 Mar 2027');
      expect(eventTime(starts, 180, 'EAT'), '06:30 EAT');
    });

    test('Swahili weekday abbreviations and glossary clock', () {
      expect(eventDayChip(starts, 180, locale: 'sw'), 'Jumapili 14 Mac');
      expect(
        eventDateTime(starts, 180, 'EAT', locale: 'sw'),
        'Jumapili 14 Mac 2027, 6:30 asubuhi EAT',
      );
      final sat = DateTime.utc(2027, 3, 13, 12);
      expect(eventWeekdayShort(eventClock(sat, 180), locale: 'sw'), 'Jumamosi');
    });

    test('a different device zone yields the "where you are" line', () {
      debugDeviceOffsetMinutesOverride = 0;
      addTearDown(() => debugDeviceOffsetMinutesOverride = null);
      expect(deviceTimeIfDifferent(starts, 180), '14 Mar, 03:30');
      debugDeviceOffsetMinutesOverride = 180;
      expect(deviceTimeIfDifferent(starts, 180), isNull);
    });

    test('windows on one day and across days', () {
      final o = DateTime.utc(2027, 3, 12, 6);
      final c = DateTime.utc(2027, 3, 12, 15);
      expect(eventWindowText(o, c, 180, 'EAT'), 'Fri 12 Mar, 09:00–18:00 EAT');
      final c2 = DateTime.utc(2027, 3, 13, 15);
      expect(eventWindowText(o, c2, 180, 'EAT'), contains(' – '));
    });

    test('days until rounds up and never goes negative', () {
      expect(daysUntil(DateTime.utc(2027, 3, 12, 21), now.toUtc()), 8);
      expect(daysUntil(DateTime.utc(2027, 3, 1), now.toUtc()), 0);
    });

    test('distance labels', () {
      expect(distanceLabel(5000), '5K');
      expect(distanceLabel(21097), '21K');
      expect(distanceLabel(42195), '42K');
      expect(distanceLabel(7500), '7.5K');
    });

    test('availability parses the server words and tolerates unknown ones', () {
      expect(
        EventAvailability.parse('closing_soon'),
        EventAvailability.closingSoon,
      );
      expect(
        EventAvailability.parse('not_yet_open'),
        EventAvailability.notYetOpen,
      );
      expect(EventAvailability.parse('weird'), EventAvailability.closed);
      expect(EventAvailability.closingSoon.wire, 'closing_soon');
    });
  });
}
