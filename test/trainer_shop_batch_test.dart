// Batches 5–7 (A4/C1/D1) — trainer booking helpers and shop cart logic.

import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/member/widgets/trainer_actions_sheet.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';

void main() {
  group('A4/C1 — nextDateForAvailabilityDay', () {
    // 2026-05-04 is a Monday.
    final monday = DateTime(2026, 5, 4);

    test('same weekday resolves to today', () {
      expect(nextDateForAvailabilityDay('monday', from: monday), '2026-05-04');
    });

    test('later weekday resolves within the same week', () {
      expect(
        nextDateForAvailabilityDay('wednesday', from: monday),
        '2026-05-06',
      );
    });

    test('earlier weekday rolls over to next week', () {
      expect(nextDateForAvailabilityDay('sunday', from: monday), '2026-05-10');
    });

    test('legacy exact-date entries pass through', () {
      expect(
        nextDateForAvailabilityDay('2026-06-15', from: monday),
        '2026-06-15',
      );
    });

    test('unknown labels return null', () {
      expect(nextDateForAvailabilityDay('someday', from: monday), isNull);
    });
  });

  group('D1 — ShopCart', () {
    ShopProduct product({String id = 'p1', num price = 5000, int stock = 3}) =>
        ShopProduct.fromJson({
          'id': id,
          'name': 'Product $id',
          'priceTzs': price,
          'stock': stock,
        });

    test('adds items and totals correctly', () {
      final cart = ShopCart();
      final p = product();
      expect(cart.add(p), isTrue);
      expect(cart.add(p), isTrue);
      expect(cart.qtyOf('p1'), 2);
      expect(cart.totalTzs, 10000);
      expect(cart.itemCount, 2);
    });

    test('caps quantity at available stock', () {
      final cart = ShopCart();
      final p = product(stock: 2);
      expect(cart.add(p), isTrue);
      expect(cart.add(p), isTrue);
      expect(cart.add(p), isFalse, reason: 'stock exhausted');
      expect(cart.qtyOf('p1'), 2);
    });

    test('removeOne decrements and clears at zero', () {
      final cart = ShopCart();
      final p = product();
      cart.add(p);
      cart.add(p);
      cart.removeOne('p1');
      expect(cart.qtyOf('p1'), 1);
      cart.removeOne('p1');
      expect(cart.isEmpty, isTrue);
    });

    test('toOrderItems builds the API payload', () {
      final cart = ShopCart();
      cart.add(product(id: 'a'));
      cart.add(product(id: 'b', price: 1000));
      cart.add(product(id: 'b', price: 1000));
      final items = cart.toOrderItems();
      expect(items, hasLength(2));
      expect(items.firstWhere((i) => i['productId'] == 'b')['qty'], 2);
    });

    test('out-of-stock product reports not purchasable', () {
      expect(product(stock: 0).inStock, isFalse);
    });

    test('parses database decimals and rich product details safely', () {
      final rich = ShopProduct.fromJson({
        'id': 'rich',
        'vendorId': 'vendor-1',
        'name': 'Resistance Bands',
        'priceTzs': '45000.00',
        'discountPriceTzs': '39000.00',
        'rating': '4.80',
        'soldCount': '64',
        'distanceKm': '3.20',
        'stock': 12,
        'vendor': {'businessName': 'Performance Store'},
        'reviews': [
          {'rating': 5, 'comment': 'Excellent'},
        ],
        'similarProducts': [
          {'id': 'similar', 'name': 'Yoga Mat', 'priceTzs': 30000},
        ],
      });

      expect(rich.effectivePrice, 39000);
      expect(rich.rating, 4.8);
      expect(rich.soldCount, 64);
      expect(rich.distanceKm, 3.2);
      expect(rich.vendor['businessName'], 'Performance Store');
      expect(rich.reviews.single['comment'], 'Excellent');
      expect(rich.similarProducts.single.name, 'Yoga Mat');
    });
  });
}
