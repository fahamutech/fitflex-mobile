// Shop home V2 (Phase 1): lib/shared/widgets/shop_home/ inside the shared
// shop screen (lib/shared/widgets/shop_browse_page.dart).
//
// The backend (GET /shop/home, POST /shop/events) is mocked at the HTTP level
// with test/support/recording_api.dart, as the rest of the shop tests do.
// The SHOP_HOME_V2 build flag is switched with debugShopHomeV2Override.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/formatters.dart';
import 'package:fitflexmobile/shared/shop_home.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';

import 'support/recording_api.dart';

Map<String, dynamic> _p(
  String id,
  String name, {
  String category = 'equipment',
  num price = 10000,
  num? discount,
  int stock = 10,
  num rating = 0,
  int reviews = 0,
}) => {
  'id': id,
  'vendorId': 'v1',
  'name': name,
  'category': category,
  'priceTzs': price,
  'discountPriceTzs': discount,
  'stock': stock,
  'rating': rating,
  'reviewCount': reviews,
  'soldCount': 0,
  'deliveryAvailable': true,
};

final _whey = _p(
  'p1',
  'Whey Protein',
  category: 'supplements_nutrition',
  price: 85000,
  rating: 4.6,
  reviews: 23,
);
final _mat = _p('p2', 'Yoga Mat', price: 30000, discount: 24000);
final _bell = _p('p3', 'Kettlebell', price: 45000, stock: 0);
final _shoes = _p(
  'p4',
  'Running Shoes',
  category: 'sportswear_footwear',
  price: 120000,
  rating: 3.0,
);

Map<String, dynamic> _section(
  String key,
  String en,
  String sw,
  List<String> ids, {
  Map<String, dynamic>? reason,
  Map<String, dynamic> query = const {},
}) => {
  'key': key,
  'title': {'en': en, 'sw': sw},
  'reason': ?reason,
  'viewAll': {'query': query},
  'productIds': ids,
};

Map<String, dynamic> _home({
  List<Map<String, dynamic>>? sections,
  Map<String, dynamic>? products,
  String mode = 'member',
  bool personalised = false,
}) => {
  'serverNow': '2026-10-19T08:00:00Z',
  'currency': 'TZS',
  'mode': mode,
  'personalised': personalised,
  'signalsUsed': <String>[],
  'categories': [
    {
      'key': 'sportswear_footwear',
      'en': 'Sportswear & footwear',
      'sw': 'Mavazi na viatu vya michezo',
    },
    {
      'key': 'supplements_nutrition',
      'en': 'Supplements & nutrition',
      'sw': 'Virutubisho na lishe',
    },
    {
      'key': 'equipment',
      'en': 'Gym & fitness equipment',
      'sw': 'Vifaa vya gym na mazoezi',
    },
    {
      'key': 'accessories_gear',
      'en': 'Accessories & gear',
      'sw': 'Vifaa vidogo na zana',
    },
    {'key': 'food_drinks', 'en': 'Food & drinks', 'sw': 'Chakula na vinywaji'},
    {
      'key': 'health_recovery',
      'en': 'Health & recovery',
      'sw': 'Afya na kupona',
    },
    {'key': 'events', 'en': 'Events & tickets', 'sw': 'Matukio na tiketi'},
    {'key': 'other', 'en': 'Other', 'sw': 'Nyingine'},
  ],
  'sections':
      sections ??
      [
        _section(
          'best_sellers',
          'Best sellers',
          'Zinazouzwa zaidi',
          ['p1', 'p3'],
          reason: {
            'en': 'The most bought on FitFlex in the last 30 days.',
            'sw':
                'Zilizonunuliwa zaidi kwenye FitFlex katika siku 30 zilizopita.',
          },
          query: {'sort': 'popularity'},
        ),
        _section(
          'deals',
          'Deals',
          'Ofa',
          ['p2'],
          query: {'promotions': 'true'},
        ),
        _section(
          'new_arrivals',
          'New arrivals',
          'Bidhaa mpya',
          ['p4'],
          query: {'category': 'sportswear_footwear'},
        ),
      ],
  'products':
      products ??
      {
        for (final p in [_whey, _mat, _bell, _shoes]) p['id']: p,
      },
};

const _member = {
  'id': 'm1',
  'userType': 'member',
  'displayName': 'Amina Juma',
  'phone': '+255700111222',
  'email': 'amina@example.com',
};

