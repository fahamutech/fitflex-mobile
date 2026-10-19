// Marketplace checkout rules that need no screen.
import 'dart:math';

import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/shop_checkout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('checkout key', () {
    test('is long, random and in the server\'s accepted format', () {
      final a = newCheckoutKey();
      final b = newCheckoutKey();
      expect(a, isNot(b));
      expect(a, matches(RegExp(r'^[A-Za-z0-9._:-]{8,100}$')));
      expect(newCheckoutKey(Random(1)), newCheckoutKey(Random(1)));
    });

    test('the same purchase keeps its key; a changed one gets a new key', () {
      var n = 0;
      String make() => 'chk_${n++}';
      final first = CheckoutAttempt.forPurchase(null, 'a', makeKey: make);
      final again = CheckoutAttempt.forPurchase(first, 'a', makeKey: make);
      final changed = CheckoutAttempt.forPurchase(first, 'b', makeKey: make);
      expect(again.key, first.key);
      expect(changed.key, isNot(first.key));
    });

    test('the signature changes with items, option, delivery and payment', () {
      String sig({
        int qty = 1,
        String? variant,
        String address = 'x',
        String pay = 'mpesa',
      }) => checkoutSignature(
        items: [
          {'productId': 'p1', 'qty': qty, 'variant': ?variant},
        ],
        deliveryMethod: 'home_delivery',
        deliveryAddress: address,
        paymentMethod: pay,
      );
      final base = sig();
      expect(sig(), base);
      expect(sig(qty: 2), isNot(base));
      expect(sig(variant: 'L'), isNot(base));
      expect(sig(address: 'y'), isNot(base));
      expect(sig(pay: 'airtel_money'), isNot(base));
    });
  });

  group('what a failure means', () {
    test('a dropped connection, timeout or server error is "unknown"', () {
      expect(orderOutcomeUnknown(Exception('timeout')), isTrue);
      expect(orderOutcomeUnknown(ApiException(503, {})), isTrue);
      expect(orderOutcomeUnknown(ApiException(500, {'error': 'x'})), isTrue);
    });

    test('a clear 4xx answer means nothing was ordered', () {
      expect(orderOutcomeUnknown(ApiException(409, {'error': 'x'})), isFalse);
      expect(orderOutcomeUnknown(ApiException(402, {})), isFalse);
    });

    test('known refusals have their own message', () {
      expect(
        shopCheckoutErrorKey(
          ApiException(409, {'error': 'insufficient_stock'}),
        ),
        'shop.errInsufficientStock',
      );
      expect(
        shopCheckoutErrorKey(ApiException(409, {'error': 'price_changed'})),
        'shop.errPriceChanged',
      );
      expect(
        shopCheckoutErrorKey(ApiException(404, {'error': 'product_not_found'})),
        'shop.errUnavailable',
      );
      expect(
        shopCheckoutErrorKey(ApiException(409, {'error': 'vendor_unavailable'})),
        'shop.errVendorUnavailable',
      );
      expect(shopCheckoutErrorKey(ApiException(422, {})), isNull);
    });
  });

  group('payment wording', () {
    String? key(String? status) =>
        shopOrderPaymentKey({'paymentStatus': status});

    test('pending is awaiting, refund_pending is not "refunded"', () {
      expect(key('pending'), 'shop.awaitingPayment');
      expect(key(null), 'shop.awaitingPayment');
      expect(key('refund_pending'), 'shop.refundPending');
      expect(key('refunded'), 'shop.refunded');
      expect(key('failed'), 'shop.paymentNotConfirmed');
      expect(key('paid'), isNull);
      expect(key('cancelled'), isNull);
    });

    test('every new string exists in English and in Swahili', () {
      const keys = [
        'shop.orderPending',
        'shop.orderUncertain',
        'shop.errInsufficientStock',
        'shop.errPriceChanged',
        'shop.errUnavailable',
        'shop.errVendorUnavailable',
        'shop.errVariantRequired',
        'shop.errChanged',
        'shop.addressRequired',
        'shop.pickupGymRequired',
        'shop.refundPending',
        'shop.refunded',
        'shop.paymentNotConfirmed',
        'shop.checkPayment',
        'shop.paymentConfirmed',
        'shop.stillAwaiting',
        'shop.chooseOption',
        'shop.optionOutOfStock',
        'shop.orderTotalIs',
      ];
      final en = FFLocale()..set(const Locale('en'));
      final sw = FFLocale()..set(const Locale('sw'));
      for (final k in keys) {
        expect(en.t(k), isNot(k), reason: 'en $k');
        expect(sw.t(k), isNot(k), reason: 'sw $k');
        expect(sw.t(k), isNot(en.t(k)), reason: 'sw copied $k');
      }
    });
  });
}
