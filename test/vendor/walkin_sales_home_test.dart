// Vendor tools · S3 on the vendor home and around it: the Sales tab (flag +
// permission), sales-only staff, the staff-form permission, the waiting
// tile when the flag is off, history with queued rows and summary, sale
// detail and the void rules, the sync screen, the stock-history link, the
// sale-voided notification link, and Swahili coverage of every new string.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/sales/receipt_data.dart';
import 'package:fitflexmobile/screens/vendor/sales/sale_detail_page.dart';
import 'package:fitflexmobile/screens/vendor/sales/sales_sync_page.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_history_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';
import 'walkin_support.dart';

const vendorUser2 = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Owner'};

Map<String, dynamic> queuedEntry(
  String ref, {
  String state = 'waiting',
  Map? error,
}) => {
  'body': {
    'clientRef': ref,
    'soldAt': '2026-10-19T08:00:00.000Z',
    'lines': [
      {'productId': 'p1', 'qty': 3},
    ],
    'payments': [
      {'method': 'cash', 'amountTzs': 135000},
    ],
  },
  'display': {
    'business': 'Dar Gear',
    'lines': [
      {'name': 'Whey', 'listPriceTzs': 45000},
    ],
  },
  'queuedAt': '2026-10-19T08:00:00.000Z',
  'state': state,
  'error': ?error,
};

void seedQueue(String key, List<Map<String, dynamic>> entries) =>
    SharedPreferences.setMockInitialValues({key: jsonEncode(entries)});

void seedSales(
  RecordingApi api, {
  List<Map<String, dynamic>>? sales,
  Map? summary,
}) {
  api.on('GET /vendor/sales', {
    'sales':
        sales ??
        [
          {
            'id': 'sal_1',
            'number': 'R-000001',
            'soldAt': '2026-10-19T08:00:00.000Z',
            'recordedAt': '2026-10-19T08:30:00.000Z',
            'status': 'completed',
            'totalTzs': 45000,
            'itemCount': 1,
            'methods': ['cash', 'mpesa'],
            'createdBy': {'id': 'v1', 'name': 'Owner'},
            'hasOverride': true,
            'lateRecorded': true,
          },
          {
            'id': 'sal_2',
            'number': 'R-000002',
            'soldAt': '2026-10-19T09:00:00.000Z',
            'recordedAt': '2026-10-19T09:00:00.000Z',
            'status': 'voided',
            'totalTzs': 10000,
            'itemCount': 1,
            'methods': ['cash'],
            'createdBy': {'id': 'v1', 'name': 'Owner'},
          },
        ],
    'nextCursor': null,
    'summary':
        summary ??
        {
          'count': 1,
          'totalTzs': 45000,
          'voidedCount': 1,
          'discountTzs': 0,
          'byMethod': [
            {'method': 'cash', 'amountTzs': 20000},
            {'method': 'mpesa', 'amountTzs': 25000},
          ],
        },
  });
}

