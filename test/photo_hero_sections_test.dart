// Section bands behind PHOTO_HERO_UI (photo-hero increment plan, slice 1):
// member Gyms list, member Trainers list and the member Shop home. With the
// flag off every page is unchanged; with it on each gets a `band` hero.

import 'dart:io';
import 'dart:typed_data';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/member_shop_tab.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:fitflexmobile/shared/shop_home.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';
import 'package:fitflexmobile/shared/widgets/shop_home/shop_category_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/recording_api.dart';

// ── fixtures ─────────────────────────────────────────────────────────────

Map<String, dynamic> _gym(String id, String name) => {
  'id': id,
  'name': name,
  'tier': 'standard',
  'location': 'Dar es Salaam',
  'perVisitRate': 5000,
  'ratePerMonth': 50000,
  'commissionRate': 10,
  'status': 'active',
  'amenities': <String>[],
};

Map<String, dynamic> _trainer(String id, String name) => {
  'id': id,
  'displayName': name,
  'specialties': ['boxing'],
  'hourlyRateTzs': 20000,
  'status': 'active',
};

MemberData _data() => MemberData()
  ..gyms = [
    Gym.fromJson(_gym('g1', 'Masaki Fit')),
    Gym.fromJson(_gym('g2', 'Mikocheni Strong')),
  ]
  ..trainers = [
    TrainerProfile.fromJson(_trainer('t1', 'Juma Ali')),
    TrainerProfile.fromJson(_trainer('t2', 'Neema Said')),
  ];

Map<String, dynamic> _product(String id, String name) => {
  'id': id,
  'vendorId': 'v1',
  'name': name,
  'category': 'equipment',
  'priceTzs': 30000,
  'stock': 10,
  'rating': 0,
  'reviewCount': 0,
  'soldCount': 0,
  'deliveryAvailable': true,
};

Map<String, dynamic> _shopHome({String mode = 'member'}) => {
  'serverNow': '2026-10-19T08:00:00Z',
  'currency': 'TZS',
  'mode': mode,
  'personalised': false,
  'signalsUsed': <String>[],
  'categories': [
    {
      'key': 'equipment',
      'en': 'Gym & fitness equipment',
      'sw': 'Vifaa vya gym na mazoezi',
    },
  ],
  'sections': [
    {
      'key': 'best_sellers',
      'title': {'en': 'Best sellers', 'sw': 'Zinazouzwa zaidi'},
      'viewAll': {'query': <String, String>{}},
      'productIds': ['p1', 'p2'],
    },
  ],
  'products': {'p1': _product('p1', 'Yoga Mat'), 'p2': _product('p2', 'Rope')},
};

void _seedShop(RecordingApi api, {String mode = 'member'}) {
  api.on('GET /shop/products', [
    _product('p1', 'Yoga Mat'),
    _product('p2', 'Rope'),
  ]);
  api.on('GET /me/shop-orders', <dynamic>[]);
  api.on('GET /gyms', <dynamic>[]);
  api.on('GET /shop/home', _shopHome(mode: mode));
}

// ── harness ─────────────────────────────────────────────────────────────

/// Pumps [page] at "/" of a router that also knows the member Trainers
/// route (the Gyms band's button goes there), inside the app's scopes.
Future<void> _host(
  WidgetTester tester,
  Widget page, {
  String lang = 'en',
  double textScale = 1,
  Size size = const Size(390, 844),
  bool dark = false,
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
            theme: dark ? buildDarkTheme() : buildTheme(),
            supportedLocales: const [Locale('en'), Locale('sw')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: c!,
            ),
          ),
        ),
      ),
    ),
  );
  await _frames(tester);
}

