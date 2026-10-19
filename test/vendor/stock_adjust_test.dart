// Vendor tools · S1: the "Adjust stock" sheet — reasons, previews, the
// request it sends, conflicts, retries with the same clientRef.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:fitflexmobile/screens/vendor/stock/adjust_stock_sheet.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

const _path = '/vendor/products/p1/stock-adjustments';

AdjustResult? _result;

/// A page with one button that opens the sheet for [product].
Widget _host(Map<String, dynamic> product, {String? variant}) {
  var n = 0;
  return Builder(
    builder: (context) => Center(
      child: ElevatedButton(
        key: const Key('open'),
        onPressed: () async => _result = await openAdjustStock(
          context,
          product: product,
          variant: variant,
          makeClientRef: () => 'ref-test-${++n}',
        ),
        child: const Text('open'),
      ),
    ),
  );
}

Future<PageHost> _open(
  WidgetTester tester,
  RecordingApi api,
  Map<String, dynamic> product, {
  String? variant,
  String lang = 'en',
}) async {
  _result = null;
  api.on('GET /vendor/products', [product]);
  final host = await pumpPage(
    tester,
    api,
    _host(product, variant: variant),
    lang: lang,
    size: const Size(400, 900),
  );
  await tester.tap(find.byKey(const Key('open')));
  await tester.pumpAndSettle();
  return host;
}

Finder get _save => find.byKey(const Key('adjust-save'));

Future<void> _reason(WidgetTester tester, String reason) async {
  await tapVisible(tester, find.byKey(Key('adjust-reason-$reason')));
}

Future<void> _qty(WidgetTester tester, String text) async {
  await typeInto(tester, find.byKey(const Key('adjust-quantity')), text);
  await tester.pumpAndSettle();
}

String _preview(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('adjust-preview'))).data ?? '';

Map<String, dynamic> _answer(int before, int after, {String? variant}) => {
  'movement': {
    'id': 'm1',
    'productId': 'p1',
    'variant': variant,
    'reason': 'count',
    'kind': 'adjustment',
    'delta': after - before,
    'stockBefore': before,
    'stockAfter': after,
    'note': null,
    'actor': {'id': 'v1', 'name': 'Asha'},
    'orderId': null,
    'document': null,
    'createdAt': '2026-10-19T10:00:00Z',
  },
  'product': {'id': 'p1', 'stock': after, 'variants': <dynamic>[]},
};