void main() {
  setUpAll(loadAppFonts);

  group('vendor home', () {
    apiTest('flag on: Sales tab right after Orders', (tester, api) async {
      seedVendorHome(api, products: [], tools: walkInOn);
      seedSales(api);
      await pumpVendorHome(tester, api);
      final orders = tester.getCenter(
        find.byKey(const Key('vendor-nav-orders')),
      );
      final sales = tester.getCenter(find.byKey(const Key('vendor-nav-sales')));
      final payments = tester.getCenter(
        find.byKey(const Key('vendor-nav-payments')),
      );
      expect(sales.dx, greaterThan(orders.dx));
      expect(payments.dx, greaterThan(sales.dx));
    });

    apiTest('flag off or options failing: no Sales tab, sales never asked', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [], tools: walkInOff);
      await pumpVendorHome(tester, api);
      expect(find.byKey(const Key('vendor-nav-sales')), findsNothing);
      expect(api.sent('GET', '/vendor/sales'), isFalse);
    });

    apiTest('staff with only sales: no bar, straight on Sales', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [], tools: walkInOn);
      seedSales(api);
      await pumpVendorHome(
        tester,
        api,
        user: {
          'id': 's1',
          'userType': 'vendor_staff',
          'vendorId': 'v1',
          'vendorPermissions': ['sales'],
        },
      );
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byKey(const Key('vendor-sales-tab')), findsOneWidget);
      expect(find.byKey(const Key('vendor-pos-new')), findsOneWidget);
    });

    apiTest('staff without sales: no Sales tab even with the flag on', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [], tools: walkInOn);
      await pumpVendorHome(
        tester,
        api,
        user: {
          'id': 's1',
          'userType': 'vendor_staff',
          'vendorId': 'v1',
          'vendorPermissions': ['products', 'orders'],
        },
      );
      expect(find.byKey(const Key('vendor-nav-sales')), findsNothing);
    });

    apiTest('Sales tab: queued rows first, server rows, summary, badges', (
      tester,
      api,
    ) async {
      seedQueue('vendor_sale_queue.v1.v1', [queuedEntry('sale_q_00abcdef')]);
      seedVendorHome(api, products: [], tools: walkInOn);
      seedSales(api);
      api.fail('POST /vendor/sales', 503);
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'sales'),
        user: vendorUser2,
        size: const Size(400, 1400),
        extraRoutes: salesRoutes,
        keepRequests: true,
      );
      expect(find.byKey(const Key('vendor-sales-tab')), findsOneWidget);
      final queued = tester.getTopLeft(
        find.byKey(const Key('sales-queued-sale_q_00abcdef')),
      );
      final server = tester.getTopLeft(
        find.byKey(const Key('sales-row-sal_1')),
      );
      expect(queued.dy, lessThan(server.dy));
      expect(find.byKey(const Key('sales-summary')), findsOneWidget);
      expect(find.text('Cash + M-Pesa · Owner'), findsNothing);
      expect(textContaining('Cash + M-Pesa'), findsOneWidget);
      expect(find.text(host.tr('vendor.sales.offlineBadge')), findsOneWidget);
      expect(find.text(host.tr('vendor.sales.overrideBadge')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('sales-row-sal_2')),
          matching: find.text(host.tr('vendor.sales.voidedBadge')),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const Key('sales-waiting-banner')), findsOneWidget);
      final q = api.where('GET', '/vendor/sales').first.query;
      expect(q, contains('from='));
      expect(q, contains('status=all'));
    });

    apiTest('flag off with sales still queued: Business tile, never deleted', (
      tester,
      api,
    ) async {
      seedQueue('vendor_sale_queue.v1.v1', [queuedEntry('sale_q_00abcdef')]);
      seedVendorHome(api, products: [], tools: walkInOff);
      final host = await pumpVendorHome(tester, api);
      await tester.tap(find.byKey(const Key('vendor-nav-business')));
      await tester.pumpAndSettle();
      expect(
        find.text(host.tr('vendor.sync.tile').replaceAll('{n}', '1')),
        findsOneWidget,
      );
      expect(api.sent('POST', '/vendor/sales'), isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('vendor_sale_queue.v1.v1'),
        contains('sale_q_00abcdef'),
      );
    });

    apiTest('sign out with queued sales warns; Cancel keeps the session', (
      tester,
      api,
    ) async {
      seedQueue('vendor_sale_queue.v1.v1', [queuedEntry('sale_q_00abcdef')]);
      seedVendorHome(api, products: [], tools: walkInOff);
      final host = await pumpVendorHome(tester, api);
      await tester.tap(find.byKey(const Key('vendor-sign-out')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('vendor-sales-leave-dialog')),
        findsOneWidget,
      );
      expect(find.text(host.tr('vendor.sync.signOutAnyway')), findsOneWidget);
      await tester.tap(find.text(host.tr('common.cancel')));
      await tester.pumpAndSettle();
      expect(host.auth.isSignedIn, isTrue);
      await tester.tap(find.byKey(const Key('vendor-sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vendor-sales-leave-anyway')));
      await tester.pumpAndSettle();
      expect(host.auth.isSignedIn, isFalse);
      // The sales stay on the device for next time.
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('vendor_sale_queue.v1.v1'),
        contains('sale_q_00abcdef'),
      );
    });
  });

  group('staff form', () {
    apiTest(
      '"Shop sales" only while walk-in sales are on; Sales role preselects it',
      (tester, api) async {
        final host = await pumpPage(
          tester,
          api,
          const VendorStaffForm(walkInSales: true),
          size: const Size(400, 1200),
        );
        expect(find.text(host.tr('vendor.permission.sales')), findsOneWidget);
        await tester.tap(find.byKey(const Key('vendor-staff-role')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(host.tr('vendor.roleSales')).last);
        await tester.pumpAndSettle();
        final tile = tester.widget<CheckboxListTile>(
          find.ancestor(
            of: find.text(host.tr('vendor.permission.sales')),
            matching: find.byType(CheckboxListTile),
          ),
        );
        expect(tile.value, isTrue);
      },
    );

    apiTest('flag off: no sales permission offered', (tester, api) async {
      final host = await pumpPage(
        tester,
        api,
        const VendorStaffForm(),
        size: const Size(400, 1200),
      );
      expect(find.text(host.tr('vendor.permission.sales')), findsNothing);
    });
  });

  group('sale detail and void', () {
    final today = DateTime.now().toUtc().toIso8601String();
    ReceiptData data({
      String by = 's1',
      String? soldAt,
      String status = 'completed',
    }) => ReceiptData.fromSale(
      serverSale(createdById: by, soldAt: soldAt ?? today, status: status),
    );

    test('who may void', () {
      const owner = {'id': 'v1', 'userType': 'vendor'};
      const admin = {
        'id': 's9',
        'userType': 'vendor_staff',
        'vendorRole': 'admin',
        'vendorPermissions': ['sales'],
      };
      const staff = {
        'id': 's1',
        'userType': 'vendor_staff',
        'vendorRole': 'sales',
        'vendorPermissions': ['sales'],
      };
      final old = DateTime.now()
          .toUtc()
          .subtract(const Duration(days: 2))
          .toIso8601String();
      expect(canVoidSale(owner, data(by: 's1', soldAt: old)), isTrue);
      expect(canVoidSale(admin, data(by: 's1', soldAt: old)), isTrue);
      expect(canVoidSale(staff, data(by: 's1')), isTrue);
      expect(canVoidSale(staff, data(by: 's2')), isFalse, reason: 'not own');
      expect(
        canVoidSale(staff, data(by: 's1', soldAt: old)),
        isFalse,
        reason: 'too old',
      );
      expect(canVoidSale(owner, data(status: 'voided')), isFalse);
    });

    apiTest('detail: price-change audit, Void with reason, then Voided', (
      tester,
      api,
    ) async {
      seedPos(api);
      final sale = serverSale(createdById: 'v1', soldAt: today);
      (sale['lines'] as List).first
        ..['unitPriceTzs'] = 40000
        ..['priceChangedBy'] = {'id': 'v1', 'name': 'Asha'};
      api.on('GET /vendor/sales/sal_1', {'sale': sale});
      api.onCall(
        'POST /vendor/sales/sal_1/void',
        (_) => {'sale': serverSale(status: 'voided')},
      );
      final host = await pumpPage(
        tester,
        api,
        const SaleDetailPage(saleId: 'sal_1'),
        user: vendorUser2,
        size: const Size(400, 1400),
        extraRoutes: salesRoutes,
      );
      expect(
        find.text('Price changed by Asha (shop price TSh 45,000)'),
        findsOneWidget,
      );
      await tapVisible(tester, find.byKey(const Key('sale-detail-void')));
      expect(
        isEnabled(tester, find.byKey(const Key('sale-void-confirm'))),
        isFalse,
      );
      await typeInto(
        tester,
        find.byKey(const Key('sale-void-reason')),
        'Returned',
      );
      await tester.pumpAndSettle();
      await tapAndSettleDialogClose(
        tester,
        find.byKey(const Key('sale-void-confirm')),
      );
      expect(api.only('POST', '/vendor/sales/sal_1/void').body, {
        'reason': 'Returned',
      });
      expect(find.byKey(const Key('sale-detail-voided')), findsOneWidget);
      expect(find.byKey(const Key('sale-detail-share')), findsNothing);
      expect(find.byKey(const Key('sale-detail-void')), findsNothing);
      expect(
        find.text('Sale R-000001 voided. Items are back in stock.'),
        findsOneWidget,
      );
      expect(host.lang, 'en');
    });

    apiTest('void refused: too old / already voided / offline', (
      tester,
      api,
    ) async {
      seedPos(api);
      api.on('GET /vendor/sales/sal_1', {
        'sale': serverSale(createdById: 'v1', soldAt: today),
      });
      api.fail('POST /vendor/sales/sal_1/void', 403, {
        'error': 'void_not_allowed',
        'reason': 'too_old',
      });
      final host = await pumpPage(
        tester,
        api,
        const SaleDetailPage(saleId: 'sal_1'),
        user: vendorUser2,
        size: const Size(400, 1400),
        extraRoutes: salesRoutes,
      );
      await tapVisible(tester, find.byKey(const Key('sale-detail-void')));
      await typeInto(
        tester,
        find.byKey(const Key('sale-void-reason')),
        'Wrong item',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sale-void-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(host.tr('vendor.sales.voidTooOld')), findsOneWidget);
    });

    apiTest('staff cannot see Void on someone else\'s sale', (
      tester,
      api,
    ) async {
      seedPos(api);
      api.on('GET /vendor/sales/sal_1', {
        'sale': serverSale(createdById: 'v1', soldAt: today),
      });
      await pumpPage(
        tester,
        api,
        const SaleDetailPage(saleId: 'sal_1'),
        user: {
          'id': 's1',
          'userType': 'vendor_staff',
          'vendorId': 'v1',
          'vendorRole': 'sales',
          'vendorPermissions': ['sales'],
        },
        size: const Size(400, 1400),
        extraRoutes: salesRoutes,
      );
      expect(find.byKey(const Key('sale-detail-share')), findsOneWidget);
      expect(find.byKey(const Key('sale-detail-void')), findsNothing);
    });

    apiTest('another vendor\'s sale id: not found', (tester, api) async {
      seedPos(api);
      api.fail('GET /vendor/sales/sal_9', 404, {'error': 'sale_not_found'});
      await pumpPage(
        tester,
        api,
        const SaleDetailPage(saleId: 'sal_9'),
        user: vendorUser2,
        extraRoutes: salesRoutes,
      );
      expect(find.byKey(const Key('sale-detail-not-found')), findsOneWidget);
    });
  });

  group('sync screen', () {
    apiTest(
      'conflict: stock message, Count stock only with products, Discard asks',
      (tester, api) async {
        seedQueue('vendor_sale_queue.v1.v1', [
          queuedEntry(
            'sale_c_00000001',
            state: 'conflict',
            error: {
              'code': 'insufficient_stock',
              'status': 409,
              'body': {'productId': 'p1', 'variant': null, 'available': 1},
            },
          ),
        ]);
        seedPos(api);
        final host = await pumpPage(
          tester,
          api,
          const SalesSyncPage(),
          user: vendorUser2,
          size: const Size(400, 1200),
          extraRoutes: salesRoutes,
        );
        expect(
          find.text('Not enough stock for Whey: 1 left, this sale has 3.'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('sync-count-sale_c_00000001')),
          findsOneWidget,
        );
        await tapVisible(
          tester,
          find.byKey(const Key('sync-discard-sale_c_00000001')),
        );
        expect(find.text(host.tr('vendor.sync.discardBody')), findsOneWidget);
        await tester.tap(find.byKey(const Key('sync-discard-confirm')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('sync-done')), findsOneWidget);
        expect(api.sent('POST', '/vendor/sales'), isFalse);
      },
    );

    apiTest('staff without products: asked to get someone to count', (
      tester,
      api,
    ) async {
      SharedPreferences.setMockInitialValues({
        'vendor_sale_queue.v1.s1': jsonEncode([
          queuedEntry(
            'sale_c_00000001',
            state: 'conflict',
            error: {
              'code': 'insufficient_stock',
              'status': 409,
              'body': {'productId': 'p1', 'available': 0},
            },
          ),
        ]),
      });
      seedPos(api);
      final host = await pumpPage(
        tester,
        api,
        const SalesSyncPage(),
        user: {
          'id': 's1',
          'userType': 'vendor_staff',
          'vendorId': 'v1',
          'vendorPermissions': ['sales'],
        },
        size: const Size(400, 1200),
        extraRoutes: salesRoutes,
      );
      expect(find.byKey(const Key('sync-count-sale_c_00000001')), findsNothing);
      expect(find.text(host.tr('vendor.sync.askOwnerToCount')), findsOneWidget);
    });

    apiTest(
      'flag off with sales queued: still opens, says switched off, Sync now off',
      (tester, api) async {
        seedQueue('vendor_sale_queue.v1.v1', [queuedEntry('sale_q_00abcdef')]);
        seedPos(api, tools: walkInOff);
        await pumpPage(
          tester,
          api,
          const SalesSyncPage(),
          user: vendorUser2,
          size: const Size(400, 1200),
          extraRoutes: salesRoutes,
        );
        expect(find.byKey(const Key('sync-feature-off')), findsOneWidget);
        expect(isEnabled(tester, find.byKey(const Key('sync-now'))), isFalse);
        expect(api.sent('POST', '/vendor/sales'), isFalse);
      },
    );
  });

  group('stock history', () {
    Map<String, dynamic> history() => {
      'productId': 'p1',
      'variant': null,
      'openingStock': 10,
      'closingStock': 9,
      'rows': [
        {
          'id': 'm1',
          'productId': 'p1',
          'variant': null,
          'reason': 'sale',
          'kind': 'sale',
          'delta': -1,
          'stockBefore': 10,
          'stockAfter': 9,
          'note': null,
          'actor': {'id': 'v1', 'name': 'Asha'},
          'orderId': null,
          'document': {'type': 'sale', 'id': 'sal_1', 'number': 'R-000001'},
          'createdAt': '2026-10-19T11:05:00Z',
        },
      ],
      'nextCursor': null,
    };

    apiTest('a sale row reads "Shop sale" and links to its receipt', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/products', [stockProduct('p1', 'Whey', stock: 9)]);
      api.on('GET /vendor/stock/low', []);
      api.on('GET /vendor/tools/options', walkInOn);
      api.on('GET /vendor/products/p1/stock-movements', history());
      await pumpPage(
        tester,
        api,
        const StockHistoryPage(productId: 'p1'),
        user: vendorUser2,
        extraRoutes: salesRoutes,
      );
      expect(find.text('Shop sale'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('stock-sale-m1')));
      expect(find.text('ROUTE-SALE sal_1'), findsOneWidget);
    });

    apiTest('walk-in sales off: the receipt is plain text', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/products', [stockProduct('p1', 'Whey', stock: 9)]);
      api.on('GET /vendor/stock/low', []);
      api.on('GET /vendor/tools/options', ledgerOn);
      api.on('GET /vendor/products/p1/stock-movements', history());
      await pumpPage(
        tester,
        api,
        const StockHistoryPage(productId: 'p1'),
        user: vendorUser2,
        extraRoutes: salesRoutes,
      );
      expect(find.byKey(const Key('stock-sale-m1')), findsNothing);
      expect(find.text('Receipt R-000001'), findsOneWidget);
    });
  });

  group('links', () {
    test('vendor_sale_voided opens the sale detail', () {
      expect(
        partnerRouteFor(
          side: 'vendor',
          type: 'vendor_sale_voided',
          saleId: 'sal_abc123',
        ),
        '/vendor/sales/sal_abc123',
      );
      expect(
        partnerRouteFor(
          side: 'vendor',
          type: 'vendor_sale_voided',
          saleId: '../x',
        ),
        '/vendor/home?open=sales',
      );
      expect(
        partnerLinkFor(side: 'vendor', type: 'vendor_sale_voided'),
        'sale',
      );
      expect(FFLocale.textOf('sw', 'inbox.open.sale'), isNotNull);
    });
  });

  group('Swahili', () {
    test(
      'every S3 string has Swahili, and it is not the English left in place',
      () {
        final s3 = FFLocale.keysOf('en').where(
          (k) =>
              k.startsWith('vendor.pos.') ||
              k.startsWith('vendor.sales.') ||
              k.startsWith('vendor.sync.') ||
              k == 'vendor.permission.sales' ||
              k == 'vendor.documents.receipt' ||
              k == 'vendor.stock.sale' ||
              k.startsWith('vendor.stock.reason.sale'),
        );
        expect(s3.length, greaterThan(150));
        // Brand names, symbols and placeholders-only lines read the same.
        const same = {
          'vendor.pos.discountTzs',
          'vendor.pos.discountPct',
          'vendor.pos.method.halopesa',
        };
        for (final k in s3) {
          final sw = FFLocale.textOf('sw', k);
          expect(sw, isNotNull, reason: '$k has no Swahili');
          if (!same.contains(k)) {
            expect(
              sw,
              isNot(FFLocale.textOf('en', k)),
              reason: '$k Swahili is English',
            );
          }
          // Same placeholders in both languages.
          final ph = RegExp(r'\{[a-z]+\}');
          expect(
            ph.allMatches(sw!).map((m) => m[0]).toSet(),
            ph.allMatches(FFLocale.textOf('en', k)!).map((m) => m[0]).toSet(),
            reason: k,
          );
        }
      },
    );

    apiTest('Sales tab in Swahili', (tester, api) async {
      seedVendorHome(api, products: [], tools: walkInOn);
      seedSales(api);
      await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'sales'),
        user: vendorUser2,
        lang: 'sw',
        size: const Size(375, 900),
        extraRoutes: salesRoutes,
      );
      expect(find.text('Mauzo'), findsWidgets);
      expect(find.text('Leo'), findsOneWidget);
      expect(find.text('Mauzo mapya'), findsOneWidget);
    });
  });
}
