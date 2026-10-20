// Photo footer band behind PHOTO_FOOTER_UI (+ PHOTO_HERO_UI): photo-hero
// spec §33 / increment plan slice 2.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/member_shop_tab.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_card.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/photo_footer_flag.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:fitflexmobile/shared/shop_home.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_api.dart';

// ── fixtures ─────────────────────────────────────────────────────────────

Map<String, dynamic> _gym(String id) => {
  'id': id,
  'name': 'Gym $id',
  'tier': 'standard',
  'location': 'Dar es Salaam',
  'perVisitRate': 5000,
  'ratePerMonth': 50000,
  'commissionRate': 10,
  'status': 'active',
  'amenities': <String>[],
};

Map<String, dynamic> _trainer(String id) => {
  'id': id,
  'displayName': 'Trainer $id',
  'specialties': ['boxing'],
  'hourlyRateTzs': 20000,
  'status': 'active',
};

MemberData _data({int gyms = 12, int trainers = 12}) => MemberData()
  ..me = MemberMeResponse.fromJson({
    'user': {'id': 'm1', 'displayName': 'Amina Juma'},
    'visitsUsed': 3,
    'visitCap': 18,
  })
  ..gyms = [for (var i = 0; i < gyms; i++) Gym.fromJson(_gym('g$i'))]
  ..trainers = [
    for (var i = 0; i < trainers; i++) TrainerProfile.fromJson(_trainer('t$i')),
  ];

Map<String, dynamic> _product(String id) => {
  'id': id,
  'vendorId': 'v1',
  'name': 'Product $id',
  'category': 'equipment',
  'priceTzs': 30000,
  'stock': 10,
  'rating': 0,
  'reviewCount': 0,
  'soldCount': 0,
  'deliveryAvailable': true,
};

void _seedShop(RecordingApi api) {
  final ids = [for (var i = 0; i < 6; i++) 'p$i'];
  api.on('GET /shop/products', [for (final id in ids) _product(id)]);
  api.on('GET /me/shop-orders', <dynamic>[]);
  api.on('GET /gyms', <dynamic>[]);
  api.on('GET /shop/home', {
    'serverNow': '2026-10-19T08:00:00Z',
    'currency': 'TZS',
    'mode': 'member',
    'personalised': false,
    'signalsUsed': <String>[],
    'categories': [
      {'key': 'equipment', 'en': 'Equipment', 'sw': 'Vifaa'},
    ],
    'sections': [
      for (final k in ['best_sellers', 'deals', 'new_arrivals'])
        {
          'key': k,
          'title': {'en': k, 'sw': k},
          'viewAll': {'query': <String, String>{}},
          'productIds': ids,
        },
    ],
    'products': {for (final id in ids) id: _product(id)},
  });
}

// ── harness ─────────────────────────────────────────────────────────────

Future<void> _host(
  WidgetTester tester,
  Widget page, {
  String lang = 'en',
  Size size = const Size(390, 844),
  bool highContrast = false,
  bool reduceMotion = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient(baseUrl: 'http://fixtures.local');
  final auth = AuthState(client);
  await auth.signIn('token', {
    'id': 'm1',
    'userType': 'member',
    'approvalStatus': 'approved',
    'onboardingCompleted': true,
    'displayName': 'Amina Juma',
  });
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: page),
      ),
      GoRoute(
        path: AppRoutes.memberTrainers,
        builder: (_, _) => const Scaffold(body: Text('ROUTE-TRAINERS')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    AppScope(
      api: client,
      auth: auth,
      child: ThemeScope(
        notifier: ThemeNotifier(),
        child: FFLocaleScope(
          notifier: FFLocale()..set(Locale(lang)),
          child: MaterialApp.router(
            routerConfig: router,
            theme: buildTheme(),
            supportedLocales: const [Locale('en'), Locale('sw')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                highContrast: highContrast,
                disableAnimations: reduceMotion,
                textScaler: TextScaler.linear(textScale),
              ),
              child: c!,
            ),
          ),
        ),
      ),
    ),
  );
  await _frames(tester);
}

