// Shop home Phase 2 · S4: the vendor's flash sales (Promotions → Flash
// sales), the sale form, the product price lock and the notification links.
//
// Mocks the contract from fitflex-functions docs/shop-flash-sales-api.md
// (feat/shop-flash-sales, SHOP_FLASH_SALES):
//   GET /vendor/tools/options → merch: {flashSales: bool}
//   GET/POST /vendor/flash-sales, GET /vendor/flash-sales/price-check,
//   PATCH /:id, POST /:id/submit | withdraw | end
//   422 discount_out_of_range, 422 price_raised_recently, 409 sale_overlap,
//   409 too_many_open_proposals, 403 vendor_suspended, 404 feature_disabled.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/vendor/merch/flash_sale_form_page.dart';
import 'package:fitflexmobile/screens/vendor/merch/flash_sale_models.dart';
import 'package:fitflexmobile/screens/vendor/merch/vendor_banners_page.dart';
import 'package:fitflexmobile/screens/vendor/merch/vendor_merch_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/formatters.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

final _now = DateTime.utc(2026, 10, 29, 8);
DateTime _clock() => _now;

const _salesOn = {
  'stockLedger': false,
  'merch': {'banners': true, 'flashSales': true},
};
const _salesOnly = {
  'stockLedger': false,
  'merch': {'flashSales': true},
};
const _bannersOnly = {
  'stockLedger': false,
  'merch': {'banners': true},
};

Finder _key(String k) => find.byKey(Key(k));

/// The vendor view of a sale (docs/shop-flash-sales-api.md "Sale view").
Map<String, dynamic> _sale(
  String id,
  String status, {
  String origin = 'vendor',
  int sale = 69000,
  int regular = 85000,
  String startsAt = '2026-10-31T06:00:00Z',
  String endsAt = '2026-11-01T06:00:00Z',
  String? statusReason,
  String? statusReasonNote,
  List<String>? actions,
}) => {
  'id': id,
  'origin': origin,
  'vendorId': 'v1',
  'productId': 'p1',
  'productName': 'Foam Roller',
  'productImage': null,
  'salePriceTzs': sale,
  'regularPriceTzs': regular,
  'discountPriceTzs': null,
  'wasPriceTzs': status == 'approved' || status == 'live' ? regular : null,
  'discountPct': ((regular - sale) * 100 / regular).floor(),
  'savingTzs': regular - sale,
  'startsAt': startsAt,
  'endsAt': endsAt,
  'status': status == 'live' ? 'approved' : status,
  'effectiveStatus': status,
  'statusReason': statusReason,
  'statusReasonNote': statusReasonNote,
  'expiresAt': status == 'pending_approval' ? '2026-10-31T06:00:00Z' : null,
  'revision': 1,
  'endedByFitflex': statusReason == 'ended_by_fitflex',
  'allowedActions':
      actions ??
      (origin == 'staff'
          ? <String>[]
          : switch (status) {
              'draft' => ['edit', 'submit', 'withdraw'],
              'pending_approval' => ['edit', 'withdraw'],
              'approved' => ['edit', 'withdraw', 'end'],
              'live' => ['end'],
              'rejected' => ['edit'],
              _ => <String>[],
            }),
};

Map<String, dynamic> _list(
  List<Map<String, dynamic>> items, {
  bool canPropose = true,
  String? reason,
  int? open,
  int max = 10,
}) => {
  'items': items,
  'total': items.length,
  'nextCursor': null,
  'vendor': {'canPropose': canPropose, 'reason': reason},
  'proposalExpiryDays': 14,
  'openProposals': {'open': open ?? items.length, 'max': max},
  'rules': {
    'minDiscountPct': 5,
    'minLengthMs': 3600000,
    'maxLengthMs': 604800000,
    'minLeadMs': 3600000,
    'priceRaiseLookbackDays': 14,
  },
};

final _products = [
  stockProduct('p1', 'Foam Roller'),
  {...stockProduct('p2', 'Yoga Mat'), 'discountPriceTzs': 79000},
  stockProduct('p3', 'Old Band', stock: 0),
];

const _checkOk = {
  'ok': true,
  'productId': 'p1',
  'regularPriceTzs': 85000,
  'discountPriceTzs': null,
  'effectivePriceTzs': 85000,
  'maxSalePriceTzs': 80750,
  'raisedAt': null,
  'raisedOn': null,
  'earliestStart': null,
  'lockedBy': null,
};

void _seed(
  RecordingApi api, {
  List<Map<String, dynamic>> sales = const [],
  Map<String, dynamic> tools = _salesOn,
  Map<String, dynamic>? list,
}) {
  api.on('GET /vendor/tools/options', tools);
  api.on('GET /vendor/flash-sales', list ?? _list(sales));
  api.on('GET /vendor/flash-sales/price-check', _checkOk);
  api.on('GET /vendor/products', _products);
  api.on('GET /vendor/shop-banners', {
    'items': [],
    'total': 0,
    'nextCursor': null,
    'vendor': {'canPropose': true, 'reason': null},
  });
  api.on('GET /vendor/profile', {'businessName': 'Duka la Asha'});
}

final _routes = <RouteBase>[
  GoRoute(
    path: AppRoutes.vendorMerch,
    builder: (_, state) => VendorMerchPage(
      now: _clock,
      tab: state.uri.queryParameters['tab'],
      item: state.uri.queryParameters['item'],
    ),
  ),
  GoRoute(
    path: AppRoutes.vendorMerchSaleNew,
    builder: (_, state) => VendorFlashSaleFormRoute(
      now: _clock,
      copyId: state.uri.queryParameters['copy'],
      productId: state.uri.queryParameters['productId'],
    ),
  ),
  GoRoute(
    path: '/vendor/merch/sale/:saleId/edit',
    builder: (_, state) => VendorFlashSaleFormRoute(
      now: _clock,
      saleId: state.pathParameters['saleId'],
    ),
  ),
];