void main() {
  setUpAll(loadAppFonts);
  final whey = stockProduct('p1', 'Whey', stock: 10);

  apiTest('reasons in order, none chosen, Save disabled until valid', (
    tester,
    api,
  ) async {
    final host = await _open(tester, api, whey);
    final labels = [
      for (final r in [
        'count',
        'restock',
        'returned',
        'found',
        'damaged',
        'expired',
        'lost',
        'other',
      ])
        host.tr('vendor.stock.reason.$r'),
    ];
    // Same row first, then left to right: compare positions.
    final positions = [for (final l in labels) tester.getTopLeft(find.text(l))];
    for (var i = 1; i < positions.length; i++) {
      final a = positions[i - 1], b = positions[i];
      expect(
        b.dy > a.dy || (b.dy == a.dy && b.dx > a.dx),
        isTrue,
        reason: '${labels[i - 1]} before ${labels[i]}',
      );
    }
    expect(find.byKey(const Key('adjust-quantity')), findsNothing);
    expect(isEnabled(tester, _save), isFalse);
    expect(find.text('10'), findsOneWidget);

    await _reason(tester, 'restock');
    expect(isEnabled(tester, _save), isFalse);
    await _qty(tester, '0');
    expect(isEnabled(tester, _save), isFalse);
    await _qty(tester, '4');
    expect(isEnabled(tester, _save), isTrue);
    expect(_preview(tester), 'Stock after: 14');
  });

  apiTest('Counted 7 from 10 shows −3 and sends a count', (tester, api) async {
    api.on('POST $_path', _answer(10, 7));
    final host = await _open(tester, api, whey);
    await _reason(tester, 'count');
    expect(find.text(host.tr('vendor.stock.saveCount')), findsOneWidget);
    await _qty(tester, '7');
    expect(_preview(tester), 'Difference: −3');
    await _qty(tester, '10');
    expect(_preview(tester), host.tr('vendor.stock.noDifference'));
    await _qty(tester, '7');
    await tapVisible(tester, _save);

    expect(api.only('POST', _path).body, {
      'reason': 'count',
      'quantity': 7,
      'expectedStock': 10,
      'clientRef': 'ref-test-1',
    });
    expect(find.text('Stock updated: 10 → 7'), findsOneWidget);
    expect(_result?.product['stock'], 7);
  });

  apiTest('Damaged more than in stock is refused before sending', (
    tester,
    api,
  ) async {
    await _open(tester, api, stockProduct('p1', 'Whey', stock: 7));
    await _reason(tester, 'damaged');
    await _qty(tester, '2');
    expect(_preview(tester), 'Stock after: 5');
    await _qty(tester, '9');
    expect(
      find.text("Only 7 in stock. You can't remove more than that."),
      findsOneWidget,
    );
    expect(isEnabled(tester, _save), isFalse);
    expect(api.sent('POST', _path), isFalse);
  });

  apiTest('Other needs a direction and a note', (tester, api) async {
    api.on('POST $_path', _answer(10, 8));
    final host = await _open(tester, api, whey);
    await _reason(tester, 'other');
    expect(find.text(host.tr('vendor.stock.noteRequired')), findsOneWidget);
    expect(find.byKey(const Key('adjust-quantity')), findsNothing);
    await tapVisible(tester, find.byKey(const Key('adjust-direction-out')));
    await _qty(tester, '2');
    await tapVisible(tester, _save);
    expect(find.text(host.tr('vendor.stock.noteMissing')), findsOneWidget);
    expect(api.sent('POST', _path), isFalse);

    await typeInto(tester, find.byKey(const Key('adjust-note')), 'Gift');
    await tapVisible(tester, _save);
    expect(api.only('POST', _path).body, {
      'reason': 'other',
      'quantity': 2,
      'direction': 'out',
      'note': 'Gift',
      'clientRef': 'ref-test-1',
    });
  });

  apiTest('note is capped at 200 characters', (tester, api) async {
    await _open(tester, api, whey);
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('adjust-note')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.maxLength, 200);
  });

  apiTest('variants: Save waits for a variant; its stock is shown', (
    tester,
    api,
  ) async {
    api.on('POST $_path', _answer(3, 5, variant: 'Large'));
    final product = stockProduct(
      'p1',
      'Tee',
      stock: 8,
      variants: [
        {'name': 'Small', 'stock': 5},
        {'name': 'Large', 'stock': 3},
      ],
    );
    await _open(tester, api, product);
    await _reason(tester, 'restock');
    expect(find.byKey(const Key('adjust-quantity')), findsOneWidget);
    await _qty(tester, '2');
    expect(isEnabled(tester, _save), isFalse);

    await tester.tap(find.byKey(const Key('adjust-variant')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large · 3').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(const Key('adjust-current'))).data,
      '3',
    );
    expect(isEnabled(tester, _save), isTrue);
    await tapVisible(tester, _save);
    expect((api.only('POST', _path).body as Map)['variant'], 'Large');
  });

  apiTest('a preselected variant is used', (tester, api) async {
    final product = stockProduct(
      'p1',
      'Tee',
      variants: [
        {'name': 'Small', 'stock': 5},
        {'name': 'Large', 'stock': 3},
      ],
    );
    await _open(tester, api, product, variant: 'Small');
    expect(
      tester.widget<Text>(find.byKey(const Key('adjust-current'))).data,
      '5',
    );
  });

  apiTest('409 stock_changed: warning, new count, field cleared, new ref', (
    tester,
    api,
  ) async {
    api.fail('POST $_path', 409, {
      'error': 'stock_changed',
      'currentStock': 12,
    });
    final host = await _open(tester, api, whey);
    await _reason(tester, 'count');
    await _qty(tester, '7');
    await tapVisible(tester, _save);

    expect(find.text(host.tr('vendor.stock.changed')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('adjust-current'))).data,
      '12',
    );
    expect(textOf(tester, find.byKey(const Key('adjust-quantity'))), '');
    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('adjust-quantity')),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.focusNode.hasFocus, isTrue);

    api.heal('POST $_path');
    api.on('POST $_path', _answer(12, 11));
    await _qty(tester, '11');
    await tapVisible(tester, _save);
    final sent = api.where('POST', _path);
    expect(sent, hasLength(2));
    expect((sent.last.body as Map)['expectedStock'], 12);
    expect((sent.last.body as Map)['clientRef'], 'ref-test-2');
  });

  apiTest('409 insufficient_stock: count updated, quantity kept', (
    tester,
    api,
  ) async {
    api.fail('POST $_path', 409, {
      'error': 'insufficient_stock',
      'currentStock': 1,
    });
    await _open(tester, api, whey);
    await _reason(tester, 'lost');
    await _qty(tester, '3');
    await tapVisible(tester, _save);
    expect(textOf(tester, find.byKey(const Key('adjust-quantity'))), '3');
    expect(
      find.text("Only 1 in stock. You can't remove more than that."),
      findsOneWidget,
    );
    expect(isEnabled(tester, _save), isFalse);
  });

  apiTest('offline: nothing saved, values kept, retry uses the same ref', (
    tester,
    api,
  ) async {
    var calls = 0;
    api.onCall('POST $_path', (_) {
      calls++;
      if (calls == 1) throw http.ClientException('offline');
      return _answer(10, 14);
    });
    final host = await _open(tester, api, whey);
    await _reason(tester, 'restock');
    await _qty(tester, '4');
    await tapVisible(tester, _save);

    expect(find.byKey(const Key('adjust-network')), findsOneWidget);
    expect(
      find.textContaining(host.tr('vendor.stock.nothingSaved')),
      findsOneWidget,
    );
    expect(textOf(tester, find.byKey(const Key('adjust-quantity'))), '4');
    expect(find.text(host.tr('common.retry')), findsOneWidget);

    await tapVisible(tester, _save);
    final sent = api.where('POST', _path);
    expect(sent, hasLength(2));
    expect(
      (sent[0].body as Map)['clientRef'],
      (sent[1].body as Map)['clientRef'],
    );
    expect(find.text('Stock updated: 10 → 14'), findsOneWidget);
  });

  apiTest('a changed entry after a failure gets a new ref', (
    tester,
    api,
  ) async {
    api.onCall('POST $_path', (_) => throw http.ClientException('offline'));
    await _open(tester, api, whey);
    await _reason(tester, 'restock');
    await _qty(tester, '4');
    await tapVisible(tester, _save);
    await _qty(tester, '5');
    await tapVisible(tester, _save);
    final refs = api
        .where('POST', _path)
        .map((r) => (r.body as Map)['clientRef'])
        .toList();
    expect(refs, ['ref-test-1', 'ref-test-2']);
  });

  apiTest('403 closes the sheet with the permission message', (
    tester,
    api,
  ) async {
    api.fail('POST $_path', 403, {'error': 'not_your_product'});
    final host = await _open(tester, api, whey);
    await _reason(tester, 'found');
    await _qty(tester, '1');
    await tapVisible(tester, _save);
    expect(find.byKey(const Key('adjust-save')), findsNothing);
    expect(host.snack(host.tr('vendor.stock.notAllowed')), findsOneWidget);
    expect(_result, isNull);
  });

  apiTest('404 closes the sheet with the not-found message', (
    tester,
    api,
  ) async {
    api.fail('POST $_path', 404, {'error': 'product_not_found'});
    final host = await _open(tester, api, whey);
    await _reason(tester, 'found');
    await _qty(tester, '1');
    await tapVisible(tester, _save);
    expect(host.snack(host.tr('vendor.stock.notFound')), findsOneWidget);
  });

  apiTest('Swahili at 375 wide and 2x text: no overflow', (tester, api) async {
    tester.view.physicalSize = const Size(375, 800);
    final errors = await captureFlutterErrors(() async {
      api.on('GET /vendor/products', [whey]);
      await pumpPage(
        tester,
        api,
        _host(whey),
        lang: 'sw',
        textScale: 2,
        size: const Size(375, 800),
      );
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      await _reason(tester, 'other');
      await tapVisible(tester, find.byKey(const Key('adjust-direction-in')));
    });
    expect(errors.where((e) => e.contains('overflowed')), isEmpty);
    expect(find.text('Muda wake umeisha'), findsOneWidget);
  });
}
