// Shop home Phase 2 · S1: the hero banner carousel
// (lib/shared/widgets/shop_home/shop_banner_carousel.dart) inside the shop
// screen, and the network source on FFPhotoHero.
//
// GET /shop/home is mocked at the HTTP level (test/support/recording_api.dart)
// with the contract's `banners[]` (fitflex-functions feat/shop-banners,
// SHOP_BANNERS). Absent or empty `banners` must leave the home unchanged.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:fitflexmobile/shared/shop_home.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';
import 'package:fitflexmobile/shared/widgets/shop_home/shop_banner_carousel.dart';
import 'package:fitflexmobile/shared/widgets/shop_home/shop_category_row.dart';

import 'support/recording_api.dart';

Map<String, dynamic> _p(String id, String name, {String vendorId = 'v1'}) => {
  'id': id,
  'vendorId': vendorId,
  'name': name,
  'category': id == 'p1' ? 'supplements_nutrition' : 'equipment',
  'priceTzs': 30000,
  'stock': 10,
  'rating': 0,
  'reviewCount': 0,
  'soldCount': 0,
  'deliveryAvailable': true,
};

final _products = [
  _p('p1', 'Whey Protein'),
  _p('p2', 'Yoga Mat', vendorId: 'v2'),
  _p('p3', 'Kettlebell'),
  _p('p4', 'Running Shoes', vendorId: 'v2'),
];

Map<String, dynamic> _banner(
  String id, {
  String origin = 'vendor',
  String? vendorName = 'Duka la Asha',
  Map<String, dynamic> target = const {'type': 'product', 'value': 'p1'},
  String lead = 'Train harder,',
  String accent = 'recover faster',
  String? subline = 'New recovery gear this week',
  String endsAt = '2026-11-01T00:00:00Z',
}) => {
  'id': id,
  // Root-relative, as the server sends them (docs/shop-banners-api.md).
  'image': {
    'url1x': '/storage/cid/$id-1x.webp',
    'url2x': '/storage/cid/$id-2x.webp',
    'urlWide': '/storage/cid/$id-wide.webp',
    'focal': {'x': -0.5, 'y': 0.25},
  },
  'imageAlt': {'en': 'A foam roller', 'sw': 'Roli ya povu'},
  'headlineLead': {'en': lead, 'sw': 'Fanya mazoezi zaidi,'},
  'headlineAccent': {'en': accent, 'sw': 'pona haraka'},
  'subline': ?(subline == null ? null : {'en': subline, 'sw': 'Vifaa vipya'}),
  'ctaLabel': {'en': 'View product', 'sw': 'Tazama bidhaa'},
  'target': target,
  'origin': origin,
  'vendorName': ?vendorName,
  'endsAt': endsAt,
};

Map<String, dynamic> _home({List<Object?>? banners}) => {
  'serverNow': '2026-10-20T08:00:00Z',
  'mode': 'member',
  'categories': [
    {
      'key': 'supplements_nutrition',
      'en': 'Supplements & nutrition',
      'sw': 'Virutubisho na lishe',
    },
    {'key': 'equipment', 'en': 'Gym equipment', 'sw': 'Vifaa vya gym'},
  ],
  'sections': [
    {
      'key': 'best_sellers',
      'title': {'en': 'Best sellers', 'sw': 'Zinazouzwa zaidi'},
      'viewAll': {
        'query': {'sort': 'popularity'},
      },
      'productIds': ['p1', 'p2', 'p3', 'p4'],
    },
  ],
  'products': {for (final p in _products) p['id']: p},
  'banners': ?banners,
};

const _member = {'id': 'm1', 'userType': 'member', 'displayName': 'Amina'};

void _seed(RecordingApi api, Map<String, dynamic> home) {
  api.on('GET /shop/products', _products);
  api.on('GET /me/shop-orders', <dynamic>[]);
  api.on('GET /shop/home', home);
}

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  String lang = 'en',
  double scale = 1,
  Size size = const Size(420, 900),
  bool showHero = false,
}) => pumpPage(
  tester,
  api,
  ShopBrowseBody(routePath: '/', showHero: showHero),
  user: _member,
  lang: lang,
  textScale: scale,
  size: size,
  keepRequests: true,
);

