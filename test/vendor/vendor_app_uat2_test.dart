// Vendor app UAT follow-up (2026-10-20): Swahili delivery address label,
// an order cancelled meanwhile (409 order_cancelled), and no "hidden after
// 7 days" note on cancelled or refunded orders.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';
import 'vendor_orders_s2_test.dart' show s2Order;

Future<PageHost> _orders(
  WidgetTester tester,
  RecordingApi api,
  List<dynamic> orders, {
  String lang = 'en',
}) async {
  seedVendorHome(api, products: const []);
  api.on('GET /vendor/orders', orders);
  final host = await pumpVendorHome(tester, api, lang: lang);
  await tester.tap(find.byKey(const Key('vendor-nav-orders')));
  await tester.pumpAndSettle();
  return host;
}

void main() {
  setUpAll(loadAppFonts);

  apiTest('Swahili: the delivery address is "Anwani ya kufikisha"', (
    tester,
    api,
  ) async {
    await _orders(tester, api, [s2Order('o1')], lang: 'sw');
    expect(find.text('Anwani ya kufikisha: Masaki 12'), findsOneWidget);
    expect(find.textContaining('Anwani ya delivery'), findsNothing);
  });

  for (final lang in ['en', 'sw']) {
    apiTest('409 order_cancelled ($lang): says so and reloads the orders', (
      tester,
      api,
    ) async {
      final host = await _orders(tester, api, [
        s2Order('o1', status: 'pending', next: ['accepted', 'cancelled']),
      ], lang: lang);
      api.fail('POST /vendor/orders/o1/status', 409, {
        'error': 'order_cancelled',
      });
      api.clear();
      await tester.tap(find.byKey(const Key('vendor-next-o1')));
      await tester.pumpAndSettle();
      expect(
        host.snack(
          lang == 'en' ? 'This order was cancelled.' : 'Oda hii imeghairiwa.',
        ),
        findsOneWidget,
      );
      expect(host.snack(host.tr('vendor.saveFailed')), findsNothing);
      expect(api.sent('GET', '/vendor/orders'), isTrue);
    });
  }

  for (final (label, order) in [
    ('cancelled', s2Order('o1', status: 'cancelled', address: null)),
    (
      'delivered then refunded',
      s2Order(
        'o1',
        status: 'delivered',
        paymentStatus: 'refunded',
        address: null,
      ),
    ),
    (
      'delivered, refund pending',
      s2Order(
        'o1',
        status: 'delivered',
        paymentStatus: 'refund_pending',
        address: null,
      ),
    ),
    (
      'delivered, order cancelled overall',
      {
        ...s2Order('o1', status: 'delivered', address: null),
        'orderStatus': 'cancelled',
      },
    ),
  ]) {
    apiTest('no "hidden after 7 days" note: $label', (tester, api) async {
      await _orders(tester, api, [order]);
      expect(
        find.byKey(const Key('vendor-order-contact-hidden-o1')),
        findsNothing,
      );
    });
  }

  apiTest('a delivered, paid order still gets the note', (tester, api) async {
    await _orders(tester, api, [
      s2Order('o1', status: 'delivered', address: null),
    ]);
    expect(
      find.byKey(const Key('vendor-order-contact-hidden-o1')),
      findsOneWidget,
    );
  });
}
