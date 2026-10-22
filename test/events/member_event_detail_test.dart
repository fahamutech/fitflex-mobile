// Events S2 (spec §11.12 member_event_detail_test): section order, event
// timezone, Swahili fallback, every CTA state, 404, cancelled, hero.
import 'package:fitflexmobile/screens/member/events/member_event_detail_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events/event_time.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events/events_options.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';

const _member = {'id': 'u1', 'userType': 'member'};

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  EventsOptions? options,
  String lang = 'en',
  Size size = const Size(375, 812),
}) => pumpPage(
  tester,
  api,
  MemberEventDetailPage(
    eventId: 'evt_1',
    options: options ?? opts(),
    now: DateTime.utc(2027, 3, 10, 12),
  ),
  user: _member,
  lang: lang,
  size: size,
  keepRequests: true,
);

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    debugPhotoHeroUiOverride = false;
    debugDeviceOffsetMinutesOverride = 180;
    EventsCache.reset();
    EventsAnalytics.debugSink = [];
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    debugPhotoHeroUiOverride = null;
    debugDeviceOffsetMinutesOverride = null;
    EventsAnalytics.debugSink = null;
  });

  apiTest('sections render in the EVT-004 order', (tester, api) async {
    api.on('GET /events/evt_1', detail('evt_1'));
    await _pump(tester, api, size: const Size(375, 4000));
    expect(api.only('GET', '/events/evt_1'), isNotNull);
    expect(find.byKey(const Key('event-title')), findsOneWidget);
    expect(find.byKey(const Key('event-facts')), findsOneWidget);
    final titles = [
      'About',
      'Organizer',
      'Date & time',
      'Venue & route',
      'Categories & prices',
      "What's included",
      'Eligibility',
      'Accessibility',
      'Kit collection',
      'Schedule',
      'Sponsors',
      'Contact',
      'Terms',
      'Refund policy',
    ];
    for (final t in titles) {
      await tester.scrollUntilVisible(
        find.text(t),
        300,
        scrollable: find.byType(Scrollable).first,
      );
    }
    expect(verticalOrder(tester, titles), titles);
    expect(find.text('Updated 2 Mar 2027'), findsOneWidget);
    expect(EventsAnalytics.debugSink!.single.name, 'event_detail_viewed');
    expect(EventsAnalytics.debugSink!.single.props['availability'], 'open');
  });

  apiTest('categories list ticket rows with price, sale window and pill', (
    tester,
    api,
  ) async {
    api.on('GET /events/evt_1', detail('evt_1'));
    await _pump(tester, api, size: const Size(375, 4000));
    await tester.scrollUntilVisible(
      find.byKey(const Key('event-ticket-tt_free')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Early bird · TSh 20,000 · until 1 Mar 2027'),
      findsOneWidget,
    );
    expect(
      find.text('Standard · TSh 25,000 · until 12 Mar 2027'),
      findsOneWidget,
    );
    expect(find.text('Free entry · Free · until 12 Mar 2027'), findsOneWidget);
    expect(find.text('7 left'), findsOneWidget);
    expect(find.text('Minimum age 18'), findsOneWidget);
    expect(find.text('Full refund until registration closes'), findsOneWidget);
    // Sold-out row: muted text, pill with text.
    final early = find.descendant(
      of: find.byKey(const Key('event-ticket-tt_early')),
      matching: find.byType(FFBadge),
    );
    expect(tester.widget<FFBadge>(early).label, 'Sold out');
  });

  apiTest(
    'times are in the event zone; a different device zone adds the local line',
    (tester, api) async {
      debugDeviceOffsetMinutesOverride = 0;
      api.on(
        'GET /events/evt_1',
        detail(
          'evt_1',
          timezone: 'Africa/Nairobi',
          utcOffsetMinutes: 180,
          timezoneAbbr: 'EAT',
        ),
      );
      await _pump(tester, api, size: const Size(375, 2000));
      expect(find.text('Sun 14 Mar 2027, 06:30 EAT'), findsWidgets);
      expect(find.text('Times are in EAT (Africa/Nairobi)'), findsOneWidget);
      expect(find.text("That's 14 Mar, 03:30 where you are"), findsOneWidget);
    },
  );

  apiTest('same device zone: no local line', (tester, api) async {
    api.on('GET /events/evt_1', detail('evt_1'));
    await _pump(tester, api, size: const Size(375, 2000));
    expect(find.byKey(const Key('event-local-time')), findsNothing);
  });

  apiTest('Swahili description when provided, English with a note when not', (
    tester,
    api,
  ) async {
    api.on('GET /events/evt_1', detail('evt_1'));
    await _pump(tester, api, lang: 'sw', size: const Size(375, 2000));
    expect(find.textContaining('Njia tambarare'), findsOneWidget);
    expect(find.byKey(const Key('event-no-swahili')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.on(
      'GET /events/evt_1',
      detail('evt_1', description: const {'en': 'English only.', 'sw': ''}),
    );
    await _pump(tester, api, lang: 'sw', size: const Size(375, 2000));
    expect(find.text('English only.'), findsOneWidget);
    expect(find.byKey(const Key('event-no-swahili')), findsOneWidget);
  });

  apiTest('S2: the bar shows a disabled Register with the "opens soon" line', (
    tester,
    api,
  ) async {
    api.on('GET /events/evt_1', detail('evt_1'));
    await _pump(tester, api);
    expect(find.byKey(const Key('event-cta-bar')), findsOneWidget);
    expect(find.text('Register'), findsOneWidget);
    expect(isEnabled(tester, find.byKey(const Key('event-cta'))), isFalse);
    expect(find.text('Registration opens soon in the app'), findsOneWidget);
  });

  group('CTA states with registration on (§11.6)', () {
    Future<void> check(
      WidgetTester tester,
      RecordingApi api,
      String availability, {
      required String label,
      String? hint,
      required bool enabled,
    }) async {
      api.on('GET /events/evt_1', detail('evt_1', availability: availability));
      await _pump(tester, api, options: opts(registration: true));
      final bar = find.byKey(const Key('event-cta-bar'));
      expect(
        find.descendant(of: bar, matching: find.text(label)),
        findsOneWidget,
        reason: availability,
      );
      expect(isEnabled(tester, find.byKey(const Key('event-cta'))), enabled);
      if (hint != null) expect(find.text(hint), findsOneWidget);
    }

    apiTest(
      'open',
      (t, a) => check(
        t,
        a,
        'open',
        label: 'Register · from TSh 25,000',
        hint: 'Closes Fri 12 Mar',
        enabled: true,
      ),
    );
    apiTest(
      'closing_soon',
      (t, a) => check(
        t,
        a,
        'closing_soon',
        label: 'Register',
        hint: 'Closing soon · 3 days left',
        enabled: true,
      ),
    );
    apiTest(
      'sold_out',
      (t, a) => check(
        t,
        a,
        'sold_out',
        label: 'Sold out',
        hint: 'Check back for cancellations',
        enabled: false,
      ),
    );
    apiTest(
      'closed',
      (t, a) =>
          check(t, a, 'closed', label: 'Registration closed', enabled: false),
    );
    apiTest(
      'not_yet_open',
      (t, a) =>
          check(t, a, 'not_yet_open', label: 'Opens Fri 1 Jan', enabled: false),
    );
    apiTest(
      'cancelled',
      (t, a) =>
          check(t, a, 'cancelled', label: 'Event cancelled', enabled: false),
    );

    apiTest('in_progress hides the bar', (tester, api) async {
      api.on('GET /events/evt_1', detail('evt_1', availability: 'in_progress'));
      await _pump(tester, api, options: opts(registration: true));
      expect(find.byKey(const Key('event-cta-bar')), findsNothing);
    });
  });

  apiTest('404 event_not_found shows the gone state with Back', (
    tester,
    api,
  ) async {
    api.fail('GET /events/evt_1', 404, {'error': 'event_not_found'});
    await _pump(tester, api);
    expect(find.byKey(const Key('event-gone')), findsOneWidget);
    expect(find.text("This event isn't available"), findsOneWidget);
    expect(buttonLabelled('Back to events'), findsOneWidget);
    expect(find.byKey(const Key('event-cta-bar')), findsNothing);
  });

  apiTest('feature_disabled shows the unavailable state', (tester, api) async {
    api.fail('GET /events/evt_1', 404, {'error': 'feature_disabled'});
    await _pump(tester, api);
    expect(find.byKey(const Key('event-unavailable')), findsOneWidget);
  });

  apiTest('a server error shows retry', (tester, api) async {
    api.fail('GET /events/evt_1', 500);
    await _pump(tester, api);
    expect(find.byKey(const Key('event-detail-error')), findsOneWidget);
    api.heal('GET /events/evt_1');
    api.on('GET /events/evt_1', detail('evt_1'));
    await tester.tap(buttonLabelled('Try again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('event-title')), findsOneWidget);
  });

  apiTest('cancelled renders the banner with the public note', (
    tester,
    api,
  ) async {
    api.on(
      'GET /events/evt_1',
      detail(
        'evt_1',
        availability: 'cancelled',
        cancellation: {
          'reason': 'weather',
          'note': {'en': 'Flooding on the course.', 'sw': 'Mafuriko njiani.'},
        },
      ),
    );
    await _pump(tester, api);
    expect(find.byKey(const Key('event-cancelled-banner')), findsOneWidget);
    expect(
      find.text('This event was cancelled. Flooding on the course.'),
      findsOneWidget,
    );
  });

  apiTest('hero flag off: image card and header; no cover → placeholder', (
    tester,
    api,
  ) async {
    api.on('GET /events/evt_1', detail('evt_1', heroImageUrl: null));
    await _pump(tester, api);
    expect(find.byKey(const Key('event-hero')), findsNothing);
    expect(find.byKey(const Key('event-image-placeholder')), findsOneWidget);
    expect(find.byKey(const Key('event-title')), findsOneWidget);
    expect(find.text('ROAD · SUN 14 MAR 2027'), findsOneWidget);
  });

  apiTest(
    'hero flag on: the band carries the cover and falls back to a bundled photo',
    (tester, api) async {
      debugPhotoHeroUiOverride = true;
      api.on('GET /events/evt_1', detail('evt_1'));
      await _pump(tester, api);
      final band = tester.widget<FFHeroBand>(
        find.byKey(const Key('event-hero')),
      );
      expect(band.networkImage?.url, 'https://img.fixtures.local/hero.webp');
      expect(band.photo, kEventsHeroFallback);
      expect(band.headlineAccent, 'Marathon');
      expect(band.headlineLead, 'Dar Half');
      await tester.pumpWidget(const SizedBox());
      api.on('GET /events/evt_1', detail('evt_1', heroImageUrl: null));
      await _pump(tester, api);
      final plain = tester.widget<FFHeroBand>(
        find.byKey(const Key('event-hero')),
      );
      expect(plain.networkImage, isNull);
    },
  );

  apiTest('favourites on: save and share controls; the heart toggles', (
    tester,
    api,
  ) async {
    api.on('GET /events/evt_1', detail('evt_1'));
    await _pump(tester, api, options: opts(favourites: true));
    expect(find.byKey(const Key('event-detail-save')), findsOneWidget);
    expect(find.byKey(const Key('event-detail-share')), findsOneWidget);
    api.clear();
    await tester.tap(find.byKey(const Key('event-detail-save')));
    await tester.pumpAndSettle();
    expect(api.only('PUT', '/me/event-favourites/evt_1'), isNotNull);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    // Share: the platform channel is a no-op in a test; the tap must not throw.
    await tester.tap(find.byKey(const Key('event-detail-share')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  apiTest('favourites off: neither heart nor share', (tester, api) async {
    api.on('GET /events/evt_1', detail('evt_1'));
    await _pump(tester, api);
    expect(find.byKey(const Key('event-detail-save')), findsNothing);
    expect(find.byKey(const Key('event-detail-share')), findsNothing);
  });

  apiTest('Swahili at 1.3x: the CTA bar grows instead of clipping', (
    tester,
    api,
  ) async {
    api.on('GET /events/evt_1', detail('evt_1'));
    final errors = await captureFlutterErrors(() async {
      await pumpPage(
        tester,
        api,
        MemberEventDetailPage(eventId: 'evt_1', options: opts()),
        user: _member,
        lang: 'sw',
        textScale: 1.3,
        size: const Size(375, 812),
      );
    });
    expect(errors.where((e) => e.contains('overflowed')), isEmpty);
    expect(
      find.text('Usajili utafunguliwa hivi karibuni kwenye app'),
      findsOneWidget,
    );
    expect(find.text('Jisajili'), findsOneWidget);
  });
}
