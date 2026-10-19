// Vendor tools · S1 gating: with the stock ledger off (or the options call
// failing) the vendor screens stay as they were; with it on, the entry
// points appear. Also pins the live-bug fix: with the ledger off an edit
// sends stock only when the vendor changed it (with stockSeen), and never
// variants[].stock.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

void main() {
  setUpAll(loadAppFonts);

  final lowProduct = stockProduct('p1', 'Whey', stock: 2, reorderLevel: 5);
  final okProduct = stockProduct('p2', 'Mat', stock: 40);
  const low = [
    {
      'productId': 'p1',
      'name': 'Whey',
      'variant': null,
      'stock': 2,
      'reorderLevel': 5,
    },
  ];

  Future<void> expectNoStockUi(WidgetTester tester, PageHost host) async {
    expect(find.byKey(const Key('vendor-filter-low')), findsNothing);
    expect(find.byKey(const Key('vendor-low-badge-p1')), findsNothing);
    expect(find.byKey(const Key('vendor-nav-low-badge')), findsNothing);
    await productMenu(tester, 'p1', host.tr('vendor.edit'));
    // The old form: comma-separated variants, no cost / reorder / rows.
    expect(find.byKey(const Key('vendor-product-variants')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-reorder')), findsNothing);
    expect(find.byKey(const Key('vendor-product-cost')), findsNothing);
    expect(find.byKey(const Key('variant-add')), findsNothing);
    expect(find.byKey(const Key('vendor-product-adjust')), findsNothing);
  }

  apiTest('stockLedger false: no stock UI, low list never asked', (
    tester,
    api,
  ) async {
    seedVendorHome(
      api,
      products: [lowProduct, okProduct],
      tools: {'stockLedger': false, 'canSeeCost': true},
      low: low,
    );
    final host = await pumpVendorHome(tester, api, user: vendorUser);
    expect(api.sent('GET', '/vendor/stock/low'), isFalse);
    // The menu has no stock items.
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('vendor-product-p1')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(host.tr('vendor.stock.adjust')), findsNothing);
    expect(find.text(host.tr('vendor.stock.history')), findsNothing);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    await expectNoStockUi(tester, host);
  });

  apiTest('options call failing: same as off, and no error shown', (
    tester,
    api,
  ) async {
    seedVendorHome(api, products: [lowProduct, okProduct], low: low);
    api.fail('GET /vendor/tools/options', 500);
    final host = await pumpVendorHome(tester, api);
    expect(find.byType(SnackBar), findsNothing);
    await expectNoStockUi(tester, host);
  });

  apiTest('flag off: editing sends no stock, variants as {name}', (
    tester,
    api,
  ) async {
    seedVendorHome(
      api,
      products: [
        stockProduct(
          'p1',
          'Whey',
          stock: 7,
          variants: [
            {'name': 'Vanilla', 'stock': 3},
            {'name': 'Cocoa', 'stock': 4},
          ],
        ),
      ],
    );
    final host = await pumpVendorHome(tester, api);
    await productMenu(tester, 'p1', host.tr('vendor.edit'));
    await tapVisible(tester, find.byKey(const Key('vendor-product-save')));
    final body = api.only('PUT', '/vendor/products/p1').body as Map;
    expect(body.containsKey('stock'), isFalse);
    expect(body.containsKey('stockSeen'), isFalse);
    expect(body['variants'], [
      {'name': 'Vanilla'},
      {'name': 'Cocoa'},
    ]);
    expect(body.containsKey('costTzs'), isFalse);
  });

  apiTest('flag off: a changed stock is sent with stockSeen', (
    tester,
    api,
  ) async {
    seedVendorHome(
      api,
      products: [
        stockProduct(
          'p1',
          'Whey',
          stock: 7,
          variants: [
            {'name': 'Vanilla', 'stock': 3},
          ],
        ),
      ],
    );
    final host = await pumpVendorHome(tester, api);
    await productMenu(tester, 'p1', host.tr('vendor.edit'));
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('vendor-product-stock')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.readOnly, isFalse);
    await typeInto(tester, find.byKey(const Key('vendor-product-stock')), '12');
    await tapVisible(tester, find.byKey(const Key('vendor-product-save')));
    final body = api.only('PUT', '/vendor/products/p1').body as Map;
    expect(body['stock'], 12);
    expect(body['stockSeen'], 7);
    expect(body['variants'], [
      {'name': 'Vanilla'},
    ]);
  });

  apiTest('flag off: 409 stock_changed shows the conflict and refreshes', (
    tester,
    api,
  ) async {
    seedVendorHome(api, products: [stockProduct('p1', 'Whey', stock: 7)]);
    api.fail('PUT /vendor/products/p1', 409, {
      'error': 'stock_changed',
      'currentStock': 5,
    });
    final host = await pumpVendorHome(tester, api);
    await productMenu(tester, 'p1', host.tr('vendor.edit'));
    await typeInto(tester, find.byKey(const Key('vendor-product-stock')), '9');
    await tapVisible(tester, find.byKey(const Key('vendor-product-save')));
    expect(host.snack(host.tr('vendor.stock.changed')), findsOneWidget);
    expect(api.sent('GET', '/vendor/products'), isTrue);
  });

  apiTest('flag off, Swahili: the conflict message is translated', (
    tester,
    api,
  ) async {
    seedVendorHome(api, products: [stockProduct('p1', 'Whey', stock: 7)]);
    api.fail('PUT /vendor/products/p1', 409, {
      'error': 'stock_changed',
      'currentStock': 5,
    });
    final host = await pumpVendorHome(tester, api, lang: 'sw');
    await productMenu(tester, 'p1', host.tr('vendor.edit'));
    await typeInto(tester, find.byKey(const Key('vendor-product-stock')), '9');
    await tapVisible(tester, find.byKey(const Key('vendor-product-save')));
    expect(
      host.snack('Stock imebadilika ulipokuwa ukihesabu. Hesabu tena.'),
      findsOneWidget,
    );
  });

  apiTest('flag on: filter, low badge, nav count and stock menu items', (
    tester,
    api,
  ) async {
    seedVendorHome(
      api,
      products: [lowProduct, okProduct],
      tools: ledgerOn,
      low: low,
    );
    final host = await pumpVendorHome(tester, api);
    expect(find.byKey(const Key('vendor-low-badge-p1')), findsOneWidget);
    expect(find.byKey(const Key('vendor-low-badge-p2')), findsNothing);
    expect(find.byKey(const Key('vendor-nav-low-badge')), findsWidgets);
    expect(
      find.text(host.tr('vendor.stock.lowFilter').replaceAll('{n}', '1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('vendor-filter-low')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vendor-product-p1')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-p2')), findsNothing);

    await tester.tap(find.byKey(const Key('vendor-filter-all')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vendor-product-p2')), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('vendor-product-p1')),
        matching: find.byType(PopupMenuButton<String>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(host.tr('vendor.stock.adjust')), findsOneWidget);
    expect(find.text(host.tr('vendor.stock.history')), findsOneWidget);
  });

  apiTest('filter=low starts on the low products', (tester, api) async {
    seedVendorHome(
      api,
      products: [lowProduct, okProduct],
      tools: ledgerOn,
      low: low,
    );
    await pumpVendorHome(tester, api, filter: 'low');
    expect(find.byKey(const Key('vendor-product-p1')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-p2')), findsNothing);
  });

  apiTest('low list failing: no badge, no filter, list still shown', (
    tester,
    api,
  ) async {
    seedVendorHome(api, products: [lowProduct, okProduct], tools: ledgerOn);
    api.fail('GET /vendor/stock/low', 500);
    await pumpVendorHome(tester, api);
    expect(find.byKey(const Key('vendor-product-p1')), findsOneWidget);
    expect(find.byKey(const Key('vendor-filter-low')), findsNothing);
    expect(find.byKey(const Key('vendor-nav-low-badge')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  apiTest('staff without products never ask for the low list', (
    tester,
    api,
  ) async {
    seedVendorHome(api, products: [lowProduct], tools: ledgerOn, low: low);
    await pumpVendorHome(
      tester,
      api,
      user: const {
        'id': 's1',
        'userType': 'vendor_staff',
        'vendorPermissions': ['orders'],
      },
    );
    expect(api.sent('GET', '/vendor/stock/low'), isFalse);
    expect(find.byKey(const Key('vendor-nav-products')), findsNothing);
  });
}
