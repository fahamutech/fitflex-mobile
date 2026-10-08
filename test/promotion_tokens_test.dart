// Promotion tokens: parsing, the session on discover requests, and the token
// on every analytics event.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/promotion.dart';
import 'package:fitflexmobile/shared/promotion_events.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const _tok = PromotionTag(
  id: 'p1',
  type: 'sponsored',
  label: 'Sponsored',
  token: 'tok-p1',
);
const _tok2 = PromotionTag(
  id: 'p2',
  type: 'featured',
  label: 'Featured',
  token: 'tok-p2',
);
const _bare = PromotionTag(id: 'p3', type: 'featured', label: 'Featured');

class _Sink {
  final batches = <List<Map<String, dynamic>>>[];
  Future<Object?> Function(int call)? behaviour;
  int calls = 0;
  Future<Object?> send(List<Map<String, dynamic>> events) async {
    calls++;
    final r = await behaviour?.call(calls);
    batches.add(events);
    return r;
  }

  List<Map<String, dynamic>> get all => [for (final b in batches) ...b];
}

DateTime _clock = DateTime.utc(2026, 10, 9, 12);

PromotionEvents _install(_Sink sink, {bool enabled = true}) {
  _clock = DateTime.utc(2026, 10, 9, 12);
  PromotionEvents.install(
    ApiClient(baseUrl: 'http://localhost:0'),
    enabled: enabled,
    sender: sink.send,
    now: () => _clock,
    flushAt: 1000,
    backoffBase: Duration.zero,
  );
  addTearDown(PromotionEvents.reset);
  return PromotionEvents.instance;
}

void _ignoreTestFontOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

class _Api extends ApiClient {
  _Api(this.answer) : super(baseUrl: 'http://localhost:0');
  final Map<String, dynamic> answer;
  final queries = <({String kind, DiscoverQuery query})>[];
  @override
  Future<Map<String, dynamic>> discover(
    String kind,
    DiscoverQuery query,
  ) async {
    queries.add((kind: kind, query: query));
    return answer;
  }

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
  }) async => [];
  @override
  Future<List<dynamic>> myShopOrders() async => [];
}

Future<void> _pump(WidgetTester tester, Widget child, _Api api) async {
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
            body: MemberDataScope(data: MemberData(), child: child),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump();
}

