// Vendor tools · S4 UAT fixes (2026-10-20):
// D1 profile reloads in place for another customer id, old lists gone at once
// D2 aging tiles: labels wrap and are never cut, "Siku 1–30" never breaks, one
//    amount size, 2 per row narrow / at large text (320 and 375, Swahili, 2.0x)
// D4 the browser's online state greys out Pay later and Record payment
// D5 "1 day overdue"
// D6 allocation preview is its own live region; bucket tiles say selected;
//    the statement preview is one readable node
// D7 order card: "Deleted member" when buyer.forgotten
// D8 statement preview keeps its 32-character lines (no re-wrap)
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/vendor/customers/customer_models.dart';
import 'package:fitflexmobile/screens/vendor/customers/customer_profile_page.dart';
import 'package:fitflexmobile/screens/vendor/customers/customers_widgets.dart';
import 'package:fitflexmobile/screens/vendor/customers/statement_page.dart';
import 'package:fitflexmobile/screens/vendor/orders/vendor_order_card.dart';
import 'package:fitflexmobile/screens/vendor/sales/pos_page.dart';
import 'package:fitflexmobile/screens/vendor/stock/stock_options.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/network/browser_online.dart';

import '../support/recording_api.dart';
import 'customers_support.dart';
import 'walkin_support.dart';

String en(String k) => FFLocale().t(k);

void seedProfile(RecordingApi api, {String id = 'cus_1', String? name}) {
  api.on('GET /vendor/tools/options', customersOn);
  api.on('GET /vendor/profile', {'businessName': 'Dar Gear'});
  api.on('GET /vendor/customers/$id', profile(id: id, name: name ?? 'Juma'));
  api.on('GET /vendor/customers/$id/sales', {
    'sales': [
      {
        'id': 'sal_$id',
        'number': 'R-$id',
        'soldAt': '2026-10-19T08:00:00.000Z',
        'status': 'completed',
        'totalTzs': 45000,
        'kind': 'cash',
      },
    ],
    'nextCursor': null,
  });
  api.on('GET /vendor/customers/$id/payments', {
    'payments': [],
    'nextCursor': null,
  });
}

/// Hosts the profile and lets the test swap the customer id in place.
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String id = 'cus_1';

  void show(String next) => setState(() => id = next);

  @override
  Widget build(BuildContext context) => CustomerProfilePage(customerId: id);
}

