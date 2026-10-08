// Promotion in discovery: the models and request, the loader that fetches
// ranked lists, the labels, and the gym and trainer tabs with a fake server.
import 'dart:async';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/discovery_loader.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/promotion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _gym(
  String id,
  String name, {
  Map<String, dynamic>? promotion,
  String tier = 'standard',
  List<String> amenities = const [],
  bool verified = false,
}) => {
  'id': id,
  'name': name,
  'tier': tier,
  'location': 'Dar es Salaam',
  'perVisitRate': 5000,
  'ratePerMonth': 50000,
  'commissionRate': 10,
  'status': 'active',
  'amenities': amenities,
  'verified': verified,
  'promotion': ?promotion,
};

Map<String, dynamic> _trainer(
  String id,
  String name, {
  Map<String, dynamic>? promotion,
  List<String> specialties = const ['boxing'],
}) => {
  'id': id,
  'displayName': name,
  'specialties': specialties,
  'hourlyRateTzs': 20000,
  'status': 'active',
  'promotion': ?promotion,
};

const _featuredTag = {
  'id': 'p1',
  'type': 'featured',
  'label': 'Featured',
  'commercial': false,
};
const _sponsoredTag = {
  'id': 'p2',
  'type': 'sponsored',
  'label': 'Sponsored',
  'commercial': true,
};

Map<String, dynamic> _answer({
  List<Map<String, dynamic>> featured = const [],
  List<Map<String, dynamic>> items = const [],
  bool applied = true,
}) => {
  'featured': featured,
  'items': items,
  'total': items.length,
  'nextCursor': null,
  'placement': 'gym_discovery',
  'promotionsApplied': applied,
};

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://localhost:0');

  final queries = <({String kind, DiscoverQuery query})>[];
  Map<String, dynamic> Function(String kind, DiscoverQuery query)? handler;
  Object? error;

  @override
  Future<Map<String, dynamic>> discover(
    String kind,
    DiscoverQuery query,
  ) async {
    queries.add((kind: kind, query: query));
    if (error != null) throw error!;
    return handler?.call(kind, query) ?? _answer();
  }
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