void main() {
  group('tag and query', () {
    test('the token is read when present and null otherwise', () {
      expect(
        PromotionTag.fromJson({
          'id': 'p',
          'type': 'featured',
          'token': 'abc',
        })?.token,
        'abc',
      );
      expect(
        PromotionTag.fromJson({'id': 'p', 'type': 'featured'})?.token,
        isNull,
      );
      expect(
        PromotionTag.fromJson({
          'id': 'p',
          'type': 'featured',
          'token': 5,
        })?.token,
        isNull,
      );
      expect(
        PromotionTag.fromJson({
          'id': 'p',
          'type': 'featured',
          'token': '',
        })?.token,
        isNull,
      );
    });

    test('session is sent only when set and well formed', () {
      expect(const DiscoverQuery().toParams().containsKey('session'), isFalse);
      expect(
        const DiscoverQuery(session: 'abcdef0123456789').toParams()['session'],
        'abcdef0123456789',
      );
      for (final bad in [
        'short',
        'has space 12345',
        'a' * 65,
        'bad/chars/12',
      ]) {
        expect(
          DiscoverQuery(session: bad).toParams().containsKey('session'),
          isFalse,
          reason: bad,
        );
      }
      expect(
        const DiscoverQuery(q: 'x').withSession('abcdef0123').toQueryString(),
        contains('session=abcdef0123'),
      );
    });

    test(
      'the launch session id is valid, and absent when analytics are off',
      () {
        final id = discoverSessionId();
        expect(id, isNotNull);
        expect(DiscoverQuery(session: id).toParams()['session'], id);
        expect(PromotionEvents.instance.currentSessionId, id);
        expect(discoverSessionId(enabled: false), isNull);
      },
    );
  });

  group('tracker', () {
    test(
      'impression and click carry the token; touched events carry the tapped card token',
      () async {
        final sink = _Sink();
        final t = _install(sink);
        t.impression('gym', 'g1', _tok);
        t.click('gym', 'g1', _tok);
        t.recordForTouched('detail_view', 'gym', 'g1');
        t.recordForTouched('save', 'gym', 'g1');
        t.recordForTouched('booking_click', 'gym', 'g1');
        t.recordForTouched('subscription_click', 'gym', 'g1');
        t.click('trainer', 't1', _tok2);
        t.recordForTouched('detail_view', 'trainer', 't1');
        await t.flush();
        for (final e in sink.all) {
          expect(
            e['token'],
            e['entityId'] == 'g1' ? 'tok-p1' : 'tok-p2',
            reason: '${e['type']}',
          );
        }
        expect(sink.all.map((e) => e['type']).toSet(), {
          'impression',
          'click',
          'detail_view',
          'save',
          'booking_click',
          'subscription_click',
        });
        expect(sink.all.length, 8);
      },
    );

    test(
      'with an older server (no tokens seen) a tagged card still goes out without the field',
      () async {
        final sink = _Sink();
        final t = _install(sink);
        t.impression('gym', 'g1', _bare);
        t.click('gym', 'g1', _bare);
        t.recordForTouched('save', 'gym', 'g1');
        await t.flush();
        expect(sink.all.length, 3);
        expect(sink.all.any((e) => e.containsKey('token')), isFalse);
      },
    );

    test(
      'once tokens are being issued, a tokenless card is not queued',
      () async {
        final sink = _Sink();
        final t = _install(sink);
        t.impression('gym', 'g1', _tok);
        t.impression('gym', 'g2', _bare);
        t.click('gym', 'g2', _bare);
        expect(t.pending, 1);
      },
    );

    test(
      'permanent rejections in the reply are dropped and never re-sent',
      () async {
        final sink = _Sink()
          ..behaviour = (_) async => {
            'accepted': 0,
            'duplicates': 0,
            'rejected': [
              {'index': 0, 'error': 'invalid_token'},
              {'index': 1, 'error': 'token_required'},
            ],
          };
        final t = _install(sink);
        t.impression('gym', 'g1', _tok);
        t.impression('gym', 'g2', _tok2);
        await t.flush();
        expect(sink.calls, 1);
        expect(t.pending, 0);
        expect(t.rejected, 2);
        await t.flush();
        expect(sink.calls, 1);
      },
    );

    test('a 4xx answer is dropped without a retry', () async {
      final sink = _Sink()
        ..behaviour = (c) async => throw ApiException(c == 1 ? 400 : 503, 'x');
      final t = _install(sink);
      t.impression('gym', 'g1', _tok);
      await t.flush();
      expect(sink.calls, 1);
      expect(t.pending, 0);
    });
  });

  group('discover calls pass the session', () {
    final session = discoverSessionId()!;
    const empty = {'featured': [], 'items': [], 'total': 0};

    testWidgets('gym tab', (tester) async {
      final api = _Api(empty);
      await _pump(tester, const MemberGymsTab(), api);
      expect(api.queries, isNotEmpty);
      expect(api.queries.first.kind, 'gyms');
      expect(api.queries.first.query.toParams()['session'], session);
    });

    testWidgets('trainer tab', (tester) async {
      final api = _Api(empty);
      await _pump(tester, const MemberTrainersTab(), api);
      expect(api.queries, isNotEmpty);
      expect(api.queries.first.kind, 'trainers');
      expect(api.queries.first.query.toParams()['session'], session);
    });

    testWidgets('shop', (tester) async {
      final api = _Api(empty);
      await _pump(tester, const ShopBrowsePage(), api);
      final q = api.queries.where((x) => x.kind == 'products');
      expect(q, isNotEmpty);
      expect(q.first.query.toParams()['session'], session);
    });
  });
}
