// Promotion analytics: the tracker (batching, retry, dedupe, attribution) and
// where the app records events (cards, detail pages, booking, subscribe, save).
import 'dart:async';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_card.dart';
import 'package:fitflexmobile/screens/member/widgets/trainer_card.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/promotion.dart';
import 'package:fitflexmobile/shared/promotion_events.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _tag = PromotionTag(
  id: 'p1',
  type: 'sponsored',
  label: 'Sponsored',
  commercial: true,
);
const _tag2 = PromotionTag(id: 'p2', type: 'featured', label: 'Featured');

/// A fake `/events` endpoint: records every request, and can fail on demand.
class _Sink {
  final batches = <List<Map<String, dynamic>>>[];
  Object? Function(int call)? behaviour;
  int calls = 0;

  Future<void> send(List<Map<String, dynamic>> events) async {
    calls++;
    final failure = behaviour?.call(calls);
    if (failure != null) throw failure;
    batches.add(events);
  }

  List<Map<String, dynamic>> get all => [for (final b in batches) ...b];
  List<String> get types => [for (final e in all) e['type'] as String];
}

class _ThrowingApi extends ApiClient {
  _ThrowingApi() : super(baseUrl: 'http://localhost:0');
  int posts = 0;
  Object error = StateError('boom');
  @override
  Future<Map<String, dynamic>> postEvents(
    List<Map<String, dynamic>> events,
  ) async {
    posts++;
    throw error;
  }
}

DateTime _clock = DateTime.utc(2026, 10, 9, 12);

PromotionEvents _install(
  _Sink sink, {
  bool enabled = true,
  int flushAt = 20,
  int queueCap = 200,
  Duration backoffBase = Duration.zero,
}) {
  _clock = DateTime.utc(2026, 10, 9, 12);
  PromotionEvents.install(
    ApiClient(baseUrl: 'http://localhost:0'),
    enabled: enabled,
    sender: sink.send,
    now: () => _clock,
    flushAt: flushAt,
    queueCap: queueCap,
    backoffBase: backoffBase,
  );
  addTearDown(PromotionEvents.reset);
  return PromotionEvents.instance;
}

/// The test renderer draws every glyph a full em wide, so text that fits on a
/// phone can overflow here. That is a property of the test font, not of the
/// screen, so it is not treated as a failure; everything else still is.
void _ignoreTestFontOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Gym _gym(String id, {PromotionTag? promotion}) => Gym.fromJson({
  'id': id,
  'name': 'Gym $id',
  'tier': 'standard',
  'location': 'Dar es Salaam',
  'perVisitRate': 5000,
  'commissionRate': 10,
  'status': 'active',
  'promotion': ?(promotion == null
      ? null
      : {
          'id': promotion.id,
          'type': promotion.type,
          'label': promotion.label,
          'commercial': promotion.commercial,
        }),
});

TrainerProfile _trainer(String id, {PromotionTag? promotion}) =>
    TrainerProfile.fromJson({
      'id': id,
      'displayName': 'Trainer $id',
      'specialties': ['boxing'],
      'hourlyRateTzs': 20000,
      'status': 'active',
      'promotion': ?(promotion == null
          ? null
          : {
              'id': promotion.id,
              'type': promotion.type,
              'label': promotion.label,
            }),
    });

Widget _app(Widget home, {ApiClient? api, MemberData? data, GoRouter? router}) {
  final a = api ?? ApiClient(baseUrl: 'http://localhost:0');
  final theme = buildTheme();
  const locales = [Locale('en'), Locale('sw')];
  const delegates = [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  final body = data == null ? home : MemberDataScope(data: data, child: home);
  return AppScope(
    api: a,
    auth: AuthState(a),
    child: FFLocaleScope(
      notifier: FFLocale(),
      child: router != null
          ? MaterialApp.router(
              theme: theme,
              supportedLocales: locales,
              localizationsDelegates: delegates,
              routerConfig: router,
            )
          : MaterialApp(
              theme: theme,
              supportedLocales: locales,
              localizationsDelegates: delegates,
              home: Scaffold(body: body),
            ),
    ),
  );
}

GoRouter _routerFor(Widget card) => GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, _) => Scaffold(body: card),
    ),
    GoRoute(
      path: '/member/gyms/:id',
      builder: (_, _) => const Scaffold(body: Text('gym page')),
    ),
    GoRoute(
      path: '/member/trainers/:id',
      builder: (_, _) => const Scaffold(body: Text('trainer page')),
    ),
  ],
);

