// Vendor tools · S4 in the POS: the customer chip and picker (sales-only
// staff see no amounts), pay later (credit) — request shape, default due
// date, zero paid now, never queued on a network failure, refusals — and a
// paid sale with a customer queued offline with the customer's id only.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/customers/customer_models.dart';
import 'package:fitflexmobile/screens/vendor/customers/customer_picker.dart';
import 'package:fitflexmobile/screens/vendor/sales/pos_page.dart';

import '../support/recording_api.dart';
import 'customers_support.dart';
import 'walkin_support.dart';

const wide = Size(1200, 1000);
const queueKey = 'vendor_sale_queue.v1.v1';

Future<PageHost> pumpPos(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = ownerUser,
  String lang = 'en',
}) => pumpPage(
  tester,
  api,
  const PosPage(),
  user: user,
  lang: lang,
  size: wide,
  extraRoutes: salesRoutes,
);

void seed(RecordingApi api, {Map<String, dynamic> tools = customersOn}) {
  seedPos(
    api,
    tools: tools,
    products: [posProduct('p1', 'Whey', price: 95000, stock: 5)],
  );
  seedCustomers(api);
}

Map<String, dynamic> creditSale() => {
  ...serverSale(id: 'sal_c', number: 'R-000009'),
  'kind': 'credit',
  'totalTzs': 95000,
  'paidTzs': 20000,
  'changeTzs': 0,
  'paidAtSaleTzs': 20000,
  'balanceTzs': 75000,
  'dueDate': '2026-10-27',
  'customer': {'id': 'cus_1', 'name': 'Juma Mussa'},
};

Future<void> addWhey(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('pos-product-p1')));
  await tester.pumpAndSettle();
}

Future<void> pickJuma(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('pos-customer-add')));
  await tapVisible(tester, find.byKey(const Key('picker-row-cus_1')));
}

Future<void> openPayment(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('pos-cart-charge')));
}