/// Chips sit in a lazily built horizontal list: scroll to one before tapping it.
/// `back` scrolls towards the start of the list instead of the end.
Future<void> _tapChip(WidgetTester tester, Finder chip, {bool back = false}) async {
  final keyed = find.byKey(const Key('gym-filter-scroll'));
  final row = keyed.evaluate().isNotEmpty
      ? find.descendant(of: keyed, matching: find.byType(Scrollable))
      : find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.right,
        ).first;
  await tester.scrollUntilVisible(chip, back ? -120 : 120, scrollable: row);
  await tester.ensureVisible(chip);                                        // fully on screen, not just in the list
  await tester.pump();
  await tester.tap(chip);
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required _Api api,
  required MemberData data,
}) async {
  _ignoreTestFontOverflow();
  tester.view.physicalSize = const Size(1440, 4800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppScope(
      api: api,
      auth: AuthState(api),
      child: FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp(
          theme: buildTheme(),
          supportedLocales: const [Locale('en'), Locale('sw')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: MemberDataScope(data: data, child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('models and request', () {
    test('a promotion tag is read from the card, and absent when there is none', () {
      final gym = Gym.fromJson(_gym('g', 'Gym', promotion: _sponsoredTag));
      expect(gym.promotion?.type, 'sponsored');
      expect(gym.promotion?.label, 'Sponsored');
      expect(gym.promotion?.commercial, isTrue);
      expect(Gym.fromJson(_gym('g', 'Gym')).promotion, isNull);
      expect(PromotionTag.fromJson('nonsense'), isNull);
      expect(PromotionTag.fromJson({'label': 'x'}), isNull);
      expect(
        TrainerProfile.fromJson(_trainer('t', 'T', promotion: _featuredTag))
            .promotion
            ?.type,
        'featured',
      );
    });

    test('a ranked answer is split into the Featured section and the list', () {
      final r = DiscoverResult.fromJson<Gym>(
        _answer(
          featured: [_gym('a', 'A', promotion: _featuredTag)],
          items: [_gym('b', 'B'), _gym('c', 'C')],
          applied: false,
        )..['nextCursor'] = 50,
        Gym.fromJson,
      );
      expect(r.featured.map((g) => g.id), ['a']);
      expect(r.items.map((g) => g.id), ['b', 'c']);
      expect(r.nextCursor, 50);
      expect(r.promotionsApplied, isFalse);
      expect(r.placement, 'gym_discovery');
      final empty = DiscoverResult.fromJson<Gym>({}, Gym.fromJson);
      expect([empty.featured, empty.items, empty.total], [isEmpty, isEmpty, 0]);
      expect(empty.promotionsApplied, isTrue);
    });

    test('only what is set is sent, so the server applies its own defaults', () {
      expect(const DiscoverQuery().toQueryString(), '');
      expect(const DiscoverQuery(q: '  ').toQueryString(), '');
      expect(
        const DiscoverQuery(
          q: 'boxing gym',
          lat: -6.8,
          lng: 39.2,
          sort: 'distance',
          filters: {'tier': 'premium', 'verified': 'true', 'brand': ''},
          limit: 50,
          cursor: 50,
        ).toParams(),
        {
          'q': 'boxing gym',
          'lat': '-6.80000',
          'lng': '39.20000',
          'sort': 'distance',
          'tier': 'premium',
          'verified': 'true',
          'limit': '50',
          'cursor': '50',
        },
      );
      // The default sort is the server's; a position needs both halves.
      expect(
        const DiscoverQuery(sort: 'relevance', lat: -6.8).toParams(),
        isEmpty,
      );
      expect(
        const DiscoverQuery(q: 'a b').toQueryString(),
        '?q=a+b',
      );
    });
  });

  group('discovery loader', () {
    testWidgets('typing is debounced into one request, and chips are not', (
      tester,
    ) async {
      final asked = <String?>[];
      final results = <DiscoverResult<Gym>?>[];
      final loader = DiscoveryLoader<Gym>(
        fetch: (q) async {
          asked.add(q.q);
          return DiscoverResult.fromJson<Gym>(_answer(), Gym.fromJson);
        },
        onResult: results.add,
      );
      loader.request(const DiscoverQuery(q: 'b'));
      loader.request(const DiscoverQuery(q: 'bo'));
      loader.request(const DiscoverQuery(q: 'box'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(asked, isEmpty);
      await tester.pump(const Duration(milliseconds: 300));
      expect(asked, ['box']);
      expect(results, hasLength(1));
      loader.request(const DiscoverQuery(q: 'box', sort: 'distance'), immediate: true);
      await tester.pump();
      expect(asked, ['box', 'box']);
      loader.dispose();
    });

    testWidgets('a slow answer to an older query never replaces a newer one', (
      tester,
    ) async {
      final first = Completer<DiscoverResult<Gym>>();
      final second = Completer<DiscoverResult<Gym>>();
      final shown = <String>[];
      final loader = DiscoveryLoader<Gym>(
        debounce: Duration.zero,
        fetch: (q) => q.q == 'old' ? first.future : second.future,
        onResult: (r) => shown.add(r?.items.first.name ?? 'none'),
      );
      DiscoverResult<Gym> one(String name) =>
          DiscoverResult.fromJson<Gym>(_answer(items: [_gym('x', name)]), Gym.fromJson);
      loader.request(const DiscoverQuery(q: 'old'));
      loader.request(const DiscoverQuery(q: 'new'));
      second.complete(one('New'));
      await tester.pump();
      first.complete(one('Old'));
      await tester.pump();
      expect(shown, ['New']);
      loader.dispose();
    });

    testWidgets('a failure falls back (null) and reports loading finished', (
      tester,
    ) async {
      final loading = <bool>[];
      final results = <DiscoverResult<Gym>?>[];
      final loader = DiscoveryLoader<Gym>(
        debounce: Duration.zero,
        fetch: (_) async => throw ApiException(500, 'boom'),
        onResult: results.add,
        onLoading: loading.add,
      );
      loader.request(const DiscoverQuery());
      await tester.pump();
      expect(results, [null]);
      expect(loading, [true, false]);
      loader.dispose();
    });

    testWidgets('nothing is delivered after dispose', (tester) async {
      final done = Completer<DiscoverResult<Gym>>();
      final results = <DiscoverResult<Gym>?>[];
      final loader = DiscoveryLoader<Gym>(
        debounce: Duration.zero,
        fetch: (_) => done.future,
        onResult: results.add,
      );
      loader.request(const DiscoverQuery());
      loader.dispose();
      done.complete(DiscoverResult.fromJson<Gym>(_answer(), Gym.fromJson));
      await tester.pump();
      loader.request(const DiscoverQuery());
      await tester.pump(const Duration(seconds: 1));
      expect(results, isEmpty);
    });
  });

  group('labels', () {
    Future<void> badge(WidgetTester tester, PromotionTag tag, [Locale? l]) =>
        tester.pumpWidget(
          FFLocaleScope(
            notifier: FFLocale(),
            child: MaterialApp(home: Scaffold(body: FFPromotionBadge(tag: tag))),
          ),
        );

    testWidgets('each kind is labelled so a customer can tell it from an organic result', (
      tester,
    ) async {
      for (final (type, text) in [
        ('featured', 'Featured'),
        ('promoted', 'Promoted'),
        ('sponsored', 'Sponsored'),
        ('recommended', 'Recommended by FitFlex'),
        ('campaign', 'Campaign'),
      ]) {
        await badge(tester, PromotionTag(id: 'p', type: type, label: text));
        expect(find.text(text), findsOneWidget, reason: type);
        expect(find.byKey(Key('promo-badge-$type')), findsOneWidget);
      }
    });

    testWidgets('a custom label chosen by FitFlex is shown as it is', (
      tester,
    ) async {
      await badge(tester, const PromotionTag(id: 'p', type: 'sponsored', label: 'Partner pick'));
      expect(find.text('Partner pick'), findsOneWidget);
      expect(find.text('Sponsored'), findsNothing);
    });

    testWidgets('an empty label falls back to the standard words', (tester) async {
      await badge(tester, const PromotionTag(id: 'p', type: 'sponsored', label: ''));
      expect(find.text('Sponsored'), findsOneWidget);
    });

    testWidgets('the Featured row takes no room when there is nothing featured', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FFFeaturedStrip(title: 'Featured', count: 0, itemBuilder: _never),
          ),
        ),
      );
      expect(find.byKey(const Key('featured-strip')), findsNothing);
      expect(find.text('Featured'), findsNothing);
    });
  });

  group('gym tab', () {
    MemberData data() => MemberData()
      ..gyms = [
        Gym.fromJson(_gym('iron', 'Iron Paradise', amenities: ['sauna'])),
        Gym.fromJson(_gym('calm', 'Calm Yoga', amenities: ['yoga'])),
      ];

    testWidgets('shows the Featured section with its label, and the list below without repeating it', (
      tester,
    ) async {
      final api = _Api()
        ..handler = (_, _) => _answer(
          featured: [_gym('calm', 'Calm Yoga', promotion: _featuredTag)],
          items: [_gym('iron', 'Iron Paradise')],
        );
      await _pump(tester, const MemberGymsTab(), api: api, data: data());
      expect(find.text('Featured gyms'), findsOneWidget);
      expect(find.byKey(const Key('gym-featured-calm')), findsOneWidget);
      expect(find.text('Featured'), findsOneWidget);                      // the badge
      expect(find.byKey(const Key('gym-card-iron')), findsOneWidget);
      expect(find.byKey(const Key('gym-card-calm')), findsNothing);
      expect(api.queries.first.kind, 'gyms');
    });

    testWidgets('a sponsored gym in the list is labelled Sponsored', (tester) async {
      final api = _Api()
        ..handler = (_, _) => _answer(
          items: [_gym('iron', 'Iron Paradise', promotion: _sponsoredTag)],
        );
      await _pump(tester, const MemberGymsTab(), api: api, data: data());
      expect(find.text('Sponsored'), findsOneWidget);
      expect(find.byKey(const Key('featured-strip')), findsNothing);
    });

    testWidgets('typing a search asks the server, and shows what it returns even when the words are spread out', (
      tester,
    ) async {
      final api = _Api()
        ..handler = (_, q) => (q.q ?? '').isEmpty
            ? _answer(items: [_gym('iron', 'Iron Paradise'), _gym('calm', 'Calm Yoga')])
            : _answer(items: [_gym('ko', 'Knockout Gym', amenities: ['boxing'])]);
      await _pump(tester, const MemberGymsTab(), api: api, data: data());
      await tester.enterText(find.byKey(const Key('gym-search')), 'boxing gym');
      await tester.pump(const Duration(milliseconds: 100));
      expect(api.queries.where((q) => q.query.q == 'boxing gym'), isEmpty);   // debounced
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.queries.last.query.q, 'boxing gym');
      await tester.pump();
      // "boxing gym" is not in the name; the phone does not filter the server's answer again.
      expect(find.byKey(const Key('gym-card-ko')), findsOneWidget);
      expect(find.byKey(const Key('gym-card-iron')), findsNothing);
    });

    testWidgets('the tier chip, verified switch and nearest go to the server', (
      tester,
    ) async {
      final api = _Api();
      await _pump(tester, const MemberGymsTab(), api: api, data: data());
      await _tapChip(tester, find.byKey(const Key('gym-filter-premium')));
      expect(api.queries.last.query.filters['tier'], 'premium');
      await _tapChip(tester, find.byKey(const Key('gym-filter-more')));
      await tester.tap(find.byKey(const Key('gym-filter-verified')));
      await tester.pump();
      expect(api.queries.last.query.filters['verified'], 'true');
      expect(api.queries.last.query.filters['tier'], 'premium');
      await _tapChip(tester, find.byKey(const Key('gym-filter-all')), back: true);
      expect(api.queries.last.query.filters.containsKey('tier'), isFalse);
    });

    testWidgets('a Featured gym that fails a filter applied on the phone is not shown', (
      tester,
    ) async {
      final api = _Api()
        ..handler = (_, _) => _answer(
          featured: [_gym('calm', 'Calm Yoga', promotion: _featuredTag, amenities: ['yoga'])],
          items: [_gym('iron', 'Iron Paradise', amenities: ['sauna'])],
        );
      await _pump(tester, const MemberGymsTab(), api: api, data: data());
      expect(find.byKey(const Key('gym-featured-calm')), findsOneWidget);
      await _tapChip(tester, find.byKey(const Key('gym-filter-more')));
      await tester.tap(find.widgetWithText(FilterChip, 'sauna'));
      await tester.pump();
      expect(find.byKey(const Key('gym-featured-calm')), findsNothing);
      expect(find.byKey(const Key('featured-strip')), findsNothing);
      expect(find.byKey(const Key('gym-card-iron')), findsOneWidget);
    });

    testWidgets('only a Featured match is still shown instead of an empty page', (
      tester,
    ) async {
      final api = _Api()
        ..handler = (_, _) => _answer(
          featured: [_gym('calm', 'Calm Yoga', promotion: _featuredTag)],
        );
      await _pump(tester, const MemberGymsTab(), api: api, data: data());
      expect(find.byKey(const Key('gym-featured-calm')), findsOneWidget);
      expect(find.text('No data yet'), findsNothing);
    });

    testWidgets('if the server cannot be reached the plain list works exactly as before', (
      tester,
    ) async {
      final api = _Api()..error = ApiException(503, 'down');
      await _pump(tester, const MemberGymsTab(), api: api, data: data());
      expect(find.byKey(const Key('gym-card-iron')), findsOneWidget);
      expect(find.byKey(const Key('gym-card-calm')), findsOneWidget);
      expect(find.byKey(const Key('featured-strip')), findsNothing);
      await tester.enterText(find.byKey(const Key('gym-search')), 'iron');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const Key('gym-card-iron')), findsOneWidget);
      expect(find.byKey(const Key('gym-card-calm')), findsNothing);       // filtered on the phone
    });

    testWidgets('Saved lists saved gyms including Featured ones, with no Featured row', (
      tester,
    ) async {
      final api = _Api()
        ..handler = (_, _) => _answer(
          featured: [_gym('calm', 'Calm Yoga', promotion: _featuredTag)],
          items: [_gym('iron', 'Iron Paradise')],
        );
      final d = data()..favoriteGymIds = {'calm'};
      await _pump(tester, const MemberGymsTab(), api: api, data: d);
      await _tapChip(tester, find.byKey(const Key('gym-filter-saved')));
      expect(find.byKey(const Key('featured-strip')), findsNothing);
      expect(find.byKey(const Key('gym-card-calm')), findsOneWidget);
      expect(find.byKey(const Key('gym-card-iron')), findsNothing);
    });
  });

  group('trainer tab', () {
    MemberData data() => MemberData()
      ..trainers = [
        TrainerProfile.fromJson(_trainer('ann', 'Ann Boxer')),
        TrainerProfile.fromJson(_trainer('bo', 'Bo Yogi', specialties: ['yoga'])),
      ];

    testWidgets('shows Featured trainers with their label, and the rest below', (
      tester,
    ) async {
      final api = _Api()
        ..handler = (_, _) => {
          'featured': [_trainer('bo', 'Bo Yogi', promotion: _featuredTag, specialties: ['yoga'])],
          'items': [_trainer('ann', 'Ann Boxer')],
          'total': 1,
        };
      await _pump(tester, const MemberTrainersTab(), api: api, data: data());
      expect(find.text('Featured trainers'), findsOneWidget);
      expect(find.byKey(const Key('trainer-featured-bo')), findsOneWidget);
      expect(find.text('Featured'), findsOneWidget);
      expect(find.byKey(const Key('trainer-card-ann')), findsOneWidget);
      expect(find.byKey(const Key('trainer-card-bo')), findsNothing);
      expect(api.queries.first.kind, 'trainers');
    });

    testWidgets('a specialty chip is sent to the server, and a failure falls back to the phone', (
      tester,
    ) async {
      final api = _Api();
      await _pump(tester, const MemberTrainersTab(), api: api, data: data());
      await _tapChip(tester, find.text('Boxing'));
      expect(api.queries.last.query.filters['specialty'], 'boxing');
      api.error = ApiException(500, 'x');
      await _tapChip(tester, find.text('Yoga'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('trainer-card-bo')), findsOneWidget);
      expect(find.byKey(const Key('trainer-card-ann')), findsNothing);    // plain filter on the phone
    });
  });
}

Widget _never(BuildContext context, int index) => const SizedBox();
