import 'package:fitflexmobile/shared/shop_checkout.dart';
import 'package:flutter_test/flutter_test.dart';

// Mirrors fitflex-functions src/shared/order-lifecycle.mjs (FORWARD,
// nextStatuses, canonicalStatus) on release-candidate.
void main() {
  test('legacy statuses read as the backend reads them', () {
    expect(shopCanonicalOrderStatus('confirmed'), 'accepted');
    expect(shopCanonicalOrderStatus('fulfilled'), 'delivered');
    expect(shopCanonicalOrderStatus('packed'), 'packed');
    expect(shopOrderIsFinal('fulfilled'), isTrue);
    expect(shopOrderIsFinal('cancelled'), isTrue);
    expect(shopOrderIsFinal('confirmed'), isFalse);
  });

  test('allowed next steps match the backend matrix', () {
    expect(shopAllowedNextStatuses('confirmed', 'home_delivery'), [
      'processing',
      'packed',
      'dispatched',
    ]);
    expect(shopAllowedNextStatuses('confirmed', 'gym_pickup'), [
      'processing',
      'packed',
      'dispatched',
      'ready_for_pickup',
    ]);
    expect(shopAllowedNextStatuses('dispatched', 'gym_pickup'), [
      'ready_for_pickup',
    ]);
    expect(shopAllowedNextStatuses('dispatched', 'home_delivery'), [
      'delivered',
    ]);
    expect(shopAllowedNextStatuses('delivered', 'home_delivery'), isEmpty);
    expect(shopAllowedNextStatuses('fulfilled', 'home_delivery'), isEmpty);
    expect(shopAllowedNextStatuses('mystery', 'home_delivery'), isEmpty);
  });

  test('every next step offered is one the backend allows', () {
    for (final method in ['home_delivery', 'gym_pickup']) {
      for (final status in [
        'pending',
        'confirmed',
        'accepted',
        'processing',
        'packed',
        'dispatched',
        'ready_for_pickup',
      ]) {
        final next = vendorNextOrderStatus({
          'status': status,
          'deliveryMethod': method,
          'paymentStatus': 'paid',
        });
        expect(next, isNotNull, reason: '$status $method');
        expect(
          shopAllowedNextStatuses(status, method),
          contains(next),
          reason: '$status $method',
        );
        // Never "the status it already has" (a silent no-op on the server).
        expect(
          shopCanonicalOrderStatus(next),
          isNot(shopCanonicalOrderStatus(status)),
        );
      }
    }
  });

  test('final and unknown statuses offer nothing', () {
    for (final status in ['delivered', 'fulfilled', 'cancelled', 'mystery']) {
      expect(
        vendorNextOrderStatus({'status': status, 'paymentStatus': 'paid'}),
        isNull,
        reason: status,
      );
    }
  });

  test('an unpaid order still shows the step it will take once paid', () {
    expect(
      vendorNextOrderStatus({
        'status': 'pending',
        'paymentStatus': 'pending',
        'nextStatuses': <String>[],
      }),
      'accepted',
    );
  });
}
