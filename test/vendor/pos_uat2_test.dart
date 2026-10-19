// Vendor tools · S3 UAT round 2 (2026-10-20): D8 root cause (unfocus before
// disabling fields), offline cold start on the last-known options (kept 7
// days, live update when the server answers), the kept "suspended" state, a
// kept cart checked against today's stock, and the minor items (Escape,
// at-limit feedback, one suspended notice, offline wording).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/sales/pos_page.dart';
import 'package:fitflexmobile/screens/vendor/sales/sale_detail_page.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';
import 'walkin_support.dart';

const owner = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Asha'};

bool anyFieldFocused(WidgetTester tester) => tester
    .widgetList<EditableText>(find.byType(EditableText))
    .any((e) => e.focusNode.hasFocus);

String keptOptions(
  Map<String, dynamic> options, {
  Duration age = const Duration(days: 1),
}) => jsonEncode({
  'at': DateTime.now().toUtc().subtract(age).toIso8601String(),
  'options': options,
});

void main() {
  setUpAll(loadAppFonts);

  group('D8: fields let go of focus before they are disabled', () {
    apiTest('payment sheet: Complete with the amount field focused', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      seedPos(api);
      api.onCall('POST /vendor/sales', (_) => {'sale': serverSale()});
      final hold = api.hold('POST /vendor/sales');
      await pumpPage(
        tester,
        api,
        const PosPage(),
        user: owner,
        size: const Size(400, 900),
        extraRoutes: salesRoutes,
      );
      await tester.tap(find.byKey(const Key('pos-product-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-charge')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-amount-0')));
      await tester.pump();
      expect(anyFieldFocused(tester), isTrue);
      // Was the field still enabled when focus left it? (Web semantics throws
      // when a focused field is disabled first — the D8 root cause.)
      final amount = find.descendant(
        of: find.byKey(const Key('pos-amount-0')),
        matching: find.byType(TextField),
      );
      bool? enabledWhenFocusLeft;
      void watch() {
        if (enabledWhenFocusLeft == null && !anyFieldFocused(tester)) {
          enabledWhenFocusLeft = tester.widget<TextField>(amount).enabled;
        }
      }

      FocusManager.instance.addListener(watch);
      await tester.tap(find.byKey(const Key('pos-complete')));
      await tester.pump();
      FocusManager.instance.removeListener(watch);
      expect(enabledWhenFocusLeft, isTrue);
      expect(tester.widget<TextField>(amount).enabled, isFalse);
      expect(anyFieldFocused(tester), isFalse);
      hold.complete();
      await tester.pumpAndSettle();
      expect(textContaining('ROUTE-RECEIPT'), findsOneWidget);
      handle.dispose();
    });

    apiTest('void dialog: Void with the reason focused', (tester, api) async {
      final handle = tester.ensureSemantics();
      seedPos(api);
      api.on('GET /vendor/sales/sal_1', {
        'sale': serverSale(
          createdById: 'v1',
          soldAt: DateTime.now().toUtc().toIso8601String(),
        ),
      });
      api.onCall(
        'POST /vendor/sales/sal_1/void',
        (_) => {'sale': serverSale(status: 'voided')},
      );
      final hold = api.hold('POST /vendor/sales/sal_1/void');
      await pumpPage(
        tester,
        api,
        const SaleDetailPage(saleId: 'sal_1'),
        user: owner,
        size: const Size(400, 1400),
        extraRoutes: salesRoutes,
      );
      await tester.tap(find.byKey(const Key('sale-detail-void')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sale-void-reason')));
      await tester.enterText(
        find.byKey(const Key('sale-void-reason')),
        'Returned',
      );
      await tester.pump();
      expect(anyFieldFocused(tester), isTrue);
      final reason = find.descendant(
        of: find.byKey(const Key('sale-void-reason')),
        matching: find.byType(TextField),
      );
      bool? enabledWhenFocusLeft;
      void watch() {
        if (enabledWhenFocusLeft == null && !anyFieldFocused(tester)) {
          enabledWhenFocusLeft = tester.widget<TextField>(reason).enabled;
        }
      }

      FocusManager.instance.addListener(watch);
      await tester.tap(find.byKey(const Key('sale-void-confirm')));
      await tester.pump();
      FocusManager.instance.removeListener(watch);
      expect(enabledWhenFocusLeft, isTrue);
      expect(anyFieldFocused(tester), isFalse);
      hold.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('sale-detail-voided')), findsOneWidget);
      handle.dispose();
    });
  });

  group('last-known options', () {
    late RecordingApi api;
    late ApiClient client;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      api = RecordingApi();
      client = ApiClient(baseUrl: 'http://fixtures.local')..setToken('t');
    });

    test(
      'kept on success; used offline under 7 days; refused answer = off',
      () async {
        await api.run(() async {
          api.on('GET /vendor/tools/options', walkInOn);
          final live = await VendorToolsOptions.load(client, 't', user: owner);
          expect(live.walkInSales, isTrue);
          expect(live.fromCache, isFalse);
          final prefs = await SharedPreferences.getInstance();
          expect(
            prefs.getString('vendor_tools_options.v1.v1'),
            contains('walkInSales'),
          );

          api.onCall(
            'GET /vendor/tools/options',
            (_) => throw http.ClientException('offline'),
          );
          final offline = await VendorToolsOptions.load(
            client,
            't',
            user: owner,
            refresh: true,
          );
          expect(offline.walkInSales, isTrue);
          expect(offline.fromCache, isTrue);

          // A refusal from the server is not "offline": fail closed.
          api.fail('GET /vendor/tools/options', 403, {'error': 'forbidden'});
          final refused = await VendorToolsOptions.load(
            client,
            't',
            user: owner,
            refresh: true,
          );
          expect(refused.walkInSales, isFalse);
        });
      },
    );

    test('older than 7 days, or another person: fail closed', () async {
      await api.run(() async {
        SharedPreferences.setMockInitialValues({
          'vendor_tools_options.v1.v1': keptOptions(
            walkInOn,
            age: const Duration(days: 8),
          ),
          'vendor_tools_options.v1.s9': keptOptions(walkInOn),
        });
        api.onCall(
          'GET /vendor/tools/options',
          (_) => throw http.ClientException('offline'),
        );
        expect(
          (await VendorToolsOptions.load(client, 't', user: owner)).walkInSales,
          isFalse,
        );
        expect(
          (await VendorToolsOptions.load(
            client,
            't',
            user: owner,
            refresh: true,
          )).walkInSales,
          isFalse,
        );
      });
    });

    apiTest(
      'offline restart: Sales tab and products from the device; live update later',
      (tester, api) async {
        SharedPreferences.setMockInitialValues({
          'vendor_tools_options.v1.v1': keptOptions(walkInOn),
          'vendor_pos_products.v1': jsonEncode({
            'cachedAt': '2026-10-19T08:00:00.000Z',
            'products': [
              stockProduct('p1', 'Whey', stock: 4)..remove('costTzs'),
            ],
          }),
        });
        for (final route in [
          'GET /vendor/tools/options',
          'GET /vendor/products',
          'GET /vendor/orders',
          'GET /vendor/profile',
          'GET /vendor/payments',
          'GET /vendor/enquiries',
          'GET /vendor/staff',
          'GET /vendor/sales',
          'GET /vendor/stock/low',
        ]) {
          api.onCall(route, (_) => throw http.ClientException('offline'));
        }
        final host = await pumpPage(
          tester,
          api,
          const VendorHomePage(),
          user: owner,
          size: const Size(400, 1000),
          extraRoutes: salesRoutes,
        );
        expect(find.byKey(const Key('vendor-nav-sales')), findsOneWidget);
        expect(find.text('Whey'), findsOneWidget);
        expect(find.text(host.tr('vendor.noProducts')), findsNothing);
        expect(find.text(host.tr('vendor.offlineKept')), findsOneWidget);
        // Back online, and the server now says walk-in sales are off: the tab
        // goes without a reload (the minute retry asks again).
        api.on('GET /vendor/tools/options', walkInOff);
        await tester.pump(const Duration(seconds: 61));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('vendor-nav-sales')), findsNothing);
      },
    );

    apiTest('offline restart with nothing kept: no Sales tab (fail closed)', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: []);
      api.onCall(
        'GET /vendor/tools/options',
        (_) => throw http.ClientException('offline'),
      );
      await pumpVendorHome(tester, api, user: owner);
      expect(find.byKey(const Key('vendor-nav-sales')), findsNothing);
    });
  });

  group('kept suspended state', () {
    apiTest(
      'a reload keeps the till off while the server still says suspended',
      (tester, api) async {
        SharedPreferences.setMockInitialValues({
          'vendor_sales_suspended.v1.v1': true,
        });
        seedPos(api);
        api.fail('GET /vendor/sales', 403, {'error': 'vendor_suspended'});
        final host = await pumpPage(
          tester,
          api,
          const PosPage(),
          user: owner,
          size: const Size(400, 900),
          extraRoutes: salesRoutes,
        );
        expect(find.text(host.tr('vendor.sales.suspended')), findsOneWidget);
        expect(
          tester
              .widget<ListTile>(find.byKey(const Key('pos-product-p1')))
              .onTap,
          isNull,
        );
      },
    );

    apiTest('a successful sales call turns it back on', (tester, api) async {
      SharedPreferences.setMockInitialValues({
        'vendor_sales_suspended.v1.v1': true,
      });
      seedPos(api);
      api.on('GET /vendor/sales', {'sales': [], 'nextCursor': null});
      final host = await pumpPage(
        tester,
        api,
        const PosPage(),
        user: owner,
        size: const Size(400, 900),
        extraRoutes: salesRoutes,
      );
      expect(find.text(host.tr('vendor.sales.suspended')), findsNothing);
      expect(
        tester.widget<ListTile>(find.byKey(const Key('pos-product-p1'))).onTap,
        isNotNull,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('vendor_sales_suspended.v1.v1'), isNull);
    });
  });

  apiTest('a kept cart is checked against the refreshed product list', (
    tester,
    api,
  ) async {
    SharedPreferences.setMockInitialValues({
      'vendor_pos_draft.v1.v1': jsonEncode({
        'lines': [
          {
            'productId': 'p1',
            'name': 'Whey',
            'listPriceTzs': 45000,
            'qty': 5,
            'discountTzs': 0,
          },
          {
            'productId': 'gone',
            'name': 'Old band',
            'listPriceTzs': 5000,
            'qty': 1,
            'discountTzs': 0,
          },
        ],
      }),
    });
    seedPos(api);
    final host = await pumpPage(
      tester,
      api,
      const PosPage(),
      user: owner,
      size: const Size(400, 900),
      extraRoutes: salesRoutes,
    );
    await host.dismissSnacks();
    await tester.tap(find.byKey(const Key('pos-cart-bar')));
    await tester.pumpAndSettle();
    // Stock is now 2: the 5 in the cart are flagged, and + is off.
    expect(find.text('Only 2 in stock.'), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(find.byKey(const Key('pos-inc-p1\u0000')))
          .onPressed,
      isNull,
    );
    expect(
      find.text("Old band can't be sold now. Remove it from the sale."),
      findsOneWidget,
    );
  });

  group('minor', () {
    apiTest('Escape closes the payment sheet', (tester, api) async {
      seedPos(api);
      await pumpPage(
        tester,
        api,
        const PosPage(),
        user: owner,
        size: const Size(1200, 900),
        extraRoutes: salesRoutes,
      );
      await tester.tap(find.byKey(const Key('pos-product-p1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('pos-cart-charge')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pos-complete')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pos-complete')), findsNothing);
    });

    apiTest('history: suspended said once; offline has its own heading', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [], tools: walkInOn);
      api.fail('GET /vendor/sales', 403, {'error': 'vendor_suspended'});
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'sales'),
        user: owner,
        size: const Size(400, 1200),
        extraRoutes: salesRoutes,
      );
      expect(find.text(host.tr('vendor.sales.suspended')), findsOneWidget);
    });

    apiTest('history offline: heading and message about sales', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [], tools: walkInOn);
      api.onCall(
        'GET /vendor/sales',
        (_) => throw http.ClientException('offline'),
      );
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'sales'),
        user: owner,
        size: const Size(400, 1200),
        extraRoutes: salesRoutes,
      );
      expect(find.text(host.tr('vendor.sales.offlineTitle')), findsOneWidget);
      expect(find.text(host.tr('vendor.sales.offline')), findsOneWidget);
    });
  });
}