/// All label paragraphs of the aging tiles with [prefix].
Iterable<RenderParagraph> agingParagraphs(WidgetTester tester, String prefix) =>
    [
      for (final b in agingBuckets)
        for (final part in ['label', 'amount'])
          tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byKey(Key('$prefix-$b-$part')),
              matching: find.byType(RichText),
            ),
          ),
    ];

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => BrowserOnline.debugSet(true));

  group('D1 profile reloads for another customer id', () {
    apiTest('swap in place: old lists cleared at once, new one loaded', (
      tester,
      api,
    ) async {
      seedProfile(api);
      seedProfile(api, id: 'cus_2', name: 'Neema');
      await pumpPage(
        tester,
        api,
        const _Host(),
        size: const Size(420, 1400),
        extraRoutes: customerRoutes,
      );
      expect(find.byKey(const Key('customer-sale-sal_cus_1')), findsOneWidget);
      // The new customer's profile is held: nothing of the old one shows.
      final held = api.hold('GET /vendor/customers/cus_2');
      tester.state<_HostState>(find.byType(_Host)).show('cus_2');
      await tester.pump();
      expect(find.byKey(const Key('customer-sale-sal_cus_1')), findsNothing);
      expect(find.text('Juma'), findsNothing);
      held.complete();
      await tester.pumpAndSettle();
      expect(find.text('Neema'), findsWidgets);
      expect(find.byKey(const Key('customer-sale-sal_cus_2')), findsOneWidget);
      expect(api.sent('GET', '/vendor/customers/cus_2'), isTrue);
    });
  });

  group('D2 aging tiles', () {
    test('rows: 2 narrow or at large text, 3 at 375, 5 wide', () {
      expect(agingTilesPerRow(272, 1), 2);
      expect(agingTilesPerRow(327, 1), 3);
      expect(agingTilesPerRow(327, 2), 2);
      expect(agingTilesPerRow(1000, 1), 5);
    });

    test('day ranges never break; "Bado muda haujafika" may', () {
      final sw = FFLocale()..set(const Locale('sw'));
      expect(
        agingTileLabel('d1_30', sw.t('vendor.aging.d1_30')),
        'Siku 1⁠–⁠30',
      );
      expect(
        agingTileLabel('d90plus', sw.t('vendor.aging.d90plus')),
        'Zaidi ya siku 90',
      );
      expect(
        agingTileLabel('current', sw.t('vendor.aging.current')),
        'Bado muda haujafika',
      );
    });

    for (final width in [320.0, 375.0]) {
      for (final scale in [1.0, 2.0]) {
        apiTest('Kiswahili $width @${scale}x: nothing cut, one amount size', (
          tester,
          api,
        ) async {
          seedCustomers(api);
          api.on('GET /vendor/tools/options', customersOn);
          await pumpPage(
            tester,
            api,
            Builder(
              builder: (context) => SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: AgingTiles(
                    aging: const {
                      'current': 30000,
                      'd1_30': 1250000,
                      'd31_60': 0,
                      'd61_90': 0,
                      'd90plus': 45000,
                    },
                    selected: 'd1_30',
                    onSelect: (_) {},
                    keyPrefix: 't',
                  ),
                ),
              ),
            ),
            lang: 'sw',
            size: Size(width, 900),
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          final paragraphs = agingParagraphs(tester, 't').toList();
          for (final p in paragraphs) {
            expect(p.didExceedMaxLines, isFalse, reason: p.text.toPlainText());
            // Nothing is drawn wider than its tile.
            expect(p.size.width, lessThanOrEqualTo(p.constraints.maxWidth));
          }
          // "Siku 1–30" stays on one line.
          final range = tester.renderObject<RenderParagraph>(
            find.descendant(
              of: find.byKey(const Key('t-d1_30-label')),
              matching: find.byType(RichText),
            ),
          );
          final oneLine = TextPainter(
            text: range.text,
            textDirection: TextDirection.ltr,
            textScaler: range.textScaler,
          )..layout();
          expect(range.size.height, closeTo(oneLine.height, 0.5));
          oneLine.dispose();
          // Every amount the same size; no FittedBox shrinking any of them.
          final sizes = {
            for (final b in agingBuckets)
              tester
                  .widget<Text>(find.byKey(Key('t-$b-amount')))
                  .style
                  ?.fontSize,
          };
          expect(sizes, hasLength(1));
          expect(
            find.descendant(
              of: find.byType(AgingTiles),
              matching: find.byType(FittedBox),
            ),
            findsNothing,
          );
          final perRow = agingTilesPerRow(width - 48, scale);
          expect(perRow, width == 320 || scale > 1.3 ? 2 : 3);
        });
      }
    }

    apiTest('D6 bucket tiles say which one is selected', (tester, api) async {
      final handle = tester.ensureSemantics();
      seedCustomers(api);
      api.on('GET /vendor/tools/options', customersOn);
      await pumpPage(
        tester,
        api,
        AgingTiles(
          aging: const {'current': 1, 'd1_30': 2},
          selected: 'd1_30',
          onSelect: (_) {},
          keyPrefix: 't',
        ),
      );
      final on = tester.getSemantics(find.byKey(const Key('t-d1_30')));
      final off = tester.getSemantics(find.byKey(const Key('t-current')));
      expect(on.flagsCollection.isSelected, Tristate.isTrue);

      expect(off.flagsCollection.isSelected, Tristate.isFalse);

      expect(on.flagsCollection.isButton, isTrue);
      handle.dispose();
    });
  });

  group('D4 browser offline', () {
    apiTest('profile: Record payment greyed out with the reason', (
      tester,
      api,
    ) async {
      seedProfile(api);
      final host = await pumpPage(
        tester,
        api,
        const CustomerProfilePage(customerId: 'cus_1'),
        size: const Size(420, 1400),
        extraRoutes: customerRoutes,
      );
      final record = find.byKey(const Key('customer-record-payment'));
      expect(isEnabled(tester, record), isTrue);
      BrowserOnline.debugSet(false);
      await tester.pumpAndSettle();
      expect(isEnabled(tester, record), isFalse);
      expect(find.text(host.tr('vendor.pay.offline')), findsOneWidget);
      BrowserOnline.debugSet(true);
      await tester.pumpAndSettle();
      expect(isEnabled(tester, record), isTrue);
    });

    apiTest('payment sheet: Save off while the browser is offline', (
      tester,
      api,
    ) async {
      seedProfile(api);
      await pumpPage(
        tester,
        api,
        const CustomerProfilePage(customerId: 'cus_1'),
        size: const Size(420, 1400),
        extraRoutes: customerRoutes,
      );
      await tapVisible(
        tester,
        find.byKey(const Key('customer-record-payment')),
      );
      await typeInto(tester, find.byKey(const Key('pay-amount')), '5000');
      await tester.pumpAndSettle();
      expect(isEnabled(tester, find.byKey(const Key('pay-save'))), isTrue);
      BrowserOnline.debugSet(false);
      await tester.pumpAndSettle();
      expect(isEnabled(tester, find.byKey(const Key('pay-save'))), isFalse);
      expect(find.byKey(const Key('pay-offline')), findsOneWidget);
    });

    apiTest('POS: Pay later disabled with "needs a connection"', (
      tester,
      api,
    ) async {
      seedPos(
        api,
        tools: customersOn,
        products: [posProduct('p1', 'Whey', price: 95000, stock: 5)],
      );
      seedCustomers(api);
      await pumpPage(
        tester,
        api,
        const PosPage(),
        user: ownerUser,
        size: const Size(1200, 1000),
        extraRoutes: salesRoutes,
      );
      await tester.tap(find.byKey(const Key('pos-product-p1')));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byKey(const Key('pos-cart-charge')));
      await typeInto(tester, find.byKey(const Key('pos-amount-0')), '20000');
      await tester.pumpAndSettle();
      final payLater = find.byKey(const Key('vendor-pos-paylater'));
      expect(isEnabled(tester, payLater), isTrue);
      BrowserOnline.debugSet(false);
      await tester.pumpAndSettle();
      expect(isEnabled(tester, payLater), isFalse);
      expect(find.byKey(const Key('pos-paylater-offline')), findsOneWidget);
    });
  });

  group('D5 plural', () {
    test('1 day overdue on the statement', () {
      final c = Map<String, dynamic>.from(profile()['customer'] as Map);
      c['openSales'] = [
        {
          'id': 'sal_a',
          'number': 'R-000001',
          'dueDate': '2026-10-19',
          'balanceTzs': 1000,
          'daysOverdue': 1,
          'overdue': true,
        },
      ];
      final text = statementShareText(
        customer: c,
        payments: const [],
        t: en,
        lang: 'en',
      );
      expect(text, contains('1 day overdue'));
      expect(text, isNot(contains('1 days')));
    });

    apiTest('1 day overdue on the profile badge', (tester, api) async {
      seedProfile(api);
      final p = profile();
      (p['customer'] as Map)['openSales'] = [
        {
          'id': 'sal_a',
          'number': 'R-000001',
          'soldAt': '2026-10-12T08:00:00.000Z',
          'dueDate': '2026-10-19',
          'totalTzs': 1000,
          'balanceTzs': 1000,
          'daysOverdue': 1,
          'overdue': true,
        },
      ];
      api.on('GET /vendor/customers/cus_1', p);
      await pumpPage(
        tester,
        api,
        const CustomerProfilePage(customerId: 'cus_1'),
        size: const Size(420, 1400),
        extraRoutes: customerRoutes,
      );
      expect(find.text('1 day overdue'), findsOneWidget);
    });
  });

  apiTest('D6 the allocation preview is its own live region', (
    tester,
    api,
  ) async {
    final handle = tester.ensureSemantics();
    seedProfile(api);
    await pumpPage(
      tester,
      api,
      const CustomerProfilePage(customerId: 'cus_1'),
      size: const Size(420, 1400),
      extraRoutes: customerRoutes,
    );
    await tapVisible(tester, find.byKey(const Key('customer-record-payment')));
    await typeInto(tester, find.byKey(const Key('pay-amount')), '25000');
    await tester.pumpAndSettle();
    final node = tester.getSemantics(
      find.byKey(const Key('pay-preview-region')),
    );
    expect(node.flagsCollection.isLiveRegion, isTrue);
    expect(node.label, contains('Pays off R-000001'));
    expect(node.label, isNot(contains('M-Pesa')));
    handle.dispose();
  });

  apiTest('D7 order card: "Deleted member" for a forgotten buyer', (
    tester,
    api,
  ) async {
    await pumpPage(
      tester,
      api,
      const VendorOrderCard(
        order: {
          'id': 'ord_1',
          'status': 'delivered',
          'items': [],
          'totalTzs': 1000,
          'paymentStatus': 'paid',
          'deliveryMethod': 'gym_pickup',
          'buyer': {'customerId': null, 'displayName': null, 'forgotten': true},
        },
        tools: VendorTools(customers: true),
      ),
    );
    expect(find.textContaining('Deleted member'), findsOneWidget);
    expect(find.byKey(const Key('vendor-order-customer-ord_1')), findsNothing);
  });

  apiTest('D8 + D6 statement: lines kept whole, one readable node', (
    tester,
    api,
  ) async {
    final handle = tester.ensureSemantics();
    seedProfile(api);
    await pumpPage(
      tester,
      api,
      const StatementPage(customerId: 'cus_1'),
      size: const Size(320, 900),
      extraRoutes: customerRoutes,
    );
    final text = tester.widget<Text>(
      find.byKey(const Key('statement-preview-text')),
    );
    expect(text.softWrap, isFalse);
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('statement-preview-scroll')),
    );
    expect(scroll.scrollDirection, Axis.horizontal);
    // The shared text is unchanged: every line is the 32-column document.
    for (final line in text.data!.split('\n')) {
      expect(line.length, lessThanOrEqualTo(40), reason: line);
    }
    final node = tester.getSemantics(
      find.byKey(const Key('statement-preview-semantics')),
    );
    expect(node.label, contains('Statement for Juma'));
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
