// Vendor tools · S2 (order privacy, fitflex-functions#200): the Orders tab
// reads the allowlisted vendor order and still works with the old shape.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/orders/vendor_order_card.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/i18n.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

/// An order in the S2 shape.
Map<String, dynamic> s2Order(
  String id, {
  String status = 'accepted',
  String paymentStatus = 'paid',
  String delivery = 'home_delivery',
  Map<String, dynamic>? buyer = const {
    'customerId': 'cus_1',
    'displayName': 'Neema',
  },
  String? address = 'Masaki 12',
  Map<String, dynamic>? pickupGym,
  String? variant = 'Vanilla',
  List<String> next = const [],
}) => {
  'id': id,
  'shortRef': id.toUpperCase(),
  'createdAt': '2026-10-19T08:00:00.000Z',
  'status': status,
  'orderStatus': status,
  'nextStatuses': next,
  'timeline': <dynamic>[],
  'items': [
    {
      'productId': 'p1',
      'name': 'Whey Protein',
      'variant': variant,
      'qty': 2,
      'priceTzs': 85000,
      'image': null,
    },
  ],
  'totalTzs': 170000,
  'paymentStatus': paymentStatus,
  'paymentMethod': 'mpesa',
  'deliveryMethod': delivery,
  'note': null,
  'pickupGymId': pickupGym?['id'],
  'pickupGym': pickupGym,
  'buyer': buyer,
  'deliveryAddress': ?address,
};

Future<PageHost> _ordersTab(
  WidgetTester tester,
  RecordingApi api,
  List<dynamic> orders, {
  Map<String, dynamic>? tools,
  String lang = 'en',
  Map<String, dynamic> user = vendorUser,
}) async {
  seedVendorHome(api, products: const [], tools: tools);
  api.on('GET /vendor/orders', orders);
  final host = await pumpVendorHome(tester, api, lang: lang, user: user);
  // One section (staff with only `orders`) has no navigation bar.
  final nav = find.byKey(const Key('vendor-nav-orders'));
  if (nav.evaluate().isNotEmpty) {
    await tester.tap(nav);
    await tester.pumpAndSettle();
  }
  return host;
}

