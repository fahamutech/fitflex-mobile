// Shop home Phase 2 · S4 (flash sales), buyer side: FFCountdown on the
// server's clock (device clock ±1 h), the boundary at endsAt, the
// sale-ended card, the flash sale rail, `expectedPriceTzs` in the order
// body, and the "Prices have changed" sheet.
//
// Mocks the contract from fitflex-functions docs/shop-flash-sales-api.md
// (feat/shop-flash-sales, SHOP_FLASH_SALES): product rows carry
// `effectivePriceTzs` and, while live, `sale {id, salePriceTzs,
// wasPriceTzs, regularPriceTzs, discountPct, startsAt, endsAt}`;
// GET /shop/home adds `flashSales` and a `flash_sale` section with
// `endsAt`; POST /me/shop-orders items[].expectedPriceTzs → 409
// price_changed {productId, currentPriceTzs, lines, expectedTotalTzs,
// totalTzs}. With the flag off none of these fields exist.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/formatters.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/shop_home.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';
import 'package:fitflexmobile/shared/widgets/shop_home/shop_flash_sale.dart';
import 'package:fitflexmobile/shared/widgets/shop_home/shop_home_page.dart';

import 'support/recording_api.dart';

/// The server's time in every answer below.
final _serverNow = DateTime.utc(2026, 10, 29, 8);
const _member = {'id': 'm1', 'userType': 'member', 'displayName': 'Amina'};

Finder _key(String k) => find.byKey(Key(k));

/// Makes the device clock [skew] away from the server and follow the
/// test's fake time from now on.
void _deviceClock(WidgetTester tester, {Duration skew = Duration.zero}) {
  final t0 = tester.binding.clock.now();
  ShopClock.debugDeviceNow = () =>
      _serverNow.add(skew).add(tester.binding.clock.now().difference(t0));
}

Map<String, dynamic> _sale(
  String id, {
  int sale = 69000,
  int was = 85000,
  Duration endsIn = const Duration(hours: 2),
}) => {
  'id': 'fls_$id',
  'salePriceTzs': sale,
  'wasPriceTzs': was,
  'regularPriceTzs': was,
  'discountPct': ((was - sale) * 100 / was).floor(),
  'startsAt': _serverNow.subtract(const Duration(hours: 1)).toIso8601String(),
  'endsAt': _serverNow.add(endsIn).toIso8601String(),
};

/// A product row. [flagOn] adds `effectivePriceTzs` (every row while
/// SHOP_FLASH_SALES is on); [sale] the live sale.
Map<String, dynamic> _p(
  String id,
  String name, {
  int price = 85000,
  bool flagOn = true,
  Map<String, dynamic>? sale,
}) => {
  'id': id,
  'vendorId': 'v1',
  'name': name,
  'category': 'equipment',
  'priceTzs': price,
  'stock': 10,
  'rating': 0,
  'reviewCount': 0,
  'soldCount': 0,
  'deliveryAvailable': true,
  if (flagOn) 'effectivePriceTzs': sale?['salePriceTzs'] ?? price,
  'sale': ?sale,
};

const _names = {
  'p1': 'Whey Protein',
  'p2': 'Yoga Mat',
  'p3': 'Kettlebell',
  'p4': 'Running Shoes',
  'p5': 'Jump Rope',
};

Map<String, dynamic> _home({
  bool flagOn = true,
  Duration endsIn = const Duration(hours: 2),
  bool onSale = true,
}) {
  final products = {
    for (final e in _names.entries)
      e.key: _p(
        e.key,
        e.value,
        flagOn: flagOn,
        sale: flagOn && onSale && e.key != 'p5'
            ? _sale(e.key, endsIn: endsIn)
            : null,
      ),
  };
  return {
    'serverNow': _serverNow.toIso8601String(),
    'mode': 'member',
    'categories': const [],
    if (flagOn) 'flashSales': {'enabled': true},
    'sections': [
      {
        'key': 'best_sellers',
        'title': {'en': 'Best sellers', 'sw': 'Zinazouzwa zaidi'},
        'viewAll': {
          'query': {'sort': 'popularity'},
        },
        'productIds': ['p5'],
      },
      if (flagOn && onSale)
        {
          'key': 'flash_sale',
          'title': {'en': 'Flash sale', 'sw': 'Ofa ya muda mfupi'},
          'reasonCodes': ['flash_sale_seller_discount'],
          'endsAt': _serverNow.add(endsIn).toIso8601String(),
          'viewAll': {
            'path': '/shop/products',
            'query': {'flashSale': 'true'},
          },
          'hasMore': false,
          'productIds': ['p1', 'p2', 'p3', 'p4'],
        },
    ],
    'products': products,
  };
}

