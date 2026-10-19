// Vendor tools · S1 — design QA and UAT fixes (2026-10-19/20): history
// reloads on a new product, readable date range picker, low-stock badges
// (warning tone, no truncation, no duplicate labels), independent loads,
// order link for an order not in the list, adjust sheet resets.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/stock/adjust_stock_sheet.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_history_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/tone_theme.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

double _luminance(Color c) => c.computeLuminance();
double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Map<String, dynamic> _page(List<Map<String, dynamic>> rows) => {
  'openingStock': 1,
  'closingStock': 1,
  'rows': rows,
  'nextCursor': null,
};

Map<String, dynamic> _row(String id, {String? orderId}) => {
  'id': id,
  'productId': 'p1',
  'variant': null,
  'reason': orderId == null ? 'count' : 'reserve',
  'delta': -1,
  'stockBefore': 2,
  'stockAfter': 1,
  'note': null,
  'actor': null,
  'orderId': orderId,
  'document': orderId == null
      ? null
      : {'type': 'order', 'id': orderId, 'number': null},
  'createdAt': '2026-10-19T11:05:00Z',
};

/// Hosts the history page with a button that switches it to product p2.
class _Switcher extends StatefulWidget {
  const _Switcher();
  @override
  State<_Switcher> createState() => _SwitcherState();
}

class _SwitcherState extends State<_Switcher> {
  String id = 'p1';
  @override
  Widget build(BuildContext context) => Column(
    children: [
      TextButton(
        key: const Key('switch'),
        onPressed: () => setState(() => id = 'p2'),
        child: const Text('switch'),
      ),
      Expanded(child: StockHistoryPage(productId: id)),
    ],
  );
}

