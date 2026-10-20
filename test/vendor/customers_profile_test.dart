// Vendor tools · S4: the customer profile (owed, aging, open sales, A-02 for
// app customers, "Deleted member"), recording a payment (allocation
// preview, over-payment, manual split, server races, retry with the same
// key), the payment receipt and its void rules, the add/edit form, and a
// credit sale's void refused while payments are allocated.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fitflexmobile/screens/vendor/customers/customer_form_page.dart';
import 'package:fitflexmobile/screens/vendor/customers/customer_models.dart';
import 'package:fitflexmobile/screens/vendor/customers/customer_profile_page.dart';
import 'package:fitflexmobile/screens/vendor/customers/payment_sheets.dart';
import 'package:fitflexmobile/screens/vendor/sales/sale_detail_page.dart';

import '../support/recording_api.dart';
import 'customers_support.dart';
import 'walkin_support.dart';

const tall = Size(420, 1400);

void seedProfile(
  RecordingApi api, {
  Map<String, dynamic>? customer,
  List<Map<String, dynamic>> payments = const [],
}) {
  api.on('GET /vendor/tools/options', customersOn);
  api.on('GET /vendor/profile', {'businessName': 'Dar Gear'});
  api.on('GET /vendor/customers/cus_1', customer ?? profile());
  api.on('GET /vendor/customers/cus_1/sales', {
    'sales': [],
    'nextCursor': null,
    'summary': {},
  });
  api.on('GET /vendor/customers/cus_1/payments', {
    'payments': payments,
    'nextCursor': null,
  });
  api.on('GET /vendor/customers/cus_1/orders', {
    'orders': [],
    'nextCursor': null,
  });
}

Future<PageHost> pumpProfile(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = ownerUser,
  String lang = 'en',
  Size size = tall,
}) => pumpPage(
  tester,
  api,
  const CustomerProfilePage(customerId: 'cus_1'),
  user: user,
  lang: lang,
  size: size,
  extraRoutes: customerRoutes,
);

Future<void> openRecordPayment(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('customer-record-payment')));
}

