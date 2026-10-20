// Vendor tools · S4: Swahili at 375 (no overflow, no clipped money) on the
// Customers tab, Owed, profile, payment sheet and POS credit mode; the sync
// screen's "Try again without customer"; and the order card's customer link
// (only when the order carries a customerId — a deleted buyer's old orders
// do not, backend #224).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/customers/customer_profile_page.dart';
import 'package:fitflexmobile/screens/vendor/orders/vendor_order_card.dart';
import 'package:fitflexmobile/screens/vendor/sales/pos_page.dart';
import 'package:fitflexmobile/screens/vendor/sales/sales_sync_page.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';

import '../support/recording_api.dart';
import 'customers_support.dart';
import 'stock_support.dart';
import 'walkin_support.dart';

const phone375 = Size(375, 812);

void seedAll(RecordingApi api) {
  seedVendorHome(
    api,
    products: [stockProduct('p1', 'Whey')],
    tools: customersOn,
  );
  seedPos(
    api,
    tools: customersOn,
    products: [posProduct('p1', 'Whey', price: 95000, stock: 5)],
  );
  seedCustomers(api);
  api.on('GET /vendor/customers/cus_1', profile());
  api.on('GET /vendor/customers/cus_1/sales', {
    'sales': [],
    'nextCursor': null,
  });
}

void main() {
  setUpAll(loadAppFonts);

  for (final scale in [1.0, 1.3]) {
    apiTest('Kiswahili 375 @${scale}x: Customers list and Owed fit', (
      tester,
      api,
    ) async {
      seedAll(api);
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(open: 'customers'),
        user: ownerUser,
        lang: 'sw',
        size: phone375,
        textScale: scale,
        extraRoutes: customerRoutes,
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Wateja'), findsWidgets);
      expect(
        find.text(host.tr('vendor.customers.filter.archived')),
        findsOneWidget,
      );
      await tester.tap(find.text('Madeni'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('owed-summary')), findsOneWidget);
    });

    apiTest('Kiswahili 375 @${scale}x: profile and payment sheet fit', (
      tester,
      api,
    ) async {
      seedAll(api);
      await pumpPage(
        tester,
        api,
        const CustomerProfilePage(customerId: 'cus_1'),
        lang: 'sw',
        size: phone375,
        textScale: scale,
        extraRoutes: customerRoutes,
      );
      expect(tester.takeException(), isNull);
      await tapVisible(
        tester,
        find.byKey(const Key('customer-record-payment')),
      );
      await typeInto(tester, find.byKey(const Key('pay-amount')), '60000');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('TSh 50,000'), findsWidgets);
    });

    apiTest('Kiswahili 375 @${scale}x: POS credit mode fits', (
      tester,
      api,
    ) async {
      seedAll(api);
      await pumpPage(
        tester,
        api,
        const PosPage(),
        user: ownerUser,
        lang: 'sw',
        size: phone375,
        textScale: scale,
        extraRoutes: salesRoutes,
      );
      await tester.tap(find.byKey(const Key('pos-product-p1')));
      await tester.pumpAndSettle();
      // On a phone the seller goes straight to payment; Pay later opens
      // the customer picker itself when no customer is attached yet.
      await tapVisible(tester, find.byKey(const Key('pos-charge')));
      await typeInto(tester, find.byKey(const Key('pos-amount-0')), '20000');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('vendor-pos-paylater')));
      await tapVisible(tester, find.byKey(const Key('picker-row-cus_1')));
      expect(tester.takeException(), isNull);
      expect(find.text('Kamilisha mauzo ya mkopo'), findsOneWidget);
      expect(find.text('Kiasi kinachodaiwa: TSh 75,000'), findsOneWidget);
    });
  }

  apiTest('sync: a sale whose customer is gone → send without customer', (
    tester,
    api,
  ) async {
    seedPos(api, tools: customersOn);
    api.onCall('POST /vendor/sales', (_) => {'sale': serverSale()});
    SharedPreferences.setMockInitialValues({
      'vendor_sale_queue.v1.v1': jsonEncode([
        {
          'body': {
            'clientRef': 'sale_q_00abcdef',
            'soldAt': '2026-10-19T08:00:00.000Z',
            'lines': [
              {'productId': 'p1', 'qty': 1},
            ],
            'payments': [
              {'method': 'cash', 'amountTzs': 45000},
            ],
            'customerId': 'cus_1',
          },
          'display': {
            'lines': [
              {'name': 'Whey', 'listPriceTzs': 45000},
            ],
          },
          'queuedAt': '2026-10-19T08:00:00.000Z',
          'state': 'conflict',
          'error': {
            'code': 'customer_archived',
            'status': 409,
            'body': {'error': 'customer_archived'},
          },
        },
      ]),
    });
    final host = await pumpPage(
      tester,
      api,
      const SalesSyncPage(),
      user: ownerUser,
      size: const Size(400, 900),
      extraRoutes: salesRoutes,
    );
    expect(find.text(host.tr('vendor.sync.conflictCustomer')), findsOneWidget);
    await tapVisible(
      tester,
      find.byKey(const Key('sync-no-customer-sale_q_00abcdef')),
    );
    final body = api.only('POST', '/vendor/sales').body as Map;
    expect(body['clientRef'], 'sale_q_00abcdef');
    expect(body.containsKey('customerId'), isFalse);
  });

  Map<String, dynamic> order(String? customerId) => {
    'id': 'ord_1',
    'shortRef': 'ABC123',
    'status': 'pending',
    'items': [
      {'name': 'Whey', 'qty': 1, 'priceTzs': 45000},
    ],
    'totalTzs': 45000,
    'paymentStatus': 'paid',
    'paymentMethod': 'mpesa',
    'deliveryMethod': 'gym_pickup',
    'buyer': {'customerId': customerId, 'displayName': 'Neema'},
  };

  apiTest('order card: customer link only with a customerId', (
    tester,
    api,
  ) async {
    const tools = VendorTools(customers: true, walkInSales: true);
    await pumpPage(
      tester,
      api,
      ListView(
        children: [
          VendorOrderCard(order: order('cus_2'), tools: tools),
          VendorOrderCard(order: {...order(null), 'id': 'ord_2'}, tools: tools),
          VendorOrderCard(
            order: {...order('cus_3'), 'id': 'ord_3'},
            tools: VendorTools.off,
          ),
        ],
      ),
      size: const Size(400, 1200),
      extraRoutes: customerRoutes,
    );
    expect(
      find.byKey(const Key('vendor-order-customer-ord_1')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('vendor-order-customer-ord_2')), findsNothing);
    expect(find.byKey(const Key('vendor-order-customer-ord_3')), findsNothing);
    await tapVisible(
      tester,
      find.byKey(const Key('vendor-order-customer-ord_1')),
    );
    expect(textContaining('ROUTE-CUSTOMER cus_2'), findsOneWidget);
  });
}