void _seed(RecordingApi api, Map<String, dynamic> home) {
  api.on('GET /shop/products', [
    for (final p in (home['products'] as Map).values) p,
  ]);
  api.on('GET /me/shop-orders', <dynamic>[]);
  api.on('GET /gyms', <dynamic>[]);
  api.on('GET /shop/home', home);
  for (final e in (home['products'] as Map).entries) {
    api.on('GET /shop/products/${e.key}', e.value);
  }
}

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  double scale = 1,
}) => pumpPage(
  tester,
  api,
  const ShopBrowseBody(),
  user: _member,
  lang: lang,
  textScale: scale,
  size: const Size(420, 900),
  keepRequests: true,
);

/// Opens the cart from the sticky bar and places the order; returns the
/// body of the (last) order request.
Future<void> _checkout(WidgetTester tester, PageHost host) async {
  await host.dismissSnacks();
  await tapVisible(tester, _key('shop-home-checkout'));
  await typeInto(tester, _key('shop-delivery-address'), 'Masaki');
  await tapVisible(tester, _key('shop-place-order'));
}

Map<String, dynamic> _priceChanged({
  String reason = 'sale_ended',
  int expected = 69000,
  int current = 85000,
}) => {
  'error': 'price_changed',
  'productId': 'p1',
  'currentPriceTzs': current,
  'lines': [
    {
      'productId': 'p1',
      'variant': null,
      'expectedPriceTzs': expected,
      'currentPriceTzs': current,
      'reason': reason,
    },
  ],
  'expectedTotalTzs': expected,
  'totalTzs': current,
};

