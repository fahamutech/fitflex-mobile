// Events S2 (spec §11.12 events_discovery_test): list states, search
// debounce, the filter sheet, pagination, errors, favourites.
import 'package:fitflexmobile/screens/member/events/events_discovery_view.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';

const _member = {'id': 'u1', 'userType': 'member'};

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  bool favourites = false,
  bool inline = false,
  String lang = 'en',
  Size size = const Size(375, 812),
}) => pumpPage(
  tester,
  api,
  inline
      ? SingleChildScrollView(
          child: EventsDiscoveryView(
            inline: true,
            options: opts(favourites: favourites),
          ),
        )
      : EventsDiscoveryView(options: opts(favourites: favourites)),
  user: _member,
  lang: lang,
  size: size,
  keepRequests: true,
  extraRoutes: [
    GoRoute(
      path: '/member/events/:eventId',
      builder: (_, s) =>
          Scaffold(body: Text('ROUTE-EVENT-${s.pathParameters['eventId']}')),
    ),
  ],
);

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsCache.reset();
    EventsAnalytics.debugSink = [];
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    EventsAnalytics.debugSink = null;
  });

  apiTest('skeleton first, then cards from a fixture of 3', (
    tester,
    api,
  ) async {
    final gate = api.hold('GET /events');
    api.on(
      'GET /events',
      page([summary('e1'), summary('e2', fromPriceTzs: 0), summary('e3')]),
    );
    await pumpPage(
      tester,
      api,
      EventsDiscoveryView(options: opts()),
      user: _member,
      settle: false,
      keepRequests: true,
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('events-loading')), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('events-loading')), findsNothing);
    expect(find.byKey(const Key('event-card-e1')), findsOneWidget);
    expect(find.byKey(const Key('event-card-e3')), findsOneWidget);
    expect(find.text('3 events'), findsOneWidget);
    expect(find.text('from TSh 25,000'), findsNWidgets(2));
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Sun 14 Mar'), findsNWidgets(3));
    final list = api.only('GET', '/events');
    expect(list.query, 'limit=20');
    expect(EventsAnalytics.debugSink!.single.name, 'event_list_viewed');
    expect(EventsAnalytics.debugSink!.single.props['resultCount'], 3);
  });

  apiTest('a card is one button with the composed label', (tester, api) async {
    api.on('GET /events', page([summary('e1')]));
    await _pump(tester, api);
    final s = tester.getSemantics(find.byKey(const Key('event-card-e1')));
    expect(s.label, contains('Dar Half Marathon'));
    expect(s.label, contains('Sun 14 Mar'));
    expect(s.label, contains('Dar es Salaam'));
    expect(s.label, contains('from TSh 25,000'));
    expect(s.label, contains('Open'));
    expect(s.label, contains('Verified organizer'));
    expect(s.flagsCollection.isButton, isTrue);
  });

  apiTest('tapping a card opens its detail route', (tester, api) async {
    api.on('GET /events', page([summary('e1')]));
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('event-card-e1')));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE-EVENT-e1'), findsOneWidget);
  });

  apiTest('search debounces to one request with q', (tester, api) async {
    api.on('GET /events', page([summary('e1')]));
    await _pump(tester, api);
    api.clear();
    await tester.enterText(find.byKey(const Key('events-search')), 'ha');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('events-search')), 'half');
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.sent('GET', '/events'), isFalse);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    final sent = api.where('GET', '/events');
    expect(sent, hasLength(1));
    expect(sent.single.query, 'q=half&limit=20');
    // Clearing restores the unfiltered list.
    api.clear();
    await tester.tap(find.byKey(const Key('events-search-clear')));
    await tester.pumpAndSettle();
    expect(api.only('GET', '/events').query, 'limit=20');
  });

  apiTest('chips apply at once; the sheet applies on Show results', (
    tester,
    api,
  ) async {
    api.on('GET /events', page([summary('e1')]));
    await _pump(tester, api);
    api.clear();
    await tester.tap(find.byKey(const Key('events-chip-open')));
    await tester.pumpAndSettle();
    expect(api.only('GET', '/events').query, 'availability=open&limit=20');
    api.clear();
    await tapVisible(tester, find.byKey(const Key('events-chip-10k')));
    expect(
      api.only('GET', '/events').query,
      'distance=10k&availability=open&limit=20',
    );
    expect(find.text('Filters · 2'), findsOneWidget);

    // The sheet: choices do not fetch until "Show results".
    api.clear();
    await tapVisible(tester, find.byKey(const Key('events-chip-filters')));
    expect(find.text('Filter events'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('events-type-trail')));
    await tapVisible(tester, find.byKey(const Key('events-price-free')));
    expect(api.sent('GET', '/events'), isFalse);
    await tapVisible(tester, find.byKey(const Key('events-filters-show')));
    final q = api.only('GET', '/events').query;
    expect(q, 'type=trail&distance=10k&price=free&availability=open&limit=20');
    expect(find.text('Filters · 4'), findsOneWidget);

    // Clear all inside the sheet resets the sheet's choices.
    api.clear();
    await tapVisible(tester, find.byKey(const Key('events-chip-filters')));
    await tapVisible(tester, find.byKey(const Key('events-filters-clear')));
    await tapVisible(tester, find.byKey(const Key('events-filters-show')));
    expect(api.only('GET', '/events').query, 'limit=20');
    expect(find.text('Filters'), findsOneWidget);
  });

  apiTest('sort changes the query', (tester, api) async {
    api.on('GET /events', page([summary('e1')]));
    await _pump(tester, api);
    api.clear();
    await tester.tap(find.byKey(const Key('events-sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lowest price').last);
    await tester.pumpAndSettle();
    expect(api.only('GET', '/events').query, 'sort=price_low&limit=20');
  });

  apiTest(
    'pagination follows nextCursor with the same filter and stops at null',
    (tester, api) async {
      api.onCall('GET /events', (r) {
        if (r.query.contains('cursor=c2')) {
          return page([summary('e21')], next: null);
        }
        return page([for (var i = 1; i <= 20; i++) summary('e$i')], next: 'c2');
      });
      await _pump(tester, api, inline: true);
      await tester.tap(find.byKey(const Key('events-chip-open')));
      await tester.pumpAndSettle();
      api.clear();
      // Inline: a Load more button is in the tree; scrolling the parent near
      // the end loads page 2 by itself, with the same filter and the cursor.
      expect(find.byKey(const Key('events-load-more')), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -9000),
      );
      await tester.pumpAndSettle();
      final more = api.only('GET', '/events');
      expect(more.query, 'availability=open&cursor=c2&limit=20');
      expect(find.byKey(const Key('event-card-wrap-e21')), findsOneWidget);
      expect(find.byKey(const Key('events-load-more')), findsNothing);
    },
  );

  apiTest('full page: scrolling near the end loads page 2', (
    tester,
    api,
  ) async {
    api.onCall('GET /events', (r) {
      if (r.query.contains('cursor=c2')) return page([summary('e21')]);
      return page([for (var i = 1; i <= 20; i++) summary('e$i')], next: 'c2');
    });
    await _pump(tester, api);
    api.clear();
    await tester.drag(
      find.byKey(const Key('events-scroll')),
      const Offset(0, -9000),
    );
    await tester.pumpAndSettle();
    expect(api.only('GET', '/events').query, 'cursor=c2&limit=20');
  });

  apiTest('a failed page 2 keeps page 1 and offers Load more', (
    tester,
    api,
  ) async {
    api.onCall('GET /events', (r) {
      if (r.query.contains('cursor=')) throw StateError('nope');
      return page([summary('e1'), summary('e2')], next: 'c2');
    });
    await _pump(tester, api, inline: true);
    // Make page 2 fail.
    api.onCall('GET /events', (r) {
      if (r.query.contains('cursor=')) return RawResponse(500, '{"error":"x"}');
      return page([summary('e1'), summary('e2')], next: 'c2');
    });
    await tapVisible(tester, find.byKey(const Key('events-load-more')));
    expect(find.byKey(const Key('events-more-failed')), findsOneWidget);
    expect(find.byKey(const Key('event-card-wrap-e1')), findsOneWidget);
    expect(find.byKey(const Key('events-load-more')), findsOneWidget);
  });

  apiTest('empty and filtered-empty states', (tester, api) async {
    api.on('GET /events', page([]));
    await _pump(tester, api);
    expect(find.byKey(const Key('events-empty')), findsOneWidget);
    expect(find.text('No events yet'), findsOneWidget);
    await tester.tap(find.byKey(const Key('events-chip-open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('events-empty-filtered')), findsOneWidget);
    api.clear();
    await tester.tap(find.byKey(const Key('events-clear-filters')));
    await tester.pumpAndSettle();
    expect(api.only('GET', '/events').query, 'limit=20');
    expect(find.byKey(const Key('events-empty')), findsOneWidget);
  });

  apiTest('a server error shows the error state with retry', (
    tester,
    api,
  ) async {
    api.fail('GET /events', 500);
    await _pump(tester, api);
    expect(find.byKey(const Key('events-error')), findsOneWidget);
    api.heal('GET /events');
    api.on('GET /events', page([summary('e1')]));
    await tester.tap(buttonLabelled('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event-card-e1')), findsOneWidget);
  });

  apiTest('feature_disabled shows the unavailable state', (tester, api) async {
    api.fail('GET /events', 404, {'error': 'feature_disabled'});
    await _pump(tester, api);
    expect(find.byKey(const Key('events-unavailable')), findsOneWidget);
    expect(find.text("Events aren't available yet"), findsOneWidget);
  });

  apiTest('offline with a cached default list shows the cached cards', (
    tester,
    api,
  ) async {
    api.on('GET /events', page([summary('e1')]));
    await _pump(tester, api);
    expect(find.byKey(const Key('event-card-e1')), findsOneWidget);
    // Now the network is gone: the cached list and the alert show.
    await tester.pumpWidget(const SizedBox());
    api.onCall('GET /events', (_) => throw const HttpClientFailure());
    await _pump(tester, api);
    expect(find.byKey(const Key('events-offline-cached')), findsOneWidget);
    expect(find.byKey(const Key('event-card-e1')), findsOneWidget);
  });

  apiTest('offline without a cache shows the offline error', (
    tester,
    api,
  ) async {
    api.onCall('GET /events', (_) => throw const HttpClientFailure());
    await _pump(tester, api);
    expect(find.byKey(const Key('events-error')), findsOneWidget);
    expect(find.text("You're offline"), findsOneWidget);
  });

  apiTest('favourites off: no heart and no Saved chip', (tester, api) async {
    api.on('GET /events', page([summary('e1')]));
    await _pump(tester, api);
    expect(find.byKey(const Key('event-save-e1')), findsNothing);
    expect(find.byKey(const Key('events-chip-saved')), findsNothing);
  });

  apiTest(
    'favourites on: the heart toggles optimistically and reverts on error',
    (tester, api) async {
      api.on('GET /events', page([summary('e1', isSaved: false)]));
      await _pump(tester, api, favourites: true);
      expect(find.byKey(const Key('events-chip-saved')), findsOneWidget);
      api.clear();
      await tester.tap(find.byKey(const Key('event-save-e1')));
      await tester.pumpAndSettle();
      expect(api.only('PUT', '/me/event-favourites/e1'), isNotNull);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(EventsAnalytics.debugSink!.last.name, 'event_saved');
      // Removing fails → reverts with a snack.
      api.fail('DELETE /me/event-favourites/e1', 500);
      await tester.tap(find.byKey(const Key('event-save-e1')));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      // The Saved chip asks for saved=1.
      api.clear();
      await tapVisible(tester, find.byKey(const Key('events-chip-saved')));
      expect(api.only('GET', '/events').query, 'saved=1&limit=20');
    },
  );

  apiTest('Swahili at 1.3x on a 375 phone lays out without overflow', (
    tester,
    api,
  ) async {
    api.on(
      'GET /events',
      page([
        summary('e1', availability: 'closing_soon'),
        summary('e2', availability: 'not_yet_open'),
      ]),
    );
    final errors = await captureFlutterErrors(() async {
      await pumpPage(
        tester,
        api,
        EventsDiscoveryView(options: opts()),
        user: _member,
        lang: 'sw',
        textScale: 1.3,
        size: const Size(375, 812),
      );
    });
    expect(errors.where((e) => e.contains('overflowed')), isEmpty);
    expect(find.text('Inafungwa karibuni'), findsOneWidget);
    expect(find.text('Matukio 2'), findsOneWidget);
    expect(find.text('kuanzia TSh 25,000'), findsNWidgets(2));
  });

  apiTest('dark theme smoke: cards and pills render', (tester, api) async {
    api.on('GET /events', page([summary('e1', availability: 'closing_soon')]));
    await pumpPage(
      tester,
      api,
      Theme(
        data: buildDarkTheme(),
        child: EventsDiscoveryView(options: opts()),
      ),
      user: _member,
    );
    expect(find.byKey(const Key('event-card-e1')), findsOneWidget);
    expect(find.byKey(const Key('event-pill-closing_soon')), findsOneWidget);
  });

  apiTest('wide screens use two columns', (tester, api) async {
    api.on('GET /events', page([summary('e1'), summary('e2'), summary('e3')]));
    await _pump(tester, api, size: const Size(1280, 800));
    final a = tester.getTopLeft(find.byKey(const Key('event-card-e1')));
    final b = tester.getTopLeft(find.byKey(const Key('event-card-e2')));
    expect(a.dy, b.dy);
    expect(b.dx, greaterThan(a.dx));
  });
}

/// Thrown by a seeded route to stand in for "the request never got out".
class HttpClientFailure implements Exception {
  const HttpClientFailure();
  @override
  String toString() => 'SocketException: Failed host lookup';
}
