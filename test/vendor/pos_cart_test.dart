// Vendor tools · S3: the cart maths, payment rules and change, the request
// body, the error-code mapping and the shared receipt text (pure Dart).
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/sales/receipt_data.dart';
import 'package:fitflexmobile/screens/vendor/sales/sale_models.dart';
import 'package:fitflexmobile/shared/i18n.dart';

PosCart cartOf(List<PosLine> lines, {int saleDiscount = 0}) =>
    PosCart(lines: lines, saleDiscountTzs: saleDiscount);

void main() {
  group('walk-in price', () {
    test('discount price when set and below the price, else the price', () {
      expect(
        walkInPrice({'priceTzs': 50000, 'discountPriceTzs': 45000}),
        45000,
      );
      expect(walkInPrice({'priceTzs': 50000, 'discountPriceTzs': 0}), 50000);
      expect(
        walkInPrice({'priceTzs': 50000, 'discountPriceTzs': 60000}),
        50000,
      );
      expect(walkInPrice({'priceTzs': 50000}), 50000);
    });
  });

  group('cart totals', () {
    test('subtotal before discounts; sale discount after line discounts', () {
      final cart = cartOf([
        PosLine(
          productId: 'p1',
          name: 'Whey',
          listPriceTzs: 45000,
          qty: 2,
          discountTzs: 5000,
        ),
        PosLine(productId: 'p2', name: 'Shaker', listPriceTzs: 10000),
      ], saleDiscount: 3000);
      final t = cart.totals;
      expect(t.subtotalTzs, 100000);
      expect(t.lineDiscountTzs, 5000);
      expect(t.afterLinesTzs, 95000);
      expect(t.discountsTzs, 8000);
      expect(t.totalTzs, 92000);
      expect(cart.itemCount, 3);
    });

    test('a price change counts in the line and is sent only when changed', () {
      final line = PosLine(
        productId: 'p1',
        name: 'Whey',
        listPriceTzs: 45000,
        qty: 2,
      )..unitPriceTzs = 40000;
      expect(line.lineTotalTzs, 80000);
      expect(line.priceChanged, isTrue);
      expect(line.toRequest(), {
        'productId': 'p1',
        'qty': 2,
        'unitPriceTzs': 40000,
      });
      line.unitPriceTzs = 45000;
      expect(line.priceChanged, isFalse);
      expect(line.toRequest().containsKey('unitPriceTzs'), isFalse);
    });

    test('10% of a 45,000 line is 4,500; % rounds down to whole TSh', () {
      expect(percentOf(45000, 10), 4500);
      expect(percentOf(999, 10), 99);
      expect(percentOf(0, 50), 0);
    });

    test('addOne merges the same product/variant and stops at stock', () {
      final cart = PosCart();
      expect(
        cart.addOne(
          productId: 'p1',
          name: 'Whey',
          priceTzs: 45000,
          available: 2,
        ),
        isTrue,
      );
      expect(
        cart.addOne(
          productId: 'p1',
          name: 'Whey',
          priceTzs: 45000,
          available: 2,
        ),
        isTrue,
      );
      expect(
        cart.addOne(
          productId: 'p1',
          name: 'Whey',
          priceTzs: 45000,
          available: 2,
        ),
        isFalse,
      );
      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.qty, 2);
      cart.addOne(
        productId: 'p1',
        variant: 'Vanilla',
        name: 'Whey',
        priceTzs: 45000,
        available: 5,
      );
      expect(cart.lines, hasLength(2));
    });

    test('per-line cap of 1000', () {
      final cart = PosCart();
      final line = PosLine(
        productId: 'p1',
        name: 'Band',
        listPriceTzs: 100,
        qty: 1000,
      );
      cart.lines.add(line);
      expect(
        cart.addOne(productId: 'p1', name: 'Band', priceTzs: 100),
        isFalse,
      );
      cart.setQty(line, 5000);
      expect(line.qty, maxQtyPerLine);
    });

    test('lowering the qty trims a line discount bigger than the line', () {
      final line = PosLine(
        productId: 'p1',
        name: 'Whey',
        listPriceTzs: 10000,
        qty: 3,
        discountTzs: 25000,
      );
      final cart = cartOf([line]);
      cart.setQty(line, 2);
      expect(line.discountTzs, 20000);
    });
  });

  group('request body and clientRef', () {
    test(
      'clientRef matches the server pattern and is fixed across retries',
      () {
        final ref = newSaleClientRef(Random(1));
        expect(RegExp(r'^[A-Za-z0-9._:-]{8,100}$').hasMatch(ref), isTrue);
        final cart = cartOf([
          PosLine(productId: 'p1', name: 'Whey', listPriceTzs: 45000),
        ]);
        final first = cart.requestBody(
          const [],
          now: () => DateTime.utc(2026, 10, 19, 11, 5),
        );
        final again = cart.requestBody(
          const [],
          now: () => DateTime.utc(2026, 10, 19, 12),
        );
        expect(again['clientRef'], first['clientRef']);
        // Online: no soldAt (the server's clock decides).
        expect(first.containsKey('soldAt'), isFalse);
        expect(again.containsKey('soldAt'), isFalse);
        // Kept on the device: same key, the time of the first Complete.
        final queued = cart.requestBody(const [], queued: true);
        expect(queued['clientRef'], first['clientRef']);
        expect(queued['soldAt'], '2026-10-19T11:05:00.000Z');
      },
    );

    test(
      '"Record with today\'s date": new key, no soldAt, date in the note',
      () {
        final cart = PosCart.fromQueuedRequest(
          {
            'clientRef': 'sale_old_000001',
            'soldAt': '2026-10-01T08:00:00.000Z',
            'lines': [
              {'productId': 'p1', 'qty': 1},
            ],
            'note': 'Blue one',
          },
          [
            {'name': 'Whey', 'listPriceTzs': 45000},
          ],
          replaces: 'sale_old_000001',
        );
        final before = cart.requestBody(const []);
        expect(before['soldAt'], '2026-10-01T08:00:00.000Z');
        cart.recordToday('originally 1 Oct 2026');
        final after = cart.requestBody(const []);
        expect(after.containsKey('soldAt'), isFalse);
        expect(after['clientRef'], isNot(before['clientRef']));
        expect(after['note'], 'Blue one · originally 1 Oct 2026');
        expect(cart.replacesClientRef, 'sale_old_000001');
      },
    );

    test('queued body recorded today; note stays within 200 characters', () {
      final body = recordTodayBody(
        {
          'clientRef': 'sale_old_000001',
          'soldAt': '2026-10-01T08:00:00.000Z',
          'lines': [],
          'note': 'x' * 200,
        },
        'originally 1 Oct 2026',
        makeClientRef: () => 'sale_new_000001',
      );
      expect(body.containsKey('soldAt'), isFalse);
      expect(body['clientRef'], 'sale_new_000001');
      expect((body['note'] as String).length, lessThanOrEqualTo(maxSaleNote));
      expect(body['note'], endsWith('originally 1 Oct 2026'));
    });

    test('sold_at_out_of_range: too old vs a phone clock ahead', () {
      const range = {
        'earliest': '2026-10-12T10:00:00.000Z',
        'latest': '2026-10-20T10:05:00.000Z',
      };
      expect(soldAtTooOld('2026-10-10T10:00:00.000Z', range), isTrue);
      expect(soldAtTooOld('2026-10-25T10:00:00.000Z', range), isFalse);
    });

    test('any cart change means a new clientRef at the next Complete', () {
      final cart = cartOf([
        PosLine(productId: 'p1', name: 'Whey', listPriceTzs: 45000),
      ]);
      final first = cart.requestBody(const [])['clientRef'];
      cart.addOne(productId: 'p1', name: 'Whey', priceTzs: 45000);
      expect(cart.clientRef, isNull);
      expect(cart.requestBody(const [])['clientRef'], isNot(first));
    });

    test(
      'body shape: line discount only when > 0, sale discount, note trimmed',
      () {
        final cart = cartOf([
          PosLine(
            productId: 'p1',
            variant: 'Chocolate',
            name: 'Whey',
            listPriceTzs: 45000,
            qty: 2,
            discountTzs: 5000,
          ),
          PosLine(productId: 'p2', name: 'Shaker', listPriceTzs: 10000),
        ], saleDiscount: 1000)..note = '  thanks  ';
        final body = cart.requestBody([
          {'method': 'cash', 'amountTzs': 60000},
          {'method': 'mpesa', 'amountTzs': 34000, 'reference': 'QK12AB34'},
        ], makeClientRef: () => 'sale_test_0001');
        expect(body['lines'], [
          {
            'productId': 'p1',
            'variant': 'Chocolate',
            'qty': 2,
            'discountTzs': 5000,
          },
          {'productId': 'p2', 'qty': 1},
        ]);
        expect(body['discountTzs'], 1000);
        expect(body['note'], 'thanks');
        expect(body['clientRef'], 'sale_test_0001');
      },
    );

    test('draft round-trips through JSON', () {
      final cart = cartOf([
        PosLine(
          productId: 'p1',
          variant: 'L',
          name: 'Tee',
          listPriceTzs: 20000,
          qty: 3,
          unitPriceTzs: 18000,
          discountTzs: 1000,
        ),
      ], saleDiscount: 500)..note = 'n';
      final back = PosCart.fromJson(cart.toJson());
      expect(back.toJson(), cart.toJson());
      expect(back.totals.totalTzs, cart.totals.totalTzs);
    });

    test('Edit sale keeps the original soldAt and gets a new clientRef', () {
      final cart = PosCart.fromQueuedRequest(
        {
          'clientRef': 'sale_old_000001',
          'soldAt': '2026-10-18T08:00:00.000Z',
          'lines': [
            {'productId': 'p1', 'qty': 3},
          ],
          'payments': [],
        },
        [
          {'name': 'Whey', 'listPriceTzs': 45000},
        ],
        replaces: 'sale_old_000001',
      );
      expect(cart.lines.single.name, 'Whey');
      cart.setQty(cart.lines.single, 2);
      final body = cart.requestBody(const []);
      expect(body['soldAt'], '2026-10-18T08:00:00.000Z');
      expect(body['clientRef'], isNot('sale_old_000001'));
      expect(cart.replacesClientRef, 'sale_old_000001');
    });

    test('tempRef is the last 6 characters in capitals', () {
      expect(tempRefOf('sale_00ab12cd34ef'), 'CD34EF');
    });
  });

  group('payments and change', () {
    PaymentCheck check(int total, List<PaymentRow> rows) =>
        PaymentCheck(total, rows);

    test('cash exact completes with no change', () {
      final c = check(45000, [PaymentRow(method: 'cash', amountTzs: 45000)]);
      expect(c.canComplete, isTrue);
      expect(c.changeTzs, 0);
    });

    test('cash 50,000 on 45,000 gives change 5,000', () {
      final c = check(45000, [PaymentRow(method: 'cash', amountTzs: 50000)]);
      expect(c.canComplete, isTrue);
      expect(c.changeTzs, 5000);
    });

    test('split cash 20,000 + M-Pesa 25,000 with a reference completes', () {
      final c = check(45000, [
        PaymentRow(method: 'cash', amountTzs: 20000),
        PaymentRow(method: 'mpesa', amountTzs: 25000, reference: 'QK12AB34'),
      ]);
      expect(c.canComplete, isTrue);
      expect(c.toRequest(), [
        {'method': 'cash', 'amountTzs': 20000},
        {'method': 'mpesa', 'amountTzs': 25000, 'reference': 'QK12AB34'},
      ]);
    });

    test(
      'M-Pesa without a reference cannot complete; card without one can',
      () {
        expect(
          check(45000, [
            PaymentRow(method: 'mpesa', amountTzs: 45000),
          ]).canComplete,
          isFalse,
        );
        expect(
          check(45000, [
            PaymentRow(method: 'card', amountTzs: 45000),
          ]).canComplete,
          isTrue,
        );
        for (final m in referenceRequiredMethods) {
          expect(
            check(1, [PaymentRow(method: m, amountTzs: 1)]).missingReferences,
            [0],
            reason: m,
          );
        }
      },
    );

    test('M-Pesa over the total is refused (only cash gives change)', () {
      final c = check(45000, [
        PaymentRow(method: 'mpesa', amountTzs: 50000, reference: 'X1'),
      ]);
      expect(c.nonCashOver, isTrue);
      expect(c.overMethod, 'mpesa');
      expect(c.canComplete, isFalse);
      expect(c.changeTzs, 0);
    });

    test('cash + non-cash over: change only up to the cash', () {
      final ok = check(45000, [
        PaymentRow(method: 'mpesa', amountTzs: 40000, reference: 'X1'),
        PaymentRow(method: 'cash', amountTzs: 10000),
      ]);
      expect(ok.changeTzs, 5000);
      expect(ok.canComplete, isTrue);
      final bad = check(45000, [
        PaymentRow(method: 'mpesa', amountTzs: 44000, reference: 'X1'),
        PaymentRow(method: 'cash', amountTzs: 500),
        PaymentRow(method: 'card', amountTzs: 2000),
      ]);
      expect(bad.nonCashOver, isTrue);
      expect(bad.canComplete, isFalse);
    });

    test('paying less keeps Complete disabled and shows what remains', () {
      final c = check(45000, [PaymentRow(method: 'cash', amountTzs: 40000)]);
      expect(c.remainingTzs, 5000);
      expect(c.canComplete, isFalse);
    });

    test('a row without a method blocks Complete', () {
      final c = check(45000, [
        PaymentRow(method: 'cash', amountTzs: 20000),
        PaymentRow(amountTzs: 25000),
      ]);
      expect(c.canComplete, isFalse);
    });

    test('total 0: nothing to pay, payments []', () {
      final c = check(0, [PaymentRow(method: 'cash', amountTzs: 0)]);
      expect(c.nothingToPay, isTrue);
      expect(c.canComplete, isTrue);
      expect(c.toRequest(), isEmpty);
    });

    test('quick cash: Exact plus round-ups, duplicates dropped', () {
      expect(quickCashAmounts(45000), [45000, 46000, 50000]);
      expect(quickCashAmounts(45500), [45500, 46000, 50000]);
      expect(quickCashAmounts(1200), [1200, 2000, 5000, 10000]);
      expect(quickCashAmounts(0), isEmpty);
    });

    test('methods in the spec order', () {
      expect(salePaymentMethods, [
        'cash',
        'mpesa',
        'airtel_money',
        'mixx',
        'halopesa',
        'card',
        'bank',
        'other',
      ]);
    });
  });

  group('error codes map to words, never the raw code', () {
    test('known codes', () {
      expect(saleErrorKey('insufficient_stock'), 'vendor.sync.conflictStock');
      expect(saleErrorKey('payment_short'), 'vendor.pos.short');
      expect(
        saleErrorKey('invalid_payment', reason: 'change_too_large'),
        'vendor.pos.err.changeTooLarge',
      );
      expect(
        saleErrorKey('invalid_payment', reason: 'paid_too_large'),
        'vendor.pos.err.paidTooLarge',
      );
      expect(saleErrorKey('reference_required'), 'vendor.pos.err.payment');
      expect(saleErrorKey('product_unavailable'), 'vendor.pos.err.unavailable');
      expect(
        saleErrorKey('sold_at_out_of_range'),
        'vendor.sync.conflictTooOld',
      );
      expect(saleErrorKey('vendor_suspended'), 'vendor.sales.suspended');
      expect(saleErrorKey('something_new'), 'vendor.sync.conflictOther');
    });

    test('every key it can answer exists in English and Swahili', () {
      final keys = {
        for (final c in [
          'insufficient_stock',
          'payment_short',
          'discount_exceeds_price',
          'invalid_payment',
          'product_not_found',
          'sold_at_out_of_range',
          'vendor_permission_forbidden',
          'vendor_suspended',
          'x',
        ])
          saleErrorKey(c),
        saleErrorKey('invalid_payment', reason: 'change_too_large'),
        saleErrorKey('invalid_payment', reason: 'paid_too_large'),
      };
      for (final k in keys) {
        expect(FFLocale.textOf('en', k), isNotNull, reason: k);
        expect(FFLocale.textOf('sw', k), isNotNull, reason: k);
      }
    });
  });

  group('receipt', () {
    final sale = {
      'id': 'sal_1',
      'number': 'R-000123',
      'status': 'completed',
      'soldAt': '2026-10-19T11:05:00.000Z',
      'recordedAt': '2026-10-19T11:05:02.000Z',
      'subtotalTzs': 100000,
      'lineDiscountTzs': 5000,
      'discountTzs': 0,
      'totalTzs': 95000,
      'paidTzs': 100000,
      'changeTzs': 5000,
      'createdBy': {'id': 'u1', 'name': 'Asha'},
      'lines': [
        {
          'nameSnapshot': 'Whey 1kg',
          'variant': 'Chocolate',
          'qty': 2,
          'listPriceTzs': 45000,
          'unitPriceTzs': 45000,
          'discountTzs': 5000,
          'lineTotalTzs': 85000,
        },
        {
          'nameSnapshot': 'Shaker',
          'variant': null,
          'qty': 1,
          'listPriceTzs': 10000,
          'unitPriceTzs': 10000,
          'discountTzs': 0,
          'lineTotalTzs': 10000,
        },
      ],
      'payments': [
        {'method': 'cash', 'amountTzs': 60000, 'reference': null},
        {'method': 'mpesa', 'amountTzs': 40000, 'reference': 'QK12AB34'},
      ],
    };

    test('share text holds the receipt in English (EAT time)', () {
      final data = ReceiptData.fromSale(
        sale,
        profile: {'businessName': 'Dar Gear'},
      );
      final en = FFLocale()..set(const Locale('en'));
      final text = receiptShareText(data, en.t, 'en');
      expect(text, contains('Dar Gear'));
      expect(text, contains('Receipt R-000123'));
      expect(text, contains('19 Oct 2026, 14:05'));
      expect(text, contains('2 x Whey 1kg (Chocolate)'));
      expect(text, contains('M-Pesa (QK12AB34)'));
      expect(text, contains('Change'));
      expect(text, contains('Served by Asha'));
      expect(text, contains('Payment received by Dar Gear.'));
      expect(text, contains('This is not a TRA fiscal receipt.'));
      expect(text, isNot(contains('TZS')));
      // Columns hold at 32 characters; a long method + reference wraps
      // and its amount stays right-aligned under it.
      for (final line in text.split('\n')) {
        if (line.contains('Payment received') || line.contains('fiscal')) {
          continue;
        }
        expect(line.length, lessThanOrEqualTo(32), reason: line);
      }
      final long = ReceiptData.fromSale({
        ...sale,
        'payments': [
          {
            'method': 'airtel_money',
            'amountTzs': 100000,
            'reference': 'AB12CD34EF56GH',
          },
        ],
      });
      final lines = receiptShareText(long, en.t, 'en').split('\n');
      final i = lines.indexOf('Airtel Money (AB12CD34EF56GH)');
      expect(i, greaterThan(0));
      expect(lines[i + 1], '${' ' * 25}100,000');
    });

    test('share text in Kiswahili uses the Swahili labels', () {
      final data = ReceiptData.fromSale(
        sale,
        profile: {'businessName': 'Dar Gear'},
      );
      final sw = FFLocale()..set(const Locale('sw'));
      final text = receiptShareText(data, sw.t, 'sw');
      expect(text, contains('Risiti R-000123'));
      expect(text, contains('Taslimu'));
      expect(text, contains('Chenji'));
      expect(text, contains('Hii si risiti ya kodi ya TRA.'));
      expect(text, isNot(contains('Served by')));
    });

    test('a queued sale is a provisional receipt with its temp ref', () {
      final data = ReceiptData.fromQueued(
        {
          'clientRef': 'sale_abcdef123456',
          'soldAt': '2026-10-19T11:05:00.000Z',
          'lines': [
            {'productId': 'p1', 'qty': 2, 'discountTzs': 1000},
          ],
          'payments': [
            {'method': 'cash', 'amountTzs': 100000},
          ],
        },
        {
          'business': 'Dar Gear',
          'servedBy': 'Asha',
          'lines': [
            {'name': 'Whey', 'listPriceTzs': 45000},
          ],
        },
      );
      expect(data.queued, isTrue);
      expect(data.totalTzs, 89000);
      expect(data.changeTzs, 11000);
      final en = FFLocale()..set(const Locale('en'));
      expect(
        receiptShareText(data, en.t, 'en'),
        contains('Provisional receipt, number to follow (ref 123456)'),
      );
    });

    test('recorded more than 5 minutes late is "recorded offline"', () {
      expect(
        recordedLate('2026-10-19T10:00:00Z', '2026-10-19T10:04:59Z'),
        isFalse,
      );
      expect(
        recordedLate('2026-10-19T10:00:00Z', '2026-10-19T10:05:01Z'),
        isTrue,
      );
      final late = ReceiptData.fromSale({...sale, 'lateRecorded': true});
      expect(late.lateRecorded, isTrue);
    });
  });
}