void _seed(RecordingApi api, {Object? home, List<dynamic>? products}) {
  api.on('GET /shop/products', products ?? [_whey, _mat, _bell, _shoes]);
  api.on('GET /me/shop-orders', <dynamic>[]);
  api.on('GET /gyms', <dynamic>[]);
  if (home != null) api.on('GET /shop/home', home);
}

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  ShopHomeMode mode = ShopHomeMode.member,
  String lang = 'en',
  double scale = 1,
  Size size = const Size(420, 900),
  bool keepRequests = true,
}) => pumpPage(
  tester,
  api,
  ShopBrowseBody(mode: mode),
  user: _member,
  lang: lang,
  textScale: scale,
  size: size,
  keepRequests: keepRequests,
);

Finder _key(String k) => find.byKey(Key(k));

List<Map<String, dynamic>> _events(RecordingApi api) => api
    .where('POST', '/shop/events')
    .map((r) => Map<String, dynamic>.from(r.body as Map))
    .toList();

/// Places the order from an open cart with the existing checkout sheet and
/// returns the body the server received.
Future<Object?> _placeOrder(WidgetTester tester, RecordingApi api) async {
  expect(_key('shop-place-order'), findsOneWidget);
  await typeInto(tester, _key('shop-delivery-address'), 'Masaki');
  await tapVisible(tester, _key('shop-place-order'));
  return api.only('POST', '/me/shop-orders').body;
}

