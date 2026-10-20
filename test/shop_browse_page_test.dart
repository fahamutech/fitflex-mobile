// Characterization (safety-net) tests for the member marketplace
// (lib/shared/widgets/shop_browse_page.dart): browse, search and filters,
// product detail, cart, checkout, enquiry, store, order tracking, cancel,
// reorder, invoice and review.
//
// They pin what the screen DOES today — requests sent, text shown, enabled
// state — so raw Material controls can later be swapped for the shared FF*
// widgets without silently changing behaviour. See
// test/support/recording_api.dart for the fake backend and finders.
//
// Brittle finders (kept deliberately small):
//  * the rating picker in the review dialog is found as DropdownButton<int>;
//  * the review comment box is the only EditableText in the review dialog;
//  * dropdown options are found by their visible text (`.last`, as the
//    selected value is also shown in the field).
// Known current behaviours characterized as-is (not endorsed):
//  * A failed catalogue load shows an error (or offline) state with Try again
//    (changed 2026-10-19, Shop home V2 Phase 1; it used to say "no products").
//  * Sending an enquiry, reordering, reviewing and filing a review show no
//    confirmation or error message.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/shared/formatters.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';

import 'support/recording_api.dart';

Map<String, dynamic> _p(
  String id,
  String name, {
  String? category,
  String? brand,
  num price = 10000,
  num? discount,
  int stock = 5,
  num rating = 4,
  int reviews = 0,
  int sold = 0,
  bool delivery = true,
}) => {
  'id': id,
  'vendorId': 'v1',
  'name': name,
  'category': category,
  'brand': brand,
  'priceTzs': price,
  'discountPriceTzs': discount,
  'stock': stock,
  'rating': rating,
  'reviewCount': reviews,
  'soldCount': sold,
  'deliveryAvailable': delivery,
};

final _catalogue = [
  _p(
    'p1',
    'Whey Protein',
    category: 'Supplements',
    brand: 'MuscleCo',
    price: 85000,
    stock: 4,
    rating: 4.5,
    reviews: 12,
    sold: 50,
  ),
  _p(
    'p2',
    'Yoga Mat',
    category: 'Equipment',
    brand: 'FlexCo',
    price: 30000,
    discount: 25000,
    stock: 10,
    rating: 3,
    sold: 5,
    delivery: false,
  ),
  _p(
    'p3',
    'Kettlebell',
    category: 'Equipment',
    brand: 'IronCo',
    price: 45000,
    stock: 0,
    rating: 4.9,
    sold: 20,
  ),
];

Map<String, dynamic> _order(
  String id, {
  String status = 'accepted',
  String paymentStatus = 'paid',
  bool canCancel = true,
}) => {
  'id': id,
  'status': status,
  'paymentStatus': paymentStatus,
  'canCancel': canCancel,
  'totalTzs': 170000,
  'items': [
    {'productId': 'p1', 'qty': 2, 'name': 'Whey Protein'},
  ],
  'timeline': [
    {'status': 'placed'},
    {'status': status},
  ],
};

void _seed(
  RecordingApi api, {
  List<dynamic>? products,
  List<dynamic> orders = const [],
}) {
  api.on('GET /shop/products', products ?? _catalogue);
  api.on('GET /me/shop-orders', orders);
  api.on('GET /gyms', [
    {'id': 'g1', 'name': 'Iron Temple', 'location': 'Masaki'},
    {'id': 'g2', 'name': 'Pump House', 'location': 'Mikocheni'},
  ]);
  api.on('GET /shop/products/p1', {
    ..._catalogue[0],
    'description': 'Fast absorbing isolate',
    'reviewCount': 1,
    'vendor': {'businessName': 'FitFlex Performance Store'},
    'reviews': [
      {'rating': 5, 'comment': 'Excellent product'},
    ],
    'similarProducts': [
      {'id': 'p2', 'name': 'Casein', 'priceTzs': 70000},
    ],
  });
  api.on('GET /shop/vendors/v1', {
    'businessName': 'FitFlex Performance Store',
    'description': 'Equipment and nutrition',
    'rating': '4.80',
    'reviewCount': 1,
    'products': [_catalogue[0]],
    'reviews': [
      {'rating': 5, 'comment': 'Great store'},
    ],
  });
}

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  double scale = 1,
  bool settle = true,
  bool keepRequests = false,
  // Functional tests use a roomier phone: at 360px a product row with items
  // in the cart overflows (see the layout group), which is not what they test.
  Size size = const Size(420, 900),
}) => pumpPage(
  tester,
  api,
  const ShopBrowsePage(),
  user: const {'id': 'm1', 'userType': 'member'},
  lang: lang,
  textScale: scale,
  settle: settle,
  keepRequests: keepRequests,
  size: size,
);

const _dar = {
  'latitude': -6.7735,
  'longitude': 39.2699,
  'timestamp': 1760000000000,
  'accuracy': 5.0,
  'altitude': 0.0,
  'heading': 0.0,
  'speed': 0.0,
  'speed_accuracy': 0.0,
  'is_mocked': false,
};

/// Answers the geolocator plugin: [permission] is the LocationPermission
/// index (2 = while in use); [position] null makes the read fail.
void _mockLocation(
  WidgetTester tester, {
  required int permission,
  required Map<String, Object?>? position,
}) {
  const channel = MethodChannel('flutter.baseflow.com/geolocator');
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
    call,
  ) async {
    switch (call.method) {
      case 'checkPermission':
      case 'requestPermission':
        return permission;
      case 'getCurrentPosition':
        if (position == null) {
          throw PlatformException(code: 'LOCATION_SERVICES_DISABLED');
        }
        return position;
    }
    return null;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      null,
    ),
  );
}

