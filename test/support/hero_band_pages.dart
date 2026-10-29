// The band and section heroes behind PHOTO_HERO_UI, each in the chrome it
// has in the app (a solid app bar and the bottom navigation on the member
// tabs and the gym owner home; a transparent bar over Activity; the trainer
// and vendor homes and Upgrade plan bring their own Scaffold), on a phone
// with real insets, for measuring where the photo, the text and the first
// control sit.

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/member_shop_tab.dart';
import 'package:fitflexmobile/screens/owner/owner_shell.dart';
import 'package:fitflexmobile/screens/trainer/trainer_home_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'recording_api.dart';

/// A phone with an iPhone's insets by default.
class BandPhone {
  const BandPhone(this.width, this.height, {this.top = 47, this.bottom = 34});
  final double width;
  final double height;
  final double top;
  final double bottom;

  Size get size => Size(width, height);

  @override
  String toString() => '${width.toInt()}x${height.toInt()}';
}

const bandP390 = BandPhone(390, 844);
const bandP430 = BandPhone(430, 932, top: 59);
const bandP360 = BandPhone(360, 640, top: 24, bottom: 0);
const bandP700 = BandPhone(390, 700, top: 24, bottom: 0);

/// One screen with a band (or section) hero.
class BandScreen {
  const BandScreen(
    this.name, {
    required this.heroKey,
    required this.control,
    required this.build,
    this.seed,
    this.user = _member,
    this.chrome = BandChrome.solidTab,
  });

  final String name;

  /// The hero's own key.
  final String heroKey;

  /// The screen's first interactive control (in the hero or under it): a
  /// key, or `text:<i18n key>` for the first widget showing that text.
  final String control;

  /// Finds [control] in [lang].
  Finder controlFinder(String lang) => control.startsWith('text:')
      ? find.text(FFLocale.textOf(lang, control.substring(5))!).first
      : find.byKey(Key(control));
  final Widget Function() build;
  final void Function(RecordingApi api)? seed;
  final Map<String, dynamic> user;
  final BandChrome chrome;

  @override
  String toString() => name;
}

/// How the screen sits in the app.
enum BandChrome {
  /// Member tabs and the owner home: a solid app bar, bottom navigation.
  solidTab,

  /// Activity: a transparent app bar over the hero, its band drawn by the
  /// shell, bottom navigation.
  heroTab,

  /// The page brings its own Scaffold (trainer, vendor homes, Upgrade).
  own,
}

const _member = {
  'id': 'm1',
  'userType': 'member',
  'approvalStatus': 'approved',
  'onboardingCompleted': true,
  'displayName': 'Amina Juma',
};

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

MemberData _memberData({Map<String, dynamic>? subscription}) => MemberData()
  ..me = MemberMeResponse.fromJson({
    'user': {
      'id': 'm1',
      'displayName': 'Amina Juma',
      'onboardingCompleted': true,
    },
    'visitsUsed': 3,
    'visitCap': 18,
    'subscription': ?subscription,
  })
  ..gyms = [
    Gym.fromJson(_gym('g1', 'Masaki Fit')),
    Gym.fromJson(_gym('g2', 'Mikocheni Strong')),
  ]
  ..trainers = [
    TrainerProfile.fromJson(_trainer('t1', 'Juma Ali')),
    TrainerProfile.fromJson(_trainer('t2', 'Neema Said')),
  ]
  ..passes = [
    PassTier.fromJson({'id': 'basic', 'price': 50000, 'visitCap': 8}),
    PassTier.fromJson({'id': 'pro', 'price': 90000, 'visitCap': 18}),
  ]
  ..passesLoaded = true
  ..activities = [
    Activity(
      id: 'a1',
      userId: 'm1',
      type: ActivityType.walking,
      source: ActivitySource.device,
      startedAt: DateTime(2026, 9, 23, 7),
      steps: 4000,
      durationMinutes: 30,
      activeMinutes: 30,
    ),
  ]
  ..activityLoaded = true;