Future<PageHost> _pumpAt(
  WidgetTester tester,
  RecordingApi api,
  String location, {
  String lang = 'en',
  double scale = 1,
}) => pumpPage(
  tester,
  api,
  const SizedBox(),
  user: vendorUser,
  lang: lang,
  textScale: scale,
  size: const Size(400, 900),
  initialLocation: location,
  extraRoutes: _routes,
  keepRequests: true,
);

/// Picks the date and time pickers' first suggestion for both dates (start
/// tomorrow, end a day later: a valid 24 h sale).
Future<void> _pickDates(WidgetTester tester) async {
  for (final k in ['merch-sale-startsAt', 'merch-sale-endsAt']) {
    await tapVisible(tester, _key(k));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    // Swahili: the 12-hour time-of-day list (QA #12), opened at the
    // suggestion; English: the Material picker's OK.
    if (_key('merch-sw-time-picker').evaluate().isNotEmpty) {
      await tester.tap(
        find.descendant(
          of: _key('merch-sw-time-picker'),
          matching: find.byIcon(Icons.check),
        ),
      );
    } else {
      await tester.tap(find.text('OK'));
    }
    await tester.pumpAndSettle();
  }
}

String? _text(WidgetTester tester, String key) {
  final f = _key(key);
  if (f.evaluate().isEmpty) return null;
  return tester.widget<Text>(f).data;
}

