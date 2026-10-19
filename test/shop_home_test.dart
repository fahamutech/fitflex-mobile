// Shop home V2 (Phase 1): lib/shared/widgets/shop_home/ inside the shared
// shop screen (lib/shared/widgets/shop_browse_page.dart).
//
// The backend (GET /shop/home, POST /shop/events) is mocked at the HTTP level
// with test/support/recording_api.dart, as the rest of the shop tests do.
// The SHOP_HOME_V2 build flag is switched with debugShopHomeV2Override.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/promotion.dart';
import 'package:fitflexmobile/shared/promotion_events.dart';
import 'package:fitflexmobile/shared/root_back_navigation.dart';
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
  String? routePath,
  String initialLocation = '/',
}) => pumpPage(
  tester,
  api,
  ShopBrowseBody(mode: mode, routePath: routePath),
  user: _member,
  lang: lang,
  textScale: scale,
  size: size,
  keepRequests: keepRequests,
  initialLocation: initialLocation,
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
  tearDown(() {
    debugShopHomeV2Override = null;
    debugShopEventsOverride = null;
  });

  group('sections', () {
    apiTest('render in the server order, with the role sent as mode', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      await _pump(tester, api);
      expect(_key('shop-home'), findsOneWidget);
      final request = api.only('GET', '/shop/home');
      final query = Uri.splitQueryString(request.query);
      expect(query['mode'], 'member');
      // The promotion session, so Featured cards come back with tokens.
      expect(query['session'], matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
      // Phase 1 sends no location.
      expect(query.keys, isNot(contains('region')));
      expect(query.keys, isNot(contains('city')));
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
        expect(
          Uri.splitQueryString(api.only('GET', '/shop/home').query)['mode'],
          mode.wire,
        );
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
        home: {
          ..._home(sections: [], products: {}),
          'allProductsCount': 0,
        },
      );
      final host = await _pump(tester, api);
      // The count says there is nothing: no product list is fetched.
      expect(api.sent('GET', '/shop/products'), isFalse);
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

    apiTest('a 500 falls back to today\'s shop (AC-02), not an error', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('GET /shop/home', 500);
      await _pump(tester, api);
      expect(_key('shop-home'), findsNothing);
      expect(_key('shop-home-error'), findsNothing);
      expect(_key('shop-product-p1'), findsOneWidget);
    });

    apiTest('a 400 still shows an error with Try again', (tester, api) async {
      _seed(api);
      api.fail('GET /shop/home', 400, {'error': 'invalid_query'});
      final host = await _pump(tester, api);
      expect(_key('shop-home-error'), findsOneWidget);
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
      expect(find.text('Tazama zote'), findsWidgets);
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
    apiTest('nothing is sent while SHOP_EVENTS is off (the default)', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      final host = await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-add-p1'));
      expect(host.snack(host.tr('shop.home.added')), findsOneWidget);
      expect(api.sent('POST', '/shop/events'), isFalse);
    });

    apiTest('carry only type, section, productId, position and mode', (
      tester,
      api,
    ) async {
      debugShopEventsOverride = true;
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

    apiTest('an HTML 404 from /shop/events is tolerated and stops sending', (
      tester,
      api,
    ) async {
      debugShopEventsOverride = true;
      _seed(api, home: _home());
      api.onCall(
        'POST /shop/events',
        (_) => const RawResponse(404, '<!DOCTYPE html><h1>Not Found</h1>'),
      );
      final host = await _pump(tester, api);
      final before = api.where('POST', '/shop/events').length;
      expect(before, greaterThan(0));
      await tapVisible(tester, _key('shop-home-add-p1'));
      expect(host.snack(host.tr('shop.home.added')), findsOneWidget);
      expect(api.where('POST', '/shop/events').length, before);
    });
  });

  group('review fixes', () {
    apiTest('an HTML 404 from /shop/home falls back to today\'s shop', (
      tester,
      api,
    ) async {
      _seed(api);
      api.onCall(
        'GET /shop/home',
        (_) => const RawResponse(
          404,
          '<!DOCTYPE html><html><body>Cannot GET /shop/home</body></html>',
        ),
      );
      await _pump(tester, api);
      expect(_key('shop-home'), findsNothing);
      expect(_key('shop-product-p1'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    apiTest('403 mode_not_allowed: retried once without mode', (
      tester,
      api,
    ) async {
      _seed(api);
      api.onCall(
        'GET /shop/home',
        (r) => Uri.splitQueryString(r.query).containsKey('mode')
            ? const RawResponse(403, '{"error":"mode_not_allowed"}')
            : _home(),
      );
      await _pump(tester, api, mode: ShopHomeMode.owner);
      final calls = api.where('GET', '/shop/home');
      expect(calls, hasLength(2));
      expect(Uri.splitQueryString(calls[0].query)['mode'], 'owner');
      expect(Uri.splitQueryString(calls[1].query).containsKey('mode'), isFalse);
      expect(_key('shop-home-section-best_sellers'), findsOneWidget);
    });

    apiTest(
      'promotion impressions and clicks carry the token and marketplace',
      (tester, api) async {
        final sent = <Map<String, dynamic>>[];
        PromotionEvents.install(
          ApiClient(baseUrl: 'http://fixtures.local'),
          enabled: true,
          sender: (events) async {
            sent.addAll(events);
            return {'accepted': events.length};
          },
          flushAt: 1000,
        );
        addTearDown(PromotionEvents.reset);
        final promoted = {
          ..._whey,
          'promotion': {
            'id': 'pr1',
            'type': 'featured',
            'label': 'Featured',
            'token': 'tok_abc123',
          },
        };
        _seed(
          api,
          home: _home(
            sections: [
              _section('featured', 'Featured', 'Zilizoangaziwa', ['p1']),
            ],
            products: {'p1': promoted},
          ),
        );
        await _pump(tester, api);
        await tapVisible(tester, _key('shop-home-card-p1'));
        await tester.tap(_key('shop-product-close'));
        await tester.pumpAndSettle();
        await PromotionEvents.instance.flush();
        final types = sent.map((e) => e['type']).toSet();
        expect(types, containsAll(['impression', 'click']));
        for (final e in sent.where(
          (e) => e['type'] == 'impression' || e['type'] == 'click',
        )) {
          expect(e['token'], 'tok_abc123');
          expect(e['placement'], 'marketplace');
          expect(e['entityId'], 'p1');
        }
      },
    );

    apiTest('View all: hidden with no query and no more; never for recent', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: _home(
          sections: [
            _section('essentials', 'Essentials', 'Bidhaa muhimu', ['p1']),
            {
              ..._section('new_arrivals', 'New arrivals', 'Bidhaa mpya', [
                'p2',
              ]),
              'hasMore': true,
            },
            _section(
              'recently_viewed',
              'Recently viewed',
              'Ulizotazama',
              ['p4'],
              query: {'ids': 'p4'},
            ),
          ],
        ),
      );
      await _pump(tester, api);
      expect(_key('shop-home-viewall-essentials'), findsNothing);
      expect(_key('shop-home-viewall-new_arrivals'), findsOneWidget);
      expect(_key('shop-home-viewall-recently_viewed'), findsNothing);
    });

    apiTest('Deals View all matches the server: 0 < sale price < price', (
      tester,
      api,
    ) async {
      final zero = _p('p5', 'Zero Sale Band', price: 20000, discount: 0);
      final notLower = _p(
        'p6',
        'Same Price Rope',
        price: 15000,
        discount: 15000,
      );
      _seed(
        api,
        home: _home(),
        products: [_whey, _mat, _bell, _shoes, zero, notLower],
      );
      await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-viewall-deals'));
      expect(_key('shop-product-p2'), findsOneWidget);
      expect(_key('shop-product-p5'), findsNothing);
      expect(_key('shop-product-p6'), findsNothing);
      expect(_key('shop-product-p1'), findsNothing);
    });

    apiTest('no server title: the app\'s own section title (en + sw)', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: _home(
          sections: [
            {
              'key': 'best_sellers',
              'productIds': ['p1'],
            },
            {
              'key': 'something_new',
              'productIds': ['p2'],
            },
          ],
        ),
      );
      final host = await _pump(tester, api, lang: 'sw');
      expect(find.text(host.tr('shop.section.best_sellers')), findsOneWidget);
      expect(host.tr('shop.section.best_sellers'), 'Zinazouzwa zaidi');
      expect(
        tester.widget<Text>(_key('shop-home-title-something_new')).data,
        host.tr('shop.section.generic'),
      );
      expect(find.text('best_sellers'), findsNothing);
    });

    apiTest('no server category name: the app\'s own label for the key', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: {
          ..._home(),
          'categories': [
            {'key': 'equipment'},
          ],
        },
      );
      await _pump(tester, api, lang: 'sw');
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(_key('shop-home-category-equipment')).label,
        'Aina: Vifaa vya gym na mazoezi',
      );
      handle.dispose();
    });

    apiTest('singular: "Only 1 left" and "Cart, 1 item"', (tester, api) async {
      final one = _p('p7', 'Last Bottle', price: 5000, stock: 1);
      _seed(
        api,
        home: _home(
          sections: [
            _section('essentials', 'Essentials', 'Bidhaa muhimu', ['p7']),
          ],
          products: {'p7': one},
        ),
      );
      final host = await _pump(tester, api);
      expect(find.text('Only 1 left'), findsOneWidget);
      await tapVisible(tester, _key('shop-home-add-p7'));
      await host.dismissSnacks();
      expect(
        tester.widget<IconButton>(_key('shop-home-cart')).tooltip,
        'Cart, 1 item',
      );
      expect(
        (FFLocale()..set(const Locale('sw'))).t('shop.home.onlyLeftOne'),
        'Imebaki 1 tu',
      );
    });

    apiTest('list rows use one "{n} in stock" line ("Zipo {n}")', (
      tester,
      api,
    ) async {
      debugShopHomeV2Override = false;
      _seed(api);
      await _pump(tester, api, lang: 'sw');
      expect(find.text('Zipo 10'), findsWidgets);
    });
  });
  qaRound1();
  qaRound1b();
}

