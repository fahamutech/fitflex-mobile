// Shared seeds for the vendor stock ledger tests (vendor tools · S1).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';

import '../support/recording_api.dart';

const vendorUser = {'id': 'v1', 'userType': 'vendor'};

Map<String, dynamic> stockProduct(
  String id,
  String name, {
  int stock = 10,
  List<Map<String, dynamic>> variants = const [],
  int? reorderLevel,
  int? costTzs,
}) => {
  'id': id,
  'name': name,
  'priceTzs': 85000,
  'stock': stock,
  'status': 'active',
  'approvalStatus': 'approved',
  'variants': variants,
  'reorderLevel': reorderLevel,
  'costTzs': costTzs,
};

/// What the vendor home page loads, plus the vendor tools answer.
void seedVendorHome(
  RecordingApi api, {
  required List<Map<String, dynamic>> products,
  Map<String, dynamic>? tools,
  List<dynamic> low = const [],
}) {
  api.on('GET /vendor/products', products);
  api.on('GET /vendor/orders', []);
  api.on('GET /vendor/profile', {
    'businessName': 'Store',
    'status': 'published',
  });
  api.on('GET /vendor/payments', {});
  api.on('GET /vendor/enquiries', []);
  api.on('GET /vendor/staff', []);
  if (tools != null) api.on('GET /vendor/tools/options', tools);
  api.on('GET /vendor/stock/low', low);
}

const ledgerOn = {'stockLedger': true, 'canSeeCost': true};
const ledgerOnNoCost = {'stockLedger': true, 'canSeeCost': false};

Future<PageHost> pumpVendorHome(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = vendorUser,
  String lang = 'en',
  String? filter,
}) => pumpPage(
  tester,
  api,
  VendorHomePage(filter: filter),
  user: user,
  lang: lang,
  size: const Size(400, 900),
);

/// Opens the overflow menu of product [id] and taps [item].
Future<void> productMenu(WidgetTester tester, String id, String item) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(Key('vendor-product-$id')),
      matching: find.byType(PopupMenuButton<String>),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}