void main() {
  group('tracker', () {
    test(
      'is a no-op until installed, and when the kill switch is off',
      () async {
        PromotionEvents.reset();
        final i = PromotionEvents.instance;
        i.impression('gym', 'g1', _tag);
        i.click('gym', 'g1', _tag);
        i.recordForTouched('detail_view', 'gym', 'g1');
        expect(i.enabled, isFalse);
        expect(i.pending, 0);
        await i.flush();

        final sink = _Sink();
        final off = _install(sink, enabled: false);
        off.impression('gym', 'g1', _tag);
        off.click('gym', 'g1', _tag);
        await off.flush();
        expect(off.pending, 0);
        expect(sink.calls, 0);
        expect(kPromotionAnalytics, isTrue); // default build has it on
      },
    );

    test('an event carries the fields the server needs', () async {
      final sink = _Sink();
      final t = _install(sink);
      t.click('trainer', 't9', _tag, placement: 'search_results');
      await t.flush();
      final e = sink.all.single;
      expect(e['type'], 'click');
      expect(e['entityType'], 'trainer');
      expect(e['entityId'], 't9');
      expect(e['promotionId'], 'p1');
      expect(e['placement'], 'search_results');
      expect((e['sessionId'] as String).length, greaterThanOrEqualTo(8));
      expect(e['at'], '2026-10-09T12:00:00.000Z');
      t.impression('gym', 'g1', _tag); // no placement: the key is left out
      await t.flush();
      expect(sink.all.last.containsKey('placement'), isFalse);
    });

    test('untagged or id-less cards record nothing', () async {
      final sink = _Sink();
      final t = _install(sink);
      t.impression('gym', 'g1', null);
      t.click('gym', 'g1', null);
      t.impression(
        'gym',
        'g1',
        const PromotionTag(id: '', type: 'featured', label: ''),
      );
      expect(t.pending, 0);
    });

    test('the session id is the same for every event in a launch', () async {
      final sink = _Sink();
      var t = _install(sink);
      t.click('gym', 'a', _tag);
      t.click('gym', 'b', _tag);
      await t.flush();
      t = _install(sink); // a new tracker in the same launch
      t.click('gym', 'c', _tag);
      await t.flush();
      expect({for (final e in sink.all) e['sessionId']}, hasLength(1));
    });

    test(
      'clicks, saves, bookings and subscriptions are never de-duplicated',
      () async {
        final sink = _Sink();
        final t = _install(sink);
        t.click('gym', 'g', _tag);
        t.click('gym', 'g', _tag);
        t.recordForTouched('save', 'gym', 'g');
        t.recordForTouched('save', 'gym', 'g');
        t.recordForTouched('subscription_click', 'gym', 'g');
        t.recordForTouched('subscription_click', 'gym', 'g');
        await t.flush();
        expect(sink.types, [
          'click',
          'click',
          'save',
          'save',
          'subscription_click',
          'subscription_click',
        ]);
      },
    );

    test(
      'an impression is sent once per promotion and placement per hour',
      () async {
        final sink = _Sink();
        final t = _install(sink);
        t.impression('gym', 'g', _tag, placement: 'a');
        t.impression('gym', 'g', _tag, placement: 'a');
        t.impression(
          'gym',
          'g',
          _tag,
          placement: 'b',
        ); // another placement counts
        t.impression(
          'gym',
          'h',
          _tag2,
          placement: 'a',
        ); // another promotion counts
        _clock = _clock.add(const Duration(minutes: 59));
        t.impression('gym', 'g', _tag, placement: 'a');
        expect(t.pending, 3);
        _clock = _clock.add(
          const Duration(minutes: 2),
        ); // an hour after the first
        t.impression('gym', 'g', _tag, placement: 'a');
        expect(t.pending, 4);
      },
    );

    test('a detail view is sent once per promotion per 10 minutes', () async {
      final sink = _Sink();
      final t = _install(sink);
      t.click('gym', 'g', _tag);
      t.recordForTouched('detail_view', 'gym', 'g');
      t.recordForTouched('detail_view', 'gym', 'g');
      _clock = _clock.add(const Duration(minutes: 9));
      t.recordForTouched('detail_view', 'gym', 'g');
      _clock = _clock.add(const Duration(minutes: 2));
      t.recordForTouched('detail_view', 'gym', 'g');
      await t.flush();
      expect(sink.types, ['click', 'detail_view', 'detail_view']);
    });

    test(
      'a touch attributes the next actions for 30 minutes, then expires',
      () async {
        final sink = _Sink();
        final t = _install(sink);
        t.recordForTouched('detail_view', 'gym', 'g'); // organic: nothing
        t.click('gym', 'g', _tag, placement: 'gym_discovery');
        _clock = _clock.add(const Duration(minutes: 29));
        t.recordForTouched(
          'booking_click',
          'trainer',
          'g',
        ); // other entity: nothing
        t.recordForTouched('subscription_click', 'gym', 'g');
        _clock = _clock.add(const Duration(minutes: 2));
        t.recordForTouched('subscription_click', 'gym', 'g'); // expired
        t.recordForTouched('save', 'gym', 'g');
        await t.flush();
        expect(sink.types, ['click', 'subscription_click']);
        final attributed = sink.all.last;
        expect(attributed['promotionId'], 'p1');
        expect(attributed['placement'], 'gym_discovery');
        // A fresh tap starts a new window.
        t.click('gym', 'g', _tag2);
        t.recordForTouched('save', 'gym', 'g');
        await t.flush();
        expect(sink.all.last['promotionId'], 'p2');
      },
    );

    test(
      'a request carries at most 50 events and everything is sent',
      () async {
        final sink = _Sink();
        final t = _install(sink, flushAt: 1000);
        for (var i = 0; i < 120; i++) {
          t.click('gym', 'g$i', _tag);
        }
        await t.flush();
        expect(sink.batches.map((b) => b.length), [50, 50, 20]);
        expect(t.pending, 0);
      },
    );

    test('the queue keeps the newest 200 events', () async {
      final sink = _Sink();
      final t = _install(sink, flushAt: 1000);
      for (var i = 0; i < 230; i++) {
        t.click('gym', 'g$i', _tag);
      }
      expect(t.pending, 200);
      await t.flush();
      expect(sink.all.first['entityId'], 'g30');
      expect(sink.all.last['entityId'], 'g229');
    });

    test('a full batch is sent as soon as 20 events are waiting', () async {
      final sink = _Sink();
      final t = _install(sink);
      for (var i = 0; i < 19; i++) {
        t.click('gym', 'g$i', _tag);
      }
      expect(sink.calls, 0);
      t.click('gym', 'g19', _tag);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(sink.all, hasLength(20));
    });

    test(
      'a network failure is retried, then dropped after 3 attempts',
      () async {
        final sink = _Sink()..behaviour = (_) => Exception('offline');
        final t = _install(sink);
        t.click('gym', 'g', _tag);
        await t.flush();
        expect(sink.calls, 3);
        expect(t.pending, 0); // dropped, not kept forever
        sink.behaviour = null;
        t.click('gym', 'h', _tag);
        await t.flush();
        expect(
          sink.all.single['entityId'],
          'h',
        ); // the dropped one is not resent
      },
    );

    test('a retry that succeeds sends the batch once', () async {
      final sink = _Sink()
        ..behaviour = (n) => n < 3 ? ApiException(503, 'down') : null;
      final t = _install(sink);
      t.click('gym', 'g', _tag);
      await t.flush();
      expect(sink.calls, 3);
      expect(sink.all, hasLength(1));
    });

    test('other 4xx answers are never retried', () async {
      for (final status in [400, 401, 413, 422]) {
        final sink = _Sink()
          ..behaviour = (_) => ApiException(status, {'error': 'x'});
        final t = _install(sink);
        t.click('gym', 'g', _tag);
        await t.flush();
        expect(sink.calls, 1, reason: '$status');
        expect(t.pending, 0, reason: '$status');
      }
    });

    testWidgets('backoff waits between attempts', (tester) async {
      final sink = _Sink()..behaviour = (_) => ApiException(500, 'x');
      final t = _install(sink, backoffBase: const Duration(seconds: 2));
      t.click('gym', 'g', _tag);
      unawaited(t.flush());
      await tester.pump();
      expect(sink.calls, 1);
      await tester.pump(const Duration(seconds: 1));
      expect(sink.calls, 1);
      await tester.pump(const Duration(seconds: 1)); // 2 s
      expect(sink.calls, 2);
      await tester.pump(const Duration(seconds: 4)); // then 4 s
      expect(sink.calls, 3);
      await tester.pump(const Duration(seconds: 10));
      expect(sink.calls, 3);
    });

    testWidgets('a 429 keeps the events and pauses sending', (tester) async {
      final sink = _Sink()
        ..behaviour = (n) =>
            n == 1 ? ApiException(429, {'error': 'rate_limited'}) : null;
      final t = _install(sink);
      t.click('gym', 'g', _tag);
      await tester.runAsync(t.flush);
      expect(sink.calls, 1);
      expect(t.pending, 1); // kept
      await tester.runAsync(t.flush); // still paused
      expect(sink.calls, 1);
      await tester.pump(const Duration(seconds: 61)); // pause ends, timer fires
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      _clock = _clock.add(const Duration(seconds: 61));
      await tester.runAsync(t.flush);
      expect(sink.all.single['entityId'], 'g');
      expect(t.pending, 0);
    });

    testWidgets('events are sent after 15 seconds without a full batch', (
      tester,
    ) async {
      final sink = _Sink();
      final t = _install(sink);
      t.click('gym', 'g', _tag);
      await tester.pump(const Duration(seconds: 14));
      expect(sink.calls, 0);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(sink.all, hasLength(1));
      expect(t.pending, 0);
    });

    test('never throws, even when the api does', () async {
      final api = _ThrowingApi();
      PromotionEvents.install(
        api,
        now: () => _clock,
        backoffBase: Duration.zero,
      );
      addTearDown(PromotionEvents.reset);
      final t = PromotionEvents.instance;
      t.click('gym', 'g', _tag);
      t.impression('gym', 'g', _tag);
      t.recordForTouched('save', 'gym', 'g');
      await t.flush();
      expect(api.posts, 3);
      api.error = ApiException(500, null);
      t.click('gym', 'g', _tag);
      await t.flush();
      expect(t.pending, 0);
    });

    testWidgets('app going to the background sends what is waiting', (
      tester,
    ) async {
      final sink = _Sink();
      final t = _install(sink);
      t.click('gym', 'g', _tag);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(sink.all, hasLength(1));
      expect(t.pending, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
  });

  group('cards', () {
    testWidgets(
      'a promoted gym card records one impression, not one per rebuild',
      (tester) async {
        _ignoreTestFontOverflow();
        final sink = _Sink();
        final t = _install(sink);
        tester.view.physicalSize = const Size(900, 1600);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        final gym = _gym('g1', promotion: _tag);
        Widget build() => _app(
          GymGridCard(gym: gym, placement: 'gym_discovery'),
          router: _routerFor(
            SizedBox(
              width: 200,
              height: 300,
              child: GymGridCard(gym: gym, placement: 'gym_discovery'),
            ),
          ),
        );
        await tester.pumpWidget(build());
        await tester.pump();
        expect(t.pending, 1);
        await tester.pumpWidget(build()); // rebuilt
        await tester.pump();
        await tester.pump();
        expect(t.pending, 1);
        await t.flush();
        expect(sink.all.single['type'], 'impression');
        expect(sink.all.single['placement'], 'gym_discovery');
        expect(sink.all.single['promotionId'], 'p1');
      },
    );

    testWidgets(
      'scrolling a promoted card out of a lazy list and back records it once',
      (tester) async {
        _ignoreTestFontOverflow();
        final sink = _Sink();
        final t = _install(sink);
        final gym = _gym('g1', promotion: _tag);
        final controller = ScrollController();
        await tester.pumpWidget(
          _app(
            ListView.builder(
              controller: controller,
              itemCount: 40,
              itemBuilder: (_, i) => i == 0
                  ? SizedBox(
                      height: 300,
                      child: GymGridCard(gym: gym, placement: 'gym_discovery'),
                    )
                  : const SizedBox(height: 300),
            ),
          ),
        );
        await tester.pump();
        expect(t.pending, 1);
        controller.jumpTo(6000); // card 0 is torn down
        await tester.pump();
        expect(find.byType(GymGridCard), findsNothing);
        controller.jumpTo(0); // and built again
        await tester.pump();
        expect(find.byType(GymGridCard), findsOneWidget);
        expect(t.pending, 1);
        await t.flush();
        expect(sink.types, ['impression']);
      },
    );

    testWidgets(
      'tapping a promoted card records a click, then navigates as before',
      (tester) async {
        _ignoreTestFontOverflow();
        final sink = _Sink();
        final t = _install(sink);
        final gym = _gym('g1', promotion: _tag);
        await tester.pumpWidget(
          _app(
            const SizedBox(),
            router: _routerFor(
              SizedBox(
                width: 200,
                height: 300,
                child: GymGridCard(gym: gym, placement: 'search_results'),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.tap(find.byType(GymGridCard));
        await tester.pumpAndSettle();
        expect(find.text('gym page'), findsOneWidget);
        await t.flush();
        expect(sink.types, ['impression', 'click']);
        expect(sink.all.last['placement'], 'search_results');
      },
    );

    testWidgets('an organic card records nothing, on show or on tap', (
      tester,
    ) async {
      _ignoreTestFontOverflow();
      final sink = _Sink();
      final t = _install(sink);
      await tester.pumpWidget(
        _app(
          const SizedBox(),
          router: _routerFor(
            Column(
              children: [
                SizedBox(
                  width: 200,
                  height: 250,
                  child: GymGridCard(
                    gym: _gym('g1'),
                    placement: 'gym_discovery',
                  ),
                ),
                SizedBox(
                  width: 200,
                  height: 250,
                  child: TrainerGridCard(
                    trainer: _trainer('t1'),
                    placement: 'x',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(TrainerGridCard));
      await tester.pumpAndSettle();
      expect(t.pending, 0);
      expect(sink.calls, 0);
    });

    testWidgets('a promoted trainer card records impression and click', (
      tester,
    ) async {
      _ignoreTestFontOverflow();
      final sink = _Sink();
      final t = _install(sink);
      await tester.pumpWidget(
        _app(
          const SizedBox(),
          router: _routerFor(
            SizedBox(
              width: 200,
              height: 300,
              child: TrainerGridCard(
                trainer: _trainer('t1', promotion: _tag2),
                placement: 'marketplace',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byType(TrainerGridCard));
      await tester.pumpAndSettle();
      await t.flush();
      expect(sink.types, ['impression', 'click']);
      expect(
        sink.all.every(
          (e) => e['entityType'] == 'trainer' && e['promotionId'] == 'p2',
        ),
        isTrue,
      );
    });

    testWidgets('the gym tab passes the placement from the discovery answer', (
      tester,
    ) async {
      _ignoreTestFontOverflow();
      final sink = _Sink();
      final t = _install(sink);
      final api = _DiscoverApi({
        'featured': [
          {
            ..._gymJson('calm'),
            'promotion': {'id': 'p1', 'type': 'featured', 'label': 'Featured'},
          },
        ],
        'items': [_gymJson('iron')],
        'total': 1,
        'placement': 'gym_discovery',
        'promotionsApplied': true,
      });
      tester.view.physicalSize = const Size(1440, 4800);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(
          const MemberGymsTab(),
          api: api,
          data: MemberData()
            ..gyms = [
              Gym.fromJson(_gymJson('calm')),
              Gym.fromJson(_gymJson('iron')),
            ],
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 500));
      await t.flush();
      // Only the promoted gym is recorded; the organic one is not.
      expect(sink.all, hasLength(1));
      expect(sink.all.single['entityId'], 'calm');
      expect(sink.all.single['placement'], 'gym_discovery');
    });
  });

  group('detail pages and actions', () {
    MemberData gymData() => MemberData()..gyms = [_gym('g1')];

    testWidgets(
      'a gym page opened from a promoted card records the view, save and subscribe',
      (tester) async {
        _ignoreTestFontOverflow();
        final sink = _Sink();
        final t = _install(sink);
        t.click('gym', 'g1', _tag, placement: 'gym_discovery');
        await tester.pumpWidget(
          _app(const MemberGymDetailPage(gymId: 'g1'), data: gymData()),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('gym-save-toggle')));
        await tester.pump();
        await tester.scrollUntilVisible(
          find.byKey(const Key('gym-subscribe-button')),
          400,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.byKey(const Key('gym-subscribe-button')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await t.flush();
        expect(sink.types, [
          'click',
          'detail_view',
          'save',
          'subscription_click',
        ]);
        expect(
          sink.all
              .skip(1)
              .every(
                (e) =>
                    e['promotionId'] == 'p1' &&
                    e['placement'] == 'gym_discovery',
              ),
          isTrue,
        );
      },
    );

    testWidgets('the same gym page opened organically records nothing', (
      tester,
    ) async {
      _ignoreTestFontOverflow();
      final sink = _Sink();
      final t = _install(sink);
      await tester.pumpWidget(
        _app(const MemberGymDetailPage(gymId: 'g1'), data: gymData()),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('gym-save-toggle')));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('gym-subscribe-button')),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('gym-subscribe-button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(t.pending, 0);
    });

    testWidgets('a gym page after the touch has expired records nothing', (
      tester,
    ) async {
      _ignoreTestFontOverflow();
      final sink = _Sink();
      final t = _install(sink);
      t.click('gym', 'g1', _tag);
      _clock = _clock.add(const Duration(minutes: 31));
      await tester.pumpWidget(
        _app(const MemberGymDetailPage(gymId: 'g1'), data: gymData()),
      );
      await tester.pump();
      await t.flush();
      expect(sink.types, ['click']);
    });

    testWidgets(
      'a trainer page opened from a promoted card records the view and Book',
      (tester) async {
        _ignoreTestFontOverflow();
        final sink = _Sink();
        final t = _install(sink);
        t.click('trainer', 't1', _tag2, placement: 'marketplace');
        final data = MemberData()..trainers = [_trainer('t1')];
        await tester.pumpWidget(
          _app(const MemberTrainerDetailPage(trainerId: 't1'), data: data),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('trainer-action-book')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        await t.flush();
        expect(sink.types, ['click', 'detail_view', 'booking_click']);
        expect(sink.all.last['promotionId'], 'p2');
        expect(sink.all.last['entityType'], 'trainer');
      },
    );

    testWidgets('a trainer page opened organically records nothing', (
      tester,
    ) async {
      _ignoreTestFontOverflow();
      final sink = _Sink();
      final t = _install(sink);
      final data = MemberData()..trainers = [_trainer('t1')];
      await tester.pumpWidget(
        _app(const MemberTrainerDetailPage(trainerId: 't1'), data: data),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('trainer-action-book')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(t.pending, 0);
    });
  });

  group('shop', () {
    Map<String, dynamic> product(
      String id, {
      Map<String, dynamic>? promotion,
    }) => {
      'id': id,
      'vendorId': 'v',
      'name': 'Protein $id',
      'category': 'supplements',
      'priceTzs': 10000,
      'stock': 5,
      'promotion': ?promotion,
    };

    testWidgets(
      'promoted products record impression, click, detail view and save; organic ones nothing',
      (tester) async {
        _ignoreTestFontOverflow();
        final sink = _Sink();
        final t = _install(sink);
        final api = _ShopApi(
          catalogue: [product('a'), product('b')],
          discovery: {
            'featured': [
              product(
                'f',
                promotion: {
                  'id': 'p3',
                  'type': 'featured',
                  'label': 'Featured',
                },
              ),
            ],
            'items': [
              product(
                'a',
                promotion: {
                  'id': 'p4',
                  'type': 'sponsored',
                  'label': 'Sponsored',
                  'commercial': true,
                },
              ),
              product('b'),
            ],
            'total': 2,
            'placement': 'marketplace',
            'promotionsApplied': true,
          },
        );
        tester.view.physicalSize = const Size(1000, 3000);
        tester.view.devicePixelRatio = 2;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_app(const ShopBrowsePage(), api: api));
        await tester.pump();
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('shop-product-a')), findsOneWidget);
        expect(find.byKey(const Key('shop-featured-f')), findsOneWidget);
        await t.flush();
        expect(
          sink.all
              .map(
                (e) =>
                    '${e['type']}:${e['entityId']}:${e['promotionId']}:${e['placement']}',
              )
              .toSet(),
          {'impression:f:p3:marketplace', 'impression:a:p4:marketplace'},
        );
        // Save before opening: not attributed (no touch yet) and so not recorded.
        await tester.tap(find.byKey(const Key('shop-save-a')));
        await tester.pump();
        expect(t.pending, 0);
        // Organic product: tap, open, save record nothing.
        await tester.tap(find.byKey(const Key('shop-product-b')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(t.pending, 0);
        Navigator.of(tester.element(find.byType(ShopBrowsePage))).pop();
        await tester.pumpAndSettle();
        // Promoted product: click + detail_view when the sheet opens.
        await tester.tap(find.byKey(const Key('shop-product-a')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await t.flush();
        expect(
          sink.all
              .skip(2)
              .map((e) => '${e['type']}:${e['entityId']}:${e['promotionId']}')
              .toList(),
          ['click:a:p4', 'detail_view:a:p4'],
        );
        expect(sink.all.last['placement'], 'marketplace');
        // Back on the list, saving the product we came from is attributed.
        Navigator.of(tester.element(find.byType(ShopBrowsePage))).pop();
        await tester.pumpAndSettle();
        // Saved earlier, before any touch: the first tap un-saves it.
        await tester.tap(find.byKey(const Key('shop-save-a')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('shop-save-a')));
        await tester.pump();
        await t.flush();
        expect(sink.types.last, 'save');
        expect(sink.all.last['promotionId'], 'p4');
      },
    );
  });
}

Map<String, dynamic> _gymJson(String id) => {
  'id': id,
  'name': 'Gym $id',
  'tier': 'standard',
  'location': 'Dar es Salaam',
  'perVisitRate': 5000,
  'ratePerMonth': 50000,
  'commissionRate': 10,
  'status': 'active',
};

class _DiscoverApi extends ApiClient {
  _DiscoverApi(this.answer) : super(baseUrl: 'http://localhost:0');
  final Map<String, dynamic> answer;
  @override
  Future<Map<String, dynamic>> discover(
    String kind,
    DiscoverQuery query,
  ) async => answer;
}

class _ShopApi extends ApiClient {
  _ShopApi({required this.catalogue, required this.discovery})
    : super(baseUrl: 'http://localhost:0');
  final List<Map<String, dynamic>> catalogue;
  final Map<String, dynamic> discovery;
  @override
  Future<List<dynamic>> listShopProducts({
    String? category,
    String? search,
    String? brand,
    String? vendorId,
    num? minPrice,
    num? maxPrice,
    num? minRating,
    num? maxDistanceKm,
    bool? delivery,
    bool? promotions,
    String? sort,
  }) async => catalogue;
  @override
  Future<List<dynamic>> myShopOrders() async => [];
  @override
  Future<Map<String, dynamic>> discover(
    String kind,
    DiscoverQuery query,
  ) async => discovery;
  @override
  Future<Map<String, dynamic>> shopProduct(String id) async =>
      catalogue.firstWhere((p) => p['id'] == id);
}
