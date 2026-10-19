// Vendor tools · S1 — design re-check of #169: the variant stock cell keeps
// readable labels at 375 and 768 (no per-character wrapping, no cut-off
// labels with long variant names), stock buttons keep a 48dp target even
// with compact (web / desktop) density, and the count preview is a live
// region.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/stock/adjust_stock_sheet.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_history_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

Finder _k(String key) => find.byKey(Key(key));

final _tee = stockProduct(
  'p1',
  'Tee',
  variants: [
    {'name': 'Extra Large Family Pack', 'stock': 5},
    {'name': 'Small', 'stock': 3},
  ],
);

/// Natural one-line width of [text] in [style].
double _natural(WidgetTester tester, String text, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.width;
}

Future<PageHost> _openEdit(
  WidgetTester tester,
  RecordingApi api,
  Size size,
) async {
  seedVendorHome(api, tools: ledgerOn, products: [_tee]);
  final host = await pumpPage(
    tester,
    api,
    const VendorHomePage(),
    user: vendorUser,
    size: size,
  );
  await productMenu(tester, 'p1', host.tr('vendor.edit'));
  return host;
}

void main() {
  setUpAll(loadAppFonts);

  for (final size in const [Size(375, 812), Size(768, 1024)]) {
    apiTest('stock cell at ${size.width.toInt()}: one-line label, '
        'button below', (tester, api) async {
      final host = await _openEdit(tester, api, size);
      await tester.ensureVisible(_k('variant-adjust-0'));
      await tester.pumpAndSettle();
      final label = _k('variant-stock-label-0');
      final text = tester.widget<Text>(label);
      final style = DefaultTextStyle.of(
        tester.element(label),
      ).style.merge(text.style);
      final natural = _natural(tester, host.tr('vendor.stock.current'), style);
      // Laid out at its full width (not squeezed to a few pixels).
      expect(tester.getSize(label).width, greaterThanOrEqualTo(natural - 1));
      // One line: no taller than about one line of text.
      expect(
        tester.getSize(label).height,
        lessThan((style.fontSize ?? 12) * 2.2),
      );
      // The Adjust button sits below the count, not beside it.
      expect(
        tester.getTopLeft(_k('variant-adjust-0')).dy,
        greaterThan(tester.getBottomLeft(_k('variant-stock-value-0')).dy - 1),
      );
      // Short field labels: the long variant name is not in them.
      expect(find.text(host.tr('vendor.costPrice')), findsWidgets);
      expect(find.textContaining('Extra Large Family Pack: '), findsNothing);
    });
  }

  apiTest('stock buttons keep 48dp with desktop (compact) density', (
    tester,
    api,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _openEdit(tester, api, const Size(768, 1024));
      for (final key in [
        'variant-adjust-0',
        'variant-add',
        'vendor-product-adjust',
        'variant-remove-0',
      ]) {
        await tester.ensureVisible(_k(key));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(_k(key)).height,
          greaterThanOrEqualTo(48),
          reason: key,
        );
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  apiTest('sheet and history buttons keep 48dp with compact density', (
    tester,
    api,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final whey = stockProduct('p1', 'Whey', stock: 10);
      api.on('GET /vendor/products', [whey]);
      api.on('GET /vendor/tools/options', ledgerOn);
      api.on('GET /vendor/stock/low', []);
      api.on('GET /vendor/products/p1/stock-movements', {
        'openingStock': 10,
        'closingStock': 10,
        'rows': [],
        'nextCursor': null,
      });
      await pumpPage(
        tester,
        api,
        const StockHistoryPage(productId: 'p1'),
        size: const Size(768, 1024),
      );
      expect(
        tester.getSize(_k('stock-adjust')).height,
        greaterThanOrEqualTo(48),
      );
      await tester.tap(_k('stock-adjust'));
      await tester.pumpAndSettle();
      for (final key in ['adjust-save', 'adjust-cancel']) {
        await tester.ensureVisible(_k(key));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(_k(key)).height,
          greaterThanOrEqualTo(48),
          reason: key,
        );
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  apiTest('the count preview is a live region', (tester, api) async {
    final handle = tester.ensureSemantics();
    final whey = stockProduct('p1', 'Whey', stock: 10);
    api.on('GET /vendor/products', [whey]);
    await pumpPage(
      tester,
      api,
      Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            key: const Key('open'),
            onPressed: () => openAdjustStock(context, product: whey),
            child: const Text('open'),
          ),
        ),
      ),
      size: const Size(400, 900),
    );
    await tester.tap(_k('open'));
    await tester.pumpAndSettle();
    await tapVisible(tester, _k('adjust-reason-count'));
    await typeInto(tester, _k('adjust-quantity'), '7');
    await tester.pumpAndSettle();
    final node = tester.getSemantics(_k('adjust-preview'));
    expect(node.label, 'Difference: −3');
    expect(node.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    handle.dispose();
  });
}
