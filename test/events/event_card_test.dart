// Events S2 (spec §11.12 event_card_test): pill tone and label per
// availability, free price, the placeholder, Swahili at 1.3x.
import 'package:fitflexmobile/screens/member/events/event_card.dart';
import 'package:fitflexmobile/screens/member/events/event_status.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events/event_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/ff_harness.dart';
import '../support/recording_api.dart' show captureFlutterErrors;
import 'fixtures.dart';

EventSummary _e(String availability, {String? thumb, int? price = 25000}) =>
    EventSummary.fromJson(
      summary(
        'e1',
        availability: availability,
        heroThumbUrl: thumb,
        fromPriceTzs: price,
      ),
    );

void main() {
  const expected = {
    'open': ('Open', FFBadgeTone.success),
    'closing_soon': ('Closing soon', FFBadgeTone.fuel),
    'sold_out': ('Sold out', FFBadgeTone.gray),
    'closed': ('Closed', FFBadgeTone.gray),
    'not_yet_open': ('Opens Fri 1 Jan', FFBadgeTone.defaultTone),
    'cancelled': ('Cancelled', FFBadgeTone.danger),
    'in_progress': ('In progress', FFBadgeTone.gray),
    'completed': ('Finished', FFBadgeTone.gray),
  };

  for (final entry in expected.entries) {
    testWidgets('pill for ${entry.key}', (tester) async {
      await pumpFF(
        tester,
        EventCard(event: _e(entry.key), onTap: () {}),
        width: 360,
      );
      final badge = tester.widget<FFBadge>(
        find.byKey(Key('event-pill-${entry.key}')),
      );
      expect(badge.label, entry.value.$1);
      expect(badge.tone, entry.value.$2);
      expect(
        availabilityTone(EventAvailability.parse(entry.key)),
        entry.value.$2,
      );
    });
  }

  testWidgets('free price and the placeholder without an image', (
    tester,
  ) async {
    await pumpFF(
      tester,
      EventCard(event: _e('open', thumb: null, price: 0), onTap: () {}),
      width: 360,
    );
    expect(find.text('Free'), findsOneWidget);
    expect(find.byKey(const Key('event-image-placeholder')), findsOneWidget);
    expect(find.byType(FFRemoteImage), findsNothing);
    expect(find.text('Road'), findsOneWidget);
    expect(find.byKey(const Key('event-card-date')), findsOneWidget);
    expect(find.byKey(const Key('event-card-verified')), findsOneWidget);
  });

  testWidgets('no price line when the server sent none', (tester) async {
    await pumpFF(
      tester,
      EventCard(event: _e('open', price: null), onTap: () {}),
      width: 360,
    );
    final price = tester.widget<Text>(
      find.byKey(const Key('event-card-price')),
    );
    expect(price.data, '');
  });

  testWidgets('distance pills show at most four plus a count', (tester) async {
    final e = EventSummary.fromJson(
      summary('e1', distancesM: [3000, 5000, 10000, 21097, 42195]),
    );
    await pumpFF(tester, EventCard(event: e, onTap: () {}), width: 360);
    expect(find.text('3K'), findsOneWidget);
    expect(find.text('21K'), findsOneWidget);
    expect(find.text('+1'), findsOneWidget);
    expect(find.text('42K'), findsNothing);
  });

  testWidgets('Swahili labels fit at 375 and 1.3x', (tester) async {
    final errors = await captureFlutterErrors(() async {
      await pumpFF(
        tester,
        EventCard(event: _e('closing_soon'), onTap: () {}),
        lang: 'sw',
        textScale: 1.3,
        width: 375 - 48,
      );
    });
    expect(errors.where((e) => e.contains('overflowed')), isEmpty);
    expect(find.text('Inafungwa karibuni'), findsOneWidget);
    expect(find.text('Jpl 14 Mac'), findsOneWidget);
    expect(find.text('kuanzia TSh 25,000'), findsOneWidget);
  });

  testWidgets('dark theme: the fuel pill keeps white text', (tester) async {
    await pumpFF(
      tester,
      EventCard(event: _e('closing_soon'), onTap: () {}),
      dark: true,
      width: 360,
    );
    final text = tester.widget<Text>(
      find.descendant(
        of: find.byKey(const Key('event-pill-closing_soon')),
        matching: find.byType(Text),
      ),
    );
    expect(text.style?.color, Colors.white);
  });
}