void main() {
  setUpAll(loadAppFonts);

  group('rules (pure)', () {
    test('5% minimum against the regular price, no maximum', () {
      expect(flashSaleMaxPrice(85000), 80750);
      expect(flashSalePercent(85000, 69000), 18);
      expect(
        flashSalePriceProblem(regular: 85000, sale: 81600),
        'min5',
        reason: '4% off',
      );
      expect(flashSalePriceProblem(regular: 85000, sale: 80750), isNull);
      expect(
        flashSalePriceProblem(regular: 85000, sale: 8500),
        isNull,
        reason: '90% off is accepted',
      );
      expect(flashSalePriceProblem(regular: 85000, sale: 1), isNull);
      expect(flashSalePriceProblem(regular: 85000, sale: 0), 'enterPrice');
      expect(flashSalePriceProblem(regular: 85000, sale: null), 'enterPrice');
    });

    test('must be below the standing discount (a real one only)', () {
      expect(
        flashSalePriceProblem(regular: 85000, discount: 79000, sale: 79000),
        'belowDiscount',
      );
      expect(
        flashSalePriceProblem(regular: 85000, discount: 79000, sale: 78999),
        isNull,
      );
      // 0 or ≥ price is not a discount.
      expect(
        flashSalePriceProblem(regular: 85000, discount: 0, sale: 80000),
        isNull,
      );
    });

    test('dates: lead time, order, 1 h to 7 days', () {
      final start = _now.add(const Duration(days: 1));
      String? p(DateTime? s, DateTime? e) =>
          flashSaleDatesProblem(startsAt: s, endsAt: e, now: _now);
      expect(p(null, start), 'required');
      expect(
        p(
          _now.add(const Duration(minutes: 30)),
          _now.add(const Duration(hours: 5)),
        ),
        'startSoon',
      );
      expect(p(start, start), 'endAfter');
      expect(p(start, start.add(const Duration(minutes: 30))), 'length');
      expect(p(start, start.add(const Duration(days: 8))), 'length');
      expect(p(start, start.add(const Duration(hours: 1))), isNull);
      expect(p(start, start.add(const Duration(days: 7))), isNull);
    });

    test('edit: the lead time counts only when the start moves', () {
      final soon = _now.add(const Duration(minutes: 30));
      expect(
        flashSaleDatesProblem(
          startsAt: soon,
          endsAt: soon.add(const Duration(hours: 2)),
          now: _now,
          checkLead: false,
        ),
        isNull,
      );
    });

    test('price check: the later of the raise and history rules wins', () {
      final c = FlashSalePriceCheck.fromJson({
        'ok': false,
        'raisedAt': '2026-10-24T09:00:00Z',
        'raisedOn': '2026-10-24',
        'earliestStart': '2026-11-07T09:00:00Z',
        'listedAt': '2026-10-26T09:00:00Z',
        'historyEarliestStart': '2026-11-09T09:00:00Z',
      });
      expect(c.raiseFails, isTrue);
      expect(c.historyFails, isTrue);
      expect(c.earliestValidStart, DateTime.utc(2026, 11, 9, 9));
      expect(c.historyShort, isTrue);
      expect(c.listedOn, DateTime(2026, 10, 26));
      final raiseLater = FlashSalePriceCheck.fromJson({
        'ok': false,
        'raisedOn': '2026-10-28',
        'earliestStart': '2026-11-11T09:00:00Z',
        'historyEarliestStart': '2026-11-09T09:00:00Z',
      });
      expect(raiseLater.earliestValidStart, DateTime.utc(2026, 11, 11, 9));
      expect(raiseLater.historyShort, isFalse);
      expect(FlashSalePriceCheck.fromJson(_checkOk).raised, isFalse);
    });

    test('every error code has a place on the form', () {
      FlashSaleError e(String code, [Map<String, dynamic> extra = const {}]) =>
          flashSaleError(ApiException(422, {'error': code, ...extra}));
      expect(
        e('discount_out_of_range', {
          'reason': 'below_minimum',
          'maxSalePriceTzs': 80750,
        }).key,
        'merch.sale.min5',
      );
      expect(
        e('discount_out_of_range', {
          'reason': 'not_below_effective',
          'discountPriceTzs': 79000,
        }).key,
        'merch.sale.belowDiscount',
      );
      expect(e('sale_length_out_of_range').target, 'endsAt');
      expect(e('end_before_start').key, 'merch.dates.endAfter');
      expect(e('start_too_soon').key, 'merch.dates.startSoon');
      expect(e('price_raised_recently').target, 'raised');
      expect(e('sale_overlap').target, 'product');
      expect(e('product_not_eligible').key, 'merch.sale.notEligible');
      expect(e('not_your_product').target, 'product');
      expect(e('too_many_open_proposals').key, 'merch.sales.tooManyOpen');
      expect(e('rate_limited').key, 'merch.rateLimited');
      expect(e('vendor_suspended').closes, isTrue);
      expect(e('vendor_not_approved').closes, isTrue);
      expect(e('not_editable').closes, isTrue);
      expect(e('feature_disabled').key, 'merch.unavailable');
      expect(e('sale_not_found').key, 'merch.notYours');
      expect(e('vendor_not_found').key, 'merch.notYours');
      expect(e('vendor_not_found').closes, isTrue);
      expect(e('vendor_suspended').key, 'merch.sale.suspended');
      final short = e('price_history_too_short', {
        'listedAt': '2026-10-25T09:00:00Z',
        'earliestStart': '2026-11-08T09:00:00Z',
      });
      expect(short.target, 'raised');
      expect(short.key, 'merch.sale.historyShort');
      expect(e('something_new').key, 'merch.saveFailed');
    });
  });

  group('gating', () {
    apiTest('merch.flashSales true → Promotions tile on the vendor home', (
      tester,
      api,
    ) async {
      seedVendorHome(
        api,
        products: [stockProduct('p1', 'Roller')],
        tools: _salesOnly,
      );
      api.on('GET /vendor/flash-sales', _list(const []));
      await pumpVendorHome(tester, api);
      expect(_key('vendor-merch-entry'), findsOneWidget);
    });

    apiTest('both tools → "Flash sales | Banners", sales first', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pumpAt(tester, api, '/vendor/merch');
      expect(_key('merch-tabs'), findsOneWidget);
      expect(_key('merch-tab-sales'), findsOneWidget);
      await tester.tap(find.text(host.tr('merch.tab.banners')));
      await tester.pumpAndSettle();
      expect(_key('merch-tab-banners'), findsOneWidget);
    });

    apiTest('flash sales off → the banners page exactly as before', (
      tester,
      api,
    ) async {
      _seed(api, tools: _bannersOnly);
      await _pumpAt(tester, api, '/vendor/merch');
      expect(_key('merch-tabs'), findsNothing);
      expect(find.byType(VendorBannersPage), findsOneWidget);
      expect(api.sent('GET', '/vendor/flash-sales'), isFalse);
    });

    apiTest('a banner link (?item=, no tab) still opens Banners', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pumpAt(tester, api, '/vendor/merch?item=b1');
      expect(_key('merch-tab-banners'), findsOneWidget);
    });

    apiTest('flash sales only → the sales list, no tabs', (tester, api) async {
      _seed(api, tools: _salesOnly);
      await _pumpAt(tester, api, '/vendor/merch');
      expect(_key('merch-tabs'), findsNothing);
      expect(_key('merch-tab-sales'), findsOneWidget);
    });

    apiTest('the form says the tool is off when it is', (tester, api) async {
      _seed(api, tools: _bannersOnly);
      final host = await _pumpAt(tester, api, AppRoutes.vendorMerchSaleNew);
      expect(_key('merch-sale-form-blocked'), findsOneWidget);
      expect(find.text(host.tr('merch.unavailable')), findsOneWidget);
    });
  });

  group('list', () {
    apiTest('grouped by state, price and −% badge, x of y open', (
      tester,
      api,
    ) async {
      _seed(
        api,
        sales: [
          _sale('s1', 'live'),
          _sale('s2', 'pending_approval'),
          _sale(
            's3',
            'rejected',
            statusReason: 'price_not_credible',
            statusReasonNote: 'Price went up last week',
          ),
        ],
      );
      final host = await _pumpAt(tester, api, '/vendor/merch?tab=sales');
      for (final g in ['live', 'waiting', 'past']) {
        expect(_key('merch-sale-group-$g'), findsOneWidget, reason: g);
      }
      expect(_text(tester, 'merch-sale-price-s1'), formatCurrency(69000));
      final badge = tester.widget<FFBadge>(_key('merch-sale-pct-s1'));
      expect(badge.label, '−18%');
      expect(badge.tone, FFBadgeTone.fuel);
      expect(
        tester.widget<FFBadge>(_key('merch-sale-status-s2')).label,
        host.tr('merch.status.pending'),
      );
      expect(
        _text(tester, 'merch-sale-line-s3'),
        contains('Price went up last week'),
      );
      expect(_text(tester, 'merch-sale-open-count'), '3 of 10 open proposals');
      // Live: End now only; pending: Edit + Withdraw.
      expect(_key('merch-sale-end-s1'), findsOneWidget);
      expect(_key('merch-sale-edit-s1'), findsNothing);
      expect(_key('merch-sale-edit-s2'), findsOneWidget);
      expect(_key('merch-sale-withdraw-s2'), findsOneWidget);
    });

    apiTest('at the open limit Propose is off and says why', (
      tester,
      api,
    ) async {
      _seed(api, list: _list([_sale('s2', 'pending_approval')], open: 10));
      final host = await _pumpAt(tester, api, '/vendor/merch?tab=sales');
      expect(isEnabled(tester, _key('merch-sale-propose')), isFalse);
      expect(
        _text(tester, 'merch-sale-open-count'),
        host
            .tr('merch.sale.openFull')
            .replaceAll('{open}', '10')
            .replaceAll('{max}', '10'),
      );
    });

    apiTest('a sale FitFlex made is read-only', (tester, api) async {
      _seed(api, sales: [_sale('s9', 'approved', origin: 'staff')]);
      final host = await _pumpAt(tester, api, '/vendor/merch?tab=sales');
      expect(
        _text(tester, 'merch-sale-byfitflex-s9'),
        host.tr('merch.sale.byFitflex'),
      );
      for (final a in ['edit', 'withdraw', 'end', 'submit']) {
        expect(_key('merch-sale-$a-s9'), findsNothing, reason: a);
      }
    });

    apiTest('a FitFlex-made sale: End now when allowed, with a confirm', (
      tester,
      api,
    ) async {
      _seed(
        api,
        sales: [
          _sale('s9', 'live', origin: 'staff', actions: const ['end']),
        ],
      );
      await _pumpAt(tester, api, '/vendor/merch?tab=sales');
      expect(_key('merch-sale-byfitflex-s9'), findsOneWidget);
      expect(_key('merch-sale-edit-s9'), findsNothing);
      expect(_key('merch-sale-withdraw-s9'), findsNothing);
      await tapVisible(tester, _key('merch-sale-end-s9'));
      expect(_key('merch-sale-end-confirm'), findsOneWidget);
      await tapVisible(tester, _key('merch-sale-end-confirm'));
      expect(api.sent('POST', '/vendor/flash-sales/s9/end'), isTrue);
    });

    apiTest('ended because the account was suspended (EN + SW)', (
      tester,
      api,
    ) async {
      final ended = {
        ..._sale('s7', 'ended', statusReason: 'vendor_suspended'),
        'endedByFitflex': true,
      };
      _seed(api, sales: [ended]);
      await _pumpAt(tester, api, '/vendor/merch?tab=sales');
      expect(
        _text(tester, 'merch-sale-line-s7'),
        'Ended because your account was suspended',
      );
      await tester.pumpWidget(const SizedBox());
      _seed(api, sales: [ended]);
      await _pumpAt(tester, api, '/vendor/merch?tab=sales', lang: 'sw');
      expect(
        _text(tester, 'merch-sale-line-s7'),
        'Imesitishwa kwa sababu akaunti yako ilisimamishwa',
      );
    });

    test('FitFlex-made sales: End falls back to live or scheduled', () {
      VendorFlashSale v(String status) => VendorFlashSale.fromJson({
        ..._sale('s9', status, origin: 'staff'),
        'allowedActions': null,
      });
      expect(v('live').canEnd, isTrue);
      expect(v('approved').canEnd, isTrue);
      expect(v('approved').canWithdraw, isFalse);
      expect(v('approved').canEdit, isFalse);
      expect(v('pending_approval').canEnd, isFalse);
    });

    apiTest('Swahili: ofa agreement in badges, groups and lines', (
      tester,
      api,
    ) async {
      _seed(
        api,
        sales: [
          _sale('s1', 'draft'),
          _sale('s2', 'pending_approval'),
          _sale('s3', 'withdrawn'),
        ],
      );
      await _pumpAt(tester, api, '/vendor/merch?tab=sales', lang: 'sw');
      expect(
        tester.widget<FFBadge>(_key('merch-sale-status-s1')).label,
        'Haijatumwa',
      );
      expect(find.text('Zinasubiri idhini'), findsOneWidget);
      expect(find.text('Bado hazijatumwa'), findsOneWidget);
      expect(_text(tester, 'merch-sale-line-s1'), 'Bado haijatumwa kwa idhini');
      expect(_text(tester, 'merch-sale-line-s2'), startsWith('Itaisha muda '));
      expect(_text(tester, 'merch-sale-line-s3'), 'Uliiondoa');
      // No banner (li-) agreement anywhere on the sales tab.
      for (final banner in ['Halijatumwa', 'Yanasubiri idhini', 'Liache']) {
        expect(find.textContaining(banner), findsNothing, reason: banner);
      }
    });

    apiTest('not approved yet → why, and the Verification centre', (
      tester,
      api,
    ) async {
      _seed(
        api,
        list: _list(const [], canPropose: false, reason: 'vendor_not_approved'),
      );
      await _pumpAt(tester, api, '/vendor/merch?tab=sales');
      expect(_key('merch-sales-pending'), findsOneWidget);
      expect(_key('merch-sale-propose'), findsNothing);
    });

    apiTest('Withdraw and End now call their endpoints', (tester, api) async {
      _seed(api, sales: [_sale('s1', 'live'), _sale('s2', 'pending_approval')]);
      await _pumpAt(tester, api, '/vendor/merch?tab=sales');
      await tapVisible(tester, _key('merch-sale-withdraw-s2'));
      await tapVisible(tester, _key('merch-sale-withdraw-confirm'));
      expect(api.sent('POST', '/vendor/flash-sales/s2/withdraw'), isTrue);
      await tapVisible(tester, _key('merch-sale-end-s1'));
      await tapVisible(tester, _key('merch-sale-end-confirm'));
      expect(api.sent('POST', '/vendor/flash-sales/s1/end'), isTrue);
    });

    apiTest('?item= from a notification outlines that sale', (
      tester,
      api,
    ) async {
      _seed(api, sales: [_sale('s1', 'live'), _sale('s2', 'approved')]);
      await _pumpAt(tester, api, '/vendor/merch?tab=sales&item=s2');
      expect(_key('merch-sale-highlight-s2'), findsOneWidget);
    });

    apiTest('the list says it failed, and offline says so', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('GET /vendor/flash-sales', 500);
      await _pumpAt(tester, api, '/vendor/merch?tab=sales');
      expect(_key('merch-sales-error'), findsOneWidget);
    });
  });

  group('form', () {
    apiTest('live "% off · buyers save", the 5% message, 90% accepted', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p1',
      );
      expect(
        _text(tester, 'merch-sale-regular'),
        'Regular price ${formatCurrency(85000)}',
      );
      await typeInto(tester, _key('merch-sale-price'), '69000');
      expect(
        _text(tester, 'merch-sale-helper'),
        '18% off · buyers save ${formatCurrency(16000)}',
      );
      // Thousands separator as typed.
      expect(textOf(tester, _key('merch-sale-price')), '69,000');
      await typeInto(tester, _key('merch-sale-price'), '81600');
      expect(_key('merch-sale-helper'), findsNothing);
      expect(
        _text(tester, 'merch-sale-error-price'),
        host.tr('merch.sale.min5').replaceAll('{max}', formatCurrency(80750)),
      );
      await typeInto(tester, _key('merch-sale-price'), '8500');
      expect(_key('merch-sale-error-price'), findsNothing);
      expect(
        _text(tester, 'merch-sale-helper'),
        '90% off · buyers save ${formatCurrency(76500)}',
      );
    });

    apiTest('a product with a discount price: the sale must be below it', (
      tester,
      api,
    ) async {
      _seed(api);
      api.on('GET /vendor/flash-sales/price-check', {
        ..._checkOk,
        'productId': 'p2',
        'discountPriceTzs': 79000,
        'effectivePriceTzs': 79000,
      });
      final host = await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p2',
      );
      expect(_key('merch-sale-current-discount'), findsOneWidget);
      await typeInto(tester, _key('merch-sale-price'), '79000');
      expect(
        _text(tester, 'merch-sale-error-price'),
        host
            .tr('merch.sale.belowDiscount')
            .replaceAll('{discount}', formatCurrency(79000)),
      );
    });

    apiTest('out of stock: allowed, with a warning', (tester, api) async {
      _seed(api);
      await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p3',
      );
      expect(_key('merch-sale-oos'), findsOneWidget);
    });

    apiTest('14-day rule: the message, Send off, "Start on" fixes it', (
      tester,
      api,
    ) async {
      _seed(api);
      const earliest = '2026-11-07T08:00:00.000Z';
      api.onCall('GET /vendor/flash-sales/price-check', (r) {
        final start = Uri.splitQueryString(r.query)['startsAt'];
        final passes =
            start != null &&
            !DateTime.parse(start).isBefore(DateTime.parse(earliest));
        return passes
            ? _checkOk
            : {
                ..._checkOk,
                'ok': false,
                'raisedAt': '2026-10-24T09:00:00Z',
                'raisedOn': '2026-10-24',
                'earliestStart': earliest,
              };
      });
      await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p1',
      );
      await typeInto(tester, _key('merch-sale-price'), '69000');
      await _pickDates(tester);
      expect(_key('merch-sale-raised'), findsOneWidget);
      expect(
        find.textContaining("You raised this product's price on 24 Oct 2026"),
        findsOneWidget,
      );
      expect(isEnabled(tester, _key('merch-sale-send')), isFalse);
      await tapVisible(tester, _key('merch-sale-start-on'));
      expect(_key('merch-sale-raised'), findsNothing);
      expect(isEnabled(tester, _key('merch-sale-send')), isTrue);
    });

    apiTest('a new product (price_history_too_short): the message and '
        '"Start on {date}"', (tester, api) async {
      _seed(api);
      var refused = false;
      api.fail('POST /vendor/flash-sales', 422);
      api.onCall('fail:POST /vendor/flash-sales', (_) {
        refused = true;
        api.heal('POST /vendor/flash-sales');
        return {
          'error': 'price_history_too_short',
          'listedAt': '2026-10-25T09:00:00Z',
          'earliestStart': '2026-11-08T09:00:00Z',
        };
      });
      api.on('POST /vendor/flash-sales', {'sale': _sale('fls_1', 'draft')});
      await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p1',
      );
      await typeInto(tester, _key('merch-sale-price'), '69000');
      await _pickDates(tester);
      await tapVisible(tester, _key('merch-sale-send'));
      expect(refused, isTrue);
      expect(_key('merch-sale-raised'), findsOneWidget);
      expect(
        find.textContaining('This product was listed on 25 Oct 2026'),
        findsOneWidget,
      );
      expect(isEnabled(tester, _key('merch-sale-send')), isFalse);
      await tapVisible(tester, _key('merch-sale-start-on'));
      expect(isEnabled(tester, _key('merch-sale-send')), isTrue);
      await tapVisible(tester, _key('merch-sale-send'));
      final sent = api.where('POST', '/vendor/flash-sales').last.body as Map;
      expect(
        DateTime.parse(sent['startsAt'] as String),
        DateTime.utc(2026, 11, 8, 9),
      );
    });

    apiTest('Swahili: the new-product message', (tester, api) async {
      _seed(api);
      api.fail('POST /vendor/flash-sales', 422, {
        'error': 'price_history_too_short',
        'listedAt': '2026-10-25T09:00:00Z',
        'earliestStart': '2026-11-08T09:00:00Z',
      });
      await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p1',
        lang: 'sw',
      );
      await typeInto(tester, _key('merch-sale-price'), '69000');
      await _pickDates(tester);
      await tapVisible(tester, _key('merch-sale-send'));
      expect(
        find.textContaining('Bidhaa hii iliwekwa dukani tarehe 25 Okt 2026'),
        findsOneWidget,
      );
    });

    apiTest('sale_overlap without dates → the general words', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('POST /vendor/flash-sales', 409, {'error': 'sale_overlap'});
      final host = await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p1',
      );
      await typeInto(tester, _key('merch-sale-price'), '69000');
      await _pickDates(tester);
      await tapVisible(tester, _key('merch-sale-send'));
      expect(
        _text(tester, 'merch-sale-error-product'),
        host.tr('merch.sale.overlapNoDates'),
      );
    });

    apiTest('the 14-day check fails: Try again offered, Send still on', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('GET /vendor/flash-sales/price-check', 500);
      final host = await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p1',
      );
      expect(_key('merch-sale-check-failed'), findsOneWidget);
      expect(
        tester.widget<FFAlert>(_key('merch-sale-check-failed')).message,
        host.tr('merch.sale.checkFailed'),
      );
      expect(_key('merch-sale-check-retry'), findsOneWidget);
      await typeInto(tester, _key('merch-sale-price'), '69000');
      await _pickDates(tester);
      expect(isEnabled(tester, _key('merch-sale-send')), isTrue);
      api.heal('GET /vendor/flash-sales/price-check');
      await tapVisible(tester, _key('merch-sale-check-retry'));
      expect(_key('merch-sale-check-failed'), findsNothing);
    });

    apiTest('price check: history rule later → its message and its date', (
      tester,
      api,
    ) async {
      _seed(api);
      api.on('GET /vendor/flash-sales/price-check', {
        ..._checkOk,
        'ok': false,
        'raisedAt': '2026-10-24T09:00:00Z',
        'raisedOn': '2026-10-24',
        'earliestStart': '2026-11-07T09:00:00Z',
        'listedAt': '2026-10-26T09:00:00Z',
        'historyEarliestStart': '2026-11-09T09:00:00Z',
      });
      await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p1',
      );
      expect(
        find.textContaining('This product was listed on 26 Oct 2026'),
        findsOneWidget,
      );
      // 9 Nov 09:00Z is 12:00 in Tanzania.
      expect(find.textContaining('9 Nov 2026, 12:00'), findsWidgets);
      expect(isEnabled(tester, _key('merch-sale-send')), isFalse);
    });

    apiTest(
      'editing without moving a start under an hour away: no lead error',
      (tester, api) async {
        _seed(
          api,
          sales: [
            _sale(
              's1',
              'pending_approval',
              startsAt: '2026-10-29T08:30:00Z',
              endsAt: '2026-10-29T12:00:00Z',
            ),
          ],
        );
        api.on('PATCH /vendor/flash-sales/s1', {
          'sale': _sale('s1', 'pending_approval'),
        });
        await _pumpAt(tester, api, '/vendor/merch/sale/s1/edit');
        await typeInto(tester, _key('merch-sale-price'), '68000');
        await tapVisible(tester, _key('merch-sale-send'));
        expect(_key('merch-sale-error-startsAt'), findsNothing);
        expect(api.sent('PATCH', '/vendor/flash-sales/s1'), isTrue);
      },
    );

    apiTest('the notes are shown (seller pays, 14-day rule, review)', (
      tester,
      api,
    ) async {
      _seed(api);
      final host = await _pumpAt(tester, api, AppRoutes.vendorMerchSaleNew);
      final notes = tester.widget<FFAlert>(_key('merch-sale-notes')).message;
      for (final k in [
        'merch.sale.youPay',
        'merch.sale.rule14',
        'merch.sale.reviewNote',
      ]) {
        expect(notes, contains(host.tr(k)), reason: k);
      }
    });

    apiTest('Send creates the draft, then sends it for approval', (
      tester,
      api,
    ) async {
      _seed(api);
      api.on('POST /vendor/flash-sales', {'sale': _sale('fls_1', 'draft')});
      api.on('POST /vendor/flash-sales/fls_1/submit', {
        'sale': _sale('fls_1', 'pending_approval'),
      });
      await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p1',
      );
      await typeInto(tester, _key('merch-sale-price'), '69000');
      await _pickDates(tester);
      await tapVisible(tester, _key('merch-sale-send'));
      final body = api.only('POST', '/vendor/flash-sales').body as Map;
      expect(body.keys.toSet(), {
        'productId',
        'salePriceTzs',
        'startsAt',
        'endsAt',
      });
      expect(body['productId'], 'p1');
      expect(body['salePriceTzs'], 69000);
      final start = DateTime.parse(body['startsAt'] as String);
      final end = DateTime.parse(body['endsAt'] as String);
      expect(end.difference(start), const Duration(days: 1));
      expect(api.sent('POST', '/vendor/flash-sales/fls_1/submit'), isTrue);
      // Back on the list.
      expect(_key('merch-tab-sales'), findsOneWidget);
    });

    apiTest('nothing filled: says what to fix', (tester, api) async {
      _seed(api);
      final host = await _pumpAt(tester, api, AppRoutes.vendorMerchSaleNew);
      await tapVisible(tester, _key('merch-sale-send'));
      expect(
        _text(tester, 'merch-sale-error-product'),
        host.tr('merch.sale.productRequired'),
      );
      expect(
        _text(tester, 'merch-sale-error-startsAt'),
        host.tr('merch.dates.required'),
      );
      expect(api.sent('POST', '/vendor/flash-sales'), isFalse);
    });

    apiTest('editing a sale longer than 7 days: the length message', (
      tester,
      api,
    ) async {
      _seed(
        api,
        sales: [
          _sale(
            's1',
            'draft',
            startsAt: '2026-10-31T06:00:00Z',
            endsAt: '2026-11-08T06:00:00Z',
          ),
        ],
      );
      final host = await _pumpAt(tester, api, '/vendor/merch/sale/s1/edit');
      expect(_key('merch-sale-product-name'), findsOneWidget);
      await tapVisible(tester, _key('merch-sale-send'));
      expect(
        _text(tester, 'merch-sale-error-endsAt'),
        host.tr('merch.sale.length'),
      );
      expect(api.sent('PATCH', '/vendor/flash-sales/s1'), isFalse);
    });

    for (final (name, status, body, check) in [
      (
        'discount_out_of_range below_minimum → under the price',
        422,
        {
          'error': 'discount_out_of_range',
          'reason': 'below_minimum',
          'minDiscountPct': 5,
          'maxSalePriceTzs': 80750,
          'regularPriceTzs': 85000,
        },
        'price',
      ),
      (
        'sale_overlap → under the product, with the dates',
        409,
        {
          'error': 'sale_overlap',
          'saleId': 'fls_9',
          'startsAt': '2026-10-30T06:00:00Z',
          'endsAt': '2026-11-02T06:00:00Z',
          'effectiveStatus': 'approved',
        },
        'product',
      ),
    ]) {
      apiTest(name, (tester, api) async {
        _seed(api);
        api.fail('POST /vendor/flash-sales', status, body);
        await _pumpAt(
          tester,
          api,
          '${AppRoutes.vendorMerchSaleNew}?productId=p1',
        );
        await typeInto(tester, _key('merch-sale-price'), '69000');
        await _pickDates(tester);
        await tapVisible(tester, _key('merch-sale-send'));
        final text = _text(tester, 'merch-sale-error-$check');
        expect(text, isNotNull);
        if (check == 'price') expect(text, contains(formatCurrency(80750)));
        if (check == 'product') expect(text, contains('30 Oct 2026'));
        expect(api.sent('POST', '/vendor/flash-sales/fls_1/submit'), isFalse);
      });
    }

    apiTest('too_many_open_proposals → said; the form stays', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('POST /vendor/flash-sales', 409, {
        'error': 'too_many_open_proposals',
        'max': 10,
        'open': 10,
      });
      final host = await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p1',
      );
      await typeInto(tester, _key('merch-sale-price'), '69000');
      await _pickDates(tester);
      await tapVisible(tester, _key('merch-sale-send'));
      expect(host.snack(host.tr('merch.sales.tooManyOpen')), findsOneWidget);
      expect(_key('merch-sale-send'), findsOneWidget);
    });

    apiTest('vendor_suspended → said, and the form closes', (
      tester,
      api,
    ) async {
      _seed(api);
      api.fail('POST /vendor/flash-sales', 403, {'error': 'vendor_suspended'});
      final host = await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p1',
      );
      await typeInto(tester, _key('merch-sale-price'), '69000');
      await _pickDates(tester);
      await tapVisible(tester, _key('merch-sale-send'));
      expect(host.snack(host.tr('merch.sale.suspended')), findsOneWidget);
      expect(_key('merch-sale-send'), findsNothing);
    });

    apiTest('Swahili at 130%: the form fits', (tester, api) async {
      _seed(api);
      await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p2',
        lang: 'sw',
        scale: 1.3,
      );
      expect(find.text('Bei ya ofa (TSh)'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('product form price lock', () {
    Future<void> openForm(
      WidgetTester tester,
      RecordingApi api,
      Map<String, dynamic> product, {
      bool showFlashSale = true,
    }) async {
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showFFSheet<bool>(
              context,
              title: 'Edit',
              child: VendorProductForm(
                product: product,
                showFlashSale: showFlashSale,
              ),
            ),
            child: const Text('open'),
          ),
        ),
        size: const Size(400, 900),
        extraRoutes: _routes,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    // Locked = greyed (disabled) like the discount price (QA #6).
    bool readOnly(WidgetTester tester, String key) =>
        tester
            .widget<TextField>(
              find.descendant(of: _key(key), matching: find.byType(TextField)),
            )
            .enabled ==
        false;

    apiTest('scheduled or live sale: price and discount read-only, View sale', (
      tester,
      api,
    ) async {
      await openForm(tester, api, {
        ...stockProduct('p1', 'Foam Roller'),
        'priceLock': {
          'saleId': 'fls_1',
          'startsAt': '2026-10-31T06:00:00Z',
          'endsAt': '2026-11-01T06:00:00Z',
          'effectiveStatus': 'approved',
        },
      });
      expect(readOnly(tester, 'vendor-product-price'), isTrue);
      expect(readOnly(tester, 'vendor-product-discount-price'), isTrue);
      expect(
        find.textContaining('Locked while your flash sale runs'),
        findsWidgets,
      );
      expect(_key('vendor-product-view-sale'), findsOneWidget);
      expect(_key('vendor-product-start-sale'), findsNothing);
    });

    apiTest('no sale: editable, and "Start a flash sale"', (tester, api) async {
      await openForm(tester, api, stockProduct('p1', 'Foam Roller'));
      expect(readOnly(tester, 'vendor-product-price'), isFalse);
      expect(_key('vendor-product-start-sale'), findsOneWidget);
    });

    apiTest('flash sales off: neither the lock nor the action', (
      tester,
      api,
    ) async {
      await openForm(tester, api, {
        ...stockProduct('p1', 'Foam Roller'),
        'priceLock': {'saleId': 'fls_1'},
      }, showFlashSale: false);
      expect(readOnly(tester, 'vendor-product-price'), isFalse);
      expect(_key('vendor-product-view-sale'), findsNothing);
      expect(_key('vendor-product-start-sale'), findsNothing);
    });
  });

  group('QA round 1 (vendor)', () {
    apiTest('#5 offline: the last list stays, actions off, offline bar', (
      tester,
      api,
    ) async {
      _seed(api, sales: [_sale('s1', 'live'), _sale('s2', 'pending_approval')]);
      final host = await _pumpAt(tester, api, '/vendor/merch?tab=sales');
      expect(_key('merch-sale-s1'), findsOneWidget);
      api.onCall(
        'GET /vendor/flash-sales',
        (_) => throw http.ClientException('XMLHttpRequest error.'),
      );
      // Pull to refresh with no connection.
      await tester.fling(
        find.byType(SingleChildScrollView).last,
        const Offset(0, 400),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(_key('merch-sales-offline-bar'), findsOneWidget);
      expect(find.text(host.tr('offline.banner')), findsOneWidget);
      expect(_key('merch-sale-s1'), findsOneWidget);
      expect(_key('merch-sale-s2'), findsOneWidget);
      expect(isEnabled(tester, _key('merch-sale-end-s1')), isFalse);
      expect(isEnabled(tester, _key('merch-sale-withdraw-s2')), isFalse);
      expect(isEnabled(tester, _key('merch-sale-propose')), isFalse);
      expect(_key('merch-sale-needs-internet'), findsOneWidget);
    });

    apiTest('#5 offline with nothing loaded before: the offline state', (
      tester,
      api,
    ) async {
      _seed(api);
      api.onCall(
        'GET /vendor/flash-sales',
        (_) => throw http.ClientException('XMLHttpRequest error.'),
      );
      await pumpPage(
        tester,
        api,
        const SizedBox(),
        user: const {'id': 'v-offline-only', 'userType': 'vendor'},
        size: const Size(400, 900),
        initialLocation: '/vendor/merch?tab=sales',
        extraRoutes: _routes,
        settle: false,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(_key('merch-sales-offline'), findsOneWidget);
    });

    apiTest('#6 locked price at 375 px, Swahili 130%: greyed, reason in full', (
      tester,
      api,
    ) async {
      await pumpPage(
        tester,
        api,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showFFSheet<bool>(
              context,
              title: 'Hariri',
              child: VendorProductForm(
                product: {
                  ...stockProduct('p1', 'Foam Roller'),
                  'priceLock': {
                    'saleId': 'fls_1',
                    'startsAt': '2026-10-31T06:00:00Z',
                    'endsAt': '2026-11-01T06:00:00Z',
                  },
                },
                showFlashSale: true,
              ),
            ),
            child: const Text('open'),
          ),
        ),
        lang: 'sw',
        textScale: 1.3,
        size: const Size(375, 812),
        extraRoutes: _routes,
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final why = tester.widget<Text>(_key('vendor-product-price-locked'));
      expect(why.maxLines, isNull);
      expect(why.overflow, isNull);
      expect(why.data, startsWith('Imefungwa wakati ofa yako inaendelea ('));
      for (final k in [
        'vendor-product-price',
        'vendor-product-discount-price',
      ]) {
        final field = tester.widget<TextField>(
          find.descendant(of: _key(k), matching: find.byType(TextField)),
        );
        expect(field.enabled, isFalse, reason: k);
      }
      expect(tester.takeException(), isNull);
    });

    apiTest('#10 Scheduled is info blue, Live success green', (
      tester,
      api,
    ) async {
      _seed(api, sales: [_sale('s1', 'live'), _sale('s2', 'approved')]);
      await _pumpAt(tester, api, '/vendor/merch?tab=sales');
      expect(
        tester.widget<FFBadge>(_key('merch-sale-status-s2')).tone,
        FFBadgeTone.info,
      );
      expect(
        tester.widget<FFBadge>(_key('merch-sale-status-s1')).tone,
        FFBadgeTone.success,
      );
    });

    apiTest('#11 the product row menu: "Start a flash sale" / "View sale"', (
      tester,
      api,
    ) async {
      seedVendorHome(
        api,
        products: [
          stockProduct('p1', 'Foam Roller'),
          {
            ...stockProduct('p2', 'Yoga Mat'),
            'priceLock': {'saleId': 'fls_9'},
          },
        ],
        tools: _salesOn,
      );
      api.on('GET /vendor/flash-sales', _list(const []));
      api.on('GET /vendor/flash-sales/price-check', _checkOk);
      api.on('GET /vendor/shop-banners', {'items': [], 'total': 0});
      final host = await pumpPage(
        tester,
        api,
        const VendorHomePage(),
        user: vendorUser,
        size: const Size(400, 900),
        extraRoutes: _routes,
      );
      // Locked product: "View sale"; the other: "Start a flash sale".
      await tester.tap(
        find.descendant(
          of: _key('vendor-product-p2'),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(host.tr('vendor.viewSale')), findsOneWidget);
      expect(find.text(host.tr('merch.sale.start')), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await productMenu(tester, 'p1', host.tr('merch.sale.start'));
      expect(_key('merch-sale-form-title'), findsOneWidget);
      expect(_text(tester, 'merch-sale-regular'), contains('85,000'));
    });

    apiTest('#11 no flash sales tool: no menu item', (tester, api) async {
      seedVendorHome(
        api,
        products: [stockProduct('p1', 'Foam Roller')],
        tools: _bannersOnly,
      );
      api.on('GET /vendor/shop-banners', {'items': [], 'total': 0});
      final host = await pumpVendorHome(tester, api);
      await tester.tap(
        find.descendant(
          of: _key('vendor-product-p1'),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(host.tr('merch.sale.start')), findsNothing);
    });

    apiTest('#12 Swahili time: a 12-hour time-of-day list, not AM/PM', (
      tester,
      api,
    ) async {
      _seed(api);
      await _pumpAt(
        tester,
        api,
        '${AppRoutes.vendorMerchSaleNew}?productId=p1',
        lang: 'sw',
        scale: 1.3,
      );
      // The title fits on two lines at 130% (descenders not clipped).
      final bar = tester.widget<AppBar>(find.byType(AppBar));
      expect(bar.toolbarHeight, greaterThan(kToolbarHeight));
      await tapVisible(tester, _key('merch-sale-startsAt'));
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(_key('merch-sw-time-picker'), findsOneWidget);
      expect(find.textContaining('AM'), findsNothing);
      expect(find.textContaining('PM'), findsNothing);
      // The suggestion (11:00 Tanzania time) is "11:00 asubuhi".
      expect(find.text('11:00 asubuhi'), findsOneWidget);
      await tester.tap(find.text('11:15 asubuhi'));
      await tester.pumpAndSettle();
      expect(find.textContaining('11:15 asubuhi'), findsWidgets);
    });

    for (final (tools, key) in [
      (_bannersOnly, 'merch.banners.title'),
      (_salesOnly, 'merch.sales.title'),
      (_salesOn, 'merch.entry.title'),
    ]) {
      apiTest('#14 the home tile names the tools that are on ($key)', (
        tester,
        api,
      ) async {
        seedVendorHome(
          api,
          products: [stockProduct('p1', 'Roller')],
          tools: tools,
        );
        api.on('GET /vendor/flash-sales', _list(const []));
        api.on('GET /vendor/shop-banners', {'items': [], 'total': 0});
        final host = await pumpVendorHome(tester, api);
        expect(
          find.descendant(
            of: _key('vendor-merch-entry'),
            matching: find.text(host.tr(key)),
          ),
          findsOneWidget,
        );
      });
    }
  });

  group('notifications', () {
    test('flash sale notices open the sale in Flash sales', () {
      for (final type in [
        'vendor_flash_sale_approved',
        'vendor_flash_sale_rejected',
        'vendor_flash_sale_expired',
        'vendor_flash_sale_ended',
      ]) {
        expect(partnerLinkFor(side: 'vendor', type: type), 'merchSale');
        expect(
          partnerRouteFor(side: 'vendor', type: type, flashSaleId: 'fls_1'),
          '/vendor/merch?tab=sales&item=fls_1',
          reason: type,
        );
      }
      // A bad id still opens the list; other sides never get it.
      expect(
        partnerRouteFor(
          side: 'vendor',
          type: 'vendor_flash_sale_approved',
          flashSaleId: '../x',
        ),
        '/vendor/merch?tab=sales',
      );
      expect(
        partnerRouteFor(side: 'trainer', type: 'vendor_flash_sale_approved'),
        isNull,
      );
    });

    test('a tapped push goes straight to the sale', () {
      final target = pushTargetFor(
        role: 'vendor',
        data: const {
          'type': 'vendor_flash_sale_approved',
          'saleId': 'fls_1',
          'open': 'merch',
          'tab': 'sales',
          'item': 'fls_1',
        },
      );
      expect(target.location, '/vendor/merch?tab=sales&item=fls_1');
      expect(target.go, isTrue);
    });
  });
}
