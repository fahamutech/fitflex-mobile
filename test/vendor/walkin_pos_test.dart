// Vendor tools · S3: the POS screen — gating, adding with the stock cap,
// payment and change, references, completing, queueing on network failure,
// refusals (409 stock, 5xx retry with the same clientRef) and the kept draft.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/sales/pos_page.dart';

import '../support/recording_api.dart';
import 'walkin_support.dart';

const vendor = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Asha'};

Future<PageHost> pumpPos(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = vendor,
  String lang = 'en',
  Size size = const Size(400, 900),
}) => pumpPage(
  tester,
  api,
  const PosPage(),
  user: user,
  lang: lang,
  size: size,
  extraRoutes: salesRoutes,
);

Future<void> addWhey(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pos-product-p1')));
  await tester.pumpAndSettle();
}

Future<void> openPayment(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pos-charge')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadAppFonts);

  apiTest('walkInSales off: straight to vendor home, no products asked', (
    tester,
    api,
  ) async {
    seedPos(api, tools: walkInOff);
    await pumpPos(tester, api);
    expect(textContaining('ROUTE-VENDOR-HOME'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  apiTest('options call failing: same as off', (tester, api) async {
    seedPos(api);
    api.fail('GET /vendor/tools/options', 500);
    await pumpPos(tester, api);
    expect(textContaining('ROUTE-VENDOR-HOME'), findsOneWidget);
  });

  apiTest('staff without sales: "no access" and back home', (
    tester,
    api,
  ) async {
    seedPos(api);
    final host = await pumpPos(
      tester,
      api,
      user: {
        'id': 's1',
        'userType': 'vendor_staff',
        'vendorId': 'v1',
        'vendorPermissions': ['orders'],
      },
    );
    expect(textContaining('ROUTE-VENDOR-HOME'), findsOneWidget);
    expect(find.text(host.tr('vendor.sales.noAccess')), findsOneWidget);
  });

  apiTest(
    'adds by tap, stops at stock with "Only n in stock", out of stock disabled',
    (tester, api) async {
      seedPos(api);
      final host = await pumpPos(tester, api);
      expect(find.text('Whey'), findsOneWidget);
      // Archived-free list, prices as walk-in price.
      expect(find.text('TSh 45,000'), findsOneWidget);
      final mat = tester.widget<ListTile>(
        find.byKey(const Key('pos-product-p2')),
      );
      expect(mat.onTap, isNull);
      expect(find.byKey(const Key('pos-out-p2')), findsOneWidget);
      await addWhey(tester);
      await addWhey(tester);
      // A third tap is refused (stock 2).
      await addWhey(tester);
      expect(
        find.text(host.tr('vendor.pos.items').replaceAll('{n}', '2')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('pos-cart-bar')));
      await tester.pumpAndSettle();
      expect(find.text('Only 2 in stock.'), findsOneWidget);
      final inc = tester.widget<IconButton>(
        find.byKey(Key('pos-inc-p1\u0000')),
      );
      expect(inc.onPressed, isNull);
    },
  );

  apiTest('cash 50,000 on 45,000: "Give change", body sent, receipt opens', (
    tester,
    api,
  ) async {
    seedPos(api);
    api.onCall('POST /vendor/sales', (r) => {'sale': serverSale()});
    final host = await pumpPos(tester, api);
    await addWhey(tester);
    await openPayment(tester);
    expect(find.byKey(const Key('pos-money-notice')), findsOneWidget);
    expect(find.text(host.tr('vendor.pos.moneyNotice')), findsOneWidget);
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '50000');
    await tester.pumpAndSettle();
    expect(find.text('Give change: TSh 5,000'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pos-complete')));
    await tester.pumpAndSettle();
    final body = api.only('POST', '/vendor/sales').body as Map;
    expect(body['lines'], [
      {'productId': 'p1', 'qty': 1},
    ]);
    expect(body['payments'], [
      {'method': 'cash', 'amountTzs': 50000},
    ]);
    expect(
      RegExp(r'^[A-Za-z0-9._:-]{8,100}$').hasMatch(body['clientRef']),
      isTrue,
    );
    // Recorded online: the server's clock, not the phone's.
    expect(body.containsKey('soldAt'), isFalse);
    expect(textContaining('ROUTE-RECEIPT sal_1'), findsOneWidget);
    // The draft is gone.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('vendor_pos_draft.v1.v1'), isNull);
  });

  apiTest(
    'M-Pesa needs a reference; card does not; M-Pesa over the total is refused',
    (tester, api) async {
      seedPos(api);
      final host = await pumpPos(tester, api);
      await addWhey(tester);
      await openPayment(tester);
      await tapVisible(tester, find.byKey(const Key('pos-method-0-mpesa')));
      expect(isEnabled(tester, find.byKey(const Key('pos-complete'))), isFalse);
      expect(
        find.text(host.tr('vendor.pos.referenceRequired')),
        findsOneWidget,
      );
      await typeInto(
        tester,
        find.byKey(const Key('pos-reference-0')),
        'QK12AB34',
      );
      await tester.pumpAndSettle();
      expect(isEnabled(tester, find.byKey(const Key('pos-complete'))), isTrue);
      await typeInto(tester, find.byKey(const Key('pos-amount-0')), '50000');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('pos-over-non-cash')), findsOneWidget);
      expect(isEnabled(tester, find.byKey(const Key('pos-complete'))), isFalse);
      await tapVisible(tester, find.byKey(const Key('pos-method-0-card')));
      await typeInto(tester, find.byKey(const Key('pos-amount-0')), '45000');
      await tester.pumpAndSettle();
      expect(isEnabled(tester, find.byKey(const Key('pos-complete'))), isTrue);
    },
  );

  apiTest(
    'paying less: "Still to pay" and Complete disabled; split completes',
    (tester, api) async {
      seedPos(api);
      api.onCall('POST /vendor/sales', (r) => {'sale': serverSale()});
      await pumpPos(tester, api);
      await addWhey(tester);
      await openPayment(tester);
      await typeInto(tester, find.byKey(const Key('pos-amount-0')), '20000');
      await tester.pumpAndSettle();
      expect(find.text('Still to pay: TSh 25,000'), findsOneWidget);
      expect(isEnabled(tester, find.byKey(const Key('pos-complete'))), isFalse);
      await tapVisible(tester, find.byKey(const Key('pos-add-payment')));
      await tapVisible(tester, find.byKey(const Key('pos-method-1-mpesa')));
      await typeInto(tester, find.byKey(const Key('pos-reference-1')), 'qk1');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      final body = api.only('POST', '/vendor/sales').body as Map;
      expect(body['payments'], [
        {'method': 'cash', 'amountTzs': 20000},
        {'method': 'mpesa', 'amountTzs': 25000, 'reference': 'qk1'},
      ]);
    },
  );

  apiTest(
    'no connection: the sale is kept on the device and a provisional receipt opens',
    (tester, api) async {
      seedPos(api);
      api.onCall(
        'POST /vendor/sales',
        (_) => throw http.ClientException('offline'),
      );
      await pumpPos(tester, api);
      await addWhey(tester);
      await openPayment(tester);
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final queue =
          jsonDecode(prefs.getString('vendor_sale_queue.v1.v1')!) as List;
      expect(queue, hasLength(1));
      final ref = (queue.single as Map)['body']['clientRef'];
      expect(textContaining('ROUTE-QUEUED $ref'), findsOneWidget);
      // Nothing private in the stored sale.
      expect(
        prefs.getString('vendor_sale_queue.v1.v1'),
        isNot(contains('costTzs')),
      );
      expect(
        prefs.getString('vendor_pos_products.v1'),
        isNot(contains('costTzs')),
      );
    },
  );

  apiTest(
    '409 insufficient_stock: line flagged with the server count, nothing recorded',
    (tester, api) async {
      seedPos(api);
      api.fail('POST /vendor/sales', 409, {
        'error': 'insufficient_stock',
        'productId': 'p1',
        'variant': null,
        'available': 0,
      });
      await pumpPos(tester, api);
      await addWhey(tester);
      await openPayment(tester);
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      await tester.pumpAndSettle();
      expect(
        find.text('Only 0 of Whey left. Lower the quantity.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('pos-line-remove')), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vendor_sale_queue.v1.v1'), isNull);
    },
  );

  apiTest(
    '5xx: Try again sends the same clientRef; Save and sync later queues it',
    (tester, api) async {
      seedPos(api);
      api.fail('POST /vendor/sales', 503, {'error': 'unavailable'});
      final host = await pumpPos(tester, api);
      await addWhey(tester);
      await openPayment(tester);
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      expect(find.text(host.tr('vendor.pos.err.server')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('pos-retry')));
      final sent = api.where('POST', '/vendor/sales');
      expect(sent, hasLength(2));
      expect(
        (sent[0].body as Map)['clientRef'],
        (sent[1].body as Map)['clientRef'],
      );
      expect((sent[0].body as Map)['soldAt'], (sent[1].body as Map)['soldAt']);
      await tapVisible(tester, find.byKey(const Key('pos-sync-later')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final queue =
          jsonDecode(prefs.getString('vendor_sale_queue.v1.v1')!) as List;
      expect(
        (queue.single as Map)['body']['clientRef'],
        (sent[0].body as Map)['clientRef'],
      );
      // Kept on the device with its sale time; it was first sent online.
      expect((queue.single as Map)['body']['soldAt'], isNotNull);
      expect((queue.single as Map)['sentOnline'], isTrue);
      expect((sent[0].body as Map).containsKey('soldAt'), isFalse);
      expect(textContaining('ROUTE-QUEUED'), findsOneWidget);
    },
  );

  apiTest('429 rate_limited behaves like 5xx (sheet stays, nothing queued)', (
    tester,
    api,
  ) async {
    seedPos(api);
    api.fail('POST /vendor/sales', 429, {
      'error': 'rate_limited',
      'retryAfterSeconds': 5,
    });
    await pumpPos(tester, api);
    await addWhey(tester);
    await openPayment(tester);
    await tapVisible(tester, find.byKey(const Key('pos-complete')));
    expect(find.byKey(const Key('pos-server-error')), findsOneWidget);
    expect(find.byKey(const Key('pos-sync-later')), findsOneWidget);
  });

  apiTest(
    'vendor_suspended: sheet closes with the suspended message, draft kept',
    (tester, api) async {
      seedPos(api);
      api.fail('POST /vendor/sales', 403, {'error': 'vendor_suspended'});
      final host = await pumpPos(tester, api);
      await addWhey(tester);
      await openPayment(tester);
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      await tester.pumpAndSettle();
      expect(find.text(host.tr('vendor.sales.suspended')), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vendor_pos_draft.v1.v1'), isNotNull);
      expect(prefs.getString('vendor_sale_queue.v1.v1'), isNull);
    },
  );

  apiTest('an unfinished sale is kept and says so', (tester, api) async {
    SharedPreferences.setMockInitialValues({
      'vendor_pos_draft.v1.v1': jsonEncode({
        'lines': [
          {
            'productId': 'p1',
            'name': 'Whey',
            'listPriceTzs': 45000,
            'qty': 2,
            'discountTzs': 0,
          },
        ],
      }),
    });
    seedPos(api);
    final host = await pumpPos(tester, api);
    expect(find.text(host.tr('vendor.pos.draftKept')), findsOneWidget);
    expect(find.text('Charge TSh 90,000'), findsOneWidget);
  });

  apiTest('line edit: 10% off a 45,000 line is −4,500; price change shown', (
    tester,
    api,
  ) async {
    seedPos(api, products: [posProduct('p1', 'Whey', stock: 5)]);
    await pumpPos(tester, api);
    await addWhey(tester);
    await tester.tap(find.byKey(const Key('pos-cart-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whey').last);
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('%'));
    await typeInto(tester, find.byKey(const Key('pos-edit-discount')), '10');
    await tester.pumpAndSettle();
    expect(find.text('−TSh 4,500'), findsOneWidget);
    await typeInto(tester, find.byKey(const Key('pos-edit-price')), '40000');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('pos-edit-save')));
    expect(find.text('Price changed from TSh 45,000'), findsOneWidget);
    // 40,000 − 10% (4,000) = 36,000.
    expect(find.text('TSh 36,000'), findsWidgets);
  });

  apiTest('a discount above the line total cannot be saved', (
    tester,
    api,
  ) async {
    seedPos(api, products: [posProduct('p1', 'Whey', stock: 5)]);
    await pumpPos(tester, api);
    await addWhey(tester);
    await tester.tap(find.byKey(const Key('pos-cart-bar')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Whey').last);
    await tester.pumpAndSettle();
    await typeInto(tester, find.byKey(const Key('pos-edit-discount')), '50000');
    await tester.pumpAndSettle();
    expect(
      find.text("The discount can't be more than TSh 45,000."),
      findsOneWidget,
    );
    expect(isEnabled(tester, find.byKey(const Key('pos-edit-save'))), isFalse);
  });

  apiTest('variants: picker with stock per variant; 0-stock variant disabled', (
    tester,
    api,
  ) async {
    seedPos(
      api,
      products: [
        posProduct(
          'p1',
          'Tee',
          stock: 3,
          variants: [
            {'name': 'M', 'stock': 3},
            {'name': 'L', 'stock': 0},
          ],
        ),
      ],
    );
    await pumpPos(tester, api);
    await tester.tap(find.byKey(const Key('pos-product-p1')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<ListTile>(find.byKey(const Key('pos-variant-L'))).enabled,
      isFalse,
    );
    await tester.tap(find.byKey(const Key('pos-variant-M')));
    await tester.pumpAndSettle();
    expect(find.text('Charge TSh 45,000'), findsOneWidget);
  });

  apiTest('search by name or SKU; no match says so', (tester, api) async {
    seedPos(
      api,
      products: [
        posProduct('p1', 'Whey', sku: 'WH-1'),
        posProduct('p2', 'Mat', sku: 'MT-9'),
      ],
    );
    final host = await pumpPos(tester, api);
    await typeInto(tester, find.byKey(const Key('pos-search')), 'mt-9');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-product-p2')), findsOneWidget);
    expect(find.byKey(const Key('pos-product-p1')), findsNothing);
    await typeInto(tester, find.byKey(const Key('pos-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(
      find.text(host.tr('vendor.pos.noResults').replaceAll('{q}', 'zzz')),
      findsOneWidget,
    );
  });

  apiTest('wide web layout: two panes; Enter on an exact SKU adds it', (
    tester,
    api,
  ) async {
    seedPos(
      api,
      products: [
        posProduct('p1', 'Whey', sku: 'WH-1'),
        posProduct('p2', 'Mat', sku: 'MT-9'),
      ],
    );
    await pumpPos(tester, api, size: const Size(1200, 900));
    expect(find.byKey(const Key('pos-cart-bar')), findsNothing);
    expect(find.byKey(const Key('pos-cart-empty')), findsOneWidget);
    await typeInto(tester, find.byKey(const Key('pos-search')), 'WH-1');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Charge TSh 45,000'), findsOneWidget);
  });

  apiTest(
    'staff with sales but not products: told why, no crash (backend gap)',
    (tester, api) async {
      seedPos(api);
      api.fail('GET /vendor/products', 403, {
        'error': 'vendor_permission_forbidden',
        'requiredPermission': 'products',
      });
      final host = await pumpPos(
        tester,
        api,
        user: {
          'id': 's1',
          'userType': 'vendor_staff',
          'vendorId': 'v1',
          'vendorPermissions': ['sales'],
        },
      );
      expect(find.text(host.tr('vendor.pos.noProductsAccess')), findsOneWidget);
    },
  );

  apiTest(
    'insufficient_stock without product or count: a generic line, no "0"',
    (tester, api) async {
      seedPos(api);
      api.fail('POST /vendor/sales', 409, {'error': 'insufficient_stock'});
      final host = await pumpPos(tester, api);
      await addWhey(tester);
      await openPayment(tester);
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      await tester.pumpAndSettle();
      expect(
        find.text(host.tr('vendor.sync.conflictStockGeneric')),
        findsOneWidget,
      );
      expect(textContaining('Only 0'), findsNothing);
    },
  );

  apiTest(
    "edited offline sale too old: Record with today's date resends without soldAt",
    (tester, api) async {
      SharedPreferences.setMockInitialValues({
        'vendor_pos_draft.v1.v1': jsonEncode({
          'lines': [
            {
              'productId': 'p1',
              'name': 'Whey',
              'listPriceTzs': 45000,
              'qty': 1,
              'discountTzs': 0,
            },
          ],
          'soldAt': '2026-10-01T08:00:00.000Z',
          'keepSoldAt': true,
          'replacesClientRef': 'sale_old_000001',
        }),
      });
      seedPos(api);
      api.onCall('POST /vendor/sales', (r) {
        final body = r.body as Map;
        if (body.containsKey('soldAt')) {
          return RawResponse(
            400,
            jsonEncode({
              'error': 'sold_at_out_of_range',
              'earliest': '2026-10-12T10:00:00.000Z',
              'latest': '2026-10-19T10:05:00.000Z',
            }),
          );
        }
        return {'sale': serverSale()};
      });
      final host = await pumpPos(tester, api);
      await host.dismissSnacks();
      await openPayment(tester);
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      expect(find.text(host.tr('vendor.pos.err.tooOld')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('pos-record-today')));
      await tester.pumpAndSettle();
      final sent = api.where('POST', '/vendor/sales');
      expect(sent, hasLength(2));
      expect((sent[0].body as Map)['soldAt'], '2026-10-01T08:00:00.000Z');
      final last = sent[1].body as Map;
      expect(last.containsKey('soldAt'), isFalse);
      expect(last['clientRef'], isNot((sent[0].body as Map)['clientRef']));
      expect(last['note'], startsWith('originally 1 Oct 2026'));
      expect(textContaining('ROUTE-RECEIPT sal_1'), findsOneWidget);
    },
  );

  apiTest("soldAt ahead of the server: Check your phone's date and time", (
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
            'qty': 1,
            'discountTzs': 0,
          },
        ],
        'soldAt': '2030-01-01T08:00:00.000Z',
        'keepSoldAt': true,
      }),
    });
    seedPos(api);
    api.fail('POST /vendor/sales', 400, {
      'error': 'sold_at_out_of_range',
      'earliest': '2026-10-12T10:00:00.000Z',
      'latest': '2026-10-19T10:05:00.000Z',
    });
    final host = await pumpPos(tester, api);
    await host.dismissSnacks();
    await openPayment(tester);
    await tapVisible(tester, find.byKey(const Key('pos-complete')));
    expect(find.text(host.tr('vendor.pos.err.clock')), findsOneWidget);
    expect(find.byKey(const Key('pos-record-today')), findsNothing);
  });

  apiTest('Swahili POS at 375 and text scale 2: no overflow', (
    tester,
    api,
  ) async {
    seedPos(api);
    final errors = await captureFlutterErrors(() async {
      await pumpPage(
        tester,
        api,
        const PosPage(),
        user: vendor,
        lang: 'sw',
        size: const Size(375, 800),
        textScale: 2,
        extraRoutes: salesRoutes,
      );
      await addWhey(tester);
      await openPayment(tester);
      await tapVisible(tester, find.byKey(const Key('pos-method-0-bank')));
    });
    expect(errors.where((e) => e.contains('overflowed')), isEmpty);
    expect(find.text('Uhamisho wa benki'), findsOneWidget);
    expect(
      find.textContaining('FitFlex haishughulikii pesa hii'),
      findsOneWidget,
    );
  });
}