/// A few frames past the fades. Not pumpAndSettle: the Gyms tab keeps a
/// location spinner running while Geolocator (no plugin in tests) waits.
Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// A test with a fresh fake backend and the photo flag set to [flag].
void sectionTest(
  String name,
  Future<void> Function(WidgetTester tester, RecordingApi api) body, {
  bool flag = true,
  bool shopV2 = true,
}) {
  testWidgets(name, (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugPhotoHeroUiOverride = flag;
    debugShopHomeV2Override = shopV2;
    addTearDown(() {
      debugPhotoHeroUiOverride = null;
      debugShopHomeV2Override = null;
    });
    _ignoreTrainerCardOverflow();
    final api = RecordingApi();
    await api.run(() async {
      await body(tester, api);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

/// The trainer grid card overflows by a fraction of a pixel at 390 wide
/// with the real fonts, flag on or off (lib/screens/member/widgets/
/// trainer_card.dart, not touched here). Only that overflow is set aside.
void _ignoreTrainerCardOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.toString();
    if (text.contains('overflowed') && text.contains('trainer_card.dart')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

Finder _key(String k) => find.byKey(Key(k));

String _tr(String lang, String key) => FFLocale.textOf(lang, key)!;

/// All visible text inside the only FFPhotoHero, joined.
String _heroText(WidgetTester tester) => [
  for (final e
      in find
          .descendant(
            of: find.byType(FFPhotoHero),
            matching: find.byType(RichText),
          )
          .evaluate())
    (e.widget as RichText).text.toPlainText(),
].join(' | ');

bool _inHero(Finder f) => find
    .descendant(of: find.byType(FFPhotoHero), matching: f)
    .evaluate()
    .isNotEmpty;

Widget _gyms() => MemberDataScope(data: _data(), child: const MemberGymsTab());
Widget _trainers() =>
    MemberDataScope(data: _data(), child: const MemberTrainersTab());

void main() {
  setUpAll(loadAppFonts);

  // ── flag off: unchanged ─────────────────────────────────────────────────

  group('flag off: pages unchanged', () {
    sectionTest('Gyms keeps its page title and ghost Trainers button', (
      tester,
      api,
    ) async {
      await _host(tester, _gyms());
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(_key('gyms-hero'), findsNothing);
      expect(_key('gym-page-scroll'), findsOneWidget);
      expect(find.byType(FFPageHeader), findsOneWidget);
      final button = tester.widget<FFButton>(_key('member-find-trainer'));
      expect(button.variant, FFButtonVariant.ghost);
      await tester.tap(_key('member-find-trainer'));
      await _frames(tester);
      expect(find.text('ROUTE-TRAINERS'), findsOneWidget);
    }, flag: false);

    sectionTest('Trainers keeps its page title', (tester, api) async {
      await _host(tester, _trainers());
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(_key('trainer-page-scroll'), findsOneWidget);
      expect(find.text(_tr('en', 'member.findTrainerTitle')), findsOneWidget);
      expect(_key('trainer-card-t1'), findsOneWidget);
    }, flag: false);

    sectionTest('member Shop home (V2 on) has no band', (tester, api) async {
      _seedShop(api);
      await _host(tester, const MemberShopTab());
      expect(_key('shop-home'), findsOneWidget);
      expect(_key('shop-hero'), findsNothing);
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(_key('shop-home-section-best_sellers'), findsOneWidget);
    }, flag: false);
  });

  // ── flag on ───────────────────────────────────────────────────────────

  group('flag on: Gyms', () {
    sectionTest('a band replaces the title and carries the Trainers button', (
      tester,
      api,
    ) async {
      await _host(tester, _gyms());
      expect(_key('gyms-hero'), findsOneWidget);
      final hero = tester.widget<FFPhotoHero>(find.byType(FFPhotoHero));
      expect(hero.photo, FFHeroPhoto.gyms);
      expect(hero.variant, FFHeroVariant.band);
      expect(find.byType(FFPageHeader), findsNothing);
      final text = _heroText(tester);
      expect(text, contains('GYMS'));
      expect(text, contains('Find your gym.'));
      // "Discover gyms" once on the screen: the section strip.
      expect(find.text(_tr('en', 'member.discoverGyms')), findsOneWidget);
      expect(text, isNot(contains('DISCOVER')));
      expect(_inHero(_key('member-find-trainer')), isTrue);
      final button = tester.widget<FFButton>(_key('member-find-trainer'));
      expect(button.variant, FFButtonVariant.onPhoto);
      // Search, filters and the list are still there, below the band.
      expect(_key('gym-page-scroll'), findsOneWidget);
      expect(
        tester.getTopLeft(_key('gym-search')).dy,
        greaterThan(tester.getBottomLeft(_key('gyms-hero')).dy),
      );
      expect(_key('gym-card-g1'), findsOneWidget);
      await tester.tap(_key('member-find-trainer'));
      await _frames(tester);
      expect(find.text('ROUTE-TRAINERS'), findsOneWidget);
    });

    for (final lang in ['en', 'sw']) {
      sectionTest('AC-L8: search stays near the top at 390x844 ($lang)', (
        tester,
        api,
      ) async {
        await _host(tester, _gyms(), lang: lang);
        expect(
          tester.getBottomLeft(_key('gym-search')).dy,
          lessThanOrEqualTo(420),
        );
        await _host(tester, _trainers(), lang: lang);
        expect(
          tester.getBottomLeft(_key('trainer-search')).dy,
          lessThanOrEqualTo(380),
        );
        _seedShop(api);
        await _host(tester, const MemberShopTab(), lang: lang);
        expect(
          tester.getBottomLeft(_key('shop-home-search')).dy,
          lessThanOrEqualTo(380),
        );
      });
    }

    sectionTest('AC-L9: focusing search low on a short screen scrolls it up', (
      tester,
      api,
    ) async {
      // A keyboard-sized viewport: the field starts below 40% of it.
      await _host(tester, _gyms(), size: const Size(360, 360));
      final heroHeight = tester.getSize(_key('gyms-hero')).height;
      final before = tester.getTopLeft(_key('gym-search')).dy;
      expect(before, greaterThan(0.4 * 360));
      await tester.tap(_key('gym-search'));
      await _frames(tester);
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: _key('gym-page-scroll'),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(position.pixels, greaterThan(0));
      // 8px under the top of the viewport (the page starts at y=0 here).
      expect(tester.getTopLeft(_key('gym-search')).dy, closeTo(8, 1));
      // The band never changes height.
      expect(tester.getSize(_key('gyms-hero')).height, heroHeight);
    });

    sectionTest('search focus does nothing with the flag off', (
      tester,
      api,
    ) async {
      await _host(tester, _gyms(), size: const Size(360, 360));
      await tester.tap(_key('gym-search'));
      await _frames(tester);
      final position = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: _key('gym-page-scroll'),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(position.pixels, 0);
    }, flag: false);

    sectionTest('Swahili copy', (tester, api) async {
      await _host(tester, _gyms(), lang: 'sw');
      final text = _heroText(tester);
      expect(text, contains('Pata gym yako.'));
      expect(text, contains(_tr('sw', 'member.gyms').toUpperCase()));
    });
  });

  group('flag on: Trainers', () {
    sectionTest('a band in place of the page title', (tester, api) async {
      await _host(tester, _trainers());
      expect(_key('trainers-hero'), findsOneWidget);
      final hero = tester.widget<FFPhotoHero>(find.byType(FFPhotoHero));
      expect(hero.photo, FFHeroPhoto.trainers);
      expect(hero.variant, FFHeroVariant.band);
      expect(find.text(_tr('en', 'member.findTrainerTitle')), findsNothing);
      expect(_heroText(tester), contains('Train with a Trainer.'));
      expect(_heroText(tester), contains('TRAINERS'));
      expect(
        find.descendant(
          of: find.byType(FFPhotoHero),
          matching: find.byType(FFButton),
        ),
        findsNothing,
      );
      expect(_key('trainer-page-scroll'), findsOneWidget);
      expect(_key('trainer-search'), findsOneWidget);
      expect(_key('trainer-card-t1'), findsOneWidget);
    });

    sectionTest('Swahili copy', (tester, api) async {
      await _host(tester, _trainers(), lang: 'sw');
      expect(_heroText(tester), contains('Fanya mazoezi na Trainer.'));
    });
  });

  group('flag on: Shop', () {
    sectionTest('member Shop home: band between search and categories', (
      tester,
      api,
    ) async {
      _seedShop(api);
      await _host(tester, const MemberShopTab());
      expect(_key('shop-hero'), findsOneWidget);
      final hero = tester.widget<FFPhotoHero>(find.byType(FFPhotoHero));
      expect(hero.photo, FFHeroPhoto.shop);
      expect(hero.variant, FFHeroVariant.band);
      expect(_heroText(tester), contains('Gear up for training.'));
      expect(_heroText(tester), contains('FITFLEX SHOP'));
      final search = tester.getBottomLeft(_key('shop-home-search')).dy;
      final band = tester.getRect(_key('shop-hero'));
      final categories = tester.getTopLeft(find.byType(ShopCategoryRow));
      expect(band.top, greaterThan(search));
      expect(categories.dy, greaterThan(band.bottom));
      // No button on the shop band.
      expect(
        find.descendant(
          of: find.byType(FFPhotoHero),
          matching: find.byType(FFButton),
        ),
        findsNothing,
      );
      // The existing section keys still work.
      expect(_key('shop-home-section-best_sellers'), findsOneWidget);
    });

    sectionTest('offline with a cached home: the alert sits above the band', (
      tester,
      api,
    ) async {
      _seedShop(api);
      await _host(tester, const MemberShopTab());
      api.onCall(
        'GET /shop/home',
        (_) => throw http.ClientException('XMLHttpRequest error.'),
      );
      final en = FFLocale()..set(const Locale('en'));
      await tester.tap(find.text(en.t('shop.myOrders')));
      await _frames(tester);
      await tester.tap(find.text(en.t('shop.browse')));
      await _frames(tester);
      expect(_key('shop-home-offline-bar'), findsOneWidget);
      expect(
        tester.getBottomLeft(_key('shop-home-offline-bar')).dy,
        lessThanOrEqualTo(tester.getTopLeft(_key('shop-hero')).dy),
      );
      expect(
        tester.getTopLeft(_key('shop-home-offline-bar')).dy,
        greaterThan(tester.getBottomLeft(_key('shop-home-search')).dy),
      );
    });

    sectionTest('member shop with SHOP_HOME_V2 off: no band (old list)', (
      tester,
      api,
    ) async {
      _seedShop(api);
      await _host(tester, const MemberShopTab());
      expect(_key('shop-home'), findsNothing);
      expect(_key('shop-hero'), findsNothing);
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(_key('shop-product-p1'), findsOneWidget);
    }, shopV2: false);

    for (final mode in [ShopHomeMode.trainer, ShopHomeMode.owner]) {
      sectionTest('the ${mode.wire} shop has no band', (tester, api) async {
        _seedShop(api, mode: mode.wire);
        await _host(tester, ShopBrowseBody(mode: mode));
        expect(_key('shop-home'), findsOneWidget);
        expect(_key('shop-hero'), findsNothing);
        expect(find.byType(FFPhotoHero), findsNothing);
      });
    }

    sectionTest('the pushed ShopBrowsePage has no band', (tester, api) async {
      _seedShop(api);
      await _host(tester, const ShopBrowsePage());
      expect(_key('shop-home'), findsOneWidget);
      expect(_key('shop-hero'), findsNothing);
    });

    sectionTest('Swahili copy', (tester, api) async {
      _seedShop(api);
      await _host(tester, const MemberShopTab(), lang: 'sw');
      expect(_heroText(tester), contains('Jiandae kwa mazoezi.'));
    });
  });

  // ── F-12: load states (flag on and off) ─────────────────────────────────

  for (final flag in [false, true]) {
    group('F-12 states (flag ${flag ? 'on' : 'off'})', () {
      sectionTest('Gyms loading: skeleton cards, never "Nothing to show yet"', (
        tester,
        api,
      ) async {
        await _host(
          tester,
          MemberDataScope(
            data: MemberData()..gymsLoaded = false,
            child: const MemberGymsTab(),
          ),
        );
        expect(_key('gym-grid-loading'), findsOneWidget);
        expect(find.text(_tr('en', 'member.noData')), findsNothing);
        expect(_key('gyms-hero'), flag ? findsOneWidget : findsNothing);
      }, flag: flag);

      sectionTest('Gyms failed with nothing cached: error + Try again', (
        tester,
        api,
      ) async {
        await _host(
          tester,
          MemberDataScope(
            data: MemberData()..gymsLoadFailed = true,
            child: const MemberGymsTab(),
          ),
          lang: 'sw',
        );
        expect(_key('gym-load-error'), findsOneWidget);
        expect(find.text(_tr('sw', 'member.gymsLoadError')), findsOneWidget);
        expect(find.text(_tr('sw', 'common.retry')), findsOneWidget);
        expect(find.text(_tr('sw', 'member.noData')), findsNothing);
      }, flag: flag);

      sectionTest('Gyms loaded and empty: "Nothing to show yet."', (
        tester,
        api,
      ) async {
        await _host(
          tester,
          MemberDataScope(data: MemberData(), child: const MemberGymsTab()),
        );
        expect(find.text(_tr('en', 'member.noData')), findsOneWidget);
        expect(_key('gym-grid-loading'), findsNothing);
      }, flag: flag);

      sectionTest('Gyms no match: message + Clear search and filters', (
        tester,
        api,
      ) async {
        await _host(tester, _gyms());
        await tester.enterText(_key('gym-search'), 'zzz-nothing');
        await _frames(tester);
        expect(_key('gym-no-match'), findsOneWidget);
        expect(find.text(_tr('en', 'member.gymsNoMatch')), findsOneWidget);
        await tester.ensureVisible(_key('gym-clear-search'));
        await tester.tap(_key('gym-clear-search'));
        await _frames(tester);
        expect(_key('gym-no-match'), findsNothing);
        expect(_key('gym-card-g1'), findsOneWidget);
        expect(
          tester.widget<TextField>(_key('gym-search')).controller!.text,
          isEmpty,
        );
      }, flag: flag);

      sectionTest('Trainers loading: skeleton cards', (tester, api) async {
        await _host(
          tester,
          MemberDataScope(
            data: MemberData()..trainersLoaded = false,
            child: const MemberTrainersTab(),
          ),
        );
        expect(_key('trainer-grid-loading'), findsOneWidget);
        expect(find.text(_tr('en', 'member.noData')), findsNothing);
      }, flag: flag);

      sectionTest('Trainers failed with nothing cached: error + Try again', (
        tester,
        api,
      ) async {
        await _host(
          tester,
          MemberDataScope(
            data: MemberData()..trainersLoadFailed = true,
            child: const MemberTrainersTab(),
          ),
        );
        expect(_key('trainer-load-error'), findsOneWidget);
        expect(
          find.text(_tr('en', 'member.trainersLoadError')),
          findsOneWidget,
        );
      }, flag: flag);

      sectionTest('Trainers no match: message + Clear search and filters', (
        tester,
        api,
      ) async {
        await _host(tester, _trainers());
        await tester.enterText(_key('trainer-search'), 'zzz-nothing');
        await _frames(tester);
        expect(_key('trainer-no-match'), findsOneWidget);
        await tester.ensureVisible(_key('trainer-clear-search'));
        await tester.tap(_key('trainer-clear-search'));
        await _frames(tester);
        expect(_key('trainer-card-t1'), findsOneWidget);
      }, flag: flag);
    });
  }

  // ── layout: no overflow ─────────────────────────────────────────────────

  group('Swahili at 1.3x on 360px: no overflow', () {
    final pages = <String, Widget Function()>{
      'gyms': _gyms,
      'trainers': _trainers,
      'shop': () => const MemberShopTab(),
    };
    for (final MapEntry(key: name, value: page) in pages.entries) {
      for (final dark in [false, true]) {
        sectionTest('$name (${dark ? 'dark' : 'light'})', (tester, api) async {
          _seedShop(api);
          final errors = await captureFlutterErrors(
            () => _host(
              tester,
              page(),
              lang: 'sw',
              textScale: 1.3,
              size: const Size(360, 640),
              dark: dark,
            ),
          );
          expect(
            errors.where(
              // Grid cards overflow at this size flag on or off (fixed card
              // aspect; not touched here). Anything else fails.
              (e) =>
                  !e.contains('trainer_card.dart') &&
                  !e.contains('gym_card.dart'),
            ),
            isEmpty,
            reason: errors.join('\n'),
          );
          expect(find.byType(FFPhotoHero), findsOneWidget);
        });
      }
    }
  });

  // ── assets ──────────────────────────────────────────────────────────────

  group('photos', () {
    const added = [FFHeroPhoto.gyms, FFHeroPhoto.trainers, FFHeroPhoto.shop];

    test('every photo names its scene (spec §34.1)', () {
      final pattern = RegExp(r'^(pexels-\d+|scene-[a-z0-9-]+)$');
      for (final p in FFHeroPhoto.values) {
        expect(p.sourceId, matches(pattern), reason: p.name);
      }
      // Crops of one scene share it.
      expect(
        {
          FFHeroPhoto.signIn.sourceId,
          FFHeroPhoto.activityTraining.sourceId,
          FFHeroPhoto.vendor.sourceId,
        },
        {'scene-tubarones-9545'},
      );
      expect(FFHeroPhoto.upgrade.sourceId, 'scene-ketut-4720');
      expect(FFHeroPhoto.activityChallenges.sourceId, 'scene-ketut-4720');
      expect(FFHeroPhoto.language.sourceId, FFHeroPhoto.activityToday.sourceId);
      expect(FFHeroPhoto.role.sourceId, FFHeroPhoto.owner.sourceId);
      expect(FFHeroPhoto.trainer.sourceId, 'scene-tima-6388');
      expect(FFHeroPhoto.gyms.sourceId, 'pexels-33832204');
      expect(FFHeroPhoto.trainers.sourceId, 'scene-carbell-sarfo-3651');
      expect(FFHeroPhoto.shop.sourceId, 'pexels-5592605');
    });

    test('the section bands use originals no other hero uses', () {
      final others = {
        for (final p in FFHeroPhoto.values)
          if (!added.contains(p)) p.sourceId,
      };
      for (final p in added) {
        expect(others, isNot(contains(p.sourceId)), reason: p.name);
      }
      expect({for (final p in added) p.sourceId}, hasLength(added.length));
    });

    test('files exist, fit the budget and carry no metadata', () {
      for (final p in added) {
        final x1 = File('assets/photos/hero/${p.file}.webp');
        final x2 = File('assets/photos/hero/2.0x/${p.file}.webp');
        expect(x1.existsSync(), isTrue, reason: x1.path);
        expect(x2.existsSync(), isTrue, reason: x2.path);
        // Per-slot caps (spec §34.2).
        expect(x2.lengthSync(), lessThanOrEqualTo(60 * 1000), reason: p.name);
        expect(x1.lengthSync(), lessThanOrEqualTo(25 * 1000), reason: p.name);
        for (final f in [x1, x2]) {
          expect(
            _webpChunks(f),
            isNot(anyOf(contains('EXIF'), contains('XMP '), contains('ICCP'))),
            reason: f.path,
          );
        }
      }
      for (final p in added) {
        expect(p.focal, isNot(Alignment.center), reason: p.name);
      }
    });

    test('every bundled photo has a licence row and all fit 1.6 MB', () {
      final licences = File(
        'assets/photos/hero/LICENSES.md',
      ).readAsStringSync();
      var total = 0;
      for (final f in Directory(
        'assets/photos/hero',
      ).listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.webp')) total += f.lengthSync();
      }
      for (final p in FFHeroPhoto.values) {
        expect(licences, contains('`${p.file}.webp`'), reason: p.name);
      }
      expect(total, lessThanOrEqualTo(1600 * 1000));
      for (final f in ['hero_trainers', 'hero_shop']) {
        final row = licences
            .split('\n')
            .firstWhere((l) => l.startsWith('| `$f.webp`'));
        expect(row, contains('no face in frame'), reason: f);
      }
    });

    test('pubspec declares the new files', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      for (final p in added) {
        expect(pubspec, contains('- ${p.asset}'), reason: p.name);
      }
    });
  });
}

/// The RIFF chunk names of a WebP file (VP8, VP8L, VP8X, ALPH, EXIF, ...).
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