void main() {
  group('orders tab (S2 shape)', () {
    apiTest('shows the order number, buyer name and item variant', (
      tester,
      api,
    ) async {
      final host = await _ordersTab(tester, api, [s2Order('ab12cd')]);
      expect(find.text('Order AB12CD'), findsOneWidget);
      expect(find.text('Buyer: Neema'), findsOneWidget);
      expect(find.text('2× Whey Protein · Variant: Vanilla'), findsOneWidget);
      expect(
        find.text('${host.tr('vendor.deliveryAddress')}: Masaki 12'),
        findsOneWidget,
      );
      // Never the buyer's internal ids.
      expect(find.textContaining('cus_1'), findsNothing);
    });

    apiTest('Swahili: variant reads "Chaguo", buyer "Mnunuzi"', (
      tester,
      api,
    ) async {
      await _ordersTab(tester, api, [s2Order('ab12cd')], lang: 'sw');
      expect(find.text('Oda AB12CD'), findsOneWidget);
      expect(find.text('Mnunuzi: Neema'), findsOneWidget);
      expect(find.text('2× Whey Protein · Chaguo: Vanilla'), findsOneWidget);
    });

    apiTest('a buyer without a display name reads "FitFlex member"', (
      tester,
      api,
    ) async {
      await _ordersTab(tester, api, [
        s2Order('o1', buyer: {'customerId': 'cus_1', 'displayName': null}),
      ]);
      expect(find.text('Buyer: FitFlex member'), findsOneWidget);
    });

    apiTest('pickup shows the gym name, not its id', (tester, api) async {
      final host = await _ordersTab(tester, api, [
        s2Order(
          'o1',
          delivery: 'gym_pickup',
          address: null,
          pickupGym: {'id': 'gym-7', 'name': 'Masaki Fitness'},
        ),
      ]);
      expect(
        find.text('${host.tr('vendor.pickupGym')}: Masaki Fitness'),
        findsOneWidget,
      );
      expect(find.textContaining('gym-7'), findsNothing);
    });

    apiTest('pickup gym without a name says so, never the raw id', (
      tester,
      api,
    ) async {
      final host = await _ordersTab(tester, api, [
        s2Order(
          'o1',
          delivery: 'gym_pickup',
          address: null,
          pickupGym: {'id': 'gym-7', 'name': null},
        ),
      ]);
      expect(
        find.text(
          '${host.tr('vendor.pickupGym')}: '
          '${host.tr('vendor.pickupGymUnknown')}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('gym-7'), findsNothing);
    });

    apiTest('the buyer phone is a call button that dials tel:', (
      tester,
      api,
    ) async {
      final dialled = <Uri>[];
      final previous = vendorOrderDialer;
      vendorOrderDialer = (uri) async {
        dialled.add(uri);
        return true;
      };
      addTearDown(() => vendorOrderDialer = previous);
      await _ordersTab(
        tester,
        api,
        [
          s2Order(
            'o1',
            buyer: {
              'customerId': 'cus_1',
              'displayName': 'Neema',
              'phone': '+255 700 000 009',
              'contactVisibleUntil': null,
            },
          ),
        ],
        tools: {'buyerContact': true},
      );
      final call = find.byKey(const Key('vendor-order-call-o1'));
      expect(call, findsOneWidget);
      expect(find.text('Call +255 700 000 009'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Call the buyer on +255 700 000 009'),
        findsOneWidget,
      );
      expect(tester.getSize(call).height, greaterThanOrEqualTo(44));
      await tester.ensureVisible(call);
      await tester.tap(call);
      await tester.pumpAndSettle();
      expect(dialled, [Uri(scheme: 'tel', path: '+255700000009')]);
    });

    apiTest('a phone app that cannot open shows the number to call', (
      tester,
      api,
    ) async {
      final previous = vendorOrderDialer;
      vendorOrderDialer = (_) async => false;
      addTearDown(() => vendorOrderDialer = previous);
      final host = await _ordersTab(tester, api, [
        s2Order(
          'o1',
          buyer: {'customerId': 'c', 'displayName': 'N', 'phone': '0700'},
        ),
      ]);
      await tester.tap(find.byKey(const Key('vendor-order-call-o1')));
      await tester.pumpAndSettle();
      expect(
        host.snack('Could not open the phone app. Call 0700 instead.'),
        findsOneWidget,
      );
    });

    apiTest('no phone in the order, no call button', (tester, api) async {
      await _ordersTab(tester, api, [s2Order('o1')]);
      expect(find.byKey(const Key('vendor-order-call-o1')), findsNothing);
    });

    apiTest('delivered orders show until when the contact stays visible', (
      tester,
      api,
    ) async {
      await _ordersTab(
        tester,
        api,
        [
          s2Order(
            'o1',
            status: 'delivered',
            buyer: {
              'customerId': 'c',
              'displayName': 'N',
              'phone': '0700',
              'contactVisibleUntil': '2026-10-26T23:59:59+03:00',
            },
          ),
        ],
        tools: {'buyerContact': true},
      );
      expect(
        find.text('You can see the phone and address until 26 Oct 2026.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('vendor-order-contact-hidden-o1')),
        findsNothing,
      );
    });

    apiTest('delivered over 7 days ago: the address is hidden, with a note', (
      tester,
      api,
    ) async {
      final host = await _ordersTab(tester, api, [
        s2Order('o1', status: 'delivered', address: null),
      ]);
      expect(
        find.text('The delivery address is hidden 7 days after delivery.'),
        findsOneWidget,
      );
      expect(
        find.text('${host.tr('vendor.deliveryAddress')}: -'),
        findsNothing,
      );
    });

    apiTest('with buyer contact on, the note names phone and address', (
      tester,
      api,
    ) async {
      await _ordersTab(
        tester,
        api,
        [s2Order('o1', status: 'delivered', address: null)],
        tools: {'buyerContact': true},
        lang: 'sw',
      );
      expect(
        find.text(
          'Simu na anwani ya mnunuzi hufichwa siku 7 baada ya kufikishwa.',
        ),
        findsOneWidget,
      );
    });

    apiTest('an open order without an address shows no hidden note', (
      tester,
      api,
    ) async {
      await _ordersTab(tester, api, [s2Order('o1', address: null)]);
      expect(
        find.byKey(const Key('vendor-order-contact-hidden-o1')),
        findsNothing,
      );
    });
  });

  group('orders tab (old backend shape)', () {
    apiTest('no shortRef, buyer or pickupGym: still renders', (
      tester,
      api,
    ) async {
      final host = await _ordersTab(tester, api, [
        {
          'id': 'ord_3b0c8f6e',
          'status': 'pending',
          'paymentStatus': 'paid',
          'paymentMethod': 'mpesa',
          'deliveryMethod': 'gym_pickup',
          'pickupGymId': 'gym-7',
          'totalTzs': 170000,
          'items': [
            {'qty': 2, 'name': 'Whey Protein'},
          ],
        },
      ]);
      // Same rule as the server's shortRef: last 6, in capitals.
      expect(find.text('Order 0C8F6E'), findsOneWidget);
      expect(find.text('2× Whey Protein'), findsOneWidget);
      expect(
        find.text(
          '${host.tr('vendor.pickupGym')}: '
          '${host.tr('vendor.pickupGymUnknown')}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Buyer:'), findsNothing);
      expect(find.byKey(const Key('vendor-next-ord_3b0c8f6e')), findsOneWidget);
    });
  });

  group('staff access turned off', () {
    const staff = {
      'id': 's1',
      'userType': 'vendor_staff',
      'vendorId': 'v1',
      'vendorPermissions': ['orders'],
    };

    apiTest('vendor_staff_inactive on load shows the staff message', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: const []);
      api.fail('GET /vendor/orders', 403, {'error': 'vendor_staff_inactive'});
      final host = await pumpVendorHome(tester, api, user: staff);
      const message = 'Your staff access is disabled. Ask the business owner.';
      expect(host.snack(message), findsOneWidget);
      expect(find.byKey(const Key('vendor-staff-disabled')), findsOneWidget);
      expect(host.snack(host.tr('vendor.loadFailed')), findsNothing);
    });

    apiTest('account_suspended for staff reads the same, in Swahili too', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: const []);
      api.fail('GET /vendor/orders', 403, {'error': 'account_suspended'});
      final host = await pumpVendorHome(tester, api, user: staff, lang: 'sw');
      expect(
        host.snack(
          'Ruhusa yako ya mfanyakazi imezimwa. Wasiliana na mmiliki wa biashara.',
        ),
        findsOneWidget,
      );
    });

    apiTest('a staff status change refused as inactive says why', (
      tester,
      api,
    ) async {
      final host = await _ordersTab(tester, api, [
        s2Order('o1', status: 'pending', next: ['accepted', 'cancelled']),
      ], user: staff);
      api.fail('POST /vendor/orders/o1/status', 403, {
        'error': 'vendor_staff_inactive',
      });
      await tester.tap(find.byKey(const Key('vendor-next-o1')));
      await tester.pumpAndSettle();
      expect(
        host.snack('Your staff access is disabled. Ask the business owner.'),
        findsOneWidget,
      );
    });

    test('mapping: inactive always; account_suspended only for staff', () {
      final en = FFLocale();
      const staffMsg = 'Your staff access is disabled. Ask the business owner.';
      expect(
        errorMessage(en, ApiException(403, {'error': 'vendor_staff_inactive'})),
        staffMsg,
      );
      expect(
        errorMessage(
          en,
          ApiException(403, {'error': 'account_suspended'}),
          vendorStaff: true,
        ),
        staffMsg,
      );
      // A member or vendor keeps the plain suspended message.
      expect(
        errorMessage(en, ApiException(403, {'error': 'account_suspended'})),
        'Request declined: This account is suspended. Contact support',
      );
      final sw = FFLocale()..set(const Locale('sw'));
      expect(
        apiErrorMessage(
          sw,
          ApiException(403, {'error': 'vendor_staff_inactive'}),
        ),
        'Ruhusa yako ya mfanyakazi imezimwa. Wasiliana na mmiliki wa biashara.',
      );
    });
  });
}
