// Vendor tools · S3: the offline queue — kept per vendor + person, synced one
// at a time oldest first with the same clientRef (idempotent retry), refusals
// become conflicts without blocking later sales, network failures and 5xx /
// 429 stay waiting, feature-off and a suspended business pause syncing, and
// nothing is ever deleted except by Discard. The product cache holds no cost.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/screens/vendor/sales/offline_sale_queue.dart';
import 'package:fitflexmobile/shared/api_client.dart';

import '../support/recording_api.dart';

QueuedSale queued(
  String ref, {
  String at = '2026-10-19T10:00:00Z',
  int qty = 1,
}) => QueuedSale(
  body: {
    'clientRef': ref,
    'soldAt': at,
    'lines': [
      {'productId': 'p1', 'qty': qty},
    ],
    'payments': [
      {'method': 'cash', 'amountTzs': 45000 * qty},
    ],
  },
  display: {
    'business': 'Dar Gear',
    'servedBy': 'Asha',
    'lines': [
      {'name': 'Whey', 'listPriceTzs': 45000},
    ],
  },
  queuedAt: at,
);

Map<String, dynamic> saleFor(String ref, String number) => {
  'sale': {'id': 'sal_$number', 'number': number, 'clientRef': ref},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RecordingApi api;
  late ApiClient client;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    api = RecordingApi();
    client = ApiClient(baseUrl: 'http://fixtures.local')..setToken('t');
  });

  SalesSession session({String vendor = 'v1', String person = 'u1'}) =>
      SalesSession(api: client, vendorId: vendor, personId: person);

  test('kept per vendor + person and survives a restart', () async {
    await api.run(() async {
      final a = session();
      await a.enqueue(queued('sale_a_000001'));
      expect(a.waiting, hasLength(1));
      // Same person later (app restarted): still there.
      final again = session();
      await again.load();
      expect(again.all.single.clientRef, 'sale_a_000001');
      // Another person on the same device sees nothing of it.
      final other = session(person: 'u2');
      await other.load();
      expect(other.isEmpty, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vendor_sale_queue.v1.u1'), isNotNull);
    });
  });

  test(
    'syncs oldest first, one at a time, and records the server number',
    () async {
      await api.run(() async {
        api.onCall('POST /vendor/sales', (r) {
          final ref = (r.body as Map)['clientRef'] as String;
          return saleFor(ref, ref.endsWith('1') ? 'R-000001' : 'R-000002');
        });
        final s = session();
        await s.enqueue(queued('sale_b_000002', at: '2026-10-19T10:05:00Z'));
        await s.enqueue(queued('sale_a_000001', at: '2026-10-19T10:00:00Z'));
        final numbers = <String>[];
        final sub = s.syncedNumbers.listen(numbers.add);
        await s.sync();
        await Future<void>.delayed(Duration.zero);
        final sent = api
            .where('POST', '/vendor/sales')
            .map((r) => (r.body as Map)['clientRef'])
            .toList();
        expect(sent, ['sale_a_000001', 'sale_b_000002']);
        expect(s.isEmpty, isTrue);
        expect(s.synced['sale_a_000001']?['number'], 'R-000001');
        expect(numbers, ['R-000001', 'R-000002']);
        await sub.cancel();
      });
    },
  );

  test(
    'a lost answer: retried later with the exact same body (idempotent)',
    () async {
      await api.run(() async {
        var calls = 0;
        api.onCall('POST /vendor/sales', (r) {
          calls += 1;
          if (calls == 1) throw http.ClientException('offline');
          return saleFor('sale_a_000001', 'R-000001');
        });
        final s = session();
        await s.enqueue(queued('sale_a_000001'));
        await s.sync();
        expect(s.waiting.single.attempts, 1);
        expect(s.waiting.single.state, 'waiting');
        await s.sync(manual: true);
        final bodies = api
            .where('POST', '/vendor/sales')
            .map((r) => jsonEncode(r.body))
            .toList();
        expect(bodies, hasLength(2));
        expect(bodies[0], bodies[1]);
        expect(s.isEmpty, isTrue);
      });
    },
  );

  test(
    'a stock refusal becomes a conflict and the next sale still syncs',
    () async {
      await api.run(() async {
        api.onCall('POST /vendor/sales', (r) {
          final ref = (r.body as Map)['clientRef'] as String;
          if (ref == 'sale_a_000001') {
            return RawResponse(
              409,
              jsonEncode({
                'error': 'insufficient_stock',
                'productId': 'p1',
                'variant': null,
                'available': 0,
              }),
            );
          }
          return saleFor(ref, 'R-000001');
        });
        final s = session();
        await s.enqueue(queued('sale_a_000001', at: '2026-10-19T10:00:00Z'));
        await s.enqueue(queued('sale_b_000002', at: '2026-10-19T10:01:00Z'));
        await s.sync();
        expect(s.conflicts.single.clientRef, 'sale_a_000001');
        expect(s.conflicts.single.errorCode, 'insufficient_stock');
        expect(s.conflicts.single.errorBody['available'], 0);
        expect(s.waiting, isEmpty);
        // Conflicts are not sent again automatically.
        api.clear();
        await s.sync();
        expect(api.sent('POST', '/vendor/sales'), isFalse);
        // Try again sends the unchanged sale.
        api.onCall(
          'POST /vendor/sales',
          (r) => saleFor('sale_a_000001', 'R-000002'),
        );
        await s.retry('sale_a_000001');
        expect(s.isEmpty, isTrue);
      });
    },
  );

  test('5xx and 429 rate_limited stay waiting and stop the loop', () async {
    for (final status in [500, 503, 429]) {
      SharedPreferences.setMockInitialValues({});
      await api.run(() async {
        api.fail('POST /vendor/sales', status, {
          'error': status == 429 ? 'rate_limited' : 'oops',
        });
        final s = SalesSession(
          api: client,
          vendorId: 'v$status',
          personId: 'u1',
        );
        await s.enqueue(queued('sale_a_000001'));
        await s.enqueue(queued('sale_b_000002', at: '2026-10-19T10:02:00Z'));
        api.clear();
        await s.sync();
        expect(
          api.where('POST', '/vendor/sales'),
          hasLength(1),
          reason: '$status',
        );
        expect(s.conflicts, isEmpty, reason: '$status');
        expect(s.waiting, hasLength(2), reason: '$status');
        api.heal('POST /vendor/sales');
      });
    }
  });

  test(
    'feature switched off: stays waiting, sync pauses, nothing deleted',
    () async {
      await api.run(() async {
        api.fail('POST /vendor/sales', 404, {'error': 'feature_disabled'});
        final s = session();
        await s.enqueue(queued('sale_a_000001'));
        await s.sync();
        expect(s.pause, SalesSyncPause.featureOff);
        expect(s.waiting, hasLength(1));
        api.clear();
        await s.sync(manual: true);
        expect(api.sent('POST', '/vendor/sales'), isFalse);
        // Back on (options say walkInSales): it syncs.
        api.heal('POST /vendor/sales');
        api.onCall(
          'POST /vendor/sales',
          (_) => saleFor('sale_a_000001', 'R-000001'),
        );
        s.featureOn();
        await Future<void>.delayed(Duration.zero);
        await s.sync();
        expect(s.isEmpty, isTrue);
      });
    },
  );

  test(
    'business suspended: stays queued, no retry loop until asked again',
    () async {
      await api.run(() async {
        api.fail('POST /vendor/sales', 403, {'error': 'vendor_suspended'});
        final s = session();
        await s.enqueue(queued('sale_a_000001'));
        await s.sync();
        expect(s.pause, SalesSyncPause.suspended);
        expect(s.waiting, hasLength(1));
        expect(s.conflicts, isEmpty);
        api.clear();
        await s.sync();
        expect(api.sent('POST', '/vendor/sales'), isFalse);
        // Sync now asks once more.
        await s.sync(manual: true);
        expect(api.where('POST', '/vendor/sales'), hasLength(1));
        expect(s.waiting, hasLength(1));
      });
    },
  );

  test(
    'permission removed: a conflict and the loop stops for this person',
    () async {
      await api.run(() async {
        api.fail('POST /vendor/sales', 403, {
          'error': 'vendor_permission_forbidden',
          'requiredPermission': 'sales',
        });
        final s = session();
        await s.enqueue(queued('sale_a_000001'));
        await s.enqueue(queued('sale_b_000002', at: '2026-10-19T10:03:00Z'));
        await s.sync();
        expect(api.where('POST', '/vendor/sales'), hasLength(1));
        expect(s.conflicts.single.clientRef, 'sale_a_000001');
        expect(s.pause, SalesSyncPause.notAllowed);
      });
    },
  );

  test('401: nothing lost, sync waits for sign-in', () async {
    await api.run(() async {
      api.fail('POST /vendor/sales', 401, {'error': 'unauthorized'});
      final s = session();
      await s.enqueue(queued('sale_a_000001'));
      await s.sync();
      expect(s.pause, SalesSyncPause.signedOut);
      expect(s.waiting, hasLength(1));
    });
  });

  test('Discard removes it locally; nothing is sent', () async {
    await api.run(() async {
      final s = session();
      await s.enqueue(queued('sale_a_000001'));
      await s.remove('sale_a_000001');
      expect(s.isEmpty, isTrue);
      expect(api.requests, isEmpty);
    });
  });

  test('queued units count against known stock', () async {
    await api.run(() async {
      final s = session();
      await s.enqueue(queued('sale_a_000001', qty: 2));
      await s.enqueue(queued('sale_b_000002', qty: 3));
      expect(s.queuedQty('p1', null), 5);
      expect(s.queuedQty('p2', null), 0);
    });
  });

  test('the offline product cache never stores cost price', () async {
    await api.run(() async {
      final s = session();
      await s.saveProducts([
        {
          'id': 'p1',
          'name': 'Whey',
          'priceTzs': 45000,
          'costTzs': 30000,
          'stock': 4,
          'reorderLevel': 2,
          'images': ['a.png', 'b.png'],
          'variants': [
            {'name': 'L', 'stock': 2, 'costTzs': 9},
          ],
        },
      ]);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('vendor_pos_products.v1')!;
      expect(raw, isNot(contains('costTzs')));
      expect(raw, isNot(contains('reorderLevel')));
      final back = await s.loadProducts();
      expect(back!.products.single['images'], ['a.png']);
      expect(back.products.single['variants'], [
        {'name': 'L', 'stock': 2},
      ]);
    });
  });

  test('identity: vendor acts for itself, staff for their vendor', () {
    expect(SalesSession.identityOf({'id': 'v1', 'userType': 'vendor'}), (
      vendorId: 'v1',
      personId: 'v1',
    ));
    expect(
      SalesSession.identityOf({
        'id': 's1',
        'userType': 'vendor_staff',
        'vendorId': 'v1',
      }),
      (vendorId: 'v1', personId: 's1'),
    );
    expect(SalesSession.identityOf({'id': 'm1', 'userType': 'member'}), isNull);
  });
}