String _location(WidgetTester tester) => GoRouter.of(
  tester.element(find.byType(ShopBrowseBody)),
).routerDelegate.currentConfiguration.uri.toString();

/// Records SystemNavigator.pop (the app closing on Android Back).
List<String> _recordSystemPop(WidgetTester tester) {
  final calls = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'SystemNavigator.pop') calls.add(call.method);
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return calls;
}

Map<String, dynamic> _many(int n) => _home(
  sections: [
    _section(
      'best_sellers',
      'Best sellers',
      'Zinazouzwa zaidi',
      [for (var i = 0; i < n; i++) 'm$i'],
      reason: {'en': 'Why', 'sw': 'Kwa nini'},
      query: {'sort': 'popularity'},
    ),
  ],
  products: {
    for (var i = 0; i < n; i++) 'm$i': _p('m$i', 'Item $i', price: 1000 + i),
  },
);

void qaRound1() {
  group('QA round 1', () {
    // 1 — small catalogue.
    apiTest('no sections: categories + an All products grid from the list', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: _home(sections: [], products: {}),
      );
      final host = await _pump(tester, api);
      expect(api.sent('GET', '/shop/products'), isTrue);
      expect(_key('shop-home-categories'), findsOneWidget);
      expect(find.text(host.tr('shop.home.allProducts')), findsOneWidget);
      expect(_key('shop-home-grid'), findsOneWidget);
      expect(_key('shop-home-card-p1'), findsOneWidget);
      expect(_key('shop-home-empty'), findsNothing);
    });

    apiTest('no sections, allProductsCount 3: the grid too', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: {
          ..._home(sections: [], products: {}),
          'allProductsCount': 3,
        },
      );
      await _pump(tester, api);
      expect(_key('shop-home-grid'), findsOneWidget);
    });

    apiTest('no sections and an empty list: getting ready', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: _home(sections: [], products: {}),
        products: [],
      );
      await _pump(tester, api);
      expect(_key('shop-home-empty'), findsOneWidget);
    });

    // 17 — no background catalogue on the home.
    apiTest('the home does not fetch the product list or discovery', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      await _pump(tester, api);
      expect(api.sent('GET', '/shop/products'), isFalse);
      expect(api.sent('GET', '/discover/products'), isFalse);
      expect(api.sent('GET', '/me/shop-orders'), isTrue);
      await tapVisible(tester, _key('shop-home-viewall-deals'));
      expect(api.sent('GET', '/shop/products'), isTrue);
    });

    // 2 — URL and Back.
    apiTest('View all / category / product are kept in the URL', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      await _pump(tester, api, routePath: '/');
      await tapVisible(
        tester,
        _key('shop-home-category-supplements_nutrition'),
      );
      expect(
        _location(tester),
        '/?view=results&category=supplements_nutrition',
      );
      await tapVisible(tester, find.text('Whey Protein'));
      expect(_location(tester), contains('product=p1'));
      await tester.tap(_key('shop-product-close'));
      await tester.pumpAndSettle();
      expect(_location(tester), isNot(contains('product=')));
      // Browser Back to the home URL: the home is shown again.
      GoRouter.of(tester.element(find.byType(ShopBrowseBody))).go('/');
      await tester.pumpAndSettle();
      expect(_key('shop-home'), findsOneWidget);
      expect(_key('shop-back-to-home'), findsNothing);
    });

    apiTest('a refresh on a results URL restores the list and filters', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      final host = await _pump(
        tester,
        api,
        routePath: '/',
        initialLocation: '/?view=results&category=equipment&sort=price_asc',
      );
      expect(_key('shop-home'), findsNothing);
      expect(_key('shop-product-p2'), findsOneWidget);
      expect(_key('shop-product-p1'), findsNothing);
      expect(find.text(host.tr('shop.priceLow')), findsWidgets);
    });

    apiTest('a refresh with ?product= reopens that product', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      api.on('GET /shop/products/p4', _shoes);
      await _pump(tester, api, routePath: '/', initialLocation: '/?product=p4');
      expect(_key('shop-detail-add-p4'), findsOneWidget);
    });

    apiTest('a link to a removed product: home + "no longer available"', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      final host = await _pump(
        tester,
        api,
        routePath: '/',
        initialLocation: '/?product=gone',
      );
      expect(host.snack(host.tr('shop.home.productGone')), findsOneWidget);
      expect(_key('shop-home'), findsOneWidget);
      expect(_location(tester), '/');
    });

    apiTest('Android Back: list -> home, then the app may close', (
      tester,
      api,
    ) async {
      final pops = _recordSystemPop(tester);
      _seed(api, home: _home());
      await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-viewall-deals'));
      expect(_key('shop-home'), findsNothing);
      handleRootBack(didPop: false);
      await tester.pumpAndSettle();
      expect(_key('shop-home'), findsOneWidget);
      expect(pops, isEmpty);
      handleRootBack(didPop: false);
      expect(pops, ['SystemNavigator.pop']);
    });

    // 3 — disclosure in Swahili.
    testWidgets('promotion disclosure: codes in the app language', (
      tester,
    ) async {
      Future<String> label(PromotionTag tag, String lang) async {
        await tester.pumpWidget(
          FFLocaleScope(
            notifier: FFLocale()..set(Locale(lang)),
            child: MaterialApp(
              home: Scaffold(body: FFPromotionBadge(tag: tag)),
            ),
          ),
        );
        return tester.widget<Text>(find.byType(Text).first).data!;
      }

      final tag = PromotionTag.fromJson({
        'id': 'pr',
        'type': 'featured',
        'label': 'Featured · Sponsored',
        'commercial': true,
        'disclosure': {
          'codes': ['featured', 'sponsored'],
          'en': 'Featured · Sponsored',
          'sw': 'Iliyoangaziwa · Iliyodhaminiwa',
        },
      })!;
      expect(await label(tag, 'en'), 'Featured · Sponsored');
      expect(await label(tag, 'sw'), 'Iliyoangaziwa · Iliyodhaminiwa');
      // Unknown code: the server's text for the language.
      final odd = PromotionTag.fromJson({
        'id': 'pr',
        'type': 'featured',
        'label': 'Featured',
        'disclosure': {
          'codes': ['partner'],
          'en': 'Partner pick',
          'sw': 'Chaguo la mshirika',
        },
      })!;
      expect(await label(odd, 'sw'), 'Chaguo la mshirika');
      // An older server (label only): never English in Swahili, and a paid
      // placement keeps "Sponsored".
      final old = PromotionTag.fromJson({
        'id': 'pr',
        'type': 'featured',
        'label': 'Featured · Sponsored',
        'commercial': true,
      })!;
      expect(await label(old, 'sw'), 'Iliyoangaziwa · Iliyodhaminiwa');
      expect(await label(old, 'en'), 'Featured · Sponsored');

      // English keeps an admin's own wording; Swahili builds from codes.
      final custom = PromotionTag.fromJson({
        'id': 'pr',
        'type': 'featured',
        'label': 'Featured',
        'commercial': true,
        'disclosure': {
          'codes': ['sponsored', 'featured'],
          'en': 'Top pick · Sponsored',
          'sw': 'Chaguo bora · Iliyodhaminiwa',
        },
      })!;
      expect(await label(custom, 'en'), 'Top pick · Sponsored');
      // Codes in the app's words, "Iliyodhaminiwa" moved to the end.
      expect(await label(custom, 'sw'), 'Iliyoangaziwa · Iliyodhaminiwa');
      // A paid placement whose wording forgets the paid word still ends
      // with it.
      final forgot = PromotionTag.fromJson({
        'id': 'pr',
        'type': 'featured',
        'label': 'Featured',
        'commercial': true,
        'disclosure': {'en': 'Top pick'},
      })!;
      expect(await label(forgot, 'en'), 'Top pick · Sponsored');
      expect(await label(forgot, 'sw'), 'Iliyoangaziwa · Iliyodhaminiwa');
      // Not paid: nothing added.
      final organic = PromotionTag.fromJson({
        'id': 'pr',
        'type': 'recommended',
        'label': 'Recommended by FitFlex',
        'disclosure': {
          'codes': ['recommended'],
          'en': 'Recommended by FitFlex',
          'sw': 'Imependekezwa na FitFlex',
        },
      })!;
      expect(await label(organic, 'en'), 'Recommended by FitFlex');
      expect(await label(organic, 'sw'), 'Imependekezwa na FitFlex');
    });

    // 4 — timeout falls back.
    apiTest('a timeout from /shop/home falls back to today\'s shop', (
      tester,
      api,
    ) async {
      _seed(api);
      api.onCall('GET /shop/home', (_) => throw TimeoutException('slow'));
      await _pump(tester, api);
      expect(_key('shop-home'), findsNothing);
      expect(_key('shop-product-p1'), findsOneWidget);
    });

    // 5 — the cart snackbar goes away.
    apiTest('"Added to cart" dismisses itself', (tester, api) async {
      _seed(api, home: _home());
      final host = await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-add-p1'));
      expect(host.snack(host.tr('shop.home.added')), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(host.snack(host.tr('shop.home.added')), findsNothing);
    });

    // 6 — phone layout.
    apiTest('375px: 16px gutter, third card peeks, ~4.5 category tiles', (
      tester,
      api,
    ) async {
      _seed(api, home: _many(6));
      await _pump(tester, api, size: const Size(375, 812));
      expect(tester.getTopLeft(_key('shop-home-search')).dx, 16);
      expect(tester.getTopLeft(_key('shop-home-card-m0')).dx, 16);
      final third = tester.getTopLeft(_key('shop-home-card-m2')).dx;
      expect(third, lessThan(375));
      expect(third, greaterThan(375 - 60));
      final visibleTiles = [
        for (final k in [
          'sportswear_footwear',
          'supplements_nutrition',
          'equipment',
          'accessories_gear',
          'food_drinks',
        ])
          if (tester.getTopLeft(_key('shop-home-category-$k')).dx < 375) k,
      ];
      expect(visibleTiles, hasLength(5)); // 4 whole + the 5th peeking
      expect(
        tester.getTopRight(_key('shop-home-category-food_drinks')).dx,
        greaterThan(375),
      );
    });

    apiTest('header: controls on the title line when they fit', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      await _pump(tester, api, size: const Size(375, 812));
      final title = tester.getCenter(_key('shop-home-title-best_sellers')).dy;
      final viewAll = tester.getCenter(_key('shop-home-viewall-best_sellers'));
      expect((viewAll.dy - title).abs(), lessThan(4));
    });

    apiTest('header: a long title moves the controls to line 2, right', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: _home(
          sections: [
            _section(
              'essentials',
              'Essentials',
              'Mahitaji muhimu ya mazoezi ya kila siku',
              ['p1'],
              reason: {'en': 'x', 'sw': 'x'},
              query: {'category': 'equipment'},
            ),
          ],
        ),
      );
      await _pump(
        tester,
        api,
        lang: 'sw',
        scale: 1.3,
        size: const Size(375, 812),
      );
      final title = tester.getRect(_key('shop-home-title-essentials'));
      final viewAll = tester.getRect(_key('shop-home-viewall-essentials'));
      expect(viewAll.top, greaterThanOrEqualTo(title.bottom - 1));
      expect(viewAll.right, closeTo(375 - 16, 2));
    });

    // 7 — desktop.
    apiTest('1280px: centred 1200 column, tiles spread, rail arrows work', (
      tester,
      api,
    ) async {
      _seed(api, home: _many(10));
      await _pump(tester, api, size: const Size(1280, 900));
      final search = tester.getRect(_key('shop-home-search'));
      expect(search.left, closeTo((1280 - 1232) / 2 + 16, 1));
      final first = tester.getRect(
        _key('shop-home-category-sportswear_footwear'),
      );
      final last = tester.getRect(_key('shop-home-category-other'));
      expect(first.left, closeTo(search.left, 1));
      expect(last.right, greaterThan(1280 - (1280 - 1232) / 2 - 16 - 2));
      expect(_key('shop-home-prev-best_sellers'), findsOneWidget);
      final before = tester.getTopLeft(_key('shop-home-card-m0')).dx;
      await tester.tap(_key('shop-home-next-best_sellers'));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(_key('shop-home-card-m0')).dx, lessThan(before));
    });

    // 8 — 48dp targets, even with desktop density.
    apiTest('targets are at least 48x48 (desktop density)', (
      tester,
      api,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        _seed(api, home: _home());
        await _pump(tester, api, size: const Size(1280, 900));
        for (final k in [
          'shop-home-why-best_sellers',
          'shop-home-cart',
          'shop-home-viewall-best_sellers',
        ]) {
          final size = tester.getSize(_key(k));
          expect(size.width, greaterThanOrEqualTo(48), reason: k);
          expect(size.height, greaterThanOrEqualTo(48), reason: k);
        }
        expect(
          tester.getSize(find.byType(SegmentedButton<int>)).height,
          greaterThanOrEqualTo(48),
        );
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    // 9 — no word broken in the middle.
    apiTest('category labels wrap on words ("Supplements" on one line)', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      await _pump(tester, api, scale: 1.3, size: const Size(375, 812));
      for (final (key, word) in [
        ('supplements_nutrition', 'Supplements'),
        ('accessories_gear', 'Accessories'),
      ]) {
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: _key('shop-home-category-label-$key'),
            matching: find.byType(RichText),
          ),
        );
        final boxes = paragraph.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: word.length),
        );
        expect(boxes.map((b) => b.top).toSet(), hasLength(1), reason: word);
      }
    });

    // 10 — disclosure never cut off.
    apiTest('the Sponsored disclosure is not truncated at 200%', (
      tester,
      api,
    ) async {
      final promoted = {
        ..._whey,
        'promotion': {
          'id': 'pr',
          'type': 'featured',
          'label': 'Featured · Sponsored',
          'commercial': true,
        },
      };
      _seed(
        api,
        home: _home(
          sections: [
            _section('featured', 'Featured', 'Zilizoangaziwa', ['p1']),
          ],
          products: {'p1': promoted},
        ),
      );
      await _pump(tester, api, scale: 2, size: const Size(375, 812));
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byKey(const Key('promo-badge-featured')),
          matching: find.byType(RichText),
        ),
      );
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(paragraph.text.toPlainText(), 'Featured · Sponsored');
    });

    // 11 — the View all category is a selected chip.
    apiTest('View all into a category shows it as a selected chip', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-viewall-new_arrivals'));
      final chip = tester.widget<FilterChip>(
        find.ancestor(
          of: find.text('Sportswear & footwear'),
          matching: find.byType(FilterChip),
        ),
      );
      expect(chip.selected, isTrue);
    });

    // 12 — offline after a load.
    apiTest('offline: Browse -> My orders -> Browse keeps the home', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      final host = await _pump(tester, api);
      expect(_key('shop-home-section-best_sellers'), findsOneWidget);
      api.onCall(
        'GET /shop/home',
        (_) => throw http.ClientException('XMLHttpRequest error.'),
      );
      await tester.tap(find.text(host.tr('shop.myOrders')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(host.tr('shop.browse')));
      await tester.pumpAndSettle();
      expect(_key('shop-home-section-best_sellers'), findsOneWidget);
      expect(_key('shop-home-offline-bar'), findsOneWidget);
      expect(_key('shop-home-offline'), findsNothing);
    });

    // 13 — Why bullets.
    for (final lang in ['en', 'sw']) {
      apiTest('Why: translated bullets + the role line ($lang)', (
        tester,
        api,
      ) async {
        _seed(
          api,
          home: _home(
            sections: [
              {
                ..._section(
                  'best_sellers',
                  'Best sellers',
                  'Zinazouzwa zaidi',
                  ['p1'],
                  reason: {'en': 'Server words', 'sw': 'Maneno ya seva'},
                ),
                'reasonCodes': [
                  'best_sellers_30d',
                  {
                    'code': 'bought_category',
                    'params': {'category': 'equipment'},
                  },
                  'role_context',
                  'mystery_code',
                ],
              },
            ],
          ),
        );
        final host = await _pump(tester, api, lang: lang);
        await tapVisible(tester, _key('shop-home-why-best_sellers'));
        expect(find.text(host.tr('shop.why.bestSellers')), findsOneWidget);
        expect(
          find.text(
            host
                .tr('shop.why.boughtCategory')
                .replaceAll(
                  '{category}',
                  lang == 'sw'
                      ? 'Vifaa vya gym na mazoezi'
                      : 'Gym & fitness equipment',
                ),
          ),
          findsOneWidget,
        );
        // The unknown code falls back to the server's own reason.
        expect(
          find.text(lang == 'sw' ? 'Maneno ya seva' : 'Server words'),
          findsOneWidget,
        );
        expect(
          tester.widget<Text>(_key('shop-why-role')).data,
          host.tr('shop.why.roleMember'),
        );
      });
    }

    // 14 — sticky cart bar.
    apiTest('a sticky cart bar opens the same checkout', (tester, api) async {
      _seed(api, home: _home());
      final host = await _pump(tester, api, size: const Size(375, 812));
      expect(_key('shop-home-checkout'), findsNothing);
      await tapVisible(tester, _key('shop-home-add-p1'));
      await host.dismissSnacks();
      final bar = tester.getRect(_key('shop-home-checkout'));
      expect(bar.bottom, greaterThan(812 - 80));
      expect(
        find.descendant(
          of: _key('shop-home-checkout'),
          matching: find.text(
            host
                .tr('shop.home.cartBarOne')
                .replaceAll('{total}', formatCurrency(85000)),
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(_key('shop-home-checkout'));
      await tester.pumpAndSettle();
      expect(_key('shop-place-order'), findsOneWidget);
    });

    apiTest('offline: the cart bar says checkout needs a connection', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      final host = await _pump(tester, api);
      await tapVisible(tester, _key('shop-home-add-p1'));
      await host.dismissSnacks();
      api.onCall(
        'GET /shop/home',
        (_) => throw http.ClientException('XMLHttpRequest error.'),
      );
      await tester.tap(find.text(host.tr('shop.myOrders')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(host.tr('shop.browse')));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: _key('shop-home-checkout'),
          matching: find.text(host.tr('shop.home.checkoutOffline')),
        ),
        findsOneWidget,
      );
      expect(isEnabled(tester, _key('shop-home-checkout')), isFalse);
    });

    // 15 — focus outline and the loading label.
    apiTest('a focused card shows an outline', (tester, api) async {
      _seed(api, home: _home());
      await _pump(tester, api);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      expect(_key('shop-home-focus-ring'), findsNothing);
      Focus.of(
        tester.element(
          find
              .descendant(
                of: _key('shop-home-card-p1'),
                matching: find.text('Whey Protein'),
              )
              .first,
        ),
      ).requestFocus();
      await tester.pumpAndSettle();
      expect(_key('shop-home-focus-ring'), findsOneWidget);
    });

    apiTest('loading exposes exactly one "Loading the shop" node', (
      tester,
      api,
    ) async {
      _seed(api, home: _home());
      final gate = api.hold('GET /shop/home');
      final handle = tester.ensureSemantics();
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
      expect(find.bySemanticsLabel('Loading the shop'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      handle.dispose();
    });

    test('no Back handler is left behind once the shop is gone', () {
      expect(rootBackHandlerCount, 0);
    });
  });
}

