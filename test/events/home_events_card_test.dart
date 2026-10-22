// Events S2 (spec §11.12 home_events_card_test): the Home card is picked
// only with the flag, the probe and at least one open event; two rows;
// "See all" navigates.
import 'package:fitflexmobile/screens/member/events/home_events_card.dart';
import 'package:fitflexmobile/screens/member/home_feed.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/events/event_summary.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';

List<EventSummary> _events(int n) => [
  for (var i = 1; i <= n; i++)
    EventSummary.fromJson(summary('e$i', title: 'Event $i')),
];

void main() {
  tearDown(() => debugEventsDiscoveryOverride = null);

  test('no events card with the flag off', () {
    debugEventsDiscoveryOverride = false;
    final d = MemberData()
      ..eventsOptions = opts()
      ..upcomingEvents = _events(2);
    final picks = pickHomeCards(d, DateTime(2027, 3, 10, 9));
    expect(picks.any((p) => p.kind == HomeCardKind.events), isFalse);
  });

  test('no events card when the probe says off or the list is empty', () {
    debugEventsDiscoveryOverride = true;
    final off = MemberData()
      ..eventsOptions = opts(discovery: false)
      ..upcomingEvents = _events(2);
    expect(
      pickHomeCards(
        off,
        DateTime(2027, 3, 10, 9),
      ).any((p) => p.kind == HomeCardKind.events),
      isFalse,
    );
    final empty = MemberData()..eventsOptions = opts();
    expect(
      pickHomeCards(
        empty,
        DateTime(2027, 3, 10, 9),
      ).any((p) => p.kind == HomeCardKind.events),
      isFalse,
    );
  });

  test('events card is picked with flag, probe and events', () {
    debugEventsDiscoveryOverride = true;
    final d = MemberData()
      ..eventsOptions = opts()
      ..upcomingEvents = _events(1);
    final picks = pickHomeCards(d, DateTime(2027, 3, 10, 9));
    final pick = picks.firstWhere((p) => p.kind == HomeCardKind.events);
    expect(pick.reason, HomeReason.upcomingEvents);
    expect(pick.score, lessThan(35));
  });

  apiTest('shows at most two rows and "See all" opens the list', (
    tester,
    api,
  ) async {
    await pumpPage(
      tester,
      api,
      HomeEventsCard(events: _events(3)),
      user: const {'id': 'u1', 'userType': 'member'},
      extraRoutes: [
        GoRoute(
          path: '/member/events',
          builder: (_, _) => const Scaffold(body: Text('ROUTE-EVENTS')),
        ),
        GoRoute(
          path: '/member/events/:eventId',
          builder: (_, s) => Scaffold(
            body: Text('ROUTE-EVENT-${s.pathParameters['eventId']}'),
          ),
        ),
      ],
    );
    expect(find.text('Upcoming events'), findsOneWidget);
    expect(find.text('Event 1'), findsOneWidget);
    expect(find.text('Event 2'), findsOneWidget);
    expect(find.text('Event 3'), findsNothing);
    final s = tester.getSemantics(find.byKey(const Key('home-events-card')));
    expect(s.label, 'Upcoming events, 2 items');
    await tester.tap(find.byKey(const Key('home-event-e2')));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE-EVENT-e2'), findsOneWidget);
  });

  apiTest('"See all" navigates to the list', (tester, api) async {
    await pumpPage(
      tester,
      api,
      HomeEventsCard(events: _events(1)),
      user: const {'id': 'u1', 'userType': 'member'},
      lang: 'sw',
      extraRoutes: [
        GoRoute(
          path: '/member/events',
          builder: (_, _) => const Scaffold(body: Text('ROUTE-EVENTS')),
        ),
      ],
    );
    expect(find.text('Matukio yajayo'), findsOneWidget);
    await tester.tap(find.byKey(const Key('home-events-see-all')));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE-EVENTS'), findsOneWidget);
  });
}