void _seedShop(RecordingApi api) {
  api.on('GET /shop/products', [
    _product('p1', 'Yoga Mat'),
    _product('p2', 'Rope'),
  ]);
  api.on('GET /me/shop-orders', <dynamic>[]);
  api.on('GET /gyms', <dynamic>[]);
  api.on('GET /shop/home', {
    'serverNow': '2026-10-19T08:00:00Z',
    'currency': 'TZS',
    'mode': 'member',
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
    'products': {
      'p1': _product('p1', 'Yoga Mat'),
      'p2': _product('p2', 'Rope'),
    },
  });
}

void _seedVendor(RecordingApi api) {
  api.on('GET /vendor/products', [
    for (var i = 0; i < 12; i++)
      {
        'id': 'p$i',
        'name': 'Product $i',
        'priceTzs': 10000,
        'stock': 5,
        'status': 'active',
      },
  ]);
  api.on('GET /vendor/profile', {
    'businessName': 'Asha Gear',
    'status': 'published',
  });
}

OwnerData _ownerData() => OwnerData()
  ..me = {
    'user': {'displayName': 'Rehema Mushi'},
  }
  ..ownerGyms = [
    {'id': 'g1', 'name': 'Mikocheni Fitness'},
  ]
  ..activeGymId = 'g1'
  ..dashboard = {'totalMembers': 12, 'periodVisits': 30};

/// Every screen with a band or section hero (Event detail is left out: it
/// needs an event fixture; it uses the same [FFHeroBand]).
final bandScreens = <BandScreen>[
  BandScreen(
    'gyms',
    heroKey: 'gyms-hero',
    control: 'gym-search',
    build: () =>
        MemberDataScope(data: _memberData(), child: const MemberGymsTab()),
  ),
  BandScreen(
    'trainers',
    heroKey: 'trainers-hero',
    control: 'trainer-search',
    build: () =>
        MemberDataScope(data: _memberData(), child: const MemberTrainersTab()),
  ),
  BandScreen(
    'shop',
    heroKey: 'shop-hero',
    // The search row sits above the band; the categories follow it.
    control: 'shop-home-search',
    build: () => const MemberShopTab(),
    seed: _seedShop,
  ),
  BandScreen(
    'upgrade',
    heroKey: 'passes-hero',
    // The first plan card.
    control: 'text:pass.basic',
    build: () =>
        MemberDataScope(data: _memberData(), child: const MemberPassesPage()),
    chrome: BandChrome.own,
  ),
  BandScreen(
    'upgrade-plan',
    heroKey: 'passes-hero',
    // The first plan to move up to.
    control: 'text:pass.pro',
    build: () => MemberDataScope(
      data: _memberData(
        subscription: {
          'id': 's1',
          'type': 'platform_pass',
          'tier': 'basic',
          'status': 'active',
          'expiresAt': DateTime.now()
              .add(const Duration(days: 30, hours: 12))
              .toUtc()
              .toIso8601String(),
        },
      ),
      child: const MemberPassesPage(),
    ),
    seed: (api) => api.on('GET /me/upgrade-options', {
      'current': {'tier': 'basic', 'priceTzs': 50000},
      'options': [
        {'tier': 'pro', 'differenceTzs': 40000, 'gymAccess': 'standard'},
      ],
    }),
    chrome: BandChrome.own,
  ),
  BandScreen(
    'activity',
    heroKey: 'activity-hero',
    control: 'activity-sections',
    build: () => MemberDataScope(
      data: _memberData(),
      child: MemberActivityTab(now: DateTime(2026, 9, 23, 20)),
    ),
    chrome: BandChrome.heroTab,
  ),
  BandScreen(
    'trainer-home',
    heroKey: 'trainer-hero',
    control: 'trainer-checkin-scan',
    build: () => const TrainerHomePage(),
    user: {
      'id': 't1',
      'userType': 'trainer',
      'approvalStatus': 'approved',
      'onboardingCompleted': true,
      'displayName': 'Juma Ali',
    },
    chrome: BandChrome.own,
  ),
  BandScreen(
    'vendor-home',
    heroKey: 'vendor-hero',
    control: 'vendor-add-product',
    build: () => const VendorHomePage(),
    seed: _seedVendor,
    user: {
      'id': 'v1',
      'userType': 'vendor',
      'approvalStatus': 'approved',
      'onboardingCompleted': true,
      'displayName': 'Asha',
    },
    chrome: BandChrome.own,
  ),
  BandScreen(
    'owner-home',
    heroKey: 'owner-hero',
    control: 'owner-checkin-primary',
    build: () => OwnerDataScope(
      data: _ownerData(),
      child: OwnerHomeTab(now: DateTime(2026, 10, 19, 19)),
    ),
  ),
];