void main() {
  setUpAll(loadAppFonts);

  apiTest('walk-in profile: owes, aging, open sales oldest first, Call', (
    tester,
    api,
  ) async {
    seedProfile(api);
    final host = await pumpProfile(tester, api);
    expect(find.byKey(const Key('customer-name-heading')), findsOneWidget);
    expect(find.text('Juma Mussa'), findsWidgets);
    expect(find.byKey(const Key('customer-owed')), findsOneWidget);
    expect(find.text('TSh 50,000'), findsWidgets);
    expect(find.text(host.tr('vendor.aging.current')), findsOneWidget);
    expect(find.text(host.tr('vendor.aging.d90plus')), findsOneWidget);
    expect(verticalOrder(tester, ['R-000001', 'R-000002']), [
      'R-000001',
      'R-000002',
    ]);
    expect(find.byKey(const Key('customer-call')), findsOneWidget);
  });

  apiTest('app customer (A-02): no phone, no Call, contact hint', (
    tester,
    api,
  ) async {
    seedProfile(
      api,
      customer: profile(source: 'marketplace', name: 'Neema', phone: null),
    );
    final host = await pumpProfile(tester, api);
    expect(find.byKey(const Key('customer-call')), findsNothing);
    expect(find.textContaining('+255'), findsNothing);
    expect(
      find.text(host.tr('vendor.customers.appContactHint')),
      findsOneWidget,
    );
  });

  apiTest('forgotten app customer: "Deleted member", no note', (
    tester,
    api,
  ) async {
    seedProfile(
      api,
      customer: profile(
        source: 'marketplace',
        name: null,
        forgotten: true,
        phone: null,
      ),
    );
    await pumpProfile(tester, api);
    expect(find.text('Deleted member'), findsWidgets);
    expect(find.byKey(const Key('customer-note-text')), findsNothing);
  });

  apiTest('record payment: preview oldest first, request, receipt (AC-24)', (
    tester,
    api,
  ) async {
    seedProfile(api);
    api.onCall(
      'POST /vendor/customers/cus_1/payments',
      (_) => {
        'payment': paymentJson(),
        'customer': {'owedTzs': 25000},
      },
    );
    await pumpProfile(tester, api);
    await openRecordPayment(tester);
    await typeInto(tester, find.byKey(const Key('pay-amount')), '25000');
    await tester.pumpAndSettle();
    expect(find.text('Pays off R-000001 (TSh 20,000)'), findsOneWidget);
    expect(
      find.text('Pays TSh 5,000 of R-000002 (TSh 25,000 left)'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('pay-notice')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pay-save')));
    final body =
        api.only('POST', '/vendor/customers/cus_1/payments').body as Map;
    expect(body['amountTzs'], 25000);
    expect(body['method'], 'cash');
    expect(body['clientRef'], startsWith('pay_'));
    expect(body.containsKey('receivedOn'), isFalse);
    expect(body.containsKey('allocations'), isFalse);
    expect(find.byKey(const Key('payment-receipt')), findsOneWidget);
    expect(find.byKey(const Key('payment-still-owed')), findsOneWidget);
  });

  apiTest('over-payment (AC-26): message and Save off; server race too', (
    tester,
    api,
  ) async {
    seedProfile(api);
    api.fail('POST /vendor/customers/cus_1/payments', 409, {
      'error': 'overpayment',
      'owedTzs': 10000,
    });
    await pumpProfile(tester, api);
    await openRecordPayment(tester);
    await typeInto(tester, find.byKey(const Key('pay-amount')), '60000');
    await tester.pumpAndSettle();
    expect(
      find.textContaining("more than the TSh 50,000 owed"),
      findsOneWidget,
    );
    expect(isEnabled(tester, find.byKey(const Key('pay-save'))), isFalse);
    await typeInto(tester, find.byKey(const Key('pay-amount')), '20000');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('pay-save')));
    // Someone else was paid first: owed is now 10,000; nothing saved.
    expect(
      find.textContaining("more than the TSh 10,000 owed"),
      findsOneWidget,
    );
    expect(isEnabled(tester, find.byKey(const Key('pay-save'))), isFalse);
  });

  apiTest('choose sales (AC-25): mismatch blocks Save; split sent', (
    tester,
    api,
  ) async {
    seedProfile(api);
    api.onCall(
      'POST /vendor/customers/cus_1/payments',
      (_) => {
        'payment': paymentJson(),
        'customer': {'owedTzs': 25000},
      },
    );
    await pumpProfile(tester, api);
    await openRecordPayment(tester);
    await typeInto(tester, find.byKey(const Key('pay-amount')), '25000');
    await tapVisible(tester, find.byKey(const Key('pay-choose-sales')));
    await typeInto(tester, find.byKey(const Key('pay-alloc-sal_a')), '');
    await typeInto(tester, find.byKey(const Key('pay-alloc-sal_b')), '20000');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pay-alloc-mismatch')), findsOneWidget);
    expect(isEnabled(tester, find.byKey(const Key('pay-save'))), isFalse);
    await typeInto(tester, find.byKey(const Key('pay-alloc-sal_b')), '25000');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('pay-save')));
    final body =
        api.only('POST', '/vendor/customers/cus_1/payments').body as Map;
    expect(body['allocations'], [
      {'saleId': 'sal_b', 'amountTzs': 25000},
    ]);
  });

  apiTest('mobile money needs a reference before Save (AC-27)', (
    tester,
    api,
  ) async {
    seedProfile(api);
    await pumpProfile(tester, api);
    await openRecordPayment(tester);
    await typeInto(tester, find.byKey(const Key('pay-amount')), '5000');
    await tapVisible(tester, find.byKey(const Key('pay-method-mpesa')));
    expect(isEnabled(tester, find.byKey(const Key('pay-save'))), isFalse);
    await typeInto(tester, find.byKey(const Key('pay-reference')), 'qk1');
    await tester.pumpAndSettle();
    expect(isEnabled(tester, find.byKey(const Key('pay-save'))), isTrue);
  });

  apiTest('no answer: not saved, Try again uses the same key (AC-28)', (
    tester,
    api,
  ) async {
    seedProfile(api);
    api.onCall(
      'POST /vendor/customers/cus_1/payments',
      (_) => throw http.ClientException('offline'),
    );
    final host = await pumpProfile(tester, api);
    await openRecordPayment(tester);
    await typeInto(tester, find.byKey(const Key('pay-amount')), '5000');
    await tapVisible(tester, find.byKey(const Key('pay-save')));
    await tester.pumpAndSettle();
    expect(find.text(host.tr('vendor.pay.failed')), findsOneWidget);
    final first = api.where('POST', '/vendor/customers/cus_1/payments').first;
    api.onCall(
      'POST /vendor/customers/cus_1/payments',
      (_) => {
        'payment': paymentJson(amount: 5000),
        'customer': {'owedTzs': 45000},
      },
    );
    await tapVisible(tester, find.byKey(const Key('pay-save')));
    final last = api.where('POST', '/vendor/customers/cus_1/payments').last;
    expect((last.body as Map)['clientRef'], (first.body as Map)['clientRef']);
  });

  apiTest('void a payment (AC-30): reason required, then voided', (
    tester,
    api,
  ) async {
    seedProfile(api, payments: [paymentJson()]);
    api.onCall(
      'POST /vendor/customers/cus_1/payments/pmt_1/void',
      (_) => {
        'payment': paymentJson(status: 'voided'),
        'customer': {'owedTzs': 50000},
      },
    );
    await pumpProfile(tester, api);
    await tapVisible(tester, find.text('Payments').last);
    await tapVisible(tester, find.byKey(const Key('customer-payment-pmt_1')));
    await tapVisible(tester, find.byKey(const Key('payment-void')));
    expect(
      isEnabled(tester, find.byKey(const Key('payment-void-confirm'))),
      isFalse,
    );
    await typeInto(
      tester,
      find.byKey(const Key('payment-void-reason')),
      'Wrong customer',
    );
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('payment-void-confirm')));
    expect(
      api.only('POST', '/vendor/customers/cus_1/payments/pmt_1/void').body,
      {'reason': 'Wrong customer'},
    );
    expect(find.byKey(const Key('payment-voided-badge')), findsOneWidget);
    expect(find.byKey(const Key('payment-voided-by')), findsOneWidget);
    // Voided payments cannot be shared.
    expect(find.byKey(const Key('payment-share')), findsNothing);
  });

  test('payment void rule mirrors the server (#224 M2)', () {
    final today = eatTodayString();
    final own = paymentJson(recordedBy: 's1', receivedOn: today);
    expect(canVoidPayment(ownerUser, own), isTrue);
    expect(
      canVoidPayment(staffUser(['customers'], role: 'support'), own),
      isTrue,
    );
    expect(
      canVoidPayment(
        staffUser(['customers'], role: 'support'),
        paymentJson(recordedBy: 'other', receivedOn: today),
      ),
      isFalse,
    );
    expect(
      canVoidPayment(
        staffUser(['customers'], role: 'support'),
        paymentJson(recordedBy: 's1', receivedOn: '2020-01-01'),
      ),
      isFalse,
    );
    expect(
      canVoidPayment(
        staffUser(['customers'], role: 'admin'),
        paymentJson(recordedBy: 'other', receivedOn: '2020-01-01'),
      ),
      isTrue,
    );
    expect(canVoidPayment(staffUser(['sales']), own), isFalse);
    expect(canVoidPayment(ownerUser, paymentJson(status: 'voided')), isFalse);
  });

  apiTest('form for an app customer: no contact fields, note only (AC-9)', (
    tester,
    api,
  ) async {
    seedProfile(
      api,
      customer: profile(source: 'marketplace', name: 'Neema', phone: null),
    );
    api.onCall(
      'PUT /vendor/customers/cus_1',
      (_) => {
        'customer':
            (profile(source: 'marketplace', name: 'Neema')['customer'] as Map),
        'phoneDuplicate': null,
      },
    );
    await pumpPage(
      tester,
      api,
      const CustomerFormPage(customerId: 'cus_1'),
      size: tall,
      extraRoutes: customerRoutes,
    );
    expect(find.byKey(const Key('customer-phone')), findsNothing);
    expect(find.byKey(const Key('customer-email')), findsNothing);
    expect(find.byKey(const Key('customer-address')), findsNothing);
    await typeInto(tester, find.byKey(const Key('customer-note')), 'VIP');
    await tapVisible(tester, find.byKey(const Key('customer-save')));
    final body = api.only('PUT', '/vendor/customers/cus_1').body as Map;
    expect(body.keys.toSet(), {'note', 'updatedAt'});
  });

  apiTest('add walk-in customer (AC-10): phone normalised; bad phone shown', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/tools/options', customersOn);
    api.onCall(
      'POST /vendor/customers',
      (_) => {
        'customer': {'id': 'cus_n', 'source': 'manual', 'name': 'Rehema'},
        'phoneDuplicate': {'id': 'cus_1', 'name': 'Juma Mussa'},
      },
    );
    final host = await pumpPage(
      tester,
      api,
      const CustomerFormPage(),
      size: tall,
      extraRoutes: customerRoutes,
    );
    await typeInto(tester, find.byKey(const Key('customer-name')), 'Rehema');
    await typeInto(tester, find.byKey(const Key('customer-phone')), '0812');
    await tapVisible(tester, find.byKey(const Key('customer-save')));
    expect(find.text(host.tr('vendor.customers.phoneInvalid')), findsOneWidget);
    expect(api.sent('POST', '/vendor/customers'), isFalse);
    await typeInto(
      tester,
      find.byKey(const Key('customer-phone')),
      '0712345678',
    );
    await tapVisible(tester, find.byKey(const Key('customer-save')));
    final body = api.only('POST', '/vendor/customers').body as Map;
    expect(body['phone'], '+255712345678');
    expect(body['name'], 'Rehema');
    expect(textContaining('ROUTE-CUSTOMER cus_n'), findsOneWidget);
  });

  apiTest('archive while owing is refused with the amount (AC-11)', (
    tester,
    api,
  ) async {
    seedProfile(api);
    await pumpPage(
      tester,
      api,
      const CustomerFormPage(customerId: 'cus_1'),
      size: tall,
      extraRoutes: customerRoutes,
    );
    await tapVisible(tester, find.byKey(const Key('customer-archive')));
    expect(find.byKey(const Key('customer-archive-error')), findsOneWidget);
    expect(find.textContaining('TSh 50,000'), findsOneWidget);
    expect(api.sent('PUT', '/vendor/customers/cus_1'), isFalse);
  });

  apiTest('void of a credit sale with payments is refused (AC-33)', (
    tester,
    api,
  ) async {
    api.on('GET /vendor/tools/options', customersOn);
    api.on('GET /vendor/profile', {'businessName': 'Dar Gear'});
    api.on('GET /vendor/sales/sal_c', {
      'sale': {
        ...serverSale(id: 'sal_c', number: 'R-000009'),
        'kind': 'credit',
        'changeTzs': 0,
        'paidAtSaleTzs': 20000,
        'balanceTzs': 25000,
        'dueDate': '2026-10-27',
        'customer': {'id': 'cus_1', 'name': 'Juma Mussa'},
        'allocations': [
          {
            'paymentId': 'pmt_1',
            'number': 'PMT-000001',
            'amountTzs': 5000,
            'receivedOn': '2026-10-20',
            'voided': false,
          },
        ],
      },
    });
    api.fail('POST /vendor/sales/sal_c/void', 409, {
      'error': 'sale_has_payments',
      'payments': [
        {'id': 'pmt_1', 'number': 'PMT-000001'},
      ],
    });
    final host = await pumpPage(
      tester,
      api,
      const SaleDetailPage(saleId: 'sal_c'),
      size: tall,
      extraRoutes: [...salesRoutes.skip(1), ...customerRoutes],
    );
    expect(find.text('Customer: Juma Mussa'), findsOneWidget);
    expect(find.byKey(const Key('sale-detail-record-payment')), findsOneWidget);
    expect(find.byKey(const Key('sales-receipt-balance')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('sale-detail-void')));
    expect(find.text(host.tr('vendor.sales.voidCreditBody')), findsOneWidget);
    await typeInto(tester, find.byKey(const Key('sale-void-reason')), 'Oops');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('sale-void-confirm')));
    expect(find.textContaining('Void them first: PMT-000001'), findsOneWidget);
    expect(find.byKey(const Key('sale-void-payment-pmt_1')), findsOneWidget);
  });
}
