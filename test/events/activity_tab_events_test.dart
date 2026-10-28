// Events S2 (spec §11.12 activity_tab_events_test): the fifth segment is
// there only with the flag and the probe; selecting it renders the list.
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api,
  MemberData data, {
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  MemberDataScope(
    data: data,
    child: MemberActivityTab(now: DateTime(2027, 3, 10, 9)),
  ),
  user: const {'id': 'u1', 'userType': 'member'},
  lang: lang,
  keepRequests: true,
);

List<String> _options(WidgetTester tester) => tester
    .widget<FFSegmented>(find.byKey(const Key('activity-sections')))
    .options
    .map((o) => o.$1)
    .toList();

void main() {
  tearDown(() => debugEventsDiscoveryOverride = null);

  apiTest('flag off: four sections', (tester, api) async {
    debugEventsDiscoveryOverride = false;
    final data = MemberData()
      ..activityLoaded = true
      ..eventsOptions = opts();
    await _pump(tester, api, data);
    expect(_options(tester), [
      'overview',
      'workouts',
      'challenges',
      'progress',
    ]);
    expect(find.text('Events'), findsNothing);
  });

  apiTest('flag on but probe off: still four', (tester, api) async {
    debugEventsDiscoveryOverride = true;
    final data = MemberData()
      ..activityLoaded = true
      ..eventsOptions = opts(discovery: false);
    await _pump(tester, api, data);
    expect(_options(tester), hasLength(4));
  });

  apiTest('both on: Events is fifth and renders the list inline', (
    tester,
    api,
  ) async {
    debugEventsDiscoveryOverride = true;
    api.on('GET /events', page([summary('e1')]));
    final data = MemberData()
      ..activityLoaded = true
      ..eventsOptions = opts();
    await _pump(tester, api, data, lang: 'sw');
    expect(_options(tester).last, 'events');
    expect(find.text('Matukio'), findsOneWidget);
    await tapVisible(tester, find.text('Matukio'));
    expect(find.byKey(const Key('activity-events')), findsOneWidget);
    expect(api.only('GET', '/events').query, 'limit=20');
    expect(find.byKey(const Key('event-card-e1')), findsOneWidget);
  });

  apiTest('the events section does not wait for activity to load', (
    tester,
    api,
  ) async {
    debugEventsDiscoveryOverride = true;
    api.on('GET /events', page([]));
    final data = MemberData()
      ..activityLoaded = false
      ..eventsOptions = opts();
    // The activity spinner never settles, so pump by hand.
    await pumpPage(
      tester,
      api,
      MemberDataScope(
        data: data,
        child: MemberActivityTab(now: DateTime(2027, 3, 10, 9)),
      ),
      user: const {'id': 'u1', 'userType': 'member'},
      settle: false,
    );
    await tester.pump();
    await tester.ensureVisible(find.text('Events'));
    await tester.tap(find.text('Events'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('events-empty')), findsOneWidget);
  });
}