BandScreen bandScreen(String name) =>
    bandScreens.firstWhere((s) => s.name == name);

/// The app's chrome around [screen] (see [BandChrome]).
Widget _chrome(BuildContext context, BandScreen screen) {
  final page = screen.build();
  NavigationBar nav() => NavigationBar(
    destinations: const [
      NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
      NavigationDestination(icon: Icon(Icons.directions_run), label: 'A'),
      NavigationDestination(icon: Icon(Icons.fitness_center), label: 'G'),
      NavigationDestination(icon: Icon(Icons.storefront), label: 'S'),
      NavigationDestination(icon: Icon(Icons.person), label: 'P'),
    ],
  );
  switch (screen.chrome) {
    case BandChrome.own:
      return page;
    case BandChrome.solidTab:
      return Scaffold(
        appBar: AppBar(title: const Text('FitFlex')),
        body: page,
        bottomNavigationBar: nav(),
      );
    case BandChrome.heroTab:
      return Builder(
        builder: (context) => Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: const Text('FitFlex'),
          ),
          body: Builder(
            builder: (context) {
              final top = MediaQuery.paddingOf(context).top;
              return Stack(
                children: [
                  Positioned.fill(child: FFPhotoBarHost(child: page)),
                  FFPhotoBarScrim(barBottom: top, visible: true),
                ],
              );
            },
          ),
          bottomNavigationBar: nav(),
        ),
      );
  }
}

/// Pumps [screen] on [phone] with a fresh fake backend already running
/// (call inside [RecordingApi.run]).
Future<void> pumpBandScreen(
  WidgetTester tester,
  RecordingApi api,
  BandScreen screen, {
  BandPhone phone = bandP390,
  String lang = 'en',
  bool dark = false,
  double textScale = 1,
  double devicePixelRatio = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  screen.seed?.call(api);
  tester.view.physicalSize = phone.size * devicePixelRatio;
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.padding = FakeViewPadding(
    top: phone.top * devicePixelRatio,
    bottom: phone.bottom * devicePixelRatio,
  );
  addTearDown(tester.view.reset);
  final client = ApiClient(baseUrl: 'http://fixtures.local');
  final auth = AuthState(client);
  await auth.signIn('token', Map<String, dynamic>.from(screen.user));
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (context, _) => _chrome(context, screen)),
      GoRoute(
        path: '/member/trainers',
        builder: (_, _) => const Scaffold(body: Text('ROUTE-TRAINERS')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('band-screen-shot'),
      child: AppScope(
        api: client,
        auth: auth,
        child: ThemeScope(
          notifier: ThemeNotifier(),
          child: FFLocaleScope(
            notifier: FFLocale()..set(Locale(lang)),
            child: MaterialApp.router(
              routerConfig: router,
              debugShowCheckedModeBanner: false,
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
    ),
  );
  // Not pumpAndSettle: some tabs keep a spinner running.
  await tester.pump();
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

/// Unmounts the screen and lets its timers finish.
Future<void> unmountBandScreen(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// The scrim token the band text sits on (for reports).
const bandTextScrim = FFTokens.heroScrimText;
