// Vendor app UAT (S2, 2026-10-20): order refs in stock history match Orders
// and the portal; payment status and method are words in EN and SW (shop
// checkout too); the product form's Save keeps 48dp on web density.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/stock/stock_history_page.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/payment_labels.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

Map<String, dynamic> _orderRow(Map<String, dynamic> document) => {
  'id': 'm1',
  'productId': 'p1',
  'variant': null,
  'reason': 'reserve',
  'delta': -1,
  'stockBefore': 2,
  'stockAfter': 1,
  'note': null,
  'actor': null,
  'orderId': document['id'],
  'document': document,
  'createdAt': '2026-10-19T11:05:00Z',
};

Future<void> _history(
  WidgetTester tester,
  RecordingApi api,
  Map<String, dynamic> document,
) async {
  api.on('GET /vendor/tools/options', ledgerOn);
  api.on('GET /vendor/stock/low', []);
  api.on('GET /vendor/products', [stockProduct('p1', 'Whey', stock: 1)]);
  api.on('GET /vendor/products/p1/stock-movements', {
    'openingStock': 2,
    'closingStock': 1,
    'rows': [_orderRow(document)],
    'nextCursor': null,
  });
  await pumpPage(
    tester,
    api,
    const StockHistoryPage(productId: 'p1'),
    size: const Size(400, 900),
  );
}

void main() {
  setUpAll(loadAppFonts);

  group('order ref in stock history', () {
    apiTest('computed like Orders: last 6 characters, capitals', (
      tester,
      api,
    ) async {
      await _history(tester, api, {
        'type': 'order',
        'id': 'ord_ab02091003',
        'number': null,
      });
      expect(find.text('Order 091003'), findsOneWidget);
      expect(find.textContaining('02091003'), findsNothing);
    });

    apiTest('the document\'s shortRef is used when sent', (tester, api) async {
      await _history(tester, api, {
        'type': 'order',
        'id': 'ord_ab02091003',
        'shortRef': 'X1Y2Z3',
        'number': null,
      });
      expect(find.text('Order X1Y2Z3'), findsOneWidget);
    });
  });

  group('payment words', () {
    Future<(String, String)> labels(
      WidgetTester tester,
      String lang,
      Object? status,
      Object? method,
    ) async {
      late String a, b;
      final locale = FFLocale()..set(Locale(lang));
      await tester.pumpWidget(
        FFLocaleScope(
          notifier: locale,
          child: Builder(
            builder: (context) {
              a = shopPaymentStatusLabel(context, status);
              b = shopPaymentMethodLabel(context, method);
              return const SizedBox();
            },
          ),
        ),
      );
      return (a, b);
    }

    testWidgets('statuses and methods in English and Swahili', (tester) async {
      expect(await labels(tester, 'en', 'paid', 'mpesa'), ('Paid', 'M-Pesa'));
      expect(await labels(tester, 'en', 'refund_pending', 'airtel_money'), (
        'Refund pending',
        'Airtel Money',
      ));
      expect(await labels(tester, 'sw', 'pending', 'card'), (
        'Inasubiri malipo',
        'Kadi',
      ));
      expect(await labels(tester, 'sw', 'refunded', 'bank'), (
        'Imerejeshwa',
        'Uhamisho wa benki',
      ));
      expect(await labels(tester, 'en', 'paid', 'mixx'), (
        'Paid',
        'Mixx by Yas',
      ));
      // Unknown codes are tidied, never dropped; nothing → "-".
      expect(await labels(tester, 'en', 'on_hold', 'lipa_namba'), (
        'on hold',
        'lipa namba',
      ));
      expect(await labels(tester, 'en', null, ''), ('-', '-'));
    });

    test('every payment key exists in both languages', () {
      final en = FFLocale.keysOf('en').where((k) => k.startsWith('payment.'));
      expect(en, isNotEmpty);
      expect(FFLocale.keysOf('sw'), containsAll(en));
    });

    apiTest('vendor order card (Swahili): status and method in words', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [stockProduct('p1', 'Whey')]);
      api.on('GET /vendor/orders', [
        {
          'id': 'ord_1abcdef',
          'shortRef': 'ABCDEF',
          'status': 'accepted',
          'paymentStatus': 'paid',
          'paymentMethod': 'airtel_money',
          'deliveryMethod': 'home_delivery',
          'deliveryAddress': 'Masaki',
          'totalTzs': 1000,
          'items': [
            {'name': 'Whey', 'qty': 1},
          ],
        },
      ]);
      final host = await pumpVendorHome(tester, api, lang: 'sw');
      await tester.tap(find.byKey(const Key('vendor-nav-orders')));
      await tester.pumpAndSettle();
      expect(
        find.text('${host.tr('vendor.payment')}: Imelipwa · Airtel Money'),
        findsOneWidget,
      );
      expect(find.textContaining('airtel_money'), findsNothing);
    });
  });

  apiTest('product form Save keeps 48dp with compact (web) density', (
    tester,
    api,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      seedVendorHome(
        api,
        tools: ledgerOn,
        products: [stockProduct('p1', 'Tee')],
      );
      final host = await pumpVendorHome(tester, api);
      await productMenu(tester, 'p1', host.tr('vendor.edit'));
      final save = find.byKey(const Key('vendor-product-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(tester.getSize(save).height, greaterThanOrEqualTo(48));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