void main() {
  setUpAll(loadAppFonts);

  group('stock history', () {
    apiTest('moving to another product reloads the page for it', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', ledgerOn);
      api.on('GET /vendor/stock/low', []);
      api.on('GET /vendor/products', [
        stockProduct('p1', 'Whey', stock: 1),
        stockProduct('p2', 'Mat', stock: 9),
      ]);
      api.on('GET /vendor/products/p1/stock-movements', _page([_row('a1')]));
      api.on('GET /vendor/products/p2/stock-movements', _page([_row('b1')]));
      await pumpPage(
        tester,
        api,
        const _Switcher(),
        size: const Size(400, 900),
      );
      expect(find.byKey(const Key('stock-row-a1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('switch')));
      await tester.pumpAndSettle();
      expect(api.sent('GET', '/vendor/products/p2/stock-movements'), isTrue);
      expect(find.byKey(const Key('stock-row-b1')), findsOneWidget);
      expect(find.byKey(const Key('stock-row-a1')), findsNothing);
      expect(find.text('Mat'), findsOneWidget);
    });

    apiTest('an order not in the vendor\'s list says so instead', (
      tester,
      api,
    ) async {
      api.on('GET /vendor/tools/options', ledgerOn);
      api.on('GET /vendor/stock/low', []);
      api.on('GET /vendor/products', [stockProduct('p1', 'Whey', stock: 1)]);
      api.on(
        'GET /vendor/products/p1/stock-movements',
        _page([_row('m1', orderId: 'ord_unpaid')]),
      );
      api.on('GET /vendor/orders', [
        {'id': 'ord_other'},
      ]);
      final host = await pumpPage(
        tester,
        api,
        const StockHistoryPage(productId: 'p1'),
        size: const Size(400, 900),
      );
      await tapVisible(tester, find.byKey(const Key('stock-order-m1')));
      expect(
        host.snack(host.tr('vendor.stock.orderNotVisible')),
        findsOneWidget,
      );
    });

    test('date range picker: in-range and chosen days are readable', () {
      for (final base in [buildTheme(), buildDarkTheme()]) {
        final themed = stockRangePickerTheme(base);
        final picker = themed.datePickerTheme;
        final surface = picker.rangePickerBackgroundColor!;
        final range = Color.alphaBlend(
          picker.rangeSelectionBackgroundColor!,
          surface,
        );
        // Days inside the range are drawn in bodyMedium's colour.
        final text = themed.textTheme.bodyMedium!.color!;
        expect(
          _contrast(text, range),
          greaterThanOrEqualTo(4.5),
          reason: '${base.brightness} in-range',
        );
        final selectedText = picker.dayForegroundColor!.resolve({
          WidgetState.selected,
        })!;
        final selectedBg = picker.dayBackgroundColor!.resolve({
          WidgetState.selected,
        })!;
        expect(
          _contrast(selectedText, selectedBg),
          greaterThanOrEqualTo(4.5),
          reason: '${base.brightness} start/end',
        );
      }
    });
  });

  group('products tab', () {
    final low = [
      {
        'productId': 'p1',
        'name': 'Tee',
        'variant': 'Small',
        'stock': 1,
        'reorderLevel': 2,
      },
    ];
    final tee = stockProduct(
      'p1',
      'Tee',
      variants: [
        {'name': 'Small', 'stock': 1},
        {'name': 'Large', 'stock': 9},
      ],
    );

    apiTest('one low variant reads "1 variant low"; badges wrap', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [tee], tools: ledgerOn, low: low);
      final host = await pumpVendorHome(tester, api);
      expect(find.text(host.tr('vendor.stock.lowVariantsOne')), findsOneWidget);
      final badge = tester.widget<FFBadge>(
        find.byKey(const Key('vendor-low-variants-p1')),
      );
      expect(badge.wrap, isTrue);
    });

    apiTest('Swahili at 375: the variant badge is never cut off', (
      tester,
      api,
    ) async {
      seedVendorHome(
        api,
        products: [tee],
        tools: ledgerOn,
        low: [
          ...low,
          {...low.first, 'variant': 'Large'},
        ],
      );
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(),
        user: vendorUser,
        lang: 'sw',
        size: const Size(375, 800),
      );
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('vendor-low-variants-p1')),
          matching: find.byType(Text),
        ),
      );
      expect(text.overflow, isNot(TextOverflow.ellipsis));
      expect(
        text.data,
        host.tr('vendor.stock.lowVariants').replaceAll('{n}', '2'),
      );
    });

    apiTest('nav badge: warning tone and one label, not repeated', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [tee], tools: ledgerOn, low: low);
      final handle = tester.ensureSemantics();
      final host = await pumpVendorHome(tester, api);
      final badge = tester.widget<Badge>(
        find.byKey(const Key('vendor-nav-low-badge')).first,
      );
      final warning = FFToneTheme.of(
        tester.element(find.byKey(const Key('vendor-nav-low-badge')).first),
      ).warning;
      expect(badge.backgroundColor, warning.fg);
      expect(
        badge.backgroundColor,
        isNot(
          Theme.of(
            tester.element(find.byType(Scaffold).first),
          ).colorScheme.error,
        ),
      );
      expect(
        _contrast(badge.textColor!, badge.backgroundColor!),
        greaterThanOrEqualTo(4.5),
      );
      final nodes = find.bySemanticsLabel(
        RegExp(host.tr('vendor.stock.lowNavLabel').replaceAll('{n}', '1')),
      );
      expect(nodes, findsWidgets);
      // The tab says "Products" once, not "Products, 1 low… 1 Products".
      expect(find.bySemanticsLabel(RegExp('Products.*Products')), findsNothing);
      handle.dispose();
    });

    apiTest('a refused business profile (staff) does not hide products', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [tee], tools: ledgerOn, low: low);
      api.fail('GET /vendor/profile', 403, {'error': 'forbidden'});
      final host = await pumpVendorHome(
        tester,
        api,
        user: const {
          'id': 's1',
          'userType': 'vendor_staff',
          'vendorPermissions': ['products', 'orders'],
        },
      );
      expect(find.byKey(const Key('vendor-product-p1')), findsOneWidget);
      expect(find.text(host.tr('vendor.noProducts')), findsNothing);
      expect(host.snack(host.tr('vendor.loadFailed')), findsNothing);
    });

    apiTest('a failed part still shows the others, with a message', (
      tester,
      api,
    ) async {
      seedVendorHome(api, products: [tee], tools: ledgerOn, low: low);
      api.fail('GET /vendor/orders', 500);
      final host = await pumpVendorHome(tester, api);
      expect(find.byKey(const Key('vendor-product-p1')), findsOneWidget);
      expect(host.snack(host.tr('vendor.loadFailed')), findsOneWidget);
    });

    apiTest('card menu button is at least 48dp', (tester, api) async {
      seedVendorHome(api, products: [tee], tools: ledgerOn, low: low);
      await pumpVendorHome(tester, api);
      final size = tester.getSize(
        find.descendant(
          of: find.byKey(const Key('vendor-product-p1')),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('adjust sheet', () {
    Future<void> open(WidgetTester tester, RecordingApi api) async {
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
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
    }

    apiTest('changing the reason clears the quantity', (tester, api) async {
      await open(tester, api);
      await tapVisible(tester, find.byKey(const Key('adjust-reason-restock')));
      await typeInto(tester, find.byKey(const Key('adjust-quantity')), '4');
      await tapVisible(tester, find.byKey(const Key('adjust-reason-lost')));
      expect(textOf(tester, find.byKey(const Key('adjust-quantity'))), '');
    });

    apiTest('after 409 stock_changed the count field has focus', (
      tester,
      api,
    ) async {
      await open(tester, api);
      api.fail('POST /vendor/products/p1/stock-adjustments', 409, {
        'error': 'stock_changed',
        'currentStock': 12,
      });
      await tapVisible(tester, find.byKey(const Key('adjust-reason-count')));
      await typeInto(tester, find.byKey(const Key('adjust-quantity')), '7');
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('adjust-save')));
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(const Key('adjust-quantity')),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.focusNode.hasFocus, isTrue);
    });

    apiTest('reason chips keep their 48dp size while saving', (
      tester,
      api,
    ) async {
      await open(tester, api);
      final gate = api.hold('POST /vendor/products/p1/stock-adjustments');
      await tapVisible(tester, find.byKey(const Key('adjust-reason-restock')));
      await typeInto(tester, find.byKey(const Key('adjust-quantity')), '1');
      await tester.pumpAndSettle();
      final before = tester.getSize(
        find.byKey(const Key('adjust-reason-found')),
      );
      await tester.tap(find.byKey(const Key('adjust-save')));
      await tester.pump();
      final during = tester.getSize(
        find.byKey(const Key('adjust-reason-found')),
      );
      expect(during, before);
      expect(during.height, greaterThanOrEqualTo(48));
      gate.complete();
      await tester.pumpAndSettle();
    });
  });
}