Finder _key(String k) => find.byKey(Key(k));

String _location(WidgetTester tester) => GoRouter.of(
  tester.element(find.byType(ShopBrowseBody)),
).routerDelegate.currentConfiguration.uri.toString();

String _slideLabel(WidgetTester tester, int i) =>
    tester.getSemantics(_key('shop-banner-slide-$i')).label;

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    debugShopHomeV2Override = true;
    ShopEvents.reset();
  });
  tearDown(() {
    debugShopHomeV2Override = null;
    debugPhotoHeroUiOverride = null;
  });

  group('no banners: the home is unchanged', () {
    for (final (name, banners) in [
      ('banners absent (SHOP_BANNERS off)', null),
    ]) {
      apiTest(name, (tester, api) async {
        _seed(api, _home(banners: banners));
        await _pump(tester, api);
        expect(_key('shop-home'), findsOneWidget);
        expect(_key('shop-banners'), findsNothing);
        expect(_key('shop-fallback-slide'), findsNothing);
        expect(find.byType(FFPhotoHero), findsNothing);
        // Categories come straight after the search row, as before.
        final search = tester.getBottomLeft(_key('shop-home-search')).dy;
        final categories = tester.getTopLeft(find.byType(ShopCategoryRow)).dy;
        expect(categories - search, lessThan(40));
      });
    }
  });

  group('banners on, none live: the P1 fallback slide (S1-AC-15)', () {
    for (final (name, banners) in [
      ('banners empty', <Object?>[]),
      (
        'only banners the app cannot use',
        <Object?>[
          {
            'id': 'x',
            'headlineLead': {'en': 'Hi', 'sw': 'Habari'},
          },
          _banner('b9', target: {'type': 'flash_sale', 'value': 's1'}),
          _banner('b8', endsAt: '2026-10-19T00:00:00Z'),
        ],
      ),
    ]) {
      apiTest('$name → the navy fallback slide, its button opens all', (
        tester,
        api,
      ) async {
        _seed(api, _home(banners: banners));
        final host = await _pump(tester, api);
        expect(_key('shop-banners'), findsNothing);
        expect(_key('shop-fallback-slide'), findsOneWidget);
        expect(find.text(host.tr('shop.home.fallbackSub')), findsOneWidget);
        // No photo, no prices.
        final hero = tester.widget<FFPhotoHero>(find.byType(FFPhotoHero));
        expect(hero.networkImage!.url, isEmpty);
        expect(
          find.descendant(
            of: _key('shop-fallback-slide'),
            matching: find.textContaining('TSh'),
          ),
          findsNothing,
        );
        await tapVisible(tester, _key('shop-fallback-cta'));
        expect(_key('shop-home'), findsNothing);
      });
    }

    apiTest('member band (PHOTO_HERO_UI) shows instead; never both', (
      tester,
      api,
    ) async {
      debugPhotoHeroUiOverride = true;
      _seed(api, _home(banners: const []));
      await _pump(tester, api, showHero: true);
      expect(_key('shop-hero'), findsOneWidget);
      expect(_key('shop-banners'), findsNothing);
      expect(_key('shop-fallback-slide'), findsNothing);
    });
  });

  group('carousel', () {
    apiTest('slot 3, replaces the band, "From {vendor}", never Sponsored', (
      tester,
      api,
    ) async {
      debugPhotoHeroUiOverride = true;
      _seed(
        api,
        _home(
          banners: [
            _banner('b1', origin: 'staff', vendorName: null),
            _banner('b2'),
          ],
        ),
      );
      await _pump(tester, api, showHero: true);
      expect(_key('shop-banners'), findsOneWidget);
      // Never both: the band is not in the tree.
      expect(_key('shop-hero'), findsNothing);
      final search = tester.getBottomLeft(_key('shop-home-search')).dy;
      final carousel = tester.getRect(_key('shop-banners'));
      final categories = tester.getTopLeft(find.byType(ShopCategoryRow)).dy;
      expect(carousel.top, greaterThan(search));
      expect(categories, greaterThan(carousel.bottom));

      // Staff banner first (server order): no chip.
      expect(_key('shop-banner-from-b1'), findsNothing);
      await tester.tap(_key('shop-banner-next'));
      await tester.pumpAndSettle();
      expect(_key('shop-banner-from-b2'), findsOneWidget);
      expect(find.text('From Duka la Asha'), findsWidgets);
      expect(find.textContaining('Sponsored'), findsNothing);
      expect(find.byType(FFPromotionBadge), findsNothing);
    });

    apiTest('slide semantics: "From {vendor}. {headline}. {subline}. '
        'Banner n of total"; the image is not read', (tester, api) async {
      final handle = tester.ensureSemantics();
      _seed(api, _home(banners: [_banner('b1'), _banner('b2'), _banner('b3')]));
      await _pump(tester, api);
      expect(
        _slideLabel(tester, 0),
        'From Duka la Asha. Train harder, recover faster. '
        'New recovery gear this week. Banner 1 of 3',
      );
      // The CTA is its own button with its visible text.
      expect(
        tester.getSemantics(_key('shop-banner-cta-b1')),
        isSemantics(label: 'View product', isButton: true, hasTapAction: true),
      );
      // The photo is decorative.
      final photo = tester.widget<Image>(_key('ff-hero-photo').first);
      expect(photo.excludeFromSemantics, isTrue);
      handle.dispose();
    });

    apiTest('Swahili: "Kutoka", "Bango 1 kati ya 2"', (tester, api) async {
      final handle = tester.ensureSemantics();
      _seed(api, _home(banners: [_banner('b1'), _banner('b2')]));
      await _pump(tester, api, lang: 'sw');
      expect(find.text('Kutoka Duka la Asha'), findsWidgets);
      expect(_slideLabel(tester, 0), endsWith('Bango 1 kati ya 2'));
      expect(_slideLabel(tester, 0), startsWith('Kutoka Duka la Asha.'));
      expect(find.text('Tazama bidhaa'), findsWidgets);
      expect(
        tester.getSemantics(_key('shop-banner-next')).tooltip,
        'Bango linalofuata',
      );
      handle.dispose();
    });

    apiTest('no auto-advance; Next / Previous wrap; dots jump', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      _seed(api, _home(banners: [_banner('b1'), _banner('b2'), _banner('b3')]));
      await _pump(tester, api);
      await tester.pump(const Duration(seconds: 40));
      await tester.pumpAndSettle();
      expect(_slideLabel(tester, 0), endsWith('Banner 1 of 3'));
      await tester.tap(_key('shop-banner-prev'));
      await tester.pumpAndSettle();
      expect(_slideLabel(tester, 2), endsWith('Banner 3 of 3'));
      await tester.tap(_key('shop-banner-next'));
      await tester.pumpAndSettle();
      expect(_slideLabel(tester, 0), endsWith('Banner 1 of 3'));
      await tester.tap(_key('shop-banner-dot-1'));
      await tester.pumpAndSettle();
      expect(_slideLabel(tester, 1), endsWith('Banner 2 of 3'));
      // Swipe left: the next slide.
      await tester.fling(
        _key('shop-banner-slide-1'),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(_slideLabel(tester, 2), endsWith('Banner 3 of 3'));
      handle.dispose();
    });

    apiTest('screen reader increase / decrease change the slide', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      _seed(api, _home(banners: [_banner('b1'), _banner('b2')]));
      await _pump(tester, api);
      final node = tester.getSemantics(_key('shop-banner-slide-0'));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(_slideLabel(tester, 1), endsWith('Banner 2 of 2'));
      final second = tester.getSemantics(_key('shop-banner-slide-1'));
      second.owner!.performAction(second.id, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(_slideLabel(tester, 0), endsWith('Banner 1 of 2'));
      handle.dispose();
    });

    apiTest('one banner: no dots, no arrows, no increase action', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      _seed(api, _home(banners: [_banner('b1')]));
      await _pump(tester, api);
      expect(_key('shop-banner-slide-0'), findsOneWidget);
      expect(_key('shop-banner-next'), findsNothing);
      expect(_key('shop-banner-dot-0'), findsNothing);
      expect(
        tester
            .getSemantics(_key('shop-banner-slide-0'))
            .getSemanticsData()
            .hasAction(SemanticsAction.increase),
        isFalse,
      );
      handle.dispose();
    });

    apiTest('controls are at least 48dp; dots 44dp', (tester, api) async {
      _seed(api, _home(banners: [_banner('b1'), _banner('b2')]));
      await _pump(tester, api);
      for (final k in ['shop-banner-prev', 'shop-banner-next']) {
        final size = tester.getSize(_key(k));
        expect(size.width, greaterThanOrEqualTo(48), reason: k);
        expect(size.height, greaterThanOrEqualTo(48), reason: k);
      }
      expect(tester.getSize(_key('shop-banner-dot-0')), const Size(44, 44));
      expect(
        tester.getSize(_key('shop-banner-cta-b1')).height,
        greaterThanOrEqualTo(48),
      );
    });

    apiTest('keyboard: Next is reachable and works with Enter', (
      tester,
      api,
    ) async {
      _seed(api, _home(banners: [_banner('b1'), _banner('b2')]));
      await _pump(tester, api);
      final next = tester.widget<IconButton>(_key('shop-banner-next'));
      next.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_key('shop-banner-cta-b2'), findsOneWidget);
    });

    apiTest('reduced motion: the new slide shows in the same frame', (
      tester,
      api,
    ) async {
      _seed(api, _home(banners: [_banner('b1'), _banner('b2')]));
      await _pump(tester, api);
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpAndSettle();
      await tester.tap(_key('shop-banner-next'));
      await tester.pump();
      expect(_key('shop-banner-cta-b2'), findsOneWidget);
      expect(_key('shop-banner-cta-b1'), findsNothing);
      // No cross-fade between slides (nor inside the hero).
      expect(
        find.descendant(
          of: _key('shop-banners'),
          matching: find.byType(AnimatedSwitcher),
        ),
        findsNothing,
      );
    });

    apiTest('130% text, Swahili, 375 wide: nothing overflows', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(
          banners: [
            _banner(
              'b1',
              vendorName: 'Duka Kubwa la Vifaa vya Michezo la Kariakoo',
            ),
            _banner('b2'),
          ],
        ),
      );
      await _pump(
        tester,
        api,
        lang: 'sw',
        scale: 1.3,
        size: const Size(375, 812),
      );
      expect(tester.takeException(), isNull);
      // At most two lines, then an ellipsis.
      final chipText = tester.widget<Text>(
        find.descendant(
          of: _key('shop-banner-from-b1'),
          matching: find.byType(Text),
        ),
      );
      expect(chipText.maxLines, 2);
      expect(chipText.overflow, TextOverflow.ellipsis);
      // The chip sits above the headline, never on it.
      final chip = tester.getRect(_key('shop-banner-from-b1'));
      final headline = tester.getRect(_key('ff-hero-headline').last);
      expect(chip.bottom, lessThanOrEqualTo(headline.top));
    });

    apiTest(
      'the photo comes from the network; the navy ground stays under it',
      (tester, api) async {
        _seed(api, _home(banners: [_banner('b1')]));
        await _pump(tester, api);
        final hero = tester.widget<FFPhotoHero>(find.byType(FFPhotoHero).last);
        expect(hero.photo, isNull);
        // Resolved on the API server; focal point from the upload.
        expect(
          hero.networkImage!.url,
          'http://fixtures.local/storage/cid/b1-1x.webp',
        );
        expect(hero.networkImage!.focal, const Alignment(-0.5, 0.25));
        expect(hero.variant, FFHeroVariant.band);
        // The placeholder is drawn whether or not the photo loads (it fails
        // in tests), so the text stays readable.
        expect(_key('ff-hero-placeholder'), findsWidgets);
        expect(find.text('Train harder, recover faster'), findsWidgets);
      },
    );

    apiTest('wide screens use the wide crop in a rounded panel', (
      tester,
      api,
    ) async {
      _seed(api, _home(banners: [_banner('b1')]));
      await _pump(tester, api, size: const Size(1280, 900));
      final hero = tester.widget<FFPhotoHero>(find.byType(FFPhotoHero).last);
      expect(
        hero.networkImage!.url,
        'http://fixtures.local/storage/cid/b1-wide.webp',
      );
      expect(hero.variant, FFHeroVariant.panel);
      expect(tester.getSize(_key('shop-banners')).height, lessThan(460));
    });
  });

  group('CTA targets', () {
    apiTest('product: the product sheet, ?product= in the URL', (
      tester,
      api,
    ) async {
      _seed(api, _home(banners: [_banner('b1')]));
      api.on('GET /shop/products/p1', _products.first);
      await _pump(tester, api);
      await tapVisible(tester, _key('shop-banner-cta-b1'));
      expect(_key('shop-detail-add-p1'), findsOneWidget);
      expect(_location(tester), contains('product=p1'));
    });

    apiTest('product gone: "no longer available", the home stays', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(
          banners: [
            _banner('b1', target: {'type': 'product', 'value': 'zz'}),
          ],
        ),
      );
      final host = await _pump(tester, api);
      await tapVisible(tester, _key('shop-banner-cta-b1'));
      expect(host.snack(host.tr('shop.home.productGone')), findsOneWidget);
      expect(_key('shop-home'), findsOneWidget);
    });

    apiTest('vendor store: results for that seller, titled; Back to home', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(
          banners: [
            _banner(
              'b1',
              vendorName: 'Mat House',
              target: {'type': 'vendor_store', 'value': 'v2'},
            ),
          ],
        ),
      );
      await _pump(tester, api);
      await tapVisible(tester, _key('shop-banner-cta-b1'));
      expect(_key('shop-home'), findsNothing);
      expect(_key('shop-results-vendor'), findsOneWidget);
      expect(find.text('Mat House'), findsOneWidget);
      expect(_key('shop-product-p2'), findsOneWidget);
      expect(_key('shop-product-p4'), findsOneWidget);
      expect(_key('shop-product-p1'), findsNothing);
      expect(_location(tester), contains('vendorId=v2'));
      await tapVisible(tester, _key('shop-back-to-home'));
      expect(_key('shop-home'), findsOneWidget);
      expect(_location(tester), '/');
    });

    apiTest('a refresh on a store URL keeps the seller filter', (
      tester,
      api,
    ) async {
      _seed(api, _home());
      await pumpPage(
        tester,
        api,
        const ShopBrowseBody(routePath: '/'),
        user: _member,
        size: const Size(420, 900),
        initialLocation: '/?view=results&vendorId=v2',
      );
      expect(_key('shop-product-p2'), findsOneWidget);
      expect(_key('shop-product-p1'), findsNothing);
    });

    apiTest('category: results in that category', (tester, api) async {
      _seed(
        api,
        _home(
          banners: [
            _banner(
              'b1',
              origin: 'staff',
              target: {'type': 'category', 'value': 'supplements_nutrition'},
            ),
          ],
        ),
      );
      await _pump(tester, api);
      await tapVisible(tester, _key('shop-banner-cta-b1'));
      expect(_location(tester), contains('category=supplements_nutrition'));
      expect(_key('shop-product-p1'), findsOneWidget);
      expect(_key('shop-product-p3'), findsNothing);
    });

    apiTest('results: the list with the filters in the value', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(
          banners: [
            _banner(
              'b1',
              origin: 'staff',
              target: {
                'type': 'results',
                'value': {'sort': 'price_asc'},
              },
            ),
          ],
        ),
      );
      await _pump(tester, api);
      await tapVisible(tester, _key('shop-banner-cta-b1'));
      expect(_key('shop-home'), findsNothing);
      expect(_location(tester), contains('sort=price_asc'));
    });
  });

  group('carousel component', () {
    Future<void> host(WidgetTester tester, ThemeData theme) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        FFLocaleScope(
          notifier: FFLocale(),
          child: MaterialApp(
            theme: theme,
            home: Scaffold(
              body: ShopBannerCarousel(
                banners: [
                  for (final id in ['a', 'b'])
                    ShopBanner.fromJson(_banner(id))!,
                ],
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Color activeDot(WidgetTester tester) {
      final box = tester.widget<AnimatedContainer>(
        find.descendant(
          of: _key('shop-banner-dot-0'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    testWidgets('Volt only in the dark theme', (tester) async {
      await host(tester, buildDarkTheme());
      expect(activeDot(tester), FFTokens.volt);
      await host(tester, buildTheme());
      expect(activeDot(tester), isNot(FFTokens.volt));
      // The accent in light theme is the brand green, not Volt.
      expect(
        FFPhotoHero.accentFor(tester.element(find.byType(FFPhotoHero).last)),
        FFTokens.heroAccentLight,
      );
    });
  });

  group('model', () {
    test('image pick: 1x / 2x by pixel ratio, wide at 840+', () {
      final b = ShopBanner.fromJson(_banner('b1'))!;
      expect(b.image.pick(375, 1), endsWith('-1x.webp'));
      expect(b.image.pick(375, 3), endsWith('-2x.webp'));
      expect(b.image.pick(900, 1), endsWith('-wide.webp'));
      const onlyWide = ShopBannerImage(urlWide: 'https://x/w.webp');
      expect(onlyWide.pick(375, 1), 'https://x/w.webp');
      // Only http(s) or a root path; never another scheme or "//host".
      for (final bad in ['javascript:x', '//evil.example/a.webp', 'data:x']) {
        expect(ShopBannerImage.fromJson({'url1x': bad}).isEmpty, isTrue);
      }
      expect(
        b.image.resolved('https://api.example/').url1x,
        'https://api.example/storage/cid/b1-1x.webp',
      );
    });

    test('vendor banner without a name shows no "From" chip', () {
      final b = ShopBanner.fromJson(_banner('b1', vendorName: null))!;
      expect(b.fromVendor, isFalse);
    });

    test('results target: the product-list query object', () {
      final t = ShopBannerTarget.fromJson({
        'type': 'results',
        'value': {'promotions': true, 'sort': 'rating', 'brand': null},
      })!;
      expect(t.query, {'promotions': 'true', 'sort': 'rating'});
      expect(ShopBannerTarget.fromJson({'type': 'results'})!.query, isEmpty);
      expect(ShopBannerTarget.fromJson({'type': 'product'}), isNull);
      expect(
        ShopBannerTarget.fromJson({'type': 'flash_sale', 'value': 's'}),
        isNull,
      );
    });
  });

  group('QA round 1 (design-QA + UAT)', () {
    Rect rectOf(WidgetTester tester, String key) => tester.getRect(_key(key));

    apiTest('#1 every slide fills the tallest height, text at the bottom '
        '(mixed lengths, Swahili, 130%, 375)', (tester, api) async {
      _seed(
        api,
        _home(
          banners: [
            _banner(
              'short',
              lead: 'Gear',
              accent: 'up',
              subline: null,
              vendorName: 'Duka',
            ),
            _banner(
              'long',
              lead: 'Everything for your home gym and much more',
              accent: 'this week only',
              vendorName:
                  'Kariakoo Wholesale Supplements & Fitness Gear Centre',
            ),
          ],
        ),
      );
      await _pump(
        tester,
        api,
        lang: 'sw',
        scale: 1.3,
        size: const Size(375, 900),
      );
      expect(tester.takeException(), isNull);
      double slideBottomGap() {
        final slide = rectOf(tester, 'shop-banner-slide-0').bottom;
        final hero = tester.getRect(
          find
              .descendant(
                of: find.byWidgetPredicate(
                  (w) =>
                      w is Semantics &&
                      w.key is ValueKey &&
                      '${(w.key as ValueKey).value}'.startsWith(
                        'shop-banner-slide',
                      ),
                ),
                matching: find.byKey(const Key('ff-hero-text-zone')),
              )
              .first,
        );
        return slide - hero.bottom;
      }

      final first = rectOf(tester, 'shop-banner-slide-0');
      // The short slide's text zone ends at the slide's bottom edge.
      expect(slideBottomGap(), lessThan(1));
      await tester.tap(_key('shop-banner-next'));
      await tester.pumpAndSettle();
      final second = rectOf(tester, 'shop-banner-slide-1');
      expect(second.height, closeTo(first.height, 0.5));
      final textZone = tester.getRect(
        find
            .descendant(
              of: _key('shop-banner-slide-1'),
              matching: find.byKey(const Key('ff-hero-text-zone')),
            )
            .first,
      );
      expect(second.bottom - textZone.bottom, lessThan(1));
    });

    apiTest('#3 the banner button shows a focus ring on the photo', (
      tester,
      api,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      _seed(api, _home(banners: [_banner('b1'), _banner('b2')]));
      await _pump(tester, api);
      final button = tester.widget<FFButton>(_key('shop-banner-cta-b1'));
      button.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expect(
        find.ancestor(
          of: _key('shop-banner-cta-b1'),
          matching: find.byKey(const Key('shop-home-focus-ring')),
        ),
        findsOneWidget,
      );
    });

    apiTest('#13 dots on the photo (bottom right); wide: arrows inside the '
        'photo edges', (tester, api) async {
      _seed(api, _home(banners: [_banner('b1'), _banner('b2'), _banner('b3')]));
      await _pump(tester, api);
      final slide = rectOf(tester, 'shop-banner-slide-0');
      final dots = rectOf(tester, 'shop-banner-dots');
      expect(slide.contains(dots.center), isTrue);
      expect(dots.right, greaterThan(slide.center.dx));
      expect(dots.bottom, greaterThan(slide.center.dy));
      // White on the scrim in the light theme (Volt only in dark).
      final active = tester.widget<AnimatedContainer>(
        find.descendant(
          of: _key('shop-banner-dot-0'),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((active.decoration! as BoxDecoration).color, Colors.white);
      // Phones: Previous / Next under the photo.
      expect(rectOf(tester, 'shop-banner-next').top, greaterThan(slide.bottom));

      await _pump(tester, api, size: const Size(1280, 900));
      final wide = rectOf(tester, 'shop-banner-slide-0');
      for (final k in ['shop-banner-prev', 'shop-banner-next']) {
        final r = rectOf(tester, k);
        expect(wide.contains(r.center), isTrue, reason: k);
        expect(r.width, greaterThanOrEqualTo(48));
      }
      expect(rectOf(tester, 'shop-banner-prev').left, lessThan(wide.left + 60));
      expect(
        rectOf(tester, 'shop-banner-next').right,
        greaterThan(wide.right - 60),
      );
    });

    apiTest('#14 the slide label has no doubled full stop', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      _seed(
        api,
        _home(banners: [_banner('b1', subline: 'New gear this week.')]),
      );
      await _pump(tester, api);
      final label = tester.getSemantics(_key('shop-banner-slide-0')).label;
      expect(label, contains('New gear this week. Banner 1 of 1'));
      expect(label, isNot(contains('..')));
      handle.dispose();
    });

    test('#14 sentences join once', () {
      expect(
        shopJoinSentences(['From Asha.', '', 'Big sale!', 'Banner 1 of 2']),
        'From Asha. Big sale. Banner 1 of 2',
      );
    });

    apiTest('#15 Back from a banner\'s target shows the same slide', (
      tester,
      api,
    ) async {
      _seed(
        api,
        _home(
          banners: [
            _banner('b1'),
            _banner(
              'b2',
              vendorName: 'Mat House',
              target: {'type': 'vendor_store', 'value': 'v2'},
            ),
            _banner('b3'),
          ],
        ),
      );
      await _pump(tester, api);
      await tester.tap(_key('shop-banner-next'));
      await tester.pumpAndSettle();
      await tapVisible(tester, _key('shop-banner-cta-b2'));
      expect(_key('shop-home'), findsNothing);
      await tapVisible(tester, _key('shop-back-to-home'));
      expect(_key('shop-banner-cta-b2'), findsOneWidget);
    });

    apiTest('#16 a refresh on a store list keeps the store-name heading', (
      tester,
      api,
    ) async {
      api.on('GET /shop/products', [
        for (final p in _products)
          {
            ...p,
            if (p['vendorId'] == 'v2') 'vendor': {'businessName': 'Mat House'},
          },
      ]);
      api.on('GET /me/shop-orders', <dynamic>[]);
      api.on('GET /shop/home', _home());
      await pumpPage(
        tester,
        api,
        const ShopBrowseBody(routePath: '/'),
        user: _member,
        size: const Size(420, 900),
        initialLocation: '/?view=results&vendorId=v2',
      );
      expect(_key('shop-results-vendor'), findsOneWidget);
      expect(find.text('Mat House'), findsOneWidget);
    });
  });

  group('QA round 2', () {
    apiTest('#2 wide: Tab goes CTA → Previous → Next, each with a visible '
        'ring on the photo', (tester, api) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      addTearDown(
        () => FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.automatic,
      );
      _seed(api, _home(banners: [_banner('b1'), _banner('b2')]));
      await _pump(tester, api, size: const Size(1280, 900));
      final cta = tester.widget<FFButton>(_key('shop-banner-cta-b1'));
      cta.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      Finder ringAround(String key) => find.ancestor(
        of: _key(key),
        matching: find.byKey(const Key('shop-home-focus-ring')),
      );
      expect(ringAround('shop-banner-cta-b1'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final prev = tester.widget<IconButton>(_key('shop-banner-prev'));
      expect(prev.focusNode!.hasPrimaryFocus, isTrue);
      expect(ringAround('shop-banner-prev'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final next = tester.widget<IconButton>(_key('shop-banner-next'));
      expect(next.focusNode!.hasPrimaryFocus, isTrue);
      expect(ringAround('shop-banner-next'), findsOneWidget);
      // Two-tone (white inside, dark outside) so it shows on any photo.
      final ring = tester.widget<DecoratedBox>(
        ringAround('shop-banner-next').first,
      );
      final border = (ring.decoration as BoxDecoration).border! as Border;
      expect(border.top.color, FFTokens.heroScrim);
      expect(
        find.descendant(
          of: ringAround('shop-banner-next').first,
          matching: find.byWidgetPredicate(
            (w) =>
                w is DecoratedBox &&
                w.decoration is BoxDecoration &&
                ((w.decoration as BoxDecoration).border as Border?)
                        ?.top
                        .color ==
                    FFTokens.heroText,
          ),
        ),
        findsOneWidget,
      );
    });

    apiTest('#3 a refreshed store list takes its heading from the product '
        'rows\' vendorName', (tester, api) async {
      api.on('GET /shop/products', [
        for (final p in _products)
          {...p, if (p['vendorId'] == 'v2') 'vendorName': 'Mat House Dar'},
      ]);
      api.on('GET /me/shop-orders', <dynamic>[]);
      api.on('GET /shop/home', _home());
      await pumpPage(
        tester,
        api,
        const ShopBrowseBody(routePath: '/'),
        user: _member,
        size: const Size(420, 900),
        initialLocation: '/?view=results&vendorId=v2',
      );
      expect(find.text('Mat House Dar'), findsOneWidget);
    });
  });
}
