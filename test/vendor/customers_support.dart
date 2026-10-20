// Shared seeds for the vendor customers tests (vendor tools · S4).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/recording_api.dart';

const customersOn = {
  'walkInSales': true,
  'stockLedger': true,
  'canSeeCost': true,
  'customers': true,
};
const customersOff = {
  'walkInSales': true,
  'stockLedger': true,
  'canSeeCost': true,
  'customers': false,
};

const ownerUser = {'id': 'v1', 'userType': 'vendor', 'displayName': 'Owner'};

Map<String, dynamic> staffUser(List<String> perms, {String role = 'sales'}) => {
  'id': 's1',
  'userType': 'vendor_staff',
  'vendorId': 'v1',
  'vendorRole': role,
  'displayName': 'Asha',
  'vendorPermissions': perms,
};

/// A list row as the server sends it to people with `customers`.
Map<String, dynamic> customerRow(
  String id,
  String? name, {
  String source = 'manual',
  int owed = 0,
  int overdue = 0,
  String? phone,
  bool forgotten = false,
  bool archived = false,
}) => {
  'id': id,
  'source': source,
  'name': name,
  'phone': phone,
  'archived': archived,
  'forgotten': forgotten,
  'lastPurchaseAt': '2026-10-18T09:00:00.000Z',
  'owedTzs': owed,
  'overdueTzs': overdue,
  'oldestDueDate': owed > 0 ? '2026-10-15' : null,
  'maxDaysOverdue': overdue > 0 ? 5 : 0,
  'aging': {
    'current': owed - overdue,
    'd1_30': overdue,
    'd31_60': 0,
    'd61_90': 0,
    'd90plus': 0,
  },
};

/// A profile (GET /vendor/customers/:id) with two open pay-later sales:
/// R-000001 (20,000, due first) and R-000002 (30,000).
Map<String, dynamic> profile({
  String id = 'cus_1',
  String? name = 'Juma Mussa',
  String source = 'manual',
  bool forgotten = false,
  bool archived = false,
  List<Map<String, dynamic>>? openSales,
  String? phone = '+255712345234',
}) {
  final open =
      openSales ??
      [
        {
          'id': 'sal_a',
          'number': 'R-000001',
          'soldAt': '2026-10-01T08:00:00.000Z',
          'dueDate': '2026-10-08',
          'totalTzs': 20000,
          'balanceTzs': 20000,
          'daysOverdue': 12,
          'overdue': true,
        },
        {
          'id': 'sal_b',
          'number': 'R-000002',
          'soldAt': '2026-10-15T08:00:00.000Z',
          'dueDate': '2026-10-22',
          'totalTzs': 30000,
          'balanceTzs': 30000,
          'daysOverdue': 0,
          'overdue': false,
        },
      ];
  final owed = open.fold<int>(0, (s, o) => s + (o['balanceTzs'] as int));
  return {
    'customer': {
      'id': id,
      'source': source,
      'name': name,
      'forgotten': forgotten,
      'phone': source == 'manual' ? phone : null,
      'email': null,
      'address': null,
      'note': forgotten ? null : 'Pays at month end',
      'archived': archived,
      'archivedAt': null,
      'createdAt': '2026-09-01T08:00:00.000Z',
      'updatedAt': '2026-10-19T08:00:00.000Z',
      'lastPurchaseAt': '2026-10-15T08:00:00.000Z',
      'totals': {
        'shopSalesTzs': 50000,
        'shopSalesCount': 2,
        'appOrdersTzs': 0,
        'appOrdersCount': 0,
        'lastPurchaseAt': '2026-10-15T08:00:00.000Z',
      },
      'owedTzs': owed,
      'overdueTzs': 20000,
      'oldestDueDate': '2026-10-08',
      'maxDaysOverdue': 12,
      'aging': {
        'current': owed - 20000,
        'd1_30': 20000,
        'd31_60': 0,
        'd61_90': 0,
        'd90plus': 0,
      },
      'asOf': '2026-10-20',
      'openSales': open,
    },
  };
}