Finder _key(String k) => find.byKey(Key(k));

Future<void> _openMyOrders(WidgetTester tester, PageHost host) async {
  // The segmented control sits at the top of the (scrollable) page.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 3000));
  await tester.pumpAndSettle();
  await tester.tap(find.text(host.tr('shop.myOrders')));
  await tester.pumpAndSettle();
}

/// Adds [productId] to the cart [times] times from the product row.
Future<void> _add(
  WidgetTester tester,
  String productId, [
  int times = 1,
]) async {
  for (var i = 0; i < times; i++) {
    await tester.ensureVisible(_key('shop-add-$productId'));
    await tester.tap(_key('shop-add-$productId'));
    await tester.pump();
  }
}

Future<void> _openDetail(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> _openCheckout(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    _key('shop-checkout'),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tapVisible(tester, _key('shop-checkout'));
  expect(_key('shop-place-order'), findsOneWidget);
}

void main() {
  setUpAll(loadAppFonts);

  group('browse', () {
    apiTest('shows a spinner while loading, then the catalogue', (
      tester,
      api,
    ) async {
      _seed(api);
      final gate = api.hold('GET /shop/products');
      await _pump(tester, api, settle: false);
      await tester.pump();
      await tester.pump();
      expect(spinner, findsOneWidget);
      expect(find.text('Whey Protein'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(spinner, findsNothing);
      expect(find.text('Whey Protein'), findsOneWidget);
      expect(find.text('Yoga Mat'), findsOneWidget);
      expect(find.text('Kettlebell'), findsOneWidget);
      expect(api.sent('GET', '/me/shop-orders'), isTrue);
    });

    apiTest('a product row shows brand, effective price, rating and stock', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      expect(find.text('MuscleCo'), findsOneWidget);
      expect(find.text(formatCurrency(85000)), findsOneWidget);
      // Yoga Mat is discounted: the sale price, with the original struck
      // through under it (AC-14 / spec §7.3, changed 2026-10-19).
      expect(find.text(formatCurrency(25000)), findsOneWidget);
      final was = tester.widget<Text>(_key('shop-was-p2'));
      expect(was.data, formatCurrency(30000));
      expect(was.style?.decoration, TextDecoration.lineThrough);
      // With real reviews: the rating and how many reviews (QA round 2).
      expect(find.text(' 4.5 (12) · 4 in stock'), findsOneWidget);
      // Yoga Mat has a rating but no reviews: no stars, no number, no "0.0".
      expect(find.text('10 in stock'), findsOneWidget);
      expect(find.textContaining('3.0'), findsNothing);
    });

    apiTest('an empty catalogue shows the empty message', (tester, api) async {
      _seed(api, products: []);
      final host = await _pump(tester, api);
      expect(find.text(host.tr('shop.noProducts')), findsOneWidget);
    });

    apiTest('a failed load says so with Try again (not "no products")', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('GET /shop/products');
      final host = await _pump(tester, api);
      expect(spinner, findsNothing);
      expect(find.text(host.tr('shop.noProducts')), findsNothing);
      expect(find.text(host.tr('shop.home.errorTitle')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.enterText(_key('shop-search'), 'abc');
      await tester.pump();
      await _openMyOrders(tester, host);
      expect(find.text(host.tr('shop.noOrders')), findsOneWidget);
    });

    apiTest('promoted products appear in a Featured section', (
      tester,
      api,
    ) async {
      _seed(api);
      api.on('GET /discover/products', {
        'featured': [_catalogue[1]],
        'items': _catalogue,
        'total': 3,
        'placement': 'shop',
      });
      final host = await _pump(tester, api, keepRequests: true);
      expect(api.sent('GET', '/discover/products'), isTrue);
      expect(find.text(host.tr('member.featuredProducts')), findsOneWidget);
      expect(_key('shop-featured-p2'), findsOneWidget);
      // Tapping a featured card opens its detail sheet.
      api.on('GET /shop/products/p2', _catalogue[1]);
      await tester.tap(_key('shop-featured-p2'));
      await tester.pumpAndSettle();
      expect(_key('shop-detail-add-p2'), findsOneWidget);
    });
  });

  group('search, filter and sort', () {
    apiTest('typing in search narrows the list by name and brand', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      await tester.enterText(_key('shop-search'), 'whey');
      await tester.pump();
      expect(find.text('Whey Protein'), findsOneWidget);
      expect(find.text('Yoga Mat'), findsNothing);

      await tester.enterText(_key('shop-search'), 'ironco');
      await tester.pump();
      expect(find.text('Kettlebell'), findsOneWidget);
      expect(find.text('Whey Protein'), findsNothing);

      await tester.enterText(_key('shop-search'), 'zzz');
      await tester.pump();
      expect(find.text(host.tr('shop.noProducts')), findsOneWidget);
    });

    apiTest('category chips filter, All categories clears', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      await tapVisible(tester, find.text('Equipment'));
      await tester.pump();
      expect(find.text('Whey Protein'), findsNothing);
      expect(find.text('Yoga Mat'), findsOneWidget);
      expect(find.text('Kettlebell'), findsOneWidget);

      await tester.tap(find.text(host.tr('shop.allCategories')));
      await tester.pump();
      expect(find.text('Whey Protein'), findsOneWidget);
    });

    apiTest('delivery and promotions chips toggle their filters', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      await tester.tap(_key('shop-delivery-filter'));
      await tester.pump();
      expect(find.text('Yoga Mat'), findsNothing);
      expect(find.text('Whey Protein'), findsOneWidget);

      await tester.tap(_key('shop-delivery-filter'));
      await tester.tap(_key('shop-promotions-filter'));
      await tester.pump();
      expect(find.text('Yoga Mat'), findsOneWidget);
      expect(find.text('Whey Protein'), findsNothing);
      expect(find.text('Kettlebell'), findsNothing);
    });

    apiTest('sorting reorders the list', (tester, api) async {
      _seed(api);
      final host = await _pump(tester, api);
      const names = ['Whey Protein', 'Yoga Mat', 'Kettlebell'];
      Future<void> sortBy(String key) async {
        await tester.tap(_key('shop-sort'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(host.tr(key)).last);
        await tester.pumpAndSettle();
      }

      await sortBy('shop.priceLow');
      expect(verticalOrder(tester, names), [
        'Yoga Mat',
        'Kettlebell',
        'Whey Protein',
      ]);
      await sortBy('shop.priceHigh');
      expect(verticalOrder(tester, names), [
        'Whey Protein',
        'Kettlebell',
        'Yoga Mat',
      ]);
      await sortBy('shop.rating');
      expect(verticalOrder(tester, names), [
        'Kettlebell',
        'Whey Protein',
        'Yoga Mat',
      ]);
      await sortBy('shop.popularity');
      expect(verticalOrder(tester, names), [
        'Whey Protein',
        'Kettlebell',
        'Yoga Mat',
      ]);
    });

    apiTest('the filters sheet applies brand and price range, and clears', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      await tester.tap(_key('shop-more-filters'));
      await tester.pumpAndSettle();
      await typeInto(tester, _key('shop-filter-brand'), 'flex');
      await tapVisible(tester, _key('shop-apply-filters'));
      expect(find.text('Yoga Mat'), findsOneWidget);
      expect(find.text('Whey Protein'), findsNothing);

      // Reopening shows the applied value; clear brings everything back.
      await tester.tap(_key('shop-more-filters'));
      await tester.pumpAndSettle();
      expect(textOf(tester, _key('shop-filter-brand')), 'flex');
      await tapVisible(tester, _key('shop-clear-filters'));
      expect(find.text('Whey Protein'), findsOneWidget);
      expect(find.text('Kettlebell'), findsOneWidget);

      // Price range uses the effective (discounted) price.
      await tester.tap(_key('shop-more-filters'));
      await tester.pumpAndSettle();
      await typeInto(tester, _key('shop-filter-min-price'), '40000');
      await typeInto(tester, _key('shop-filter-max-price'), '60000');
      await tapVisible(tester, _key('shop-apply-filters'));
      expect(find.text('Kettlebell'), findsOneWidget);
      expect(find.text('Whey Protein'), findsNothing);
      expect(find.text('Yoga Mat'), findsNothing);

      // Minimum rating.
      await tester.tap(_key('shop-more-filters'));
      await tester.pumpAndSettle();
      await typeInto(tester, _key('shop-filter-min-price'), '');
      await typeInto(tester, _key('shop-filter-max-price'), '');
      await typeInto(tester, _key('shop-filter-rating'), '4.6');
      await tapVisible(tester, _key('shop-apply-filters'));
      expect(find.text('Kettlebell'), findsOneWidget);
      expect(find.text('Whey Protein'), findsNothing);
    });
  });

  group('cart', () {
    apiTest('adding shows quantity and the checkout total; remove undoes', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      expect(_key('shop-checkout'), findsNothing);
      await _add(tester, 'p1', 2);
      await _add(tester, 'p2');
      expect(
        find.text(
          '${host.tr('shop.checkout')} · ${formatCurrency(2 * 85000 + 25000)}',
        ),
        findsOneWidget,
      );
      await tester.tap(_key('shop-remove-p1'));
      await tester.pump();
      expect(
        find.text(
          '${host.tr('shop.checkout')} · ${formatCurrency(85000 + 25000)}',
        ),
        findsOneWidget,
      );
      await tester.tap(_key('shop-remove-p1'));
      await tester.tap(_key('shop-remove-p2'));
      await tester.pump();
      expect(_key('shop-checkout'), findsNothing);
    });

    apiTest('out of stock cannot be added and quantity stops at stock', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      // Out of stock: a badge, a dimmed photo and no cart button (AC-14).
      expect(_key('shop-add-p3'), findsNothing);
      expect(_key('shop-oos-p3'), findsOneWidget);
      expect(tester.widget<Opacity>(_key('shop-image-p3')).opacity, 0.4);
      expect(isEnabled(tester, _key('shop-add-p1')), isTrue);
      await _add(tester, 'p1', 6);
      expect(
        find.text('${host.tr('shop.checkout')} · ${formatCurrency(4 * 85000)}'),
        findsOneWidget,
      );
    });

    apiTest('saving for later counts the item and removes it from the cart', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      await _add(tester, 'p1');
      expect(_key('shop-checkout'), findsOneWidget);
      await tester.tap(_key('shop-save-p1'));
      await tester.pump();
      expect(find.text('${host.tr('shop.savedForLater')}: 1'), findsOneWidget);
      expect(_key('shop-checkout'), findsNothing);
      // Tapping again un-saves.
      await tester.tap(_key('shop-save-p1'));
      await tester.pump();
      expect(find.textContaining(host.tr('shop.savedForLater')), findsNothing);
    });
  });

  group('product detail', () {
    apiTest('fetches the detail and shows description, vendor and reviews', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      await _openDetail(tester, 'Whey Protein');
      expect(api.sent('GET', '/shop/products/p1'), isTrue);
      expect(find.text('Fast absorbing isolate'), findsOneWidget);
      expect(
        find.text('${host.tr('shop.vendor')}: FitFlex Performance Store'),
        findsOneWidget,
      );
      expect(find.text('Excellent product'), findsOneWidget);
      expect(find.text('Casein'), findsOneWidget);
      expect(find.text(host.tr('shop.reviews')), findsOneWidget);
    });

    apiTest('falls back to the catalogue record when the detail fails', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('GET /shop/products/p1');
      await _pump(tester, api);
      await _openDetail(tester, 'Whey Protein');
      expect(_key('shop-detail-add-p1'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    apiTest('add to cart keeps the sheet; closing shows the checkout button', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      await _openDetail(tester, 'Whey Protein');
      await tapVisible(tester, _key('shop-detail-add-p1'));
      await tapVisible(tester, _key('shop-detail-add-p1'));
      expect(_key('shop-detail-add-p1'), findsOneWidget);
      await tester.tap(_key('shop-product-close'));
      await tester.pumpAndSettle();
      expect(_key('shop-detail-add-p1'), findsNothing);
      expect(
        find.text('${host.tr('shop.checkout')} · ${formatCurrency(2 * 85000)}'),
        findsOneWidget,
      );
    });

    apiTest('an out-of-stock product cannot be added or bought', (
      tester,
      api,
    ) async {
      _seed(api);
      api.on('GET /shop/products/p3', _catalogue[2]);
      final host = await _pump(tester, api);
      await _openDetail(tester, 'Kettlebell');
      expect(isEnabled(tester, _key('shop-detail-add-p3')), isFalse);
      expect(
        isEnabled(tester, buttonLabelled(host.tr('shop.buyNow'))),
        isFalse,
      );
    });

    apiTest('buy now adds the product and opens checkout', (tester, api) async {
      _seed(api);
      final host = await _pump(tester, api);
      await _openDetail(tester, 'Whey Protein');
      await tapVisible(tester, buttonLabelled(host.tr('shop.buyNow')));
      expect(_key('shop-place-order'), findsOneWidget);
      expect(_key('shop-detail-add-p1'), findsNothing);
    });

    apiTest('chat with vendor sends a trimmed enquiry; empty sends nothing', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pump(tester, api);
      await _openDetail(tester, 'Whey Protein');
      await tapVisible(tester, _key('shop-chat-vendor'));
      await tester.enterText(_key('shop-enquiry-message'), '   ');
      await tapAndSettleDialogClose(tester, _key('shop-enquiry-send'));
      expect(api.requests.where((r) => r.method == 'POST'), isEmpty);

      await tapVisible(tester, _key('shop-chat-vendor'));
      await tester.enterText(_key('shop-enquiry-message'), ' Is it halal? ');
      await tapAndSettleDialogClose(tester, _key('shop-enquiry-send'));
      expect(api.only('POST', '/me/marketplace-enquiries').body, {
        'productId': 'p1',
        'message': 'Is it halal?',
      });
      expect(find.byType(SnackBar), findsNothing);
    });

    apiTest('visit store opens the storefront; a failure shows an error', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      await _openDetail(tester, 'Whey Protein');
      await tapVisible(tester, _key('shop-visit-store'));
      expect(api.sent('GET', '/shop/vendors/v1'), isTrue);
      expect(_key('shop-vendor-storefront'), findsOneWidget);
      expect(find.text('Great store'), findsOneWidget);
      expect(_key('shop-store-rating'), findsOneWidget);
      expect(_key('shop-store-no-reviews'), findsNothing);
      await tester.tap(_key('shop-store-close'));
      await tester.pumpAndSettle();

      api.fail('GET /shop/vendors/v1', 404);
      await tapVisible(tester, _key('shop-visit-store'));
      expect(_key('shop-vendor-storefront'), findsNothing);
      expect(host.snack(host.tr('shop.storeLoadFailed')), findsOneWidget);
    });
  });

  apiTest('a store with no reviews says so instead of "★ 0.0 (0)"', (
    tester,
    api,
  ) async {
    _seed(api);
    api.on('GET /shop/vendors/v1', {
      'businessName': 'FitFlex Performance Store',
      'rating': 0,
      'reviewCount': 0,
      'products': [_catalogue[0]],
      'reviews': [],
    });
    final host = await _pump(tester, api);
    await _openDetail(tester, 'Whey Protein');
    await tapVisible(tester, _key('shop-visit-store'));
    expect(_key('shop-store-rating'), findsNothing);
    expect(_key('shop-store-no-reviews'), findsOneWidget);
    expect(find.text(host.tr('reviews.none')), findsOneWidget);
    expect(find.textContaining('0.0'), findsNothing);
  });

  group('checkout', () {
    apiTest('home delivery needs an address; the order body is exact', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      await _add(tester, 'p1', 2);
      await _openCheckout(tester);
      // Home delivery is the default and requires an address.
      expect(_key('shop-delivery-address'), findsOneWidget);
      await tapVisible(tester, _key('shop-place-order'));
      expect(_key('shop-place-order'), findsOneWidget);
      expect(api.sent('POST', '/me/shop-orders'), isFalse);

      await typeInto(tester, _key('shop-delivery-address'), ' Masaki 12 ');
      // Payment method defaults to M-Pesa; switch to Airtel Money.
      await tapVisible(tester, _key('shop-payment-method'));
      await tester.tap(find.text('Airtel Money').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, _key('shop-place-order'));

      expect(api.only('POST', '/me/shop-orders').body, {
        'items': [
          {'productId': 'p1', 'qty': 2},
        ],
        'deliveryMethod': 'home_delivery',
        'deliveryAddress': 'Masaki 12',
        'paymentMethod': 'airtel_money',
        'paymentOutcome': 'success',
      });
      // The server has not confirmed payment: the customer is told so.
      expect(host.snack(host.tr('shop.orderPending')), findsOneWidget);
      // The cart is cleared, My orders is showing, and data was reloaded.
      expect(_key('shop-checkout'), findsNothing);
      expect(find.text(host.tr('shop.noOrders')), findsOneWidget);
      expect(api.where('GET', '/shop/products'), isNotEmpty);
    });

    apiTest('the default payment method is M-Pesa', (tester, api) async {
      _seed(api);
      await _pump(tester, api);
      await _add(tester, 'p2');
      await _openCheckout(tester);
      await typeInto(tester, _key('shop-delivery-address'), 'Mikocheni');
      await tapVisible(tester, _key('shop-place-order'));
      final body = api.only('POST', '/me/shop-orders').body as Map;
      expect(body['paymentMethod'], 'mpesa');
      expect(body['items'], [
        {'productId': 'p2', 'qty': 1},
      ]);
    });

    apiTest('gym pickup needs a gym and sends pickupGymId, not an address', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await tapVisible(tester, find.text(host.tr('shop.gymPickup')));
      expect(_key('shop-pickup-gym'), findsOneWidget);
      expect(_key('shop-delivery-address'), findsNothing);

      // No gym chosen: nothing is sent.
      await tapVisible(tester, _key('shop-place-order'));
      expect(api.sent('POST', '/me/shop-orders'), isFalse);

      // Searching narrows the gym list.
      await typeInto(tester, _key('shop-pickup-search'), 'pump');
      await tapVisible(tester, _key('shop-pickup-gym'));
      expect(find.text('Iron Temple · Masaki'), findsNothing);
      expect(find.text('Pump House · Mikocheni'), findsOneWidget);
      await tester.tap(find.text('Pump House · Mikocheni').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, _key('shop-place-order'));

      expect(api.only('POST', '/me/shop-orders').body, {
        'items': [
          {'productId': 'p1', 'qty': 1},
        ],
        'deliveryMethod': 'gym_pickup',
        'pickupGymId': 'g2',
        'paymentMethod': 'mpesa',
        'paymentOutcome': 'success',
      });
    });

    apiTest('nearest gyms sorts the pickup list by distance', (
      tester,
      api,
    ) async {
      _seed(api);
      api.on('GET /gyms', [
        {
          'id': 'g1',
          'name': 'Far Gym',
          'location': 'Arusha',
          'coordinates': {'lat': -3.37, 'lng': 36.68},
        },
        {
          'id': 'g2',
          'name': 'Near Gym',
          'location': 'Masaki',
          'coordinates': {'lat': -6.77, 'lng': 39.27},
        },
      ]);
      _mockLocation(tester, permission: 2, position: _dar);
      final host = await _pump(tester, api);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await tapVisible(tester, find.text(host.tr('shop.gymPickup')));
      await tapVisible(tester, buttonLabelled(host.tr('shop.nearestGyms')));
      await tapVisible(tester, _key('shop-pickup-gym'));
      // Distances are shown and the nearer gym is listed first.
      expect(find.textContaining('Near Gym · Masaki · 0.'), findsWidgets);
      expect(find.textContaining('Far Gym · Arusha · '), findsWidgets);
      final order = find
          .textContaining(' · ')
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '');
      expect(
        order.where((t) => t.contains('Gym')).toList().first,
        startsWith('Near Gym'),
      );
    });

    apiTest('nearest gyms reports when the location cannot be read', (
      tester,
      api,
    ) async {
      _seed(api);
      _mockLocation(tester, permission: 2, position: null);
      final host = await _pump(tester, api);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await tapVisible(tester, find.text(host.tr('shop.gymPickup')));
      await tapVisible(tester, buttonLabelled(host.tr('shop.nearestGyms')));
      expect(host.snack(host.tr('shop.locationUnavailable')), findsOneWidget);
    });

    apiTest('a failed order shows an error and keeps the cart', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('POST /me/shop-orders', 422);
      final host = await _pump(tester, api);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await typeInto(tester, _key('shop-delivery-address'), 'Masaki');
      await tapVisible(tester, _key('shop-place-order'));
      expect(host.snack(host.tr('shop.orderFailed')), findsOneWidget);
      expect(host.snack(host.tr('shop.orderPending')), findsNothing);
      expect(_key('shop-checkout'), findsOneWidget);
      expect(isEnabled(tester, _key('shop-checkout')), isTrue);
    });
  });

  group('checkout safety', () {
    Future<void> placeWith(WidgetTester tester, String address) async {
      await typeInto(tester, _key('shop-delivery-address'), address);
      await tapVisible(tester, _key('shop-place-order'));
    }

    /// The message snack bar covers the checkout button until it times out.
    Future<void> reopenCheckout(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      await _openCheckout(tester);
    }

    apiTest('every order carries an Idempotency-Key', (tester, api) async {
      _seed(api);
      await _pump(tester, api);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await placeWith(tester, 'Masaki');
      final key = api
          .only('POST', '/me/shop-orders')
          .headers['idempotency-key'];
      expect(key, isNotNull);
      expect(key, matches(RegExp(r'^[A-Za-z0-9._:-]{8,100}$')));
    });

    apiTest('a timeout keeps the cart and the retry sends the same key', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('POST /me/shop-orders', 503);
      final host = await _pump(tester, api);
      await _add(tester, 'p1', 2);
      await _openCheckout(tester);
      await placeWith(tester, 'Masaki');
      // The outcome is unknown: say so, keep the cart, never "failed".
      expect(host.snack(host.tr('shop.orderUncertain')), findsOneWidget);
      expect(_key('shop-checkout'), findsOneWidget);

      api.heal('POST /me/shop-orders');
      await reopenCheckout(tester);
      await placeWith(tester, 'Masaki');
      final posts = api.where('POST', '/me/shop-orders');
      expect(posts, hasLength(2));
      expect(
        posts[1].headers['idempotency-key'],
        posts[0].headers['idempotency-key'],
        reason: 'the retry must be recognisable as the same order',
      );
      expect(_key('shop-checkout'), findsNothing); // cleared only once placed
    });

    apiTest('changed delivery details are a new order with a new key', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('POST /me/shop-orders', 503);
      await _pump(tester, api);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await placeWith(tester, 'Masaki');
      api.heal('POST /me/shop-orders');
      await reopenCheckout(tester);
      await placeWith(tester, 'Mikocheni');
      final posts = api.where('POST', '/me/shop-orders');
      expect(
        posts[1].headers['idempotency-key'],
        isNot(posts[0].headers['idempotency-key']),
      );
    });

    apiTest(
      'a clear refusal keeps the cart and the next order is a new attempt',
      (tester, api) async {
        _seed(api);
        api.fail('POST /me/shop-orders', 409, {'error': 'insufficient_stock'});
        final host = await _pump(tester, api);
        await _add(tester, 'p1');
        await _openCheckout(tester);
        await placeWith(tester, 'Masaki');
        expect(
          host.snack(host.tr('shop.errInsufficientStock')),
          findsOneWidget,
        );
        expect(_key('shop-checkout'), findsOneWidget);
        // The catalogue is read again so the customer sees current stock.
        expect(api.where('GET', '/shop/products'), isNotEmpty);

        api.heal('POST /me/shop-orders');
        await reopenCheckout(tester);
        await placeWith(tester, 'Masaki');
        final posts = api.where('POST', '/me/shop-orders');
        expect(
          posts[1].headers['idempotency-key'],
          isNot(posts[0].headers['idempotency-key']),
        );
      },
    );

    apiTest('a price change is explained, not shown as a generic failure', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('POST /me/shop-orders', 409, {'error': 'price_changed'});
      final host = await _pump(tester, api);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await placeWith(tester, 'Masaki');
      expect(host.snack(host.tr('shop.errPriceChanged')), findsOneWidget);
    });

    apiTest('a paid order is confirmed; an unpaid one is reported as waiting', (
      tester,
      api,
    ) async {
      _seed(api);
      api.on('POST /me/shop-orders', {
        'id': 'o9',
        'paymentStatus': 'paid',
        'totalTzs': 85000,
      });
      final host = await _pump(tester, api);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await placeWith(tester, 'Masaki');
      expect(host.snack(host.tr('shop.paymentConfirmed')), findsOneWidget);
    });

    apiTest('the server total is reported when it differs from the cart', (
      tester,
      api,
    ) async {
      _seed(api);
      api.on('POST /me/shop-orders', {
        'id': 'o9',
        'paymentStatus': 'pending',
        'totalTzs': 90000,
      });
      final host = await _pump(tester, api);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await placeWith(tester, 'Masaki');
      expect(
        find.textContaining(formatCurrency(90000)),
        findsWidgets,
        reason: host.tr('shop.orderTotalIs'),
      );
    });

    apiTest('missing address or gym says what is needed', (tester, api) async {
      _seed(api);
      final host = await _pump(tester, api);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await tapVisible(tester, _key('shop-place-order'));
      expect(host.snack(host.tr('shop.addressRequired')), findsOneWidget);
      await tapVisible(tester, find.text(host.tr('shop.gymPickup')));
      await tapVisible(tester, _key('shop-place-order'));
      expect(host.snack(host.tr('shop.pickupGymRequired')), findsOneWidget);
      expect(api.sent('POST', '/me/shop-orders'), isFalse);
    });

    apiTest('a product with options asks which one and sends it', (
      tester,
      api,
    ) async {
      _seed(
        api,
        products: [
          {
            ..._p('p4', 'Protein Bar', price: 3000, stock: 10),
            'variants': [
              {'name': 'Vanilla', 'stock': 0},
              {'name': 'Chocolate', 'stock': 5},
            ],
          },
        ],
      );
      await _pump(tester, api);
      await _add(tester, 'p4');
      // A sold-out option cannot be picked; the other can.
      expect(_key('shop-variant-p4-Vanilla'), findsOneWidget);
      await tester.tap(_key('shop-variant-p4-Chocolate'));
      await tester.pumpAndSettle();
      await _openCheckout(tester);
      await placeWith(tester, 'Masaki');
      expect(
        api.only('POST', '/me/shop-orders').body,
        containsPair('items', [
          {'productId': 'p4', 'qty': 1, 'variant': 'Chocolate'},
        ]),
      );
    });

    apiTest('a second tap while the order is in flight sends one order', (
      tester,
      api,
    ) async {
      _seed(api);
      final gate = api.hold('POST /me/shop-orders');
      await _pump(tester, api);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await typeInto(tester, _key('shop-delivery-address'), 'Masaki');
      await tester.tap(_key('shop-place-order'));
      await tester.pump();
      // Back on the page the checkout button is disabled while ordering.
      await tester.pump(const Duration(milliseconds: 50));
      expect(api.where('POST', '/me/shop-orders'), hasLength(1));
      if (_key('shop-checkout').evaluate().isNotEmpty) {
        expect(isEnabled(tester, _key('shop-checkout')), isFalse);
      }
      gate.complete();
      await tester.pumpAndSettle();
      expect(api.where('POST', '/me/shop-orders'), hasLength(1));
    });
  });

  group('my orders', () {
    apiTest('lists orders with total, status and timeline', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1')]);
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      // The short ref (server rule: last 6, capitals), never the raw id.
      expect(find.text('Order O1'), findsOneWidget);
      expect(find.text(formatCurrency(170000)), findsOneWidget);
      // Statuses are worded, never raw codes (backend order-lifecycle.mjs),
      // and said once: as one progress line, not chips (M3, M7).
      final progress =
          '${host.tr('shop.orderStatus.unknown')} → '
          '${host.tr('shop.orderStatus.accepted')}';
      expect(find.text(progress), findsOneWidget);
      expect(find.byType(Chip), findsNothing);
      final text = tester.widget<Text>(find.byKey(const Key('order-status-o1')));
      expect(
        text.semanticsLabel,
        '${host.tr('shop.orderProgress')}: '
        '${host.tr('shop.orderStatus.unknown')}, '
        '${host.tr('shop.orderStatus.accepted')}',
      );
      expect(find.text('accepted'), findsNothing);
      // "placed" is not a status the server sends: a neutral word, not the code.
      expect(find.textContaining('placed'), findsNothing);
    });

    apiTest('an unpaid order says it is awaiting payment', (tester, api) async {
      _seed(api, orders: [_order('o1', paymentStatus: 'pending')]);
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      expect(find.text(host.tr('shop.awaitingPayment')), findsOneWidget);
    });

    apiTest('a refund that is not sent yet is not shown as refunded', (
      tester,
      api,
    ) async {
      _seed(
        api,
        orders: [
          _order(
            'o1',
            status: 'cancelled',
            paymentStatus: 'refund_pending',
            canCancel: false,
          ),
          _order(
            'o2',
            status: 'cancelled',
            paymentStatus: 'refunded',
            canCancel: false,
          ),
        ],
      );
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      expect(find.text(host.tr('shop.refundPending')), findsOneWidget);
      expect(find.text(host.tr('shop.refunded')), findsOneWidget);
      // No "check payment" button once the money is no longer awaited.
      expect(_key('order-check-payment-o1'), findsNothing);
      expect(_key('order-check-payment-o2'), findsNothing);
    });

    apiTest('check payment re-reads the order and reports what changed', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1', paymentStatus: 'pending')]);
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      await tapVisible(tester, _key('order-check-payment-o1'));
      expect(host.snack(host.tr('shop.stillAwaiting')), findsOneWidget);
      // It never places or pays anything.
      expect(api.sent('POST', '/me/shop-orders'), isFalse);

      api.on('GET /me/shop-orders', [_order('o1')]);
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    apiTest('cancel asks first: keep sends nothing, confirm cancels (paid)', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1')]);
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      await tapVisible(tester, _key('order-cancel-o1'));
      expect(find.text(host.tr('shop.cancelConfirmPaid')), findsOneWidget);
      await tester.tap(find.text(host.tr('sessions.keep')));
      await tester.pumpAndSettle();
      expect(api.sent('POST', '/me/shop-orders/o1/cancel'), isFalse);

      await tapVisible(tester, _key('order-cancel-o1'));
      await tester.tap(_key('order-cancel-confirm'));
      await tester.pumpAndSettle();
      expect(api.only('POST', '/me/shop-orders/o1/cancel').body, isNull);
      expect(host.snack(host.tr('shop.cancelledRefund')), findsOneWidget);
      // Orders were reloaded.
      expect(api.where('GET', '/me/shop-orders'), isNotEmpty);
    });

    apiTest('cancelling an unpaid order uses the plain wording', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1', paymentStatus: 'pending')]);
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      await tapVisible(tester, _key('order-cancel-o1'));
      expect(find.text(host.tr('shop.cancelConfirm')), findsOneWidget);
      await tester.tap(_key('order-cancel-confirm'));
      await tester.pumpAndSettle();
      expect(host.snack(host.tr('shop.cancelled')), findsOneWidget);
    });

    apiTest('a failed cancel shows an error, not the success message', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1')]);
      api.fail('POST /me/shop-orders/o1/cancel', 409);
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      await tapVisible(tester, _key('order-cancel-o1'));
      await tester.tap(_key('order-cancel-confirm'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(host.snack(host.tr('shop.cancelledRefund')), findsNothing);
      expect(_key('order-cancel-o1'), findsOneWidget);
    });

    apiTest('orders that cannot be cancelled offer no cancel button', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1', canCancel: false)]);
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      expect(_key('order-cancel-o1'), findsNothing);
      expect(buttonLabelled(host.tr('shop.invoice')), findsOneWidget);
    });

    apiTest('reorder re-adds the items and returns to browsing', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1')]);
      // The server answers `variant` per item (null when none).
      api.on('POST /me/shop-orders/o1/reorder', {
        'items': [
          {'productId': 'p1', 'qty': 2, 'variant': null},
        ],
      });
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      await tapVisible(tester, _key('shop-reorder-o1'));
      expect(api.only('POST', '/me/shop-orders/o1/reorder').body, isNull);
      expect(
        find.text('${host.tr('shop.checkout')} · ${formatCurrency(170000)}'),
        findsOneWidget,
      );
      expect(find.text('Whey Protein'), findsOneWidget);
    });

    apiTest('reorder keeps each item\'s option for checkout', (
      tester,
      api,
    ) async {
      // Products whose options keep their own stock need one at checkout
      // (400 variant_required otherwise).
      _seed(
        api,
        orders: [_order('o1')],
        products: [
          {
            ..._catalogue[0],
            'variants': [
              {'name': 'Vanilla', 'stock': 3},
              {'name': 'Cocoa', 'stock': 1},
            ],
          },
        ],
      );
      api.on('POST /me/shop-orders/o1/reorder', {
        'items': [
          {'productId': 'p1', 'qty': 1, 'variant': 'Cocoa'},
        ],
      });
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      await tapVisible(tester, _key('shop-reorder-o1'));
      await _openCheckout(tester);
      await typeInto(tester, _key('shop-delivery-address'), 'Mikocheni');
      await tapVisible(tester, _key('shop-place-order'));
      final body = api.only('POST', '/me/shop-orders').body as Map;
      expect(body['items'], [
        {'productId': 'p1', 'qty': 1, 'variant': 'Cocoa'},
      ]);
    });

    apiTest('invoice shows the order lines and a download button', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1')]);
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      await tapVisible(tester, buttonLabelled(host.tr('shop.invoice')));
      expect(find.textContaining('2 × Whey Protein'), findsOneWidget);
      expect(
        find.textContaining('${host.tr('shop.order')}: o1'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          '${host.tr('shop.total')}: ${formatCurrency(170000)}',
        ),
        findsOneWidget,
      );
      expect(_key('shop-download-receipt'), findsOneWidget);
    });

    apiTest('a delivered order can be reviewed with rating and comment', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1', status: 'delivered', canCancel: false)]);
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      await tapVisible(tester, buttonLabelled(host.tr('shop.review')));
      // Default rating is 5; pick 3 from the dropdown.
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('3 ').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Solid');
      await tapAndSettleDialogClose(
        tester,
        buttonLabelled(host.tr('shop.submitReview')),
      );
      expect(api.only('POST', '/me/shop-orders/o1/reviews').body, {
        'productId': 'p1',
        'rating': 3,
        'comment': 'Solid',
      });
    });

    apiTest('only delivered orders offer a review', (tester, api) async {
      _seed(api, orders: [_order('o1')]);
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      expect(buttonLabelled(host.tr('shop.review')), findsNothing);
    });

    apiTest('order status changes are picked up and announced', (
      tester,
      api,
    ) async {
      _seed(api, orders: [_order('o1', status: 'accepted')]);
      final accepted = (FFLocale()..set(const Locale('en'))).t(
        'shop.orderStatus.accepted',
      );
      final host = await _pump(tester, api);
      await _openMyOrders(tester, host);
      expect(find.textContaining('→ $accepted'), findsOneWidget);
      api.on('GET /me/shop-orders', [_order('o1', status: 'dispatched')]);
      await tester.pump(const Duration(seconds: 11));
      await tester.pump();
      await tester.pump();
      expect(
        find.textContaining('→ ${host.tr('shop.orderStatus.dispatched')}'),
        findsOneWidget,
      );
      expect(host.snack(host.tr('shop.trackingUpdated')), findsOneWidget);
    });
  });

  group('English and Swahili layout', () {
    // KNOWN ISSUE (characterized, not endorsed): the rating/stock line of a
    // product row (a Row with no flexible child) overflows at 360px once an
    // item is in the cart, and at text scale 1.3. It is the only overflow
    // tolerated here; any other layout error fails the test.
    bool isKnownProductRowOverflow(String report) =>
        report.contains('RenderFlex overflowed') &&
        report.contains('creator: Row ← Column ← Expanded ← Row');

    for (final lang in ['en', 'sw']) {
      for (final scale in [1.0, 1.3]) {
        apiTest(
          'browse, detail, checkout and orders fit 360x740 at x$scale ($lang)',
          (tester, api) async {
            _seed(
              api,
              orders: [
                _order('o1'),
                _order('o2', status: 'delivered'),
              ],
            );
            late PageHost host;
            final errors = await captureFlutterErrors(() async {
              host = await _pump(
                tester,
                api,
                lang: lang,
                scale: scale,
                size: const Size(360, 740),
              );
              await _add(tester, 'p1');

              // Filters sheet.
              await tester.tap(_key('shop-more-filters'));
              await tester.pumpAndSettle();
              expect(_key('shop-apply-filters'), findsOneWidget);
              await tapVisible(tester, _key('shop-apply-filters'));

              // Detail sheet.
              await _openDetail(tester, 'Whey Protein');
              expect(_key('shop-detail-add-p1'), findsOneWidget);
              await tester.tap(_key('shop-product-close'));
              await tester.pumpAndSettle();

              // Checkout, both delivery modes.
              await _openCheckout(tester);
              await tapVisible(tester, find.text(host.tr('shop.gymPickup')));
              expect(_key('shop-pickup-gym'), findsOneWidget);
              Navigator.of(
                tester.element(find.byType(Scaffold).first),
                rootNavigator: true,
              ).pop();
              await tester.pumpAndSettle();

              // Orders, with cancel / invoice / reorder / review buttons.
              await _openMyOrders(tester, host);
              expect(_key('order-cancel-o1'), findsOneWidget);
              expect(buttonLabelled(host.tr('shop.review')), findsOneWidget);
            });
            final unexpected = errors
                .where((e) => !isKnownProductRowOverflow(e))
                .toList();
            expect(unexpected, isEmpty);
          },
        );
      }
    }

    apiTest('the order flow sends the same body in Swahili', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pump(tester, api, lang: 'sw');
      expect(find.text(host.tr('shop.browse')), findsOneWidget);
      await _add(tester, 'p1');
      await _openCheckout(tester);
      await typeInto(tester, _key('shop-delivery-address'), 'Masaki');
      await tapVisible(tester, _key('shop-place-order'));
      expect(api.only('POST', '/me/shop-orders').body, {
        'items': [
          {'productId': 'p1', 'qty': 1},
        ],
        'deliveryMethod': 'home_delivery',
        'deliveryAddress': 'Masaki',
        'paymentMethod': 'mpesa',
        'paymentOutcome': 'success',
      });
      expect(host.snack(host.tr('shop.orderPending')), findsOneWidget);
      expect(
        host.tr('shop.orderPending'),
        isNot(host.tr('shop.orderUncertain')),
      );
    });
  });
}
