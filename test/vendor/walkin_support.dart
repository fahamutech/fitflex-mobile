// Shared seeds for the vendor walk-in sales tests (vendor tools · S3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/recording_api.dart';

const walkInOn = {'walkInSales': true, 'stockLedger': true, 'canSeeCost': true};
const walkInOff = {
  'walkInSales': false,
  'stockLedger': true,
  'canSeeCost': true,
};

Map<String, dynamic> posProduct(
  String id,
  String name, {
  int price = 45000,
  int? discountPrice,
  int stock = 10,
  List<Map<String, dynamic>> variants = const [],
  String status = 'active',
  String? sku,
}) => {
  'id': id,
  'name': name,
  'priceTzs': price,
  'discountPriceTzs': ?discountPrice,
  'stock': stock,
  'status': status,
  'approvalStatus': 'approved',
  'variants': variants,
  'sku': ?sku,
  'costTzs': 30000,
};

void seedPos(
  RecordingApi api, {
  Map<String, dynamic> tools = walkInOn,
  List<Map<String, dynamic>>? products,
}) {
  api.on('GET /vendor/tools/options', tools);
  api.on('GET /vendor/profile', {
    'businessName': 'Dar Gear',
    'contactNumber': '+255700000001',
    'status': 'published',
  });
  api.on(
    'GET /vendor/products',
    products ??
        [
          posProduct('p1', 'Whey', stock: 2),
          posProduct('p2', 'Mat', price: 10000, stock: 0),
        ],
  );
}

Map<String, dynamic> serverSale({
  String id = 'sal_1',
  String number = 'R-000001',
  String status = 'completed',
  String createdById = 'v1',
  String soldAt = '2026-10-19T11:05:00.000Z',
}) => {
  'id': id,
  'number': number,
  'status': status,
  'kind': 'cash',
  'soldAt': soldAt,
  'recordedAt': soldAt,
  'clientRef': 'sale_x_00000001',
  'subtotalTzs': 45000,
  'lineDiscountTzs': 0,
  'discountTzs': 0,
  'totalTzs': 45000,
  'paidTzs': 50000,
  'changeTzs': 5000,
  'note': null,
  'createdBy': {'id': createdById, 'name': 'Asha'},
  'voidedBy': status == 'voided' ? {'id': 'v1', 'name': 'Owner'} : null,
  'voidedAt': status == 'voided' ? soldAt : null,
  'voidReason': status == 'voided' ? 'Returned' : null,
  'lines': [
    {
      'id': 'sln_1',
      'productId': 'p1',
      'variant': null,
      'nameSnapshot': 'Whey',
      'qty': 1,
      'listPriceTzs': 45000,
      'unitPriceTzs': 45000,
      'priceChanged': false,
      'priceChangedBy': null,
      'discountTzs': 0,
      'lineTotalTzs': 45000,
    },
  ],
  'payments': [
    {'method': 'cash', 'amountTzs': 50000, 'reference': null},
  ],
};

/// Pages the sales screens move to, shown as markers.
final salesRoutes = <RouteBase>[
  GoRoute(
    path: '/vendor/home',
    builder: (_, s) => Scaffold(body: Text('ROUTE-VENDOR-HOME ${s.uri.query}')),
  ),
  GoRoute(
    path: '/vendor/sales/new',
    builder: (_, _) => const Scaffold(body: Text('ROUTE-POS')),
  ),
  GoRoute(
    path: '/vendor/sales/sync',
    builder: (_, _) => const Scaffold(body: Text('ROUTE-SYNC')),
  ),
  GoRoute(
    path: '/vendor/sales/receipt/queued/:ref',
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-QUEUED ${s.pathParameters['ref']}')),
  ),
  GoRoute(
    path: '/vendor/sales/receipt/:id',
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-RECEIPT ${s.pathParameters['id']}')),
  ),
  GoRoute(
    path: '/vendor/sales/:id',
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-SALE ${s.pathParameters['id']}')),
  ),
];

Finder textContaining(String part) => find.byWidgetPredicate(
  (w) => w is Text && (w.data ?? '').contains(part),
  description: 'text containing "$part"',
);