Map<String, dynamic> paymentJson({
  String id = 'pmt_1',
  String number = 'PMT-000001',
  int amount = 25000,
  String status = 'recorded',
  String recordedBy = 'v1',
  String receivedOn = '2026-10-20',
}) => {
  'id': id,
  'number': number,
  'customerId': 'cus_1',
  'status': status,
  'amountTzs': amount,
  'method': 'mpesa',
  'reference': 'QK12AB34',
  'receivedOn': receivedOn,
  'note': null,
  'clientRef': 'pay_x',
  'recordedAt': '2026-10-20T08:00:00.000Z',
  'recordedBy': {'id': recordedBy, 'name': 'Owner'},
  'allocations': [
    {'saleId': 'sal_a', 'saleNumber': 'R-000001', 'amountTzs': 20000},
    {'saleId': 'sal_b', 'saleNumber': 'R-000002', 'amountTzs': 5000},
  ],
  'voidedAt': status == 'voided' ? '2026-10-20T09:00:00.000Z' : null,
  'voidedBy': status == 'voided' ? {'id': 'v1', 'name': 'Owner'} : null,
  'voidReason': status == 'voided' ? 'Wrong customer' : null,
};

/// Everything stored on the device, as one string (A-02 checks).
Future<String> deviceStorage() async {
  final prefs = await SharedPreferences.getInstance();
  return [for (final k in prefs.getKeys()) '$k=${prefs.get(k)}'].join('\n');
}

/// Pages the customer screens move to, shown as markers.
final customerRoutes = <RouteBase>[
  GoRoute(
    path: '/vendor/home',
    builder: (_, s) => Scaffold(body: Text('ROUTE-VENDOR-HOME ${s.uri.query}')),
  ),
  GoRoute(
    path: '/vendor/customers/new',
    builder: (_, _) => const Scaffold(body: Text('ROUTE-CUSTOMER-NEW')),
  ),
  GoRoute(
    path: '/vendor/customers/:id',
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-CUSTOMER ${s.pathParameters['id']}')),
    routes: [
      GoRoute(
        path: 'edit',
        builder: (_, s) => Scaffold(
          body: Text('ROUTE-CUSTOMER-EDIT ${s.pathParameters['id']}'),
        ),
      ),
      GoRoute(
        path: 'statement',
        builder: (_, s) =>
            Scaffold(body: Text('ROUTE-STATEMENT ${s.pathParameters['id']}')),
      ),
    ],
  ),
  GoRoute(
    path: '/vendor/sales/:id',
    builder: (_, s) =>
        Scaffold(body: Text('ROUTE-SALE ${s.pathParameters['id']}')),
  ),
];

/// Seeds a customer list and the aging answer.
void seedCustomers(
  RecordingApi api, {
  List<Map<String, dynamic>>? rows,
  Map<String, dynamic>? aging,
}) {
  api.on('GET /vendor/customers', {
    'customers':
        rows ??
        [
          customerRow('cus_1', 'Juma Mussa', owed: 50000, overdue: 20000),
          customerRow('cus_2', 'Neema', source: 'marketplace'),
        ],
    'nextCursor': null,
    'asOf': '2026-10-20',
  });
  api.on(
    'GET /vendor/receivables/aging',
    aging ??
        {
          'asOf': '2026-10-20',
          'totals': {
            'owedTzs': 50000,
            'overdueTzs': 20000,
            'customerCount': 1,
            'overdueCustomerCount': 1,
            'openSaleCount': 2,
            'overdueSaleCount': 1,
            'current': 30000,
            'd1_30': 20000,
            'd31_60': 0,
            'd61_90': 0,
            'd90plus': 0,
          },
          'rows': [
            {
              'customerId': 'cus_1',
              'name': 'Juma Mussa',
              'source': 'manual',
              'owedTzs': 50000,
              'overdueTzs': 20000,
              'oldestDueDate': '2026-10-08',
              'maxDaysOverdue': 12,
              'openSaleCount': 2,
              'overdueSaleCount': 1,
              'current': 30000,
              'd1_30': 20000,
              'd31_60': 0,
              'd61_90': 0,
              'd90plus': 0,
            },
          ],
          'nextCursor': null,
        },
  );
}