const _orderBody = {
  'items': [
    {'productId': 'p1', 'qty': 1},
  ],
  'deliveryMethod': 'home_delivery',
  'deliveryAddress': 'Masaki',
  'paymentMethod': 'mpesa',
  'paymentOutcome': 'success',
};

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    debugShopHomeV2Override = true;
    ShopEvents.reset();
  });
  tearDown(() => debugShopHomeV2Override = null);

  group('sections', () {
    apiTest('render in the server order, with the role sent as mode', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      await _pump(tester, api);
      expect(_key('shop-home'), findsOneWidget);
      final request = api.only('GET', '/shop/home');
      expect(request.query, 'mode=member');
      expect(verticalOrder(tester, ['New arrivals', 'Best sellers', 'Deals']), [
        'Best sellers',
        'Deals',
        'New arrivals',
      ]);
      // The old list is not shown on the home.
      expect(_key('shop-product-p1'), findsNothing);
    });

    for (final mode in [ShopHomeMode.trainer, ShopHomeMode.owner]) {
      apiTest('the ${mode.wire} shop asks for mode=${mode.wire}', (
        tester,
        api,
      ) async {
        _seed(api, home: _home(mode: mode.wire));
        await _pump(tester, api, mode: mode);
        expect(api.only('GET', '/shop/home').query, 'mode=${mode.wire}');
        expect(_key('shop-home-section-best_sellers'), findsOneWidget);
      });
    }

    apiTest('a section key the app has never seen renders the same way', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: _home(
          sections: [
            _section(
              'popular_near_you',
              'Popular near you',
              'Maarufu karibu nawe',
              ['p1'],
            ),
            _section('phase_two_thing', 'Something new', 'Kitu kipya', ['p2']),
          ],
        ),
      );
      await _pump(tester, api);
      expect(find.text('Popular near you'), findsOneWidget);
      expect(find.text('Something new'), findsOneWidget);
      expect(_key('shop-home-card-p2'), findsOneWidget);
    });

    apiTest('cold start (no profile, not personalised) still shows the home', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: _home(
          personalised: false,
          sections: [
            _section('best_sellers', 'Best sellers', 'Zinazouzwa zaidi', [
              'p1',
              'p2',
            ]),
          ],
        ),
      );
      await _pump(tester, api);
      // Nothing viewed yet on this device: no `recent` sent.
      expect(api.only('GET', '/shop/home').query, isNot(contains('recent')));
      expect(_key('shop-home-card-p1'), findsOneWidget);
      expect(_key('shop-home-categories'), findsOneWidget);
    });

    apiTest('empty sections and ids without a product are hidden', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: _home(
          sections: [
            _section('featured', 'Featured', 'Zilizoangaziwa', []),
            _section('recently_viewed', 'Recently viewed', 'Ulizotazama', [
              'gone',
            ]),
            _section('essentials', 'Essentials', 'Muhimu', ['p1']),
          ],
        ),
      );
      await _pump(tester, api);
      expect(find.text('Featured'), findsNothing);
      expect(find.text('Recently viewed'), findsNothing);
      expect(find.text('Essentials'), findsOneWidget);
    });

    apiTest('no products at all: the shop-is-getting-ready state', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: _home(sections: [], products: {}),
      );
      final host = await _pump(tester, api);
      expect(_key('shop-home-empty'), findsOneWidget);
      expect(find.text(host.tr('shop.home.emptyTitle')), findsOneWidget);
      expect(_key('shop-home-categories'), findsNothing);
    });

    apiTest('Why am I seeing this? shows only the server reason', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      await _pump(tester, api);
      // Only sections with a reason get the button.
      expect(_key('shop-home-why-deals'), findsNothing);
      await tapVisible(tester, _key('shop-home-why-best_sellers'));
      expect(_key('shop-why-best_sellers'), findsOneWidget);
      expect(
        find.text('The most bought on FitFlex in the last 30 days.'),
        findsOneWidget,
      );
      // Personalisation is Phase 2: no switch, no settings link.
      expect(find.byType(Switch), findsNothing);
    });
  });

  group('product card', () {
    apiTest('out of stock: badge, no cart button', (tester, api) async {
      _seed(api, home: _home());
      await _pump(tester, api);
      expect(_key('shop-home-oos-p3'), findsOneWidget);
      expect(_key('shop-home-add-p3'), findsNothing);
      expect(_key('shop-home-add-p1'), findsOneWidget);
    });

    apiTest('rating only with real reviews (never "0.0")', (tester, api) async {
      _seed(api, home: _home());
      await _pump(tester, api);
      expect(_key('shop-home-rating-p1'), findsOneWidget);
      expect(find.text('4.6 (23)'), findsOneWidget);
      // p4 has a rating number but no reviews; p2 has neither.
      expect(_key('shop-home-rating-p4'), findsNothing);
      expect(_key('shop-home-rating-p2'), findsNothing);
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.textContaining('3.0'), findsNothing);
    });

    apiTest(
      'discount: Fuel badge (rounded down), sale price, struck original',
      (tester, api) async {
        _seed(api, home: _home());
        await _pump(tester, api);
        expect(find.text('−20%'), findsOneWidget);
        expect(
          tester.widget<Text>(_key('shop-home-sale-p2')).data,
          formatCurrency(24000),
        );
        final was = tester.widget<Text>(_key('shop-home-was-p2'));
        expect(was.data, formatCurrency(30000));
        expect(was.style?.decoration, TextDecoration.lineThrough);
        // Not on sale: no badge and no struck price.
        expect(_key('shop-home-discount-p1'), findsNothing);
        expect(_key('shop-home-was-p1'), findsNothing);
      },
    );

    apiTest('screen readers hear name, price, "was" and rating', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      await _pump(tester, api);
      final handle = tester.ensureSemantics();
      final sale = tester.getSemantics(_key('shop-home-card-p2'));
      expect(sale.label, contains('Yoga Mat'));
      expect(sale.label, contains('was ${formatCurrency(30000)}'));
      expect(sale.label, contains('20 percent off'));
      final rated = tester.getSemantics(_key('shop-home-card-p1'));
      expect(rated.label, contains('Rated 4.6 out of 5 from 23 reviews'));
      final unrated = tester.getSemantics(_key('shop-home-card-p4'));
      expect(unrated.label, isNot(contains('Rated')));
      final cart = tester.getSemantics(_key('shop-home-add-p1'));
      expect(cart.label, 'Add Whey Protein to cart');
      // 48dp target for the cart button.
      expect(tester.getSize(_key('shop-home-add-p1')), const Size(48, 48));
      handle.dispose();
    });
  });

  group('commerce is unchanged', () {
    apiTest(
      'flag on: add from a card -> same cart -> same checkout and order',
      (tester, api) async {
        _seed(api, home: _home());
        final host = await _pump(tester, api);
        await tapVisible(tester, _key('shop-home-add-p1'));
        expect(host.snack(host.tr('shop.home.added')), findsOneWidget);
        await host.dismissSnacks();
        // The button now shows the quantity in the cart.
        expect(
          tester.getSemantics(_key('shop-home-add-p1')).label,
          'Whey Protein, 1 in cart. Add one more',
        );
        final checkout = tester.widget(_key('shop-home-checkout'));
        expect(checkout, isNotNull);
        expect(
          find.descendant(
            of: _key('shop-home-checkout'),
            matching: find.textContaining(formatCurrency(85000)),
          ),
          findsOneWidget,
        );
        await tapVisible(tester, _key('shop-home-checkout'));
        expect(await _placeOrder(tester, api), _orderBody);
        // Order history is the existing My orders view.
        expect(find.text(host.tr('shop.orderPending')), findsWidgets);
        expect(api.sent('GET', '/me/shop-orders'), isTrue);
      },
    );

    apiTest('flag off: the same journey on the old list sends the same order', (
      tester,
      api,
    ) async {
      debugShopHomeV2Override = false;
      _seed(api, home: _home());
      await _pump(tester, api);
      expect(api.sent('GET', '/shop/home'), isFalse);
      expect(_key('shop-home'), findsNothing);
      expect(_key('shop-back-to-home'), findsNothing);
      await tapVisible(tester, _key('shop-add-p1'));
      await tapVisible(tester, _key('shop-checkout'));
      expect(await _placeOrder(tester, api), _orderBody);
      // No shop events while the flag is off.
      expect(api.sent('POST', '/shop/events'), isFalse);
    });

    apiTest('the header cart opens the existing checkout', (tester, api) async {
      _seed(api, home: _home());
      final host = await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-cart'));
      expect(host.snack(host.tr('shop.home.cartEmpty')), findsOneWidget);
      await host.dismissSnacks();
      await tapVisible(tester, _key('shop-home-add-p1'));
      await host.dismissSnacks();
      await tapVisible(tester, _key('shop-home-cart'));
      expect(_key('shop-place-order'), findsOneWidget);
    });

    apiTest('My orders still lists orders with the home on', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      api.on('GET /me/shop-orders', [
        {
          'id': 'o1',
          'status': 'accepted',
          'paymentStatus': 'paid',
          'canCancel': true,
          'totalTzs': 85000,
          'items': [
            {'productId': 'p1', 'qty': 1, 'name': 'Whey Protein'},
          ],
          'timeline': [
            {'status': 'placed'},
          ],
        },
      ]);
      final host = await _pump(tester, api);
      await tester.tap(find.text(host.tr('shop.myOrders')));
      await tester.pumpAndSettle();
      expect(find.text('${host.tr('shop.order')} o1'), findsOneWidget);
      expect(_key('order-cancel-o1'), findsOneWidget);
      expect(_key('shop-reorder-o1'), findsOneWidget);
    });

    apiTest('vendor tools are untouched with the flag on', (tester, api) async {
      api.on('GET /vendor/products', [
        {
          'id': 'vp1',
          'name': 'Vendor Whey',
          'priceTzs': 85000,
          'stock': 4,
          'status': 'active',
        },
      ]);
      api.on('GET /vendor/orders', <dynamic>[]);
      api.on('GET /vendor/profile', {
        'businessName': 'Store',
        'status': 'published',
      });
      api.on('GET /vendor/payments', <String, dynamic>{});
      api.on('GET /vendor/enquiries', <dynamic>[]);
      api.on('GET /vendor/staff', <dynamic>[]);
      await pumpPage(
        tester,
        api,
        const VendorHomePage(),
        user: const {'id': 'v1', 'userType': 'vendor'},
        keepRequests: true,
      );
      expect(api.sent('GET', '/vendor/products'), isTrue);
      expect(api.sent('GET', '/shop/home'), isFalse);
      expect(api.sent('POST', '/shop/events'), isFalse);
      expect(_key('shop-home'), findsNothing);
      expect(find.byKey(const Key('vendor-product-vp1')), findsOneWidget);
    });
  });

  group('fallback', () {
    for (final (status, error) in [
      (404, 'feature_disabled'),
      (403, 'mode_not_allowed'),
    ]) {
      apiTest('$status $error falls back to today\'s shop', (
        tester,
        api,
      ) async {
        _seed(api);
        api.fail('GET /shop/home', status, {'error': error});
        await _pump(tester, api);
        expect(_key('shop-home'), findsNothing);
        expect(_key('shop-search'), findsOneWidget);
        expect(_key('shop-product-p1'), findsOneWidget);
        // Nothing to go "back" to.
        expect(_key('shop-back-to-home'), findsNothing);
      });
    }

    apiTest('a server error shows an error with Try again', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('GET /shop/home', 500);
      final host = await _pump(tester, api);
      expect(_key('shop-home-error'), findsOneWidget);
      expect(find.text(host.tr('shop.home.errorTitle')), findsOneWidget);
      api.heal('GET /shop/home');
      api.on('GET /shop/home', _home());
      await tapVisible(tester, find.text(host.tr('common.retry')));
      expect(_key('shop-home-section-best_sellers'), findsOneWidget);
    });
  });

  group('navigation', () {
    apiTest('View all opens the list with the section filters, Back returns', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-viewall-new_arrivals'));
      expect(_key('shop-home'), findsNothing);
      expect(_key('shop-product-p4'), findsOneWidget);
      expect(_key('shop-product-p1'), findsNothing);
      await tapVisible(tester, _key('shop-back-to-home'));
      expect(_key('shop-home'), findsOneWidget);
    });

    apiTest('a category tile opens that category; any role can browse all', (
      tester,
      api,
    ) async {
      _seed(api, home: _home(mode: 'owner'));
      await _pump(tester, api, mode: ShopHomeMode.owner);
      for (final key in [
        'sportswear_footwear',
        'supplements_nutrition',
        'equipment',
        'accessories_gear',
        'food_drinks',
        'health_recovery',
        'events',
        'other',
      ]) {
        expect(_key('shop-home-category-$key'), findsOneWidget);
      }
      await tapVisible(
        tester,
        _key('shop-home-category-supplements_nutrition'),
      );
      expect(_key('shop-product-p1'), findsOneWidget);
      expect(_key('shop-product-p2'), findsNothing);
    });

    apiTest('search goes to the list with the text kept', (tester, api) async {
      _seed(api, home: _home());
      await _pump(tester, api);
      await tester.enterText(_key('shop-home-search'), 'kettle');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(textOf(tester, _key('shop-search')), 'kettle');
      expect(_key('shop-product-p3'), findsOneWidget);
      expect(_key('shop-product-p1'), findsNothing);
    });

    apiTest('opening a product remembers it and sends it as recent', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      final host = await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-card-p4'));
      expect(_key('shop-detail-add-p4'), findsOneWidget);
      await tester.tap(_key('shop-product-close'));
      await tester.pumpAndSettle();
      expect(await RecentlyViewedProducts.load('m1'), ['p4']);
      // The next home load (leaving for My orders and coming back) sends it.
      api.clear();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.tap(find.text(host.tr('shop.myOrders')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(host.tr('shop.browse')));
      await tester.pumpAndSettle();
      expect(api.only('GET', '/shop/home').query, contains('recent=p4'));
    });
  });

  test('recently viewed keeps the newest 20, without repeats', () async {
    SharedPreferences.setMockInitialValues({});
    for (var i = 0; i < 25; i++) {
      await RecentlyViewedProducts.add('u1', 'p$i');
    }
    await RecentlyViewedProducts.add('u1', 'p10');
    final list = await RecentlyViewedProducts.load('u1');
    expect(list, hasLength(20));
    expect(list.first, 'p10');
    expect(list.where((id) => id == 'p10'), hasLength(1));
    // Another account on the same device has its own list.
    expect(await RecentlyViewedProducts.load('u2'), isEmpty);
  });

  group('states', () {
    apiTest('skeleton while loading, announced once', (tester, api) async {
      _seed(api, home: _home());
      final gate = api.hold('GET /shop/home');
      await pumpPage(
        tester,
        api,
        const ShopBrowseBody(),
        user: _member,
        size: const Size(420, 900),
        settle: false,
      );
      await tester.pump();
      await tester.pump();
      expect(_key('shop-home-loading'), findsOneWidget);
      expect(spinner, findsNothing);
      gate.complete();
      await tester.pumpAndSettle();
      expect(_key('shop-home-loading'), findsNothing);
    });

    apiTest('offline: "You\'re offline" with Try again on the home', (
      tester,
      api,
    ) async {
      _seed(api);
      api.onCall(
        'GET /shop/home',
        (_) => throw http.ClientException('XMLHttpRequest error.'),
      );
      final host = await _pump(tester, api);
      expect(_key('shop-home-offline'), findsOneWidget);
      expect(find.text(host.tr('shop.home.offlineTitle')), findsOneWidget);
      expect(find.text(host.tr('shop.noProducts')), findsNothing);
    });

    apiTest('offline on the old list (flag off) no longer says "no products"', (
      tester,
      api,
    ) async {
      debugShopHomeV2Override = false;
      _seed(api);
      api.onCall(
        'GET /shop/products',
        (_) => throw http.ClientException('XMLHttpRequest error.'),
      );
      final host = await _pump(tester, api);
      expect(_key('shop-offline'), findsOneWidget);
      expect(find.text(host.tr('shop.home.offlineTitle')), findsOneWidget);
      expect(find.text(host.tr('shop.noProducts')), findsNothing);
    });
  });

  group('language and size', () {
    apiTest('Swahili: server titles and short category labels', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      final host = await _pump(tester, api, lang: 'sw');
      expect(find.text('Zinazouzwa zaidi'), findsOneWidget);
      expect(find.text('Best sellers'), findsNothing);
      expect(find.text('Virutubisho'), findsOneWidget);
      expect(find.text(host.tr('shop.home.categories')), findsOneWidget);
      expect(find.text('Ona zote'), findsWidgets);
      expect(host.tr('shop.home.viewAll'), isNot('View all'));
    });

    for (final lang in ['en', 'sw']) {
      apiTest('200% text on a 360px phone ($lang): no overflow', (
        tester,
        api,
      ) async {
        _seed(api, home: _home());
        final errors = await captureFlutterErrors(() async {
          await _pump(
            tester,
            api,
            lang: lang,
            scale: 2,
            size: const Size(360, 740),
          );
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -600),
          );
          await tester.pumpAndSettle();
        });
        expect(errors.where((e) => e.contains('overflowed')), isEmpty);
      });
    }

    apiTest('old list Featured strip grows with text (image not squeezed)', (
      tester,
      api,
    ) async {
      debugShopHomeV2Override = false;
      final promoted = {
        ..._whey,
        'promotion': {'id': 'pr1', 'type': 'featured', 'label': 'Featured'},
      };
      _seed(api, products: [promoted]);
      api.on('GET /discover/products', {
        'featured': [promoted],
        'items': [promoted],
        'total': 1,
        'placement': 'shop',
      });
      // The sort dropdown above already overflows at 200% on
      // release-candidate; that is not what this test is about.
      await captureFlutterErrors(() async {
        await _pump(tester, api, scale: 2, size: const Size(360, 740));
      });
      expect(_key('shop-featured-p1'), findsOneWidget);
      // With the old fixed 210px strip the photo was squeezed to 22px here.
      final image = find.descendant(
        of: _key('shop-featured-p1'),
        matching: find.byType(Expanded),
      );
      expect(tester.getSize(image.first).height, greaterThanOrEqualTo(80));
    });
  });

  group('events', () {
    apiTest('carry only type, section, productId, position and mode', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      final host = await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-add-p1'));
      await host.dismissSnacks();
      await tapVisible(tester, _key('shop-home-card-p2'));
      await tester.tap(_key('shop-product-close'));
      await tester.pumpAndSettle();
      await tester.enterText(_key('shop-home-search'), 'secret whey search');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      final events = _events(api);
      final types = events.map((e) => e['type']).toSet();
      expect(
        types,
        containsAll([
          'shop_home_viewed',
          'section_viewed',
          'product_impression',
          'add_to_cart',
          'product_clicked',
          'search_submitted',
        ]),
      );
      for (final e in events) {
        expect(
          ShopEvents.allowedFields.containsAll(e.keys),
          isTrue,
          reason: '$e',
        );
        expect(e['mode'], 'member');
        final text = jsonEncode(e);
        for (final pii in [
          'secret whey search',
          'Amina',
          '+255700111222',
          'amina@example.com',
          'm1',
        ]) {
          expect(text, isNot(contains(pii)), reason: text);
        }
      }
      final add = events.firstWhere((e) => e['type'] == 'add_to_cart');
      expect(add, {
        'type': 'add_to_cart',
        'mode': 'member',
        'section': 'best_sellers',
        'productId': 'p1',
        'position': 0,
      });
      // Impressions are counted once per load.
      final p1 = events.where(
        (e) => e['type'] == 'product_impression' && e['productId'] == 'p1',
      );
      expect(p1, hasLength(1));
    });

    apiTest('a 404 from /shop/events is tolerated and stops sending', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      api.fail('POST /shop/events', 404, {'error': 'not_found'});
      final host = await _pump(tester, api);
      final before = api.where('POST', '/shop/events').length;
      expect(before, greaterThan(0));
      await tapVisible(tester, _key('shop-home-add-p1'));
      expect(host.snack(host.tr('shop.home.added')), findsOneWidget);
      expect(api.where('POST', '/shop/events').length, before);
    });
  });
}
