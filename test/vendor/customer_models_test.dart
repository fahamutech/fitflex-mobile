// Vendor tools · S4: the pure rules — allocation preview (oldest due first),
// over-payment, manual split, references, pay-later checks, aging buckets,
// due-date range, names of forgotten customers, phone normalisation, the
// plain-text documents (no contact details) and the POS draft keeping the
// customer's id only.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/customers/customer_models.dart';
import 'package:fitflexmobile/screens/vendor/sales/receipt_data.dart';
import 'package:fitflexmobile/screens/vendor/sales/sale_models.dart';
import 'package:fitflexmobile/shared/i18n.dart';

import 'customers_support.dart';

String en(String k) => FFLocale().t(k);

void main() {
  final open = openSalesOf(profile()['customer'] as Map);

  group('allocation preview (AC-24)', () {
    test('25,000 pays off R-000001 then 5,000 of R-000002', () {
      final lines = allocateOldestFirst(open, 25000);
      expect(lines.map((l) => (l.sale.number, l.amountTzs)), [
        ('R-000001', 20000),
        ('R-000002', 5000),
      ]);
      expect(lines.first.paysOff, isTrue);
      expect(lines.last.paysOff, isFalse);
      expect(lines.last.leftTzs, 25000);
    });

    test('open sales are ordered by due date whatever the server order', () {
      final c = profile()['customer'] as Map;
      final reversed = {
        ...c,
        'openSales': (c['openSales'] as List).reversed.toList(),
      };
      expect(openSalesOf(reversed).map((s) => s.number), [
        'R-000001',
        'R-000002',
      ]);
    });
  });

  group('payment check', () {
    CustomerPaymentCheck check({
      int amount = 25000,
      String method = 'cash',
      String reference = '',
      Map<String, int>? manual,
      bool online = true,
    }) => CustomerPaymentCheck(
      owedTzs: 50000,
      amountTzs: amount,
      method: method,
      reference: reference,
      openSales: open,
      manual: manual,
      online: online,
    );

    test('over-payment (O-8) is refused: no Save', () {
      final c = check(amount: 50001);
      expect(c.overOwed, isTrue);
      expect(c.canSave, isFalse);
      expect(c.preview, isEmpty);
      expect(check(amount: 50000).canSave, isTrue);
    });

    test('M-Pesa needs a reference; cash never sends one', () {
      expect(check(method: 'mpesa').canSave, isFalse);
      expect(check(method: 'mpesa', reference: 'qk1').canSave, isTrue);
      expect(
        check(
          method: 'mpesa',
          reference: 'qk1',
        ).toRequest(clientRef: 'pay_12345678')['reference'],
        'QK1',
      );
      expect(
        check(
          method: 'cash',
          reference: 'x',
        ).toRequest(clientRef: 'pay_12345678').containsKey('reference'),
        isFalse,
      );
    });

    test('manual split must add up (AC-25) and not exceed a balance', () {
      final ok = check(manual: {'sal_b': 25000});
      expect(ok.allocMismatch, isFalse);
      expect(ok.canSave, isTrue);
      expect(ok.toRequest(clientRef: 'pay_12345678')['allocations'], [
        {'saleId': 'sal_b', 'amountTzs': 25000},
      ]);
      final short = check(manual: {'sal_b': 20000});
      expect(short.allocMismatch, isTrue);
      expect(short.canSave, isFalse);
      final over = check(manual: {'sal_a': 25000});
      expect(over.allocOverBalance, isTrue);
      expect(over.canSave, isFalse);
    });

    test('receivedOn is sent only when the vendor picked a day', () {
      expect(
        check().toRequest(clientRef: 'pay_12345678').containsKey('receivedOn'),
        isFalse,
      );
      expect(
        check().toRequest(
          clientRef: 'pay_12345678',
          receivedOn: '2026-10-19',
        )['receivedOn'],
        '2026-10-19',
      );
    });

    test('offline: Save stays off (never queued)', () {
      expect(check(online: false).canSave, isFalse);
    });
  });

  group('pay later (credit) check', () {
    test('paid now below the total, zero allowed; never change', () {
      final none = CreditCheck(95000, [PaymentRow(method: 'cash')]);
      expect(none.rows, isEmpty);
      expect(none.balanceTzs, 95000);
      expect(
        none.canComplete(hasCustomer: true, hasDueDate: true, online: true),
        isTrue,
      );
      final part = CreditCheck(95000, [
        PaymentRow(method: 'cash', amountTzs: 20000),
      ]);
      expect(part.balanceTzs, 75000);
      final full = CreditCheck(95000, [
        PaymentRow(method: 'cash', amountTzs: 95000),
      ]);
      expect(full.fullyPaid, isTrue);
      expect(
        full.canComplete(hasCustomer: true, hasDueDate: true, online: true),
        isFalse,
      );
      final over = CreditCheck(95000, [
        PaymentRow(method: 'cash', amountTzs: 100000),
      ]);
      expect(over.wouldGiveChange, isTrue);
    });

    test('needs a customer, a due date, a connection and references', () {
      final c = CreditCheck(95000, [
        PaymentRow(method: 'mpesa', amountTzs: 20000),
      ]);
      expect(
        c.canComplete(hasCustomer: true, hasDueDate: true, online: true),
        isFalse,
      );
      final ok = CreditCheck(95000, [
        PaymentRow(method: 'cash', amountTzs: 20000),
      ]);
      expect(
        ok.canComplete(hasCustomer: false, hasDueDate: true, online: true),
        isFalse,
      );
      expect(
        ok.canComplete(hasCustomer: true, hasDueDate: true, online: false),
        isFalse,
      );
    });

    test('permission rule: both sales and customers, both tools', () {
      expect(
        payLaterAllowed(
          customersFlag: true,
          walkInSales: true,
          canSales: true,
          canCustomers: false,
        ),
        isFalse,
      );
      expect(
        payLaterAllowed(
          customersFlag: false,
          walkInSales: true,
          canSales: true,
          canCustomers: true,
        ),
        isFalse,
      );
      expect(
        payLaterAllowed(
          customersFlag: true,
          walkInSales: true,
          canSales: true,
          canCustomers: true,
        ),
        isTrue,
      );
    });

    test('due date: sale day up to +365 (AC-19), default +7', () {
      expect(dueDateInRange('2026-10-20', '2026-10-20'), isTrue);
      expect(dueDateInRange('2026-10-19', '2026-10-20'), isFalse);
      expect(dueDateInRange('2027-10-20', '2026-10-20'), isTrue);
      expect(dueDateInRange('2027-10-21', '2026-10-20'), isFalse);
      expect(addDaysTo('2026-10-20', defaultDueDays), '2026-10-27');
    });

    test('request body: credit kind, due date and customer id', () {
      final cart = PosCart()
        ..addOne(productId: 'p1', name: 'Whey', priceTzs: 95000)
        ..setCustomer('cus_1', name: 'Juma');
      final body = cart.requestBody(
        [
          {'method': 'cash', 'amountTzs': 20000},
        ],
        creditDueDate: '2026-10-27',
        makeClientRef: () => 'sale_12345678',
      );
      expect(body['kind'], 'credit');
      expect(body['dueDate'], '2026-10-27');
      expect(body['customerId'], 'cus_1');
      expect(body.containsKey('soldAt'), isFalse);
      final cash = cart.requestBody(const []);
      expect(cash.containsKey('kind'), isFalse);
      expect(cash['customerId'], 'cus_1');
    });

    test('the draft keeps the customer id only, never the name', () {
      final cart = PosCart()
        ..addOne(productId: 'p1', name: 'Whey', priceTzs: 95000)
        ..setCustomer('cus_1', name: 'Juma Mussa', owedTzs: 7777);
      final stored = jsonEncode(cart.toJson());
      expect(stored, contains('cus_1'));
      expect(stored, isNot(contains('Juma')));
      expect(stored, isNot(contains('7777')));
      final back = PosCart.fromJson(jsonDecode(stored));
      expect(back.customerId, 'cus_1');
      expect(back.customerName, isNull);
    });

    test('another customer is another sale: a new key', () {
      final cart = PosCart()
        ..addOne(productId: 'p1', name: 'Whey', priceTzs: 95000);
      cart.requestBody(const [], makeClientRef: () => 'sale_aaaaaaaa');
      expect(cart.clientRef, 'sale_aaaaaaaa');
      cart.setCustomer('cus_1');
      expect(cart.clientRef, isNull);
    });
  });

  group('aging (§10.2, AC-34 with EAT today = 20 Oct)', () {
    int days(String due) => daysBetween('2026-10-20', due);
    test('buckets', () {
      expect(agingBucketOf(days('2026-10-20')), 'current');
      expect(agingBucketOf(days('2026-10-19')), 'd1_30');
      expect(agingBucketOf(days('2026-09-19')), 'd31_60');
      expect(agingBucketOf(days('2026-07-21')), 'd90plus');
      expect(agingBucketOf(61), 'd61_90');
    });

    test('EAT today flips at 21:00 UTC', () {
      expect(eatTodayString(DateTime.utc(2026, 10, 19, 20, 59)), '2026-10-19');
      expect(eatTodayString(DateTime.utc(2026, 10, 19, 21, 0)), '2026-10-20');
    });

    test('payments: up to 30 days back, never future (Q-4)', () {
      final r = receivedOnRange('2026-10-20');
      expect(r.earliest, '2026-09-20');
      expect(r.latest, '2026-10-20');
    });
  });

  group('names and phones', () {
    test('forgotten app customer → "Deleted member"', () {
      expect(
        customerDisplayName({
          'name': null,
          'forgotten': true,
          'source': 'marketplace',
        }, en),
        'Deleted member',
      );
      expect(customerDisplayName({'name': 'Juma'}, en), 'Juma');
    });

    test('phone ending, never the full number', () {
      expect(phoneEnding({'phoneLast3': '234'}), '•••• 234');
      expect(phoneEnding({'phone': '+255712345234'}), '•••• 234');
      expect(phoneEnding({'phone': null}), isNull);
    });

    test('Tanzanian phone normalisation (AC-10)', () {
      expect(normaliseTzPhone('0712345678'), '+255712345678');
      expect(normaliseTzPhone('712 345 678'), '+255712345678');
      expect(normaliseTzPhone('+255 612-345-678'), '+255612345678');
      expect(normaliseTzPhone('0812345678'), isNull);
      expect(normaliseTzPhone('12345'), isNull);
    });
  });

  group('plain-text documents', () {
    test('payment receipt (§7.2): sales paid and still owed', () {
      final text = paymentShareText(
        paymentJson(),
        customerName: 'Juma M.',
        stillOwedTzs: 25000,
        business: 'Dar Gear',
        t: en,
        lang: 'en',
      );
      expect(text, contains('Payment PMT-000001'));
      expect(text, contains('Customer: Juma M.'));
      expect(text, contains('R-000001'));
      expect(text, contains('Still owed'));
      expect(text, contains('not a TRA fiscal receipt.'));
    });

    test('statement (§7.3): open sales, total, no phone', () {
      final c = profile()['customer'] as Map;
      final text = statementShareText(
        customer: c,
        payments: [
          paymentJson(),
          paymentJson(id: 'p2', status: 'voided'),
        ],
        business: 'Dar Gear',
        t: en,
        lang: 'en',
      );
      expect(text, contains('Statement for Juma Mussa'));
      expect(text, contains('R-000002'));
      expect(text, contains('12 days overdue'));
      expect(text, contains('Total owed'));
      expect(text, isNot(contains('+255')));
      expect('PMT-000001'.allMatches(text).length, 1);
    });

    test('credit receipt share: paid now, balance, due by; no change', () {
      final r = ReceiptData.fromSale(
        {
          'id': 'sal_c',
          'number': 'R-000009',
          'status': 'completed',
          'kind': 'credit',
          'soldAt': '2026-10-20T08:00:00.000Z',
          'subtotalTzs': 95000,
          'lineDiscountTzs': 0,
          'discountTzs': 0,
          'totalTzs': 95000,
          'paidTzs': 20000,
          'changeTzs': 0,
          'paidAtSaleTzs': 20000,
          'balanceTzs': 75000,
          'dueDate': '2026-10-27',
          'customer': {'id': 'cus_1', 'name': 'Juma M.'},
          'lines': [],
          'payments': [
            {'method': 'cash', 'amountTzs': 20000},
          ],
        },
        profile: {'businessName': 'Dar Gear'},
      );
      final text = receiptShareText(r, en, 'en');
      expect(text, contains('Customer: Juma M.'));
      expect(text, contains('Paid now'));
      expect(text, contains('Balance due'));
      expect(text, contains('27 Oct 2026'));
      expect(text, contains('Dar Gear recorded the balance due.'));
      expect(text, isNot(contains('Change')));
    });

    test('a queued sale with a customer: "Customer shown after sync"', () {
      final r = ReceiptData.fromQueued(
        {
          'clientRef': 'sale_12345678',
          'lines': [],
          'payments': [],
          'customerId': 'cus_1',
        },
        {'business': 'Dar Gear'},
      );
      expect(
        receiptShareText(r, en, 'en'),
        contains('Customer shown after sync'),
      );
    });
  });

  test('customer conflicts on sync', () {
    expect(isCustomerConflict('customer_archived', const {}), isTrue);
    expect(
      isCustomerConflict('feature_disabled', const {'feature': 'customers'}),
      isTrue,
    );
    expect(isCustomerConflict('feature_disabled', const {}), isFalse);
  });
}