/// Hosts a bare [FFCountdown] (for the clock and boundary cases).
Future<void> _pumpCountdown(
  WidgetTester tester,
  DateTime endsAt, {
  VoidCallback? onEnded,
}) async {
  await tester.pumpWidget(
    FFLocaleScope(
      notifier: FFLocale(),
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: FFCountdown(
              endsAt: endsAt,
              serverOffset: ShopClock.offset,
              now: ShopClock.deviceNow,
              onEnded: onEnded,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The time left the chips show.
Duration _left(WidgetTester tester) {
  final p = _chips(tester).split(':').map(int.parse).toList();
  return Duration(hours: p[0], minutes: p[1], seconds: p[2]);
}

/// Within 10 s of [d] (pumping moves the test clock a little).
Matcher _about(Duration d) => predicate<Duration>(
  (v) => (v - d).abs() <= const Duration(seconds: 10),
  'about $d',
);

String _chips(WidgetTester tester) => [
  for (final k in ['h', 'm', 's'])
    (tester.widget<Text>(
      find.descendant(of: _key('ff-countdown-$k'), matching: find.byType(Text)),
    )).data,
].join(':');

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    debugShopHomeV2Override = true;
    ShopEvents.reset();
    ShopHomeViewState.debugRefetchJitter = () => const Duration(seconds: 2);
  });
  tearDown(() {
    debugShopHomeV2Override = null;
    ShopClock.reset();
    ShopHomeViewState.debugRefetchJitter = null;
  });

  group('FFCountdown on the server clock', () {
    for (final skew in [const Duration(hours: 1), const Duration(hours: -1)]) {
      testWidgets('device clock ${skew.isNegative ? '1 h slow' : '1 h fast'}: '
          'still counts to the server end', (tester) async {
        _deviceClock(tester, skew: skew);
        // The answer arrived now: serverNow against the (wrong) device time.
        ShopClock.sync(_serverNow);
        expect(ShopClock.offset, -skew);
        final endsAt = _serverNow.add(const Duration(hours: 2));
        await _pumpCountdown(tester, endsAt);
        expect(_chips(tester), '02:00:00');
        await tester.pump(const Duration(seconds: 1));
        expect(_chips(tester), '01:59:59');
        // Minute precision for screen readers, never per second.
        expect(
          tester.getSemantics(_key('ff-countdown')).label,
          'Sale ends in 1 hour 59 minutes',
        );
        await tester.pump(const Duration(seconds: 20));
        expect(
          tester.getSemantics(_key('ff-countdown')).label,
          'Sale ends in 1 hour 59 minutes',
        );
        expect(
          tester
              .getSemantics(_key('ff-countdown'))
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isFalse,
        );
      });
    }

    testWidgets(
      'without the server offset a wrong clock would be an hour off',
      (tester) async {
        _deviceClock(tester, skew: const Duration(hours: 1));
        // No sync: the device's own (wrong) time.
        await _pumpCountdown(tester, _serverNow.add(const Duration(hours: 2)));
        expect(_chips(tester), '01:00:00');
      },
    );

    testWidgets('boundary: 00:00:01 → "Sale ended" at endsAt, once', (
      tester,
    ) async {
      _deviceClock(tester);
      ShopClock.sync(_serverNow);
      var ended = 0;
      await _pumpCountdown(
        tester,
        _serverNow.add(const Duration(seconds: 2)),
        onEnded: () => ended++,
      );
      expect(_chips(tester), '00:00:02');
      await tester.pump(const Duration(seconds: 1));
      expect(_chips(tester), '00:00:01');
      expect(
        tester.getSemantics(_key('ff-countdown')).label,
        'Sale ends in less than a minute',
      );
      expect(ended, 0);
      // 1 ms before the end it is still on.
      await tester.pump(const Duration(milliseconds: 999));
      expect(_key('ff-countdown-ended'), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(_key('ff-countdown-ended'), findsOneWidget);
      expect(find.text('Sale ended'), findsOneWidget);
      expect(ended, 1);
      await tester.pump(const Duration(seconds: 5));
      expect(ended, 1);
    });

    testWidgets('more than 24 h left: "Ends in N days" instead of chips', (
      tester,
    ) async {
      _deviceClock(tester);
      ShopClock.sync(_serverNow);
      await _pumpCountdown(
        tester,
        _serverNow.add(const Duration(days: 2, hours: 3)),
      );
      expect(_key('ff-countdown-h'), findsNothing);
      expect(find.text('Ends in 2 days'), findsOneWidget);
    });

    testWidgets('a sale already over says "Sale ended" and calls back', (
      tester,
    ) async {
      _deviceClock(tester);
      ShopClock.sync(_serverNow);
      var ended = 0;
      await _pumpCountdown(
        tester,
        _serverNow.subtract(const Duration(seconds: 1)),
        onEnded: () => ended++,
      );
      await tester.pump();
      expect(find.text('Sale ended'), findsOneWidget);
      expect(ended, 1);
    });
  });

  group('flash sale rail', () {
    apiTest('heads the rails, Fuel badge, sale + struck "was", countdown', (
      tester,
      api,
    ) async {
      _deviceClock(tester);
      _seed(api, _home());
      final host = await _pump(tester, api);
      final flash = _key('shop-home-section-flash_sale');
      final best = _key('shop-home-section-best_sellers');
      expect(flash, findsOneWidget);
      // First, whatever order the server listed it in.
      expect(tester.getTopLeft(flash).dy, lessThan(tester.getTopLeft(best).dy));
      expect(find.text(host.tr('shop.section.flash_sale')), findsWidgets);
      expect(_key('shop-flash-countdown'), findsOneWidget);
      expect(_left(tester), _about(const Duration(hours: 2)));
      expect(find.text(host.tr('shop.home.endsIn')), findsOneWidget);
      final badge = tester.widget<FFBadge>(_key('shop-home-discount-p1'));
      expect(badge.label, '−18%');
      expect(badge.tone, FFBadgeTone.fuel);
      expect(
        tester.widget<Text>(_key('shop-home-sale-p1')).data,
        formatCurrency(69000),
      );
      final was = tester.widget<Text>(_key('shop-home-was-p1'));
      expect(was.data, formatCurrency(85000));
      expect(was.style?.decoration, TextDecoration.lineThrough);
      // Read once: the struck price is inside the card's one label.
      expect(
        tester.getSemantics(_key('shop-home-card-p1')).label,
        contains(
          'Sale price ${formatCurrency(69000)}, was ${formatCurrency(85000)}, '
          '18 percent off',
        ),
      );
    });

    apiTest('clock 1 h fast: the rail still shows the server time left', (
      tester,
      api,
    ) async {
      _deviceClock(tester, skew: const Duration(hours: 1));
      _seed(api, _home());
      await _pump(tester, api);
      // Not 3 h (the device's own clock): the server's 2 h.
      expect(_left(tester), _about(const Duration(hours: 2)));
    });

    apiTest('Swahili at 130%: the rail title and countdown fit', (
      tester,
      api,
    ) async {
      _deviceClock(tester);
      _seed(api, _home());
      await _pump(tester, api, lang: 'sw', scale: 1.3);
      expect(find.text('Ofa ya muda mfupi'), findsWidgets);
      expect(find.text('Inaisha baada ya'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    apiTest('at endsAt: "Sale ended", ended cards, no cart buttons, refetch '
        'and the rail goes', (tester, api) async {
      _deviceClock(tester);
      _seed(api, _home(endsIn: const Duration(seconds: 3)));
      final host = await _pump(tester, api);
      expect(_key('shop-home-add-p1'), findsOneWidget);
      final homeCalls = api.where('GET', '/shop/home').length;
      // After the end the server no longer sends the sale.
      api.on('GET /shop/home', _home(onSale: false));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(find.text(host.tr('shop.home.saleEnded')), findsWidgets);
      expect(_key('shop-home-sale-ended-p1'), findsOneWidget);
      expect(_key('shop-home-discount-p1'), findsNothing);
      expect(_key('shop-home-was-p1'), findsNothing);
      expect(_key('shop-home-add-p1'), findsNothing);
      expect(
        tester.getSemantics(_key('shop-home-card-p1')).label,
        contains(host.tr('shop.home.saleEndedUpdating')),
      );
      // One refetch after the jitter (2 s here), then no rail.
      expect(api.where('GET', '/shop/home').length, homeCalls);
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(api.where('GET', '/shop/home').length, homeCalls + 1);
      expect(_key('shop-home-section-flash_sale'), findsNothing);
    });

    apiTest('flag off: no rail, no sale UI, the order body as before', (
      tester,
      api,
    ) async {
      _deviceClock(tester);
      _seed(api, _home(flagOn: false));
      final host = await _pump(tester, api);
      expect(_key('shop-home-section-flash_sale'), findsNothing);
      expect(_key('shop-flash-countdown'), findsNothing);
      expect(find.byType(FFCountdown), findsNothing);
      await tapVisible(tester, _key('shop-home-add-p5'));
      await _checkout(tester, host);
      expect(api.only('POST', '/me/shop-orders').body, {
        'items': [
          {'productId': 'p5', 'qty': 1},
        ],
        'deliveryMethod': 'home_delivery',
        'deliveryAddress': 'Masaki',
        'paymentMethod': 'mpesa',
        'paymentOutcome': 'success',
      });
    });
  });

  group('checkout', () {
    apiTest('each line sends the price shown as expectedPriceTzs', (
      tester,
      api,
    ) async {
      _deviceClock(tester);
      _seed(api, _home());
      final host = await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-add-p1'));
      await tapVisible(tester, _key('shop-home-add-p5'));
      // The cart line shows the sale price, the regular one struck.
      await host.dismissSnacks();
      await tapVisible(tester, _key('shop-home-checkout'));
      expect(
        tester.widget<Text>(_key('shop-cart-line-sale-p1')).data,
        formatCurrency(69000),
      );
      await typeInto(tester, _key('shop-delivery-address'), 'Masaki');
      await tapVisible(tester, _key('shop-place-order'));
      final body = api.only('POST', '/me/shop-orders').body as Map;
      expect(body['items'], [
        {'productId': 'p1', 'qty': 1, 'expectedPriceTzs': 69000},
        {'productId': 'p5', 'qty': 1, 'expectedPriceTzs': 85000},
      ]);
    });

    apiTest('409 price_changed: the sheet lists the change; Continue resends '
        'with the new price and places the order', (tester, api) async {
      _deviceClock(tester);
      _seed(api, _home());
      // The first attempt is refused; the retry goes through.
      api.fail('POST /me/shop-orders', 409);
      api.onCall('fail:POST /me/shop-orders', (_) {
        api.heal('POST /me/shop-orders');
        return _priceChanged();
      });
      api.on('POST /me/shop-orders', {
        'id': 'ord_1',
        'totalTzs': 85000,
        'paymentStatus': 'pending',
      });
      // The fresh row: the sale is gone.
      api.on('GET /shop/products/p1', _p('p1', 'Whey Protein'));
      final host = await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-add-p1'));
      await _checkout(tester, host);
      expect(_key('shop-price-changed'), findsOneWidget);
      expect(find.text(host.tr('shop.priceChanged.title')), findsOneWidget);
      expect(
        tester.getSemantics(_key('price-changed-p1')).label,
        'Whey Protein, was ${formatCurrency(69000)}, now '
        '${formatCurrency(85000)}, Sale ended',
      );
      expect(
        tester.getSemantics(_key('shop-price-changed-totals')).label,
        'Total was ${formatCurrency(69000)}, new total ${formatCurrency(85000)}',
      );
      expect(
        find.text('Continue with ${formatCurrency(85000)}'),
        findsOneWidget,
      );
      await tapVisible(tester, _key('shop-price-changed-continue'));
      final orders = api.where('POST', '/me/shop-orders');
      expect(orders, hasLength(2));
      expect(((orders[1].body as Map)['items'] as List).single, {
        'productId': 'p1',
        'qty': 1,
        'expectedPriceTzs': 85000,
      });
      // A new attempt after the refusal: a new idempotency key.
      expect(
        orders[1].headers['idempotency-key'],
        isNot(orders[0].headers['idempotency-key']),
      );
      expect(_key('shop-price-changed'), findsNothing);
      expect(find.text(host.tr('shop.orderPending')), findsWidgets);
    });

    apiTest('prices change again: the same sheet updates and says so', (
      tester,
      api,
    ) async {
      _deviceClock(tester);
      _seed(api, _home());
      var calls = 0;
      api.fail('POST /me/shop-orders', 409);
      api.onCall('fail:POST /me/shop-orders', (_) {
        calls++;
        return calls == 1
            ? _priceChanged()
            : _priceChanged(
                reason: 'price_changed',
                expected: 85000,
                current: 90000,
              );
      });
      final host = await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-add-p1'));
      await _checkout(tester, host);
      await tapVisible(tester, _key('shop-price-changed-continue'));
      expect(_key('shop-price-changed'), findsOneWidget);
      expect(_key('shop-price-changed-again'), findsOneWidget);
      expect(find.text(host.tr('shop.priceChanged.again')), findsOneWidget);
      expect(
        find.text('Continue with ${formatCurrency(90000)}'),
        findsOneWidget,
      );
      expect(find.byType(ShopPriceChangedBody), findsOneWidget);
    });

    apiTest(
      'Back to cart closes the sheet and reopens the cart, details kept',
      (tester, api) async {
        _deviceClock(tester);
        _seed(api, _home());
        api.fail('POST /me/shop-orders', 409, _priceChanged());
        final host = await _pump(tester, api);
        await tapVisible(tester, _key('shop-home-add-p1'));
        await _checkout(tester, host);
        await tapVisible(tester, _key('shop-price-changed-back'));
        expect(_key('shop-price-changed'), findsNothing);
        expect(_key('shop-place-order'), findsOneWidget);
        expect(textOf(tester, _key('shop-delivery-address')), 'Masaki');
        // The cart line is now at the server's price.
        expect(
          find.descendant(
            of: _key('shop-cart-summary'),
            matching: find.text(formatCurrency(85000)),
          ),
          findsWidgets,
        );
      },
    );

    apiTest('Swahili: the price-changed sheet', (tester, api) async {
      _deviceClock(tester);
      _seed(api, _home());
      api.fail('POST /me/shop-orders', 409, _priceChanged());
      final host = await _pump(tester, api, lang: 'sw', scale: 1.3);
      await tapVisible(tester, _key('shop-home-add-p1'));
      await _checkout(tester, host);
      expect(find.text('Bei zimebadilika'), findsOneWidget);
      expect(find.text('Rudi kwenye kikapu'), findsOneWidget);
      expect(find.text('Ofa imeisha'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('countdown words (singular, no "0 minutes")', () {
    testWidgets('English and Swahili', (tester) async {
      final out = <String, List<String>>{};
      for (final lang in ['en', 'sw']) {
        await tester.pumpWidget(
          FFLocaleScope(
            notifier: FFLocale()..set(Locale(lang)),
            child: MaterialApp(
              home: Builder(
                builder: (context) {
                  out[lang] = [
                    for (final d in const [
                      Duration(hours: 24),
                      Duration(hours: 2),
                      Duration(hours: 1),
                      Duration(hours: 1, minutes: 1),
                      Duration(hours: 1, minutes: 30),
                      Duration(hours: 2, minutes: 1),
                      Duration(hours: 2, minutes: 14),
                      Duration(minutes: 1),
                      Duration(minutes: 9),
                      Duration(seconds: 30),
                    ])
                      ffCountdownA11yLabel(context, d),
                  ];
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
      }
      expect(out['en'], [
        'Sale ends in 24 hours',
        'Sale ends in 2 hours',
        'Sale ends in 1 hour',
        'Sale ends in 1 hour 1 minute',
        'Sale ends in 1 hour 30 minutes',
        'Sale ends in 2 hours 1 minute',
        'Sale ends in 2 hours 14 minutes',
        'Sale ends in 1 minute',
        'Sale ends in 9 minutes',
        'Sale ends in less than a minute',
      ]);
      expect(out['sw'], [
        'Ofa inaisha baada ya saa 24',
        'Ofa inaisha baada ya saa 2',
        'Ofa inaisha baada ya saa 1',
        'Ofa inaisha baada ya saa 1 na dakika 1',
        'Ofa inaisha baada ya saa 1 na dakika 30',
        'Ofa inaisha baada ya saa 2 na dakika 1',
        'Ofa inaisha baada ya saa 2 na dakika 14',
        'Ofa inaisha baada ya dakika 1',
        'Ofa inaisha baada ya dakika 9',
        'Ofa inaisha kabla ya dakika moja',
      ]);
      for (final words in [...out['en']!, ...out['sw']!]) {
        expect(words, isNot(contains(' 0 ')), reason: words);
      }
    });
  });

  group('capabilities and the server clock', () {
    apiTest('X-FF-Shop-Caps: flash_sale on /shop/home, /shop/products and '
        '/shop/products/:id', (tester, api) async {
      _deviceClock(tester);
      _seed(api, _home());
      await _pump(tester, api);
      // Results (GET /shop/products), then a product (GET /:id).
      await tapVisible(tester, _key('shop-home-browse-all'));
      await tapVisible(tester, find.text('Whey Protein').first);
      for (final path in [
        '/shop/home',
        '/shop/products',
        '/shop/products/p1',
      ]) {
        final calls = api.where('GET', path);
        expect(calls, isNotEmpty, reason: path);
        for (final c in calls) {
          expect(c.headers['x-ff-shop-caps'], 'flash_sale', reason: path);
        }
      }
      // Never on other calls (orders, gyms).
      expect(
        api.where('GET', '/me/shop-orders').first.headers['x-ff-shop-caps'],
        isNull,
      );
    });

    test('serverNow on /shop/products/:id syncs the clock', () async {
      ShopClock.debugDeviceNow = () => _serverNow.add(const Duration(hours: 1));
      final api = RecordingApi()
        ..on('GET /shop/products/p1', {
          ..._p('p1', 'Whey'),
          'serverNow': _serverNow.toIso8601String(),
        });
      await api.run(
        () => ApiClient(baseUrl: 'http://fixtures.local').shopProduct('p1'),
      );
      expect(ShopClock.offset, const Duration(hours: -1));
      ShopClock.reset();
    });

    test('no serverNow: the HTTP Date header syncs the clock', () async {
      ShopClock.debugDeviceNow = () =>
          _serverNow.subtract(const Duration(hours: 1));
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode([_p('p1', 'Whey')]),
          200,
          headers: {
            'content-type': 'application/json',
            'date': 'Thu, 29 Oct 2026 08:00:00 GMT',
          },
        ),
      );
      await http.runWithClient(
        () => ApiClient(baseUrl: 'http://fixtures.local').listShopProducts(),
        () => client,
      );
      expect(ShopClock.offset, const Duration(hours: 1));
      ShopClock.reset();
    });

    test('parseHttpDate', () {
      expect(
        parseHttpDate('Thu, 29 Oct 2026 08:00:00 GMT'),
        DateTime.utc(2026, 10, 29, 8),
      );
      expect(parseHttpDate(null), isNull);
      expect(parseHttpDate('yesterday'), isNull);
      // A body serverNow wins over the header.
      ShopClock.debugDeviceNow = () => _serverNow;
      ShopClock.syncFrom({
        'serverNow': _serverNow
            .add(const Duration(minutes: 5))
            .toIso8601String(),
      }, 'Thu, 29 Oct 2026 09:00:00 GMT');
      expect(ShopClock.offset, const Duration(minutes: 5));
      ShopClock.reset();
    });
  });

  group('models', () {
    test('ShopFlashSale: needs id, end and a real reduction', () {
      expect(ShopFlashSale.fromJson(_sale('p1')), isNotNull);
      expect(ShopFlashSale.fromJson({..._sale('p1'), 'id': ''}), isNull);
      expect(
        ShopFlashSale.fromJson({..._sale('p1'), 'salePriceTzs': 85000}),
        isNull,
      );
      expect(ShopFlashSale.fromJson({..._sale('p1'), 'endsAt': 'x'}), isNull);
      expect(ShopFlashSale.fromJson(null), isNull);
    });

    test('live is decided by the server clock to the millisecond', () {
      ShopClock.debugDeviceNow = () => _serverNow;
      final sale = ShopFlashSale.fromJson(
        _sale('p1', endsIn: const Duration(milliseconds: 1)),
      )!;
      expect(sale.live, isTrue);
      ShopClock.debugDeviceNow = () =>
          _serverNow.add(const Duration(milliseconds: 1));
      expect(sale.live, isFalse);
      ShopClock.reset();
    });

    test('ShopCart: expectedPriceTzs only while the server checks prices', () {
      ShopClock.debugDeviceNow = () => _serverNow;
      final cart = ShopCart()
        ..add(ShopProduct.fromJson(_p('p1', 'Whey', sale: _sale('p1'))))
        ..add(ShopProduct.fromJson(_p('p2', 'Mat', flagOn: false)));
      expect(cart.toOrderItems(), [
        {'productId': 'p1', 'qty': 1, 'expectedPriceTzs': 69000},
        {'productId': 'p2', 'qty': 1},
      ]);
      expect(cart.totalTzs, 69000 + 85000);
      cart.confirmPrice('p1', 85000);
      expect(cart.toOrderItems().first['expectedPriceTzs'], 85000);
      // A sale that ended: the regular price, and the line is flagged.
      ShopClock.debugDeviceNow = () => _serverNow.add(const Duration(hours: 3));
      final later = ShopCart()
        ..add(ShopProduct.fromJson(_p('p1', 'Whey', sale: _sale('p1'))));
      expect(later.unitPriceOf('p1'), 85000);
      expect(later.saleEndedProducts.map((p) => p.id), ['p1']);
      ShopClock.reset();
    });

    test('ShopPriceChange.fromError reads lines, totals and old shapes', () {
      final full = ShopPriceChange.fromError(
        ApiException(409, _priceChanged()),
      )!;
      expect(full.lines.single.reason, 'sale_ended');
      expect(full.lines.single.reasonKey, 'shop.priceChanged.saleEnded');
      expect(full.expectedTotalTzs, 69000);
      expect(full.totalTzs, 85000);
      final started = ShopPriceChange.fromError(
        ApiException(409, _priceChanged(reason: 'sale_started')),
      )!;
      expect(started.lines.single.reasonKey, 'shop.priceChanged.saleStarted');
      // Only the first line (older clients' fields).
      final first = ShopPriceChange.fromError(
        ApiException(409, {
          'error': 'price_changed',
          'productId': 'p1',
          'currentPriceTzs': 85000,
        }),
      )!;
      expect(first.lines.single.currentPriceTzs, 85000);
      expect(first.lines.single.reasonKey, 'shop.priceChanged.changed');
      // A bare code (old backend): no sheet, the plain message instead.
      expect(
        ShopPriceChange.fromError(
          ApiException(409, {'error': 'price_changed'}),
        ),
        isNull,
      );
      expect(
        ShopPriceChange.fromError(ApiException(409, {'error': 'other'})),
        isNull,
      );
    });
  });
}
