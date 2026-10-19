// Vendor tools · S1: variant rows and the product form with the stock
// ledger on — what is sent on create and on edit (never stock on edit),
// validation, removing a variant that has stock, and cost price only for
// those allowed to see it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/stock/variant_rows_editor.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

VariantDraft _draft(String name, {int? stored, String stock = ''}) =>
    VariantDraft(original: stored == null ? null : name, storedStock: stored)
      ..name.text = name
      ..stock.text = stock;

Finder _k(String key) => find.byKey(Key(key));

void main() {
  setUpAll(loadAppFonts);

  group('variantsPayload', () {
    test('create sends stock; empty cost and reorder send null', () {
      final rows = [
        _draft('Small', stock: '5')..cost.text = '1000',
        _draft('Large')..reorder.text = '2',
      ];
      expect(variantsPayload(rows, creating: true, withCost: true), [
        {'name': 'Small', 'stock': 5, 'costTzs': 1000, 'reorderLevel': null},
        {'name': 'Large', 'stock': 0, 'costTzs': null, 'reorderLevel': 2},
      ]);
    });

    test('edit never sends stock', () {
      final rows = [_draft('Small', stored: 5, stock: '9')];
      final out = variantsPayload(rows, creating: false, withCost: true);
      expect(out.single.containsKey('stock'), isFalse);
    });

    test('without cost permission no costTzs key at all', () {
      final rows = [_draft('Small', stock: '1')..cost.text = '500'];
      final out = variantsPayload(rows, creating: true, withCost: false);
      expect(out.single.containsKey('costTzs'), isFalse);
    });
  });

  group('validateVariants', () {
    test('empty and duplicate (any case) names', () {
      final errors = validateVariants([
        _draft('Small'),
        _draft(' '),
        _draft('small '),
      ]);
      expect(errors, {
        0: 'vendor.variant.duplicateName',
        1: 'vendor.variant.nameRequired',
        2: 'vendor.variant.duplicateName',
      });
    });

    test('renaming a stored variant that has stock is refused', () {
      final row = _draft('Small', stored: 4)..name.text = 'Tiny';
      expect(validateVariants([row]), {0: 'vendor.variant.removeHasStock'});
      final empty = _draft('Large', stored: 0)..name.text = 'Big';
      expect(validateVariants([empty]), isEmpty);
    });
  });

  group('product form, ledger on', () {
    apiTest('create: rows with starting stock; total shown; body exact', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [], tools: ledgerOn);
      final host = await pumpVendorHome(tester, api);
      await tester.tap(_k('vendor-add-product'));
      await tester.pumpAndSettle();
      expect(_k('vendor-product-variants'), findsNothing);

      await typeInto(tester, _k('vendor-product-name'), 'Tee');
      await typeInto(tester, _k('vendor-product-price'), '20000');
      await typeInto(tester, _k('vendor-product-cost'), '12000');
      await typeInto(tester, _k('vendor-product-reorder'), '3');
      await tapVisible(tester, _k('variant-add'));
      await typeInto(tester, _k('variant-name-0'), 'Small');
      await typeInto(tester, _k('variant-stock-0'), '5');
      await tapVisible(tester, _k('variant-add'));
      await typeInto(tester, _k('variant-name-1'), 'Large');
      await typeInto(tester, _k('variant-stock-1'), '3');
      await tester.pumpAndSettle();
      expect(textOf(tester, _k('vendor-product-stock')), '8');
      expect(
        find.text(host.tr('vendor.stock.totalFromVariants')),
        findsOneWidget,
      );
      await tapVisible(tester, _k('vendor-product-save'));

      final body = api.only('POST', '/vendor/products').body as Map;
      expect(body['stock'], 8);
      expect(body['costTzs'], 12000);
      expect(body['reorderLevel'], 3);
      expect(body['variants'], [
        {'name': 'Small', 'stock': 5, 'costTzs': null, 'reorderLevel': null},
        {'name': 'Large', 'stock': 3, 'costTzs': null, 'reorderLevel': null},
      ]);
      expect(host.snack(host.tr('vendor.productSaved')), findsOneWidget);
    });

    apiTest('edit: stock read-only, PUT has no stock anywhere', (
      tester,
      api,
    ) async {
      seedVendorHome(
        api,
        tools: ledgerOn,
        products: [
          stockProduct(
            'p1',
            'Tee',
            stock: 8,
            costTzs: 9000,
            reorderLevel: 2,
            variants: [
              {'name': 'Small', 'stock': 5, 'costTzs': null},
              {'name': 'Large', 'stock': 3, 'reorderLevel': 1},
            ],
          ),
        ],
      );
      final host = await pumpVendorHome(tester, api);
      await productMenu(tester, 'p1', host.tr('vendor.edit'));
      expect(_k('variant-stock-0'), findsNothing);
      expect(tester.widget<Text>(_k('variant-stock-value-0')).data, '5');
      expect(_k('variant-adjust-0'), findsOneWidget);
      expect(_k('vendor-product-adjust'), findsOneWidget);
      final stockField = tester.widget<TextField>(
        find.descendant(
          of: _k('vendor-product-stock'),
          matching: find.byType(TextField),
        ),
      );
      expect(stockField.readOnly, isTrue);

      // A new variant shows no stock field and says it starts at 0.
      await tapVisible(tester, _k('variant-add'));
      await typeInto(tester, _k('variant-name-2'), 'Medium');
      expect(_k('variant-stock-2'), findsNothing);
      expect(_k('variant-new-zero'), findsOneWidget);

      await typeInto(tester, _k('vendor-product-reorder'), '4');
      await tapVisible(tester, _k('vendor-product-save'));
      final body = api.only('PUT', '/vendor/products/p1').body as Map;
      expect(body.containsKey('stock'), isFalse);
      expect(body['reorderLevel'], 4);
      expect(body['costTzs'], 9000);
      for (final v in body['variants'] as List) {
        expect((v as Map).containsKey('stock'), isFalse, reason: '$v');
      }
      expect((body['variants'] as List).map((v) => v['name']), [
        'Small',
        'Large',
        'Medium',
      ]);
    });

    apiTest('empty / duplicate names: inline errors, nothing sent', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [], tools: ledgerOn);
      final host = await pumpVendorHome(tester, api);
      await tester.tap(_k('vendor-add-product'));
      await tester.pumpAndSettle();
      await typeInto(tester, _k('vendor-product-name'), 'Tee');
      await typeInto(tester, _k('vendor-product-price'), '20000');
      await tapVisible(tester, _k('variant-add'));
      await tapVisible(tester, _k('variant-add'));
      await typeInto(tester, _k('variant-name-0'), 'Red');
      await tapVisible(tester, _k('vendor-product-save'));
      expect(find.text(host.tr('vendor.variant.nameRequired')), findsOneWidget);
      await typeInto(tester, _k('variant-name-1'), 'red');
      await tapVisible(tester, _k('vendor-product-save'));
      expect(
        find.text(host.tr('vendor.variant.duplicateName')),
        findsNWidgets(2),
      );
      expect(api.sent('POST', '/vendor/products'), isFalse);
    });

    apiTest('removing a variant with stock warns and keeps it', (
      tester,
      api,
    ) async {
      seedVendorHome(
        api,
        tools: ledgerOn,
        products: [
          stockProduct(
            'p1',
            'Tee',
            stock: 5,
            variants: [
              {'name': 'Small', 'stock': 5},
              {'name': 'Large', 'stock': 0},
            ],
          ),
        ],
      );
      final host = await pumpVendorHome(tester, api);
      await productMenu(tester, 'p1', host.tr('vendor.edit'));
      await tapVisible(tester, _k('variant-remove-0'));
      expect(_k('variant-has-stock-0'), findsOneWidget);
      expect(_k('variant-name-0'), findsOneWidget);
      // An empty one goes.
      await tapVisible(tester, _k('variant-remove-1'));
      expect(_k('variant-row-1'), findsNothing);
      // Save is held back while the warning stands.
      await tapVisible(tester, _k('vendor-product-save'));
      expect(api.sent('PUT', '/vendor/products/p1'), isFalse);
    });

    apiTest('server refusals stay in the open form with values kept', (
      tester,
      api,
    ) async {
      seedVendorHome(
        api,
        tools: ledgerOn,
        products: [
          stockProduct(
            'p1',
            'Tee',
            variants: [
              {'name': 'Small', 'stock': 0},
            ],
          ),
        ],
      );
      api.fail('PUT /vendor/products/p1', 409, {
        'error': 'variant_has_reservations',
        'variant': 'Small',
      });
      final host = await pumpVendorHome(tester, api);
      await productMenu(tester, 'p1', host.tr('vendor.edit'));
      await typeInto(tester, _k('vendor-product-reorder'), '6');
      await tapVisible(tester, _k('variant-remove-0'));
      await tapVisible(tester, _k('vendor-product-save'));
      expect(
        find.text(
          host
              .tr('vendor.variant.hasReservations')
              .replaceAll('{name}', 'Small'),
        ),
        findsOneWidget,
      );
      expect(textOf(tester, _k('vendor-product-reorder')), '6');
      expect(_k('vendor-product-save'), findsOneWidget);
    });

    apiTest('cost_forbidden (stale options) is explained in the form', (
      tester,
      api,
    ) async {
      seedVendorHome(
        api,
        tools: ledgerOn,
        products: [stockProduct('p1', 'Tee', costTzs: 100)],
      );
      api.fail('PUT /vendor/products/p1', 403, {'error': 'cost_forbidden'});
      final host = await pumpVendorHome(tester, api);
      await productMenu(tester, 'p1', host.tr('vendor.edit'));
      await tapVisible(tester, _k('vendor-product-save'));
      expect(find.text(host.tr('vendor.costForbidden')), findsOneWidget);
      expect(_k('vendor-product-save'), findsOneWidget);
    });

    apiTest('stock_changed on save: message, new count shown, form open', (
      tester,
      api,
    ) async {
      seedVendorHome(
        api,
        tools: ledgerOn,
        products: [
          stockProduct(
            'p1',
            'Tee',
            variants: [
              {'name': 'Small', 'stock': 2},
            ],
          ),
        ],
      );
      api.fail('PUT /vendor/products/p1', 409, {
        'error': 'stock_changed',
        'currentStock': 1,
        'variant': 'Small',
      });
      final host = await pumpVendorHome(tester, api);
      await productMenu(tester, 'p1', host.tr('vendor.edit'));
      await tapVisible(tester, _k('vendor-product-save'));
      expect(find.text(host.tr('vendor.stock.changedForm')), findsOneWidget);
      expect(tester.widget<Text>(_k('variant-stock-value-0')).data, '1');
      expect(_k('vendor-product-save'), findsOneWidget);
    });

    apiTest('no cost permission: no cost fields, costTzs never sent', (
      tester,
      api,
    ) async {
      seedVendorHome(
        api,
        tools: ledgerOnNoCost,
        products: [
          stockProduct(
            'p1',
            'Tee',
            variants: [
              {'name': 'Small', 'stock': 2},
            ],
          ),
        ],
      );
      final host = await pumpVendorHome(tester, api);
      await productMenu(tester, 'p1', host.tr('vendor.edit'));
      expect(_k('vendor-product-cost'), findsNothing);
      expect(_k('variant-cost-0'), findsNothing);
      expect(find.text(host.tr('vendor.costPrice')), findsNothing);
      expect(_k('vendor-product-reorder'), findsOneWidget);
      expect(_k('variant-reorder-0'), findsOneWidget);
      await tapVisible(tester, _k('vendor-product-save'));
      final body = api.only('PUT', '/vendor/products/p1').body as Map;
      expect(body.containsKey('costTzs'), isFalse);
      expect((body['variants'] as List).single.containsKey('costTzs'), isFalse);
    });

    apiTest('adjusting from the form updates its read-only stock', (
      tester,
      api,
    ) async {
      final product = stockProduct('p1', 'Whey', stock: 10);
      seedVendorHome(api, tools: ledgerOn, products: [product]);
      api.on('POST /vendor/products/p1/stock-adjustments', {
        'movement': {'stockBefore': 10, 'stockAfter': 14, 'delta': 4},
        'product': {'id': 'p1', 'stock': 14, 'variants': []},
      });
      final host = await pumpVendorHome(tester, api);
      await productMenu(tester, 'p1', host.tr('vendor.edit'));
      await tapVisible(tester, _k('vendor-product-adjust'));
      await tapVisible(tester, _k('adjust-reason-restock'));
      await typeInto(tester, _k('adjust-quantity'), '4');
      await tester.pumpAndSettle();
      await tapVisible(tester, _k('adjust-save'));
      expect(textOf(tester, _k('vendor-product-stock')), '14');
      expect(find.text('Stock updated: 10 → 14'), findsOneWidget);
    });

    apiTest('Swahili, 375 wide, 2x text: form rows stack, no overflow', (
      tester,
      api,
    ) async {
      seedVendorHome(
        api,
        tools: ledgerOn,
        products: [
          stockProduct(
            'p1',
            'Tee',
            variants: [
              {'name': 'Small', 'stock': 2},
            ],
          ),
        ],
      );
      late PageHost host;
      final overflow = await captureFlutterErrors(() async {
        host = await pumpPage(
          tester,
          api,
          const VendorHomePage(),
          user: vendorUser,
          lang: 'sw',
          textScale: 2,
          size: const Size(375, 800),
        );
        await productMenu(tester, 'p1', host.tr('vendor.edit'));
        await tester.ensureVisible(_k('variant-reorder-0'));
        await tester.pumpAndSettle();
      });
      expect(overflow.where((e) => e.contains('overflowed')), isEmpty);
      // Two-up rows stack at this size: cost sits above reorder level.
      expect(
        tester.getTopLeft(_k('variant-reorder-0')).dy,
        greaterThan(tester.getTopLeft(_k('variant-cost-0')).dy),
      );
      expect(find.text('Kiwango cha kuagiza tena'), findsWidgets);
    });
  });
}