/// Fixed frames (the Gyms tab keeps a location spinner running in tests).
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void footerTest(
  String name,
  Future<void> Function(WidgetTester tester, RecordingApi api) body, {
  bool hero = true,
  bool footer = true,
}) {
  testWidgets(name, (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugPhotoHeroUiOverride = hero;
    debugPhotoFooterUiOverride = footer;
    debugShopHomeV2Override = true;
    addTearDown(() {
      debugPhotoHeroUiOverride = null;
      debugPhotoFooterUiOverride = null;
      debugShopHomeV2Override = null;
    });
    final api = RecordingApi();
    await api.run(() async {
      await body(tester, api);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

Finder _key(String k) => find.byKey(Key(k));

Widget _scoped(MemberData d, Widget child) =>
    MemberDataScope(data: d, child: child);

ScrollPosition _position(WidgetTester tester, String scrollKey) => tester
    .state<ScrollableState>(
      find
          .descendant(of: _key(scrollKey), matching: find.byType(Scrollable))
          .first,
    )
    .position;

Future<void> _toEnd(WidgetTester tester, String scrollKey) async {
  final p = _position(tester, scrollKey);
  for (var i = 0; i < 6; i++) {
    p.jumpTo(p.maxScrollExtent);
    await tester.pump();
  }
  await _frames(tester);
}

void main() {
  setUpAll(loadAppFonts);

  // ── flag ───────────────────────────────────────────────────────────────

  group('flag', () {
    test('needs PHOTO_HERO_UI too', () {
      debugPhotoFooterUiOverride = true;
      debugPhotoHeroUiOverride = false;
      addTearDown(() {
        debugPhotoFooterUiOverride = null;
        debugPhotoHeroUiOverride = null;
      });
      expect(photoFooterUi, isFalse);
      debugPhotoHeroUiOverride = true;
      expect(photoFooterUi, isTrue);
      debugPhotoFooterUiOverride = false;
      expect(photoFooterUi, isFalse);
    });

    for (final (hero, footer) in [(false, true), (true, false)]) {
      footerTest(
        'hero $hero, footer $footer: no footer, pages keep ListView',
        (tester, api) async {
          await _host(tester, _scoped(_data(), const MemberGymsTab()));
          await _toEnd(tester, 'gym-page-scroll');
          expect(_key('photo-footer'), findsNothing);
          expect(_key('gyms-footer'), findsNothing);
          await _host(tester, _scoped(_data(), const MemberProfileTab()));
          // Flag-off parity: the same ListView as before.
          if (hero) {
            expect(tester.widget(_key('profile-scroll')), isA<ListView>());
          }
          expect(find.byType(CustomScrollView), findsNothing);
          expect(_key('photo-footer'), findsNothing);
        },
        hero: hero,
        footer: footer,
      );
    }
  });

  // ── photo choice ─────────────────────────────────────────────────────

  group('photo choice (spec §33.6, AC-M4)', () {
    test('the stand-in mapping equals the spec table', () {
      expect(footerPagePhotos, {
        'member.home': FFHeroPhoto.footerStudio,
        'member.activity': FFHeroPhoto.footerGymFloor,
        'member.profile': FFHeroPhoto.footerRack,
        'member.passes': FFHeroPhoto.footerRack,
        'member.gyms': FFHeroPhoto.footerStudio,
        'member.trainers': FFHeroPhoto.footerGymFloor,
        'member.shop': FFHeroPhoto.footerShelves,
        'member.gymDetail': FFHeroPhoto.footerRack,
        'member.trainerDetail': FFHeroPhoto.footerStudio,
        'trainer.home': FFHeroPhoto.footerShelves,
        'vendor.products': FFHeroPhoto.footerRack,
        'owner.home': FFHeroPhoto.footerStudio,
      });
    });

    test('the pool: four different scenes', () {
      expect(footerPhotoPool.map((p) => p.sourceId).toSet(), hasLength(4));
    });

    test('pages one step apart never share a footer photo', () {
      // Member tabs in nav order, then the links between pages (§33.6).
      const steps = [
        ('member.home', 'member.activity'),
        ('member.activity', 'member.gyms'),
        ('member.gyms', 'member.shop'),
        ('member.shop', 'member.profile'),
        ('member.activity', 'member.profile'),
        ('member.home', 'member.passes'),
        ('member.home', 'member.shop'),
        ('member.gyms', 'member.trainers'),
        ('member.gyms', 'member.gymDetail'),
        ('member.trainers', 'member.trainerDetail'),
        ('member.gymDetail', 'member.trainerDetail'),
      ];
      for (final (a, b) in steps) {
        expect(
          footerPagePhotos[a]!.sourceId,
          isNot(footerPagePhotos[b]!.sourceId),
          reason: '$a / $b',
        );
      }
    });

    test('never the same scene as any top photo the page can show', () {
      const tops = <String, List<FFHeroPhoto?>>{
        'member.home': [FFHeroPhoto.homeStart, FFHeroPhoto.homePass],
        'member.activity': [
          FFHeroPhoto.activityToday,
          FFHeroPhoto.activityTraining,
          FFHeroPhoto.activityChallenges,
          FFHeroPhoto.activityProgress,
        ],
        'member.profile': [FFHeroPhoto.profile],
        'member.passes': [FFHeroPhoto.upgrade],
        'member.gyms': [FFHeroPhoto.gyms],
        'member.trainers': [FFHeroPhoto.trainers],
        'member.shop': [FFHeroPhoto.shop],
        'member.gymDetail': [null],
        'member.trainerDetail': [null],
        'trainer.home': [FFHeroPhoto.trainer],
        'vendor.products': [FFHeroPhoto.vendor],
        'owner.home': [FFHeroPhoto.owner],
      };
      expect(tops.keys.toSet(), footerPagePhotos.keys.toSet());
      for (final MapEntry(key: page, value: photos) in tops.entries) {
        for (final top in photos) {
          final footer = footerPhotoFor(page, top: top);
          expect(footer, footerPagePhotos[page], reason: '$page / $top');
          if (top != null) {
            expect(footer.sourceId, isNot(top.sourceId), reason: page);
          }
        }
      }
    });

    test('a clash with the top photo moves to the next pool photo', () {
      // footerStudio shares the Profile photo's scene.
      expect(
        footerPhotoFor('member.home', top: FFHeroPhoto.profile),
        FFHeroPhoto.footerGymFloor,
      );
      // footerShelves shares the vendor photo's scene (pool wraps around).
      expect(
        footerPhotoFor('member.shop', top: FFHeroPhoto.vendor),
        FFHeroPhoto.footerStudio,
      );
      // A page not in the table: a stable pick, the same every time.
      expect(footerPhotoFor('some.page'), footerPhotoFor('some.page'));
      expect(fnv1a32('a'), 0xe40c292c); // FNV-1a 32 test vector
    });
  });

  // ── short-page rule, states ───────────────────────────────────────────

  group('when it shows', () {
    footerTest('long Gyms list: after the content, with Back to top', (
      tester,
      api,
    ) async {
      await _host(tester, _scoped(_data(), const MemberGymsTab()));
      await _toEnd(tester, 'gym-page-scroll');
      expect(_key('photo-footer'), findsOneWidget);
      expect(
        tester.getTopLeft(_key('photo-footer')).dy,
        greaterThan(tester.getBottomLeft(find.byType(GymGridCard).last).dy),
      );
      expect(find.text('FitFlex Africa'), findsOneWidget);
      expect(find.text("That's all for now."), findsNothing);
      expect(_key('photo-footer-back-to-top'), findsOneWidget);
      // 24px corners, inside the page padding.
      expect(tester.getTopLeft(_key('photo-footer')).dx, FFTokens.spacingLg);
    });

    footerTest('short Trainers list: no footer; growing past the screen '
        'shows it, and it stays (hysteresis)', (tester, api) async {
      final data = _data(trainers: 1);
      await _host(
        tester,
        _scoped(data, const MemberTrainersTab()),
        size: const Size(430, 932),
      );
      expect(_key('photo-footer'), findsNothing);
      expect(
        find.byKey(const Key('photo-footer-short'), skipOffstage: false),
        findsOneWidget,
      );
      data.update(
        (d) => d.trainers = [
          for (var i = 0; i < 12; i++) TrainerProfile.fromJson(_trainer('t$i')),
        ],
      );
      await _frames(tester);
      await _toEnd(tester, 'trainer-page-scroll');
      expect(_key('photo-footer'), findsOneWidget);
      // Shorter again but still a list: the footer stays.
      data.update(
        (d) => d.trainers = [
          for (var i = 0; i < 2; i++) TrainerProfile.fromJson(_trainer('t$i')),
        ],
      );
      await _frames(tester);
      expect(_key('photo-footer'), findsOneWidget);
    });

    footerTest('hidden while loading, on failure and on no match', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        _scoped(MemberData()..gymsLoaded = false, const MemberGymsTab()),
      );
      expect(_key('photo-footer'), findsNothing);
      expect(
        find.byKey(const Key('photo-footer-off'), skipOffstage: false),
        findsOneWidget,
      );
      await _host(
        tester,
        _scoped(MemberData()..gymsLoadFailed = true, const MemberGymsTab()),
      );
      expect(_key('photo-footer'), findsNothing);
      await _host(tester, _scoped(_data(), const MemberGymsTab()));
      await tester.enterText(find.byKey(const Key('gym-search')), 'zzz');
      await _frames(tester);
      expect(_key('gym-no-match'), findsOneWidget);
      expect(_key('photo-footer'), findsNothing);
    });

    footerTest('Upgrade plan: no footer while a pass payment is pending', (
      tester,
      api,
    ) async {
      final data = _data()
        ..passesLoaded = true
        ..passes = [
          PassTier.fromJson({'id': 'basic', 'price': 50000, 'visitCap': 8}),
        ]
        ..me = MemberMeResponse.fromJson({
          'user': {'id': 'm1', 'displayName': 'Amina'},
          'pendingPayments': [
            {
              'id': 'pr1',
              'status': 'pending',
              'productType': 'FITFLEX_PASS',
              'tier': 'basic',
              'amountTzs': 50000,
            },
          ],
        });
      await _host(
        tester,
        _scoped(data, const MemberPassesPage()),
        size: const Size(390, 400),
      );
      await _toEnd(tester, 'passes-scroll');
      expect(_key('photo-footer'), findsNothing);
    });
  });

  // ── pages ─────────────────────────────────────────────────────────────

  group('pages', () {
    footerTest('gym and trainer detail: footer, no stock photo at the top', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        _scoped(_data(), const MemberGymDetailPage(gymId: 'g1')),
        size: const Size(390, 600),
      );
      expect(find.byType(FFPhotoHero), findsNothing);
      await _toEnd(tester, 'gym-detail-scroll');
      expect(_key('photo-footer'), findsOneWidget);
      expect(_key('photo-footer-back-to-top'), findsNothing);

      await _host(
        tester,
        _scoped(_data(), const MemberTrainerDetailPage(trainerId: 't1')),
        size: const Size(390, 600),
      );
      expect(find.byType(FFPhotoHero), findsNothing);
      final list = find.byType(CustomScrollView).first;
      final p = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      for (var i = 0; i < 6; i++) {
        p.jumpTo(p.maxScrollExtent);
        await tester.pump();
      }
      await _frames(tester);
      expect(_key('photo-footer'), findsOneWidget);
      // The pinned action bar is outside the scroll view: the footer ends
      // above it.
      expect(
        tester.getBottomLeft(_key('photo-footer')).dy,
        lessThanOrEqualTo(tester.getTopLeft(_key('trainer-actions')).dy),
      );
    });

    footerTest('AC-M15: scroll keys still find the scroll views', (
      tester,
      api,
    ) async {
      final data = _data()
        ..activities = [
          for (var i = 0; i < 6; i++)
            Activity(
              id: 'a$i',
              userId: 'm1',
              type: ActivityType.walking,
              source: ActivitySource.device,
              startedAt: DateTime(2026, 9, 23, 7 + i),
              steps: 4000,
              durationMinutes: 30,
              activeMinutes: 30,
            ),
        ]
        ..activityLoaded = true;
      for (final (page, key) in <(Widget, String)>[
        (MemberActivityTab(now: DateTime(2026, 9, 23, 20)), 'activity-scroll'),
        (const MemberProfileTab(), 'profile-scroll'),
        (const MemberGymsTab(), 'gym-page-scroll'),
        (const MemberTrainersTab(), 'trainer-page-scroll'),
      ]) {
        await _host(tester, _scoped(data, page), size: const Size(390, 640));
        expect(_key(key), findsOneWidget, reason: key);
        await _toEnd(tester, key);
        expect(_key('photo-footer'), findsOneWidget, reason: key);
      }
    });

    footerTest('Shop: after the rails and above the cart bar', (
      tester,
      api,
    ) async {
      _seedShop(api);
      await _host(tester, const MemberShopTab());
      await tester.tap(find.byKey(const Key('shop-home-add-p0')).first);
      await _frames(tester);
      expect(_key('shop-home-checkout'), findsOneWidget);
      final list = find
          .ancestor(
            of: _key('shop-home'),
            matching: find.byType(CustomScrollView),
          )
          .first;
      final p = tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)).first,
          )
          .position;
      for (var i = 0; i < 6; i++) {
        p.jumpTo(p.maxScrollExtent);
        await tester.pump();
      }
      await _frames(tester);
      expect(_key('photo-footer'), findsOneWidget);
      expect(
        tester.getTopLeft(_key('photo-footer')).dy,
        greaterThan(tester.getBottomLeft(_key('shop-home-browse-all')).dy),
      );
      // The cart bar is a sibling below the list: the band ends above it
      // with 24px to spare.
      expect(
        tester.getBottomLeft(_key('photo-footer')).dy + FFTokens.spacingLg,
        lessThanOrEqualTo(tester.getTopLeft(_key('shop-home-checkout')).dy),
      );
      expect(_key('photo-footer-back-to-top'), findsOneWidget);
    });

    footerTest('Shop for trainers and owners: no footer', (tester, api) async {
      _seedShop(api);
      await _host(tester, const ShopBrowseBody(mode: ShopHomeMode.trainer));
      expect(_key('shop-footer'), findsNothing);
    });
  });

  // ── padding, behaviour, a11y ──────────────────────────────────────────

  group('component', () {
    Widget page({
      double extraBottom = 0,
      int items = 30,
      bool backToTop = false,
      FocusNode? focus,
      Widget? top,
    }) => CustomScrollView(
      key: const Key('page'),
      slivers: [
        if (top != null) SliverToBoxAdapter(child: top),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (_, i) => SizedBox(height: 60, child: Text('item $i')),
            childCount: items,
          ),
        ),
        FFPhotoFooter.sliver(
          pageKey: 'member.gyms',
          top: FFHeroPhoto.gyms,
          extraBottom: extraBottom,
          backToTop: backToTop,
          headingFocus: focus,
        ),
      ],
    );

    footerTest('vendor FAB room: 88px extra under the band', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        Stack(
          children: [
            page(extraBottom: 88),
            const Positioned(
              right: 16,
              bottom: 16,
              child: SizedBox(key: Key('fab'), width: 160, height: 56),
            ),
          ],
        ),
      );
      await _toEnd(tester, 'page');
      final band = tester.getRect(_key('photo-footer'));
      expect(band.bottom, lessThanOrEqualTo(tester.getTopLeft(_key('fab')).dy));
      expect(844 - band.bottom, closeTo(24 + 88, 0.5));
    });

    footerTest('lazy: the photo is not decoded until the footer is near', (
      tester,
      api,
    ) async {
      await _host(tester, page(items: 200));
      expect(_key('photo-footer-photo'), findsNothing);
      await _toEnd(tester, 'page');
      expect(_key('photo-footer-photo'), findsOneWidget);
    });

    footerTest('brand lockup: mark on a light plate, name and tagline', (
      tester,
      api,
    ) async {
      await _host(tester, page());
      await _toEnd(tester, 'page');
      final band = tester.getRect(_key('photo-footer'));
      final logo = _key('photo-footer-logo');
      expect(logo, findsOneWidget);
      final img = tester.widget<Image>(logo);
      expect((img.image as ResizeImage).imageProvider, isA<AssetImage>());
      expect(
        ((img.image as ResizeImage).imageProvider as AssetImage).assetName,
        'assets/brand/fitflex-icon.png',
      );
      final size = tester.getSize(logo);
      expect(size.width, greaterThanOrEqualTo(40));
      expect(size.height, greaterThanOrEqualTo(40));
      // Full opacity: no Opacity / FadeTransition between band and mark.
      expect(
        find.ancestor(of: logo, matching: find.byType(Opacity)),
        findsNothing,
      );
      // A light round plate under the navy pin, larger than the mark.
      final plate = tester.widget<Container>(_key('photo-footer-plate'));
      final deco = plate.decoration! as BoxDecoration;
      expect(deco.shape, BoxShape.circle);
      expect(deco.color, FFTokens.heroText);
      expect(
        tester.getSize(_key('photo-footer-plate')).width,
        greaterThan(size.width),
      );
      // Name (Inter 900, heroText) and tagline (heroTextBody), centred.
      final brand = tester.widget<Text>(_key('photo-footer-brand'));
      expect(brand.data, 'FitFlex Africa');
      expect(brand.style!.fontWeight, FontWeight.w900);
      expect(brand.style!.fontFamily, FFTokens.fontSans);
      expect(brand.style!.color, FFTokens.heroText);
      final tagline = tester.widget<Text>(_key('photo-footer-tagline'));
      expect(tagline.data, 'Fitness Without Limits');
      expect(tagline.style!.color, FFTokens.heroTextBody);
      // Order: mark, name, tagline; all inside the band.
      expect(
        tester.getRect(logo).bottom,
        lessThanOrEqualTo(tester.getRect(_key('photo-footer-brand')).top),
      );
      expect(
        tester.getRect(_key('photo-footer-brand')).bottom,
        lessThanOrEqualTo(tester.getRect(_key('photo-footer-tagline')).top),
      );
      expect(band.contains(tester.getCenter(logo)), isTrue);
      expect(tester.getCenter(logo).dx, closeTo(band.center.dx, 0.5));
      expect(find.text("That's all for now."), findsNothing);
    });

    test('i18n: no end line; brand words the same in English and Swahili', () {
      for (final lang in ['en', 'sw']) {
        expect(FFLocale.keysOf(lang), isNot(contains('footer.endLine')));
        expect(FFLocale.textOf(lang, 'footer.brand'), 'FitFlex Africa');
        expect(
          FFLocale.textOf(lang, 'footer.tagline'),
          'Fitness Without Limits',
        );
      }
      // The English tagline is the splash tagline.
      expect(
        FFLocale.textOf('en', 'footer.tagline'),
        FFLocale.textOf('en', 'splash.tagline'),
      );
      expect(FFLocale.textOf('sw', 'footer.backToTop'), 'Rudi juu');
    });

    footerTest('high contrast: navy ground, no photo, same text', (
      tester,
      api,
    ) async {
      await _host(tester, page(), highContrast: true);
      await _toEnd(tester, 'page');
      expect(_key('photo-footer'), findsOneWidget);
      expect(_key('photo-footer-photo'), findsNothing);
      final ground = tester.widget<ColoredBox>(_key('photo-footer-ground'));
      expect(ground.color, FFTokens.heroPlaceholder);
      expect(find.text('FitFlex Africa'), findsOneWidget);
      expect(find.text('Fitness Without Limits'), findsOneWidget);
      expect(_key('photo-footer-logo'), findsOneWidget);
    });

    footerTest('screen reader: one lockup node and the button; mark silent', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      await _host(tester, page(backToTop: true));
      await _toEnd(tester, 'page');
      final node = tester.getSemantics(
        find
            .ancestor(
              of: _key('photo-footer-lockup'),
              matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.container,
              ),
            )
            .first,
      );
      final labels = <String>[];
      void walk(SemanticsNode n) {
        final l = n.label;
        if (l.isNotEmpty) labels.add(l);
        n.visitChildren((c) {
          walk(c);
          return true;
        });
      }

      walk(node);
      expect(labels, [
        'FitFlex Africa, Fitness Without Limits',
        'Back to top',
      ], reason: '$labels');
      // The mark is decorative: no separate "FitFlex" (app.title) label.
      expect(labels.where((l) => l == 'FitFlex'), isEmpty);
      expect(
        tester.getSemantics(_key('photo-footer-back-to-top')),
        matchesSemantics(
          label: 'Back to top',
          isButton: true,
          hasTapAction: true,
          isEnabled: true,
          hasEnabledState: true,
        ),
      );
      // ≥44px touch target.
      expect(
        tester.getSize(_key('photo-footer-back-to-top')).height,
        greaterThanOrEqualTo(44),
      );
      handle.dispose();
    });

    footerTest('Swahili at 1.3x on 360: text not clipped', (tester, api) async {
      final errors = await captureFlutterErrors(() async {
        await _host(
          tester,
          page(backToTop: true),
          lang: 'sw',
          textScale: 1.3,
          size: const Size(360, 640),
        );
        await _toEnd(tester, 'page');
      });
      expect(errors, isEmpty, reason: errors.join('\n'));
      // Owner 2026-10-20: the brand words are the same in Swahili.
      expect(find.text('FitFlex Africa'), findsOneWidget);
      expect(find.text('Fitness Without Limits'), findsOneWidget);
      expect(find.text('Hiyo ndiyo yote kwa sasa.'), findsNothing);
      expect(find.text('Rudi juu'), findsOneWidget);
      for (final k in ['photo-footer-brand', 'photo-footer-tagline']) {
        final line = tester.renderObject<RenderParagraph>(
          find.descendant(of: _key(k), matching: find.byType(RichText)),
        );
        expect(line.didExceedMaxLines, isFalse, reason: k);
        // One line each, even at 1.3x on a 360 phone.
        expect(line.size.height, lessThan(2 * 22 * 1.3), reason: k);
      }
    });

    for (final reduce in [false, true]) {
      footerTest('Back to top scrolls up and focuses the heading '
          '(reduced motion $reduce)', (tester, api) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await _host(
          tester,
          page(
            backToTop: true,
            focus: focus,
            top: Focus(
              focusNode: focus,
              skipTraversal: true,
              child: const SizedBox(height: 100, child: Text('HEADING')),
            ),
          ),
          reduceMotion: reduce,
        );
        await _toEnd(tester, 'page');
        await tester.tap(_key('photo-footer-back-to-top'));
        await tester.pump();
        final p = _position(tester, 'page');
        if (reduce) expect(p.pixels, 0);
        await tester.pump(const Duration(milliseconds: 500));
        expect(p.pixels, 0);
        expect(focus.hasFocus, isTrue);
      }, hero: true);
    }
  });

  group('Gyms: Back to top lands on the band heading', () {
    footerTest('focus moves to the band heading (no extra Tab stop)', (
      tester,
      api,
    ) async {
      await _host(tester, _scoped(_data(), const MemberGymsTab()));
      await _toEnd(tester, 'gym-page-scroll');
      await tester.tap(_key('photo-footer-back-to-top'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(_position(tester, 'gym-page-scroll').pixels, 0);
      final heading = find.descendant(
        of: _key('gyms-hero'),
        matching: find.byKey(const Key('ff-hero-heading-focus')),
      );
      expect(heading, findsOneWidget);
      final focus = Focus.of(tester.element(heading));
      expect(focus.hasFocus, isTrue);
      expect(focus.skipTraversal, isTrue);
    });
  });

  // ── assets ──────────────────────────────────────────────────────────

  group('photos', () {
    test('caps, licence rows, no metadata, total within 1.6 MB', () {
      final licences = File(
        'assets/photos/hero/LICENSES.md',
      ).readAsStringSync();
      for (final p in footerPhotoPool) {
        final x1 = File('assets/photos/hero/${p.file}.webp');
        final x2 = File('assets/photos/hero/2.0x/${p.file}.webp');
        expect(x2.lengthSync(), lessThanOrEqualTo(60 * 1000), reason: p.name);
        expect(x1.lengthSync(), lessThanOrEqualTo(25 * 1000), reason: p.name);
        for (final f in [x1, x2]) {
          expect(_webpChunks(f), ['VP8 '], reason: f.path);
        }
        final row = licences
            .split('\n')
            .firstWhere((l) => l.startsWith('| `${p.file}.webp`'));
        expect(row, contains('no face in frame'), reason: p.name);
      }
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final p in footerPhotoPool) {
        expect(pubspec, contains('- ${p.asset}'), reason: p.name);
      }
      var total = 0;
      for (final f in Directory(
        'assets/photos/hero',
      ).listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.webp')) total += f.lengthSync();
      }
      expect(total, lessThanOrEqualTo(1600 * 1000));
    });

    test('sharp set: 1080px wide at 2x, 540 at 1x, 16:7 (from the file)', () {
      for (final p in footerPhotoPool) {
        final (w2, h2) = _vp8Size(
          File('assets/photos/hero/2.0x/${p.file}.webp'),
        );
        final (w1, h1) = _vp8Size(File('assets/photos/hero/${p.file}.webp'));
        expect(w2, greaterThanOrEqualTo(1080), reason: p.name);
        expect(w1, greaterThanOrEqualTo(540), reason: p.name);
        expect(w2 / h2, closeTo(16 / 7, 0.01), reason: p.name);
        expect(w1 / h1, closeTo(16 / 7, 0.01), reason: p.name);
        expect(p.aspect, closeTo(w2 / h2, 0.001), reason: p.name);
      }
      // The licence rows record source crops at least as large as the
      // output: never upscaled.
      final licences = File(
        'assets/photos/hero/LICENSES.md',
      ).readAsStringSync();
      for (final p in footerPhotoPool) {
        final row = licences
            .split('\n')
            .firstWhere((l) => l.startsWith('| `${p.file}.webp`'));
        final m = RegExp(r'\((\d+)x(\d+), 16:7\)').firstMatch(row)!;
        expect(int.parse(m[1]!), greaterThanOrEqualTo(1080), reason: p.name);
        expect(int.parse(m[2]!), greaterThanOrEqualTo(472), reason: p.name);
      }
    });

    testWidgets('sharp set: decoded size at 2x is at least 1080 wide', (
      tester,
    ) async {
      await tester.runAsync(() async {
        for (final p in footerPhotoPool) {
          final bytes = File(
            'assets/photos/hero/2.0x/${p.file}.webp',
          ).readAsBytesSync();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          expect(frame.image.width, greaterThanOrEqualTo(1080), reason: p.name);
          expect(frame.image.height, greaterThanOrEqualTo(472), reason: p.name);
          frame.image.dispose();
          codec.dispose();
        }
      });
    });

    test('distribute-android: photo_footer only on manual runs', () {
      final wf = File(
        '.github/workflows/distribute-android.yml',
      ).readAsStringSync();
      expect(wf, contains('photo_footer:'));
      expect(
        wf,
        contains(
          "PHOTO_FOOTER_UI: \${{ github.event_name == 'workflow_dispatch' "
          "&& inputs.photo_footer && 'true' || 'false' }}",
        ),
      );
      expect(wf, contains('--dart-define=PHOTO_FOOTER_UI="\$PHOTO_FOOTER_UI"'));
    });
  });
}

/// Width and height from a simple (lossy, `VP8 `) WebP's frame header.
(int, int) _vp8Size(File f) {
  final b = f.readAsBytesSync();
  expect(String.fromCharCodes(b.sublist(12, 16)), 'VP8 ');
  // Chunk data: 3-byte frame tag, start code 9d 01 2a, then 14-bit sizes.
  final d = 20;
  expect(b.sublist(d + 3, d + 6), [0x9d, 0x01, 0x2a]);
  final data = ByteData.sublistView(b);
  return (
    data.getUint16(d + 6, Endian.little) & 0x3fff,
    data.getUint16(d + 8, Endian.little) & 0x3fff,
  );
}

List<String> _webpChunks(File f) {
  final b = f.readAsBytesSync();
  final data = ByteData.sublistView(b);
  final names = <String>[];
  var i = 12;
  while (i + 8 <= b.length) {
    names.add(String.fromCharCodes(b.sublist(i, i + 4)));
    final n = data.getUint32(i + 4, Endian.little);
    i += 8 + n + (n & 1);
  }
  return names;
}