void main() {
  setUpAll(loadAppFonts);

  apiTest('customers off: no customer chip, no pay later', (tester, api) async {
    seed(api, tools: customersOff);
    await pumpPos(tester, api);
    await addWhey(tester);
    expect(find.byKey(const Key('pos-customer-add')), findsNothing);
    await openPayment(tester);
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '20000');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vendor-pos-paylater')), findsNothing);
  });

  apiTest('pick a customer: chip shows the name, × removes it', (
    tester,
    api,
  ) async {
    seed(api);
    await pumpPos(tester, api);
    await addWhey(tester);
    await pickJuma(tester);
    expect(find.byKey(const Key('pos-customer-name')), findsOneWidget);
    expect(find.text('Juma Mussa'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pos-customer-remove')));
    expect(find.byKey(const Key('pos-customer-add')), findsOneWidget);
  });

  apiTest('pay later (AC-15): credit body, due +7, receipt opens', (
    tester,
    api,
  ) async {
    seed(api);
    api.onCall('POST /vendor/sales', (_) => {'sale': creditSale()});
    await pumpPos(tester, api);
    await addWhey(tester);
    await pickJuma(tester);
    await openPayment(tester);
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '20000');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('vendor-pos-paylater')));
    expect(find.text('Pay later: TSh 75,000 owed'), findsOneWidget);
    expect(find.text('Balance due: TSh 75,000'), findsOneWidget);
    // Juma already owes 50,000: a warning, not a block (Q-5).
    expect(find.byKey(const Key('pos-credit-already-owes')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pos-credit-complete')));
    final body = api.only('POST', '/vendor/sales').body as Map;
    expect(body['kind'], 'credit');
    expect(body['customerId'], 'cus_1');
    expect(body['dueDate'], addDaysTo(eatTodayString(), 7));
    expect(body['payments'], [
      {'method': 'cash', 'amountTzs': 20000},
    ]);
    expect(body.containsKey('soldAt'), isFalse);
    expect(textContaining('ROUTE-RECEIPT sal_c'), findsOneWidget);
  });

  apiTest('pay later with nothing paid now (AC-16) and 14-day due', (
    tester,
    api,
  ) async {
    seed(api);
    api.onCall('POST /vendor/sales', (_) => {'sale': creditSale()});
    await pumpPos(tester, api);
    await addWhey(tester);
    await pickJuma(tester);
    await openPayment(tester);
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '0');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('vendor-pos-paylater')));
    await tapVisible(tester, find.byKey(const Key('pos-due-14')));
    expect(find.text('Balance due: TSh 95,000'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('pos-credit-complete')));
    final body = api.only('POST', '/vendor/sales').body as Map;
    expect(body['payments'], isEmpty);
    expect(body['dueDate'], addDaysTo(eatTodayString(), 14));
  });

  apiTest('credit mode: cash above the rest → no change, Complete off', (
    tester,
    api,
  ) async {
    seed(api);
    final host = await pumpPos(tester, api);
    await addWhey(tester);
    await pickJuma(tester);
    await openPayment(tester);
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '20000');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('vendor-pos-paylater')));
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '100000');
    await tester.pumpAndSettle();
    expect(find.text(host.tr('vendor.pos.credit.noChange')), findsOneWidget);
    expect(
      isEnabled(tester, find.byKey(const Key('pos-credit-complete'))),
      isFalse,
    );
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '95000');
    await tester.pumpAndSettle();
    expect(find.text(host.tr('vendor.pos.credit.fullyPaid')), findsOneWidget);
    // M-Pesa without a reference keeps it off too (AC-18).
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '20000');
    await tapVisible(tester, find.byKey(const Key('pos-method-0-mpesa')));
    expect(
      isEnabled(tester, find.byKey(const Key('pos-credit-complete'))),
      isFalse,
    );
  });

  apiTest('no connection on a pay-later sale (AC-21): not queued, cart kept', (
    tester,
    api,
  ) async {
    seed(api);
    api.onCall(
      'POST /vendor/sales',
      (_) => throw http.ClientException('offline'),
    );
    final host = await pumpPos(tester, api);
    await addWhey(tester);
    await pickJuma(tester);
    await openPayment(tester);
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '20000');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('vendor-pos-paylater')));
    await tapVisible(tester, find.byKey(const Key('pos-credit-complete')));
    await tester.pumpAndSettle();
    expect(find.text(host.tr('vendor.pos.credit.failed')), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(queueKey);
    expect(raw == null || (jsonDecode(raw) as List).isEmpty, isTrue);
    // Try again resends the same sale (same key).
    final first = api.where('POST', '/vendor/sales').first.body as Map;
    api.onCall('POST /vendor/sales', (_) => {'sale': creditSale()});
    await tapVisible(tester, find.byKey(const Key('pos-credit-complete')));
    final last = api.where('POST', '/vendor/sales').last.body as Map;
    expect(last['clientRef'], first['clientRef']);
    expect(textContaining('ROUTE-RECEIPT sal_c'), findsOneWidget);
  });

  apiTest('403 credit_not_allowed: stays in credit mode with the reason', (
    tester,
    api,
  ) async {
    seed(api);
    api.fail('POST /vendor/sales', 403, {'error': 'credit_not_allowed'});
    final host = await pumpPos(tester, api);
    await addWhey(tester);
    await pickJuma(tester);
    await openPayment(tester);
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '20000');
    await tester.pumpAndSettle();
    await tapVisible(tester, find.byKey(const Key('vendor-pos-paylater')));
    await tapVisible(tester, find.byKey(const Key('pos-credit-complete')));
    expect(find.text(host.tr('vendor.pos.credit.notAllowed')), findsOneWidget);
    expect(find.byKey(const Key('pos-credit-complete')), findsOneWidget);
  });

  apiTest('409 customer_archived: chip cleared, choose again', (
    tester,
    api,
  ) async {
    seed(api);
    api.fail('POST /vendor/sales', 409, {'error': 'customer_archived'});
    final host = await pumpPos(tester, api);
    await addWhey(tester);
    await pickJuma(tester);
    await openPayment(tester);
    await tapVisible(tester, find.byKey(const Key('pos-complete')));
    expect(find.text(host.tr('vendor.pos.customer.gone')), findsOneWidget);
  });

  apiTest('sales-only staff: picker without amounts, no pay later (AC-3)', (
    tester,
    api,
  ) async {
    seed(api);
    seedCustomers(
      api,
      rows: [
        {
          'id': 'cus_1',
          'source': 'manual',
          'name': 'Juma Mussa',
          'phoneLast3': '234',
          'forgotten': false,
        },
      ],
    );
    await pumpPos(tester, api, user: staffUser(['sales']));
    await addWhey(tester);
    await tapVisible(tester, find.byKey(const Key('pos-customer-add')));
    expect(find.textContaining('•••• 234'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(CustomerPicker),
        matching: find.textContaining('TSh'),
      ),
      findsNothing,
    );
    await tapVisible(tester, find.byKey(const Key('picker-row-cus_1')));
    await openPayment(tester);
    await typeInto(tester, find.byKey(const Key('pos-amount-0')), '20000');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('vendor-pos-paylater')), findsNothing);
  });

  apiTest(
    'offline paid sale with a customer (AC-22): queued with the id only',
    (tester, api) async {
      seed(api);
      api.onCall(
        'POST /vendor/sales',
        (_) => throw http.ClientException('offline'),
      );
      await pumpPos(tester, api);
      await addWhey(tester);
      await pickJuma(tester);
      await openPayment(tester);
      await tapVisible(tester, find.byKey(const Key('pos-complete')));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(queueKey)!;
      final queue = jsonDecode(raw) as List;
      expect(queue, hasLength(1));
      expect((queue.single as Map)['body']['customerId'], 'cus_1');
      expect((queue.single as Map)['body'].containsKey('kind'), isFalse);
      final stored = await deviceStorage();
      expect(stored, isNot(contains('Juma')));
      expect(stored, isNot(contains('+255712345234')));
    },
  );

  apiTest('picker offline: nothing selectable', (tester, api) async {
    seed(api);
    api.onCall(
      'GET /vendor/customers',
      (_) => throw http.ClientException('offline'),
    );
    final host = await pumpPos(tester, api);
    await addWhey(tester);
    await tapVisible(tester, find.byKey(const Key('pos-customer-add')));
    await tester.pumpAndSettle();
    expect(find.text(host.tr('vendor.pos.customer.offline')), findsOneWidget);
    expect(find.byKey(const Key('picker-new')), findsNothing);
  });

  apiTest('quick-add from the picker: name + phone, then attached', (
    tester,
    api,
  ) async {
    seed(api);
    api.onCall(
      'POST /vendor/customers',
      (r) => {
        'customer': {
          'id': 'cus_new',
          'source': 'manual',
          'name': 'Rehema',
          'phone': '+255712000111',
        },
        'phoneDuplicate': null,
      },
    );
    await pumpPos(tester, api);
    await addWhey(tester);
    await tapVisible(tester, find.byKey(const Key('pos-customer-add')));
    await tapVisible(tester, find.byKey(const Key('picker-new')));
    await typeInto(tester, find.byKey(const Key('picker-add-name')), 'Rehema');
    await typeInto(
      tester,
      find.byKey(const Key('picker-add-phone')),
      '0712000111',
    );
    await tapVisible(tester, find.byKey(const Key('picker-add-save')));
    final body = api.only('POST', '/vendor/customers').body as Map;
    expect(body['name'], 'Rehema');
    expect(body['phone'], '+255712000111');
    expect(body['clientRef'], isNotEmpty);
    expect(find.text('Rehema'), findsOneWidget);
  });
}