void qaRound1b() {
  group('QA round 1 follow-up', () {
    for (final lang in ['en', 'sw']) {
      apiTest('Why: every server reason code has app wording ($lang)', (
        tester,
        api,
      ) async {
        const codes = {
          'profile_goal': 'shop.why.profileGoal',
          'trainer_specialty': 'shop.why.trainerSpecialty',
          'recently_viewed': 'shop.why.recentlyViewed',
          'seller_discount': 'shop.why.sellerDiscount',
          'new_arrival': 'shop.why.newArrival',
          'generic': 'shop.why.generic',
          'flash_sale_seller_discount': 'shop.why.flashSale',
        };
        _seed(
          api,
          home: _home(
            sections: [
              {
                ..._section(
                  'essentials',
                  'Essentials',
                  'Bidhaa muhimu',
                  ['p1'],
                  reason: {'en': 'Server words', 'sw': 'Maneno ya seva'},
                ),
                'reasonCodes': [...codes.keys, 'role_context'],
              },
            ],
          ),
        );
        final host = await _pump(tester, api, lang: lang);
        await tapVisible(tester, _key('shop-home-why-essentials'));
        for (final key in codes.values) {
          expect(find.text(host.tr(key)), findsOneWidget, reason: key);
          expect(host.tr(key), isNot(key));
        }
        // All codes were known: no server sentence.
        expect(find.text('Server words'), findsNothing);
        expect(find.text('Maneno ya seva'), findsNothing);
        expect(
          host.tr('shop.why.sellerDiscount'),
          isNot(host.tr('shop.why.flashSale')),
        );
      });
    }

    apiTest('Why: only role_context -> the server sentence + role line', (
      tester,
      api,
    ) async {
      _seed(
        api,
        home: _home(
          sections: [
            {
              ..._section(
                'essentials',
                'Training essentials',
                'Mahitaji muhimu ya mazoezi',
                ['p1'],
                reason: {
                  'en': 'Picked for people shopping as a member.',
                  'sw': 'Imechaguliwa kwa wanaonunua kama mwanachama.',
                },
              ),
              'reasonCodes': ['role_context'],
            },
          ],
        ),
      );
      final host = await _pump(tester, api, lang: 'sw');
      await tapVisible(tester, _key('shop-home-why-essentials'));
      expect(
        find.text('Imechaguliwa kwa wanaonunua kama mwanachama.'),
        findsOneWidget,
      );
      expect(
        tester.widget<Text>(_key('shop-why-role')).data,
        host.tr('shop.why.roleMember'),
      );
    });

    test('Swahili follows the glossary and the server copy', () {
      final sw = FFLocale()..set(const Locale('sw'));
      expect(
        sw.t('shop.why.popularWithRole'),
        'Ni maarufu kwa wengine wanaonunua katika nafasi hii.',
      );
      expect(sw.t('shop.why.popularWithRole'), isNot(contains('jukumu')));
      expect(sw.t('shop.why.deliversToArea'), contains('delivery'));
      expect(sw.t('shop.why.featured'), contains('"Iliyodhaminiwa"'));
      expect(sw.t('shop.why.featured'), isNot(contains('“')));
    });
  });
}
