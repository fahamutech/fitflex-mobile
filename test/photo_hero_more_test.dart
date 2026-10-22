// Photo hero addendum behind PHOTO_HERO_UI (docs/design/photo-hero-screens.md
// §18–§30): Language tagline, member Profile, PIN entry and flows, Upgrade
// plan, Activity, and the trainer, vendor and gym owner homes.

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/screens/language_screen.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/owner/owner_shell.dart';
import 'package:fitflexmobile/screens/pin_flows.dart';
import 'package:fitflexmobile/screens/trainer/trainer_home_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hero_scrim.dart';
import 'support/recording_api.dart';

// ── harness ─────────────────────────────────────────────────────────────

/// Pumps [page] at "/" of a small router inside the app's scopes, signed in
/// as [user], answering `package:http` from [api].
Future<AuthState> _host(
  WidgetTester tester,
  RecordingApi api,
  Widget page, {
  Map<String, dynamic> user = const {
    'id': 'u1',
    'userType': 'member',
    'approvalStatus': 'approved',
    'onboardingCompleted': true,
  },
  String lang = 'en',
  bool dark = false,
  double textScale = 1,
  Size size = const Size(390, 844),
  bool reduceMotion = false,
  bool settle = true,
  bool scaffold = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final client = ApiClient(baseUrl: 'http://fixtures.local');
  final auth = AuthState(client);
  await auth.signIn('token', Map<String, dynamic>.from(user));
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => scaffold ? Scaffold(body: page) : page,
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
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                disableAnimations: reduceMotion,
              ),
              child: c!,
            ),
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  return auth;
}

/// A test with a fresh fake backend and the flag on (unless [flag] is off).
void heroTest(
  String name,
  Future<void> Function(WidgetTester tester, RecordingApi api) body, {
  bool flag = true,
}) {
  testWidgets(name, (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugPhotoHeroUiOverride = flag;
    addTearDown(() => debugPhotoHeroUiOverride = null);
    final api = RecordingApi();
    await api.run(() async {
      await body(tester, api);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}

/// All visible text inside [hero] (default: the only FFPhotoHero), joined.
String _heroText(WidgetTester tester, [Finder? hero]) => [
  for (final e
      in find
          .descendant(
            of: hero ?? find.byType(FFPhotoHero),
            matching: find.byType(RichText),
          )
          .evaluate())
    (e.widget as RichText).text.toPlainText(),
].join(' | ');

FFPhotoHero _hero(WidgetTester tester) =>
    tester.widget<FFPhotoHero>(find.byType(FFPhotoHero));

bool _inHero(Finder f) => find
    .descendant(of: find.byType(FFPhotoHero), matching: f)
    .evaluate()
    .isNotEmpty;

String _tr(String lang, String key) => FFLocale.textOf(lang, key)!;

Finder _key(String k) => find.byKey(Key(k));

/// Past the 250ms cross-fade (some sections keep a spinner running, so
/// pumpAndSettle would never return).
Future<void> _pumpSwitch(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Errors whose source is in [allowed] (overflows that also happen with the
/// flag off, below the hero) are set aside; returns the rest.
List<String> _unexpectedErrors(
  List<FlutterErrorDetails> errors,
  List<String> allowed,
) => [
  for (final e in errors)
    if (!allowed.any((a) => e.toString().contains(a))) e.toString(),
];

// ── member data ─────────────────────────────────────────────────────────

Map<String, dynamic> _pass({String tier = 'pro', int daysLeft = 30}) => {
  'id': 's1',
  'type': 'platform_pass',
  'tier': tier,
  'status': 'active',
  'expiresAt': DateTime.now()
      .add(Duration(days: daysLeft, hours: 12))
      .toUtc()
      .toIso8601String(),
};

MemberData _member({
  String name = 'Amina Juma',
  Map<String, dynamic>? subscription,
  List<Map<String, dynamic>> pending = const [],
}) => MemberData()
  ..me = MemberMeResponse.fromJson({
    'user': {'id': 'm1', 'displayName': name, 'onboardingCompleted': true},
    'visitsUsed': 3,
    'visitCap': 18,
    'subscription': ?subscription,
    'pendingPayments': pending,
  });

Widget _scoped(MemberData data, Widget child) =>
    MemberDataScope(data: data, child: child);

final _passes = [
  PassTier.fromJson({'id': 'basic', 'price': 50000, 'visitCap': 8}),
  PassTier.fromJson({'id': 'pro', 'price': 90000, 'visitCap': 18}),
];

final _now = DateTime(2026, 9, 23, 20);

MemberData _activityData({bool loaded = true}) => _member()
  ..activities = [
    Activity(
      id: 'a1',
      userId: 'u1',
      type: ActivityType.walking,
      source: ActivitySource.device,
      startedAt: DateTime(2026, 9, 23, 7),
      steps: 4000,
      durationMinutes: 30,
      activeMinutes: 30,
    ),
  ]
  ..activityLoaded = loaded;

void main() {
  // ── Language and the tagline (owner ask 1, O-20) ───────────────────────

  group('Language: no Swahili tagline (AC-A10)', () {
    for (final lang in ['en', 'sw']) {
      heroTest(
        '$lang: one headline, "FitFlex Africa. Fitness without limits."',
        (tester, api) async {
          final handle = tester.ensureSemantics();
          await _host(
            tester,
            api,
            const LanguageScreen(),
            lang: lang,
            scaffold: false,
          );
          expect(_heroText(tester), 'FITFLEX AFRICA | Fitness without limits.');
          expect(find.textContaining('Pamoja'), findsNothing);
          final label = tester
              .getSemantics(_key('ff-hero-text'))
              .getSemanticsData()
              .label;
          expect(label, 'FITFLEX AFRICA\nFitness without limits.');
          expect(label, isNot(contains('Pamoja')));
          handle.dispose();
        },
      );
    }

    heroTest('Home offline in Swahili: the Swahili of the tagline, no Pamoja', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        _scoped(MemberData()..offline = true, MemberHomeTab(now: _now)),
        lang: 'sw',
      );
      expect(_heroText(tester), contains('Siha bila kikomo.'));
      expect(_heroText(tester), isNot(contains('Pamoja')));
    });

    test('no photo-hero string uses "Pamoja tuna nguvu"', () {
      for (final k in FFLocale.keysOf('sw')) {
        if (!k.startsWith('hero.') && !k.startsWith('home.hero.')) continue;
        expect(
          FFLocale.textOf('sw', k)!.toLowerCase(),
          isNot(contains('pamoja tuna')),
          reason: k,
        );
      }
    });
  });

  // ── Profile (§21) ──────────────────────────────────────────────────────

  group('Profile', () {
    for (final dark in [false, true]) {
      heroTest('loaded (${dark ? 'dark' : 'light'}): avatar, PROFILE, name; '
          'badge first on the solid sheet', (tester, api) async {
        await _host(
          tester,
          api,
          _scoped(_member(subscription: _pass()), const MemberProfileTab()),
          dark: dark,
        );
        final hero = _hero(tester);
        expect(hero.photo, FFHeroPhoto.profile);
        expect(hero.variant, FFHeroVariant.compact);
        expect(hero.actions, isEmpty);
        expect(hero.headlineAccent, isNull);
        expect(_heroText(tester), contains('PROFILE'));
        expect(_heroText(tester), contains('Amina Juma'));
        expect(_key('ff-hero-leading'), findsOneWidget);
        expect(_inHero(find.byType(FFAvatar)), isTrue);
        // The name is said once; the old profile card is gone.
        expect(find.text('Amina Juma'), findsOneWidget);
        expect(_inHero(_key('profile-plan-badge')), isFalse);
        expect(_key('profile-plan-badge'), findsOneWidget);
        expect(
          tester.getTopLeft(_key('profile-plan-badge')).dy,
          lessThan(tester.getTopLeft(_key('profile-edit')).dy),
        );
        expect(find.text('No pass yet'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    heroTest('loading: skeleton headline and badge, never "No pass yet"', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        _scoped(MemberData(), const MemberProfileTab()),
        settle: false,
      );
      expect(_hero(tester).headlineLoading, isTrue);
      expect(_key('profile-badge-loading'), findsOneWidget);
      expect(find.text('No pass yet'), findsNothing);
      expect(_key('profile-edit'), findsOneWidget);
    });

    heroTest('offline with nothing loaded: name fallback, empty badge slot', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        _scoped(MemberData()..offline = true, const MemberProfileTab()),
        lang: 'sw',
      );
      expect(_heroText(tester), contains('Mwanachama'));
      expect(_key('profile-plan-badge'), findsNothing);
      expect(find.text(_tr('sw', 'pass.state.noPass')), findsNothing);
    });

    heroTest('flag off: today\'s card with avatar, name and badge', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        _scoped(_member(subscription: _pass()), const MemberProfileTab()),
      );
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(find.text('Amina Juma'), findsOneWidget);
      expect(
        find.ancestor(of: find.byType(FFAvatar), matching: find.byType(FFCard)),
        findsOneWidget,
      );
      expect(_key('profile-plan-badge'), findsOneWidget);
    }, flag: false);
  });

  // ── PIN entry (§22.1) ──────────────────────────────────────────────────

  group('PIN entry', () {
    Widget pin({EmailAuthMode mode = EmailAuthMode.signIn}) =>
        EmailAuthScreen(initialEmail: 'qa@example.test', initialMode: mode);

    void expectKeypadOnScreen(WidgetTester tester, double height) {
      final ok = find.text('OK');
      expect(ok, findsOneWidget);
      final key = find.ancestor(of: ok, matching: find.byType(Material)).first;
      expect(tester.getRect(key).bottom, lessThanOrEqualTo(height));
      expect(tester.getRect(key).top, greaterThanOrEqualTo(0));
      // Both layouts keep the keys at 44px or more (the no-hero layout
      // since fix/activity-pin-layout).
      expect(tester.getSize(key).height, greaterThanOrEqualTo(44));
    }

    for (final dark in [false, true]) {
      heroTest('390x844 ${dark ? 'dark' : 'light'}: hero, keypad on the '
          'solid sheet, OK fully on screen', (tester, api) async {
        await _host(tester, api, pin(), dark: dark, scaffold: false);
        final hero = _hero(tester);
        expect(hero.photo, FFHeroPhoto.pin);
        expect(_heroText(tester), contains('VERIFICATION PIN'));
        expect(_heroText(tester), contains('One last step.'));
        expect(_heroText(tester), contains('qa@example.test'));
        // Dots, keypad and links are never on the photo.
        expect(_inHero(find.byType(PinInputRow)), isFalse);
        expect(_inHero(find.byType(CustomKeypad)), isFalse);
        expect(_inHero(find.text('OK')), isFalse);
        expect(
          find.ancestor(
            of: find.byType(CustomKeypad),
            matching: find.byType(FFHeroSheet),
          ),
          findsOneWidget,
        );
        expectKeypadOnScreen(tester, 844);
        // 52px keys on a phone this tall.
        final one = find
            .ancestor(of: find.text('1'), matching: find.byType(Material))
            .first;
        expect(tester.getSize(one).height, closeTo(52, 0.5));
        // The hero's text sits below the app bar.
        expect(
          tester.getTopLeft(_key('ff-hero-text')).dy,
          greaterThanOrEqualTo(kToolbarHeight),
        );
        expect(tester.takeException(), isNull);
      });
    }

    heroTest('390x700: no hero (too short), keypad fully on screen', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        pin(),
        size: const Size(390, 700),
        scaffold: false,
      );
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(find.text('Verification PIN'), findsOneWidget);
      expectKeypadOnScreen(tester, 700);
      expect(tester.takeException(), isNull);
    });

    heroTest('390x760: hero, 44px keys, keypad on screen', (tester, api) async {
      await _host(
        tester,
        api,
        pin(),
        size: const Size(390, 760),
        scaffold: false,
      );
      expect(find.byType(FFPhotoHero), findsOneWidget);
      expectKeypadOnScreen(tester, 760);
      final one = find
          .ancestor(of: find.text('1'), matching: find.byType(Material))
          .first;
      expect(tester.getSize(one).height, closeTo(44, 0.5));
      expect(tester.takeException(), isNull);
    });

    heroTest('360x640: today\'s layout, OK on screen', (tester, api) async {
      await _host(
        tester,
        api,
        pin(),
        size: const Size(360, 640),
        scaffold: false,
      );
      expect(find.byType(FFPhotoHero), findsNothing);
      expectKeypadOnScreen(tester, 640);
    });

    heroTest('1.3x text at 390x844 falls back; nothing clips', (
      tester,
      api,
    ) async {
      await _host(tester, api, pin(), textScale: 1.3, scaffold: false);
      expect(find.byType(FFPhotoHero), findsNothing);
      expectKeypadOnScreen(tester, 844);
      expect(tester.takeException(), isNull);
    });

    heroTest('sign-up mode: CREATE PIN, "A PIN only you know."', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        pin(mode: EmailAuthMode.signUp),
        scaffold: false,
      );
      expect(_heroText(tester), contains('CREATE PIN'));
      expect(_heroText(tester), contains('A PIN only you know.'));
    });

    heroTest('flag off: today\'s screen at 390x844', (tester, api) async {
      await _host(tester, api, pin(), scaffold: false);
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(find.text('Verification PIN'), findsOneWidget);
      expect(find.text('qa@example.test'), findsOneWidget);
      expectKeypadOnScreen(tester, 844);
    }, flag: false);
  });

  // ── PIN flows (§22.2) ──────────────────────────────────────────────────

  group('PIN flows', () {
    heroTest('Forgot PIN contact step: pin photo, reset headline, scrolls', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        const ForgotPinScreen(contact: '0712345678'),
        scaffold: false,
      );
      expect(_hero(tester).photo, FFHeroPhoto.pin);
      expect(_heroText(tester), contains('RESET YOUR PIN'));
      expect(_heroText(tester), contains("Let's get you back in."));
      expect(_key('pin-flow-contact'), findsOneWidget);
      expect(_inHero(_key('pin-flow-contact')), isFalse);
    });

    Widget setup() => const PinSetupScreen(
      setupToken: 't',
      contact: '0712345678',
      needsCode: false,
      needsNewPin: true,
      currentPin: '12345',
    );

    heroTest('PIN setup choose step at 390x844: hero, OK on screen', (
      tester,
      api,
    ) async {
      await _host(tester, api, setup(), scaffold: false);
      expect(_heroText(tester), contains('ONE-TIME CHECK'));
      expect(_heroText(tester), contains('A PIN only you know.'));
      final ok = find.ancestor(
        of: find.text('OK'),
        matching: find.byType(Material),
      );
      expect(tester.getRect(ok.first).bottom, lessThanOrEqualTo(844));
      expect(_inHero(find.byType(CustomKeypad)), isFalse);
      expect(tester.takeException(), isNull);
    });

    heroTest('PIN setup choose step at 390x760: no hero, OK on screen', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        setup(),
        size: const Size(390, 760),
        scaffold: false,
      );
      expect(find.byType(FFPhotoHero), findsNothing);
      final ok = find.ancestor(
        of: find.text('OK'),
        matching: find.byType(Material),
      );
      expect(tester.getRect(ok.first).bottom, lessThanOrEqualTo(760));
    });

    heroTest('flag off: Forgot PIN keeps its app bar title', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        const ForgotPinScreen(contact: '0712345678'),
        scaffold: false,
      );
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Reset your PIN'),
        ),
        findsOneWidget,
      );
    }, flag: false);
  });

  // ── Upgrade plan (§23) ─────────────────────────────────────────────────

  group('Upgrade plan /member/passes', () {
    MemberData buyer() => _member()
      ..passes = _passes
      ..passesLoaded = true;
    MemberData upgrader() => _member(subscription: _pass(tier: 'basic'))
      ..passes = _passes
      ..passesLoaded = true;

    void noNumbersOnHero(WidgetTester tester) =>
        expect(_heroText(tester), isNot(matches(RegExp(r'\d'))));

    heroTest('buy mode: band hero, FITFLEX PASS, plan body said once', (
      tester,
      api,
    ) async {
      await _host(tester, api, _scoped(buyer(), const MemberPassesPage()));
      final hero = _hero(tester);
      expect(hero.variant, FFHeroVariant.band);
      expect(hero.photo, FFHeroPhoto.upgrade);
      expect(_heroText(tester), contains('FITFLEX PASS'));
      expect(_heroText(tester), contains('One pass. Many gyms.'));
      expect(find.text(_tr('en', 'member.planBody')), findsOneWidget);
      noNumbersOnHero(tester);
      // Prices and the continue button stay on the solid page.
      expect(find.text(_tr('en', 'member.continuePayment')), findsOneWidget);
      expect(_inHero(find.text(_tr('en', 'member.continuePayment'))), isFalse);
    });

    heroTest('upgrade with options: Move up a level; no amounts on the hero', (
      tester,
      api,
    ) async {
      api.on('GET /me/upgrade-options', {
        'current': {'tier': 'basic', 'priceTzs': 50000},
        'options': [
          {'tier': 'pro', 'differenceTzs': 40000, 'gymAccess': 'standard'},
        ],
      });
      await _host(tester, api, _scoped(upgrader(), const MemberPassesPage()));
      expect(_heroText(tester), contains('UPGRADE PLAN'));
      expect(_heroText(tester), contains('Move up a level.'));
      noNumbersOnHero(tester);
      expect(find.textContaining('40,000'), findsWidgets);
      expect(_inHero(find.textContaining('40,000')), isFalse);
      // Pick the plan: the submit button (with the amount) is on the page.
      await tester.tap(find.text(_tr('en', 'pass.pro')));
      await tester.pumpAndSettle();
      expect(_key('upgrade-submit'), findsOneWidget);
      expect(_inHero(_key('upgrade-submit')), isFalse);
      noNumbersOnHero(tester);
      // The app bar no longer repeats the plan body.
      expect(find.text(_tr('en', 'member.planBody')), findsNothing);
    });

    heroTest('top plan: "You\'re at the top.", highest alert hidden', (
      tester,
      api,
    ) async {
      api.on('GET /me/upgrade-options', {
        'current': {'tier': 'pro', 'priceTzs': 90000},
        'options': [],
      });
      await _host(tester, api, _scoped(upgrader(), const MemberPassesPage()));
      expect(_heroText(tester), contains("You're at the top."));
      expect(find.text(_tr('en', 'upgrade.highest')), findsNothing);
      expect(find.text(_tr('en', 'upgrade.currentPlan')), findsOneWidget);
    });

    heroTest('loading options: eyebrow only, FFSpinner below', (
      tester,
      api,
    ) async {
      final hold = api.hold('GET /me/upgrade-options');
      await _host(
        tester,
        api,
        _scoped(upgrader(), const MemberPassesPage()),
        settle: false,
      );
      expect(_heroText(tester), 'UPGRADE PLAN');
      expect(find.byType(FFSpinner), findsOneWidget);
      hold.complete();
      await tester.pumpAndSettle();
    });

    heroTest('server says nothing to upgrade from: buy list with its hero', (
      tester,
      api,
    ) async {
      api.fail('GET /me/upgrade-options', 409, {'error': 'no_pass'});
      await _host(tester, api, _scoped(upgrader(), const MemberPassesPage()));
      expect(find.byType(FFPhotoHero), findsOneWidget);
      expect(_heroText(tester), contains('One pass. Many gyms.'));
      expect(find.text(_tr('en', 'member.continuePayment')), findsOneWidget);
    });

    heroTest('pending pass payment: One step to go, pending card below', (
      tester,
      api,
    ) async {
      final data = _member(
        pending: [
          {
            'id': 'p1',
            'productType': 'FITFLEX_PASS',
            'status': 'pending',
            'tier': 'pro',
            'amountTzs': 90000,
          },
        ],
      )..passesLoaded = true;
      await _host(tester, api, _scoped(data, const MemberPassesPage()));
      expect(_heroText(tester), contains('One step to go.'));
      noNumbersOnHero(tester);
      expect(
        find.text(_tr('en', 'member.paymentPendingTitle')),
        findsOneWidget,
      );
    });

    heroTest('passes failed to load: eyebrow only, Retry below', (
      tester,
      api,
    ) async {
      final data = _member()..passesLoaded = true;
      await _host(tester, api, _scoped(data, const MemberPassesPage()));
      expect(_heroText(tester), 'FITFLEX PASS');
      expect(find.text('Retry'), findsOneWidget);
    });

    heroTest('flag off: app bar subtitle, no hero', (tester, api) async {
      await _host(tester, api, _scoped(buyer(), const MemberPassesPage()));
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text(_tr('en', 'member.planBody')),
        ),
        findsOneWidget,
      );
    }, flag: false);
  });

  // ── Activity (§24) ─────────────────────────────────────────────────────

  group('Activity', () {
    const sections = [
      ('overview', 'Today', FFHeroPhoto.activityToday, 'Every step counts.'),
      (
        'workouts',
        'Training',
        FFHeroPhoto.activityTraining,
        'Train with a plan.',
      ),
      (
        'challenges',
        'Challenges',
        FFHeroPhoto.activityChallenges,
        'Take on a challenge.',
      ),
      (
        'progress',
        'Progress',
        FFHeroPhoto.activityProgress,
        "See how far you've come.",
      ),
    ];

    Future<void> tapSection(WidgetTester tester, String label) async {
      await tester.tap(
        find.descendant(
          of: _key('activity-sections'),
          matching: find.text(label),
        ),
      );
    }

    heroTest('each section has its own photo and headline', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        _scoped(_activityData(), MemberActivityTab(now: _now)),
      );
      final photos = <FFHeroPhoto>{};
      for (final (_, label, photo, headline) in sections) {
        await tapSection(tester, label);
        await _pumpSwitch(tester);
        expect(_hero(tester).photo, photo);
        expect(_heroText(tester), contains(headline));
        expect(_heroText(tester), contains('ACTIVITY'));
        photos.add(photo);
      }
      expect(photos, hasLength(4));
      expect({for (final p in photos) p.file}, hasLength(4));
    });

    for (final lang in ['en', 'sw']) {
      for (final width in [360.0, 390.0, 430.0]) {
        for (final dark in [false, true]) {
          heroTest('$lang ${width.toInt()} ${dark ? 'dark' : 'light'}: hero '
              'height is fixed across sections', (tester, api) async {
            await _host(
              tester,
              api,
              _scoped(_activityData(), MemberActivityTab(now: _now)),
              lang: lang,
              dark: dark,
              size: Size(width, 844),
            );
            final heights = <double>{};
            for (final (key, _, _, _) in sections) {
              await tapSection(tester, _tr(lang, 'activity.$key'));
              await _pumpSwitch(tester);
              heights.add(tester.getSize(find.byType(FFPhotoHero)).height);
            }
            expect(heights, hasLength(1), reason: '$heights');
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    for (final lang in ['en', 'sw']) {
      heroTest('$lang 390x844: segmented control ends <= 440px, on the sheet', (
        tester,
        api,
      ) async {
        await _host(
          tester,
          api,
          _scoped(_activityData(), MemberActivityTab(now: _now)),
          lang: lang,
        );
        expect(
          tester.getBottomLeft(_key('activity-sections')).dy,
          lessThanOrEqualTo(440),
        );
        expect(_inHero(_key('activity-sections')), isFalse);
      });
    }

    heroTest('reduced motion: the switch is instant, one photo at a time', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        _scoped(_activityData(), MemberActivityTab(now: _now)),
        reduceMotion: true,
      );
      await tapSection(tester, 'Training');
      await tester.pump();
      expect(_key('ff-hero-photo'), findsOneWidget);
      expect(_hero(tester).photo, FFHeroPhoto.activityTraining);
      expect(_heroText(tester), contains('Train with a plan.'));
      expect(find.byType(AnimatedSwitcher), findsNothing);
    });

    heroTest('motion on: the photos cross-fade, done within 250ms', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        _scoped(_activityData(), MemberActivityTab(now: _now)),
      );
      await tapSection(tester, 'Training');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(_key('ff-hero-photo'), findsNWidgets(2));
      await tester.pump(const Duration(milliseconds: 160));
      expect(_key('ff-hero-photo'), findsOneWidget);
    });

    heroTest('Log activity sits on the hero as an onPhoto button', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        _scoped(_activityData(), MemberActivityTab(now: _now)),
      );
      expect(_inHero(_key('activity-log-open')), isTrue);
      final b = tester.widget<FFButton>(_key('activity-log-open'));
      expect(b.variant, FFButtonVariant.onPhoto);
      expect(find.byType(FFPageHeader), findsNothing);
      expect(
        tester.getSize(_key('activity-log-open')).height,
        greaterThanOrEqualTo(44),
      );
    });

    heroTest('loading: photo and headline, no Log activity, spinner', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        _scoped(_activityData(loaded: false), MemberActivityTab(now: _now)),
        settle: false,
      );
      expect(_heroText(tester), contains('Every step counts.'));
      expect(_key('activity-log-open'), findsNothing);
      expect(find.byType(FFSpinner), findsOneWidget);
    });

    heroTest('opening Progress directly shows its photo on the first frame', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        _scoped(
          _activityData(),
          MemberActivityTab(now: _now, initialSection: 'progress'),
        ),
        settle: false,
      );
      expect(_hero(tester).photo, FFHeroPhoto.activityProgress);
      expect(_key('ff-hero-photo'), findsOneWidget);
    });

    heroTest('flag off: page header with Log activity, no hero', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        _scoped(_activityData(), MemberActivityTab(now: _now)),
      );
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(find.byType(FFPageHeader), findsOneWidget);
      expect(
        tester.widget<FFButton>(_key('activity-log-open')).variant,
        FFButtonVariant.secondary,
      );
    }, flag: false);
  });

  // ── Partner homes (§25) ────────────────────────────────────────────────

  group('Trainer home', () {
    const trainer = {
      'id': 't1',
      'userType': 'trainer',
      'approvalStatus': 'approved',
      'onboardingCompleted': true,
      'displayName': 'Juma Ali',
    };

    heroTest('band hero carries check-in; the old card is gone', (
      tester,
      api,
    ) async {
      await _host(tester, api, const TrainerHomePage(), user: trainer);
      final hero = _hero(tester);
      expect(hero.variant, FFHeroVariant.band);
      expect(hero.photo, FFHeroPhoto.trainer);
      expect(_heroText(tester), matches(RegExp(r'GOOD \w+, JUMA')));
      expect(_heroText(tester), contains('Ready to coach?'));
      expect(_heroText(tester), contains(_tr('en', 'checkin.body')));
      expect(_key('trainer-checkin-scan'), findsOneWidget);
      expect(_key('trainer-checkin-qr'), findsOneWidget);
      expect(_inHero(_key('trainer-checkin-scan')), isTrue);
      expect(
        tester.widget<FFButton>(_key('trainer-checkin-qr')).variant,
        FFButtonVariant.onPhoto,
      );
      expect(_key('trainer-checkin-card'), findsNothing);
      expect(_key('trainer-appbar-qr'), findsOneWidget);
      // No QR code on the photo.
      expect(_inHero(find.byType(FFQrCode)), isFalse);
    });

    heroTest('flag off: the check-in card, no hero', (tester, api) async {
      await _host(tester, api, const TrainerHomePage(), user: trainer);
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(_key('trainer-checkin-card'), findsOneWidget);
    }, flag: false);
  });

  group('Vendor home', () {
    Map<String, dynamic> vendor({String status = 'approved'}) => {
      'id': 'v1',
      'userType': 'vendor',
      'approvalStatus': status,
      'onboardingCompleted': true,
      'displayName': 'Asha',
    };

    void seed(RecordingApi api, {int products = 12}) {
      api.on('GET /vendor/products', [
        for (var i = 0; i < products; i++)
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

    heroTest('Products: band hero, one Add product, no FAB until scrolled', (
      tester,
      api,
    ) async {
      seed(api);
      await _host(tester, api, const VendorHomePage(), user: vendor());
      final hero = _hero(tester);
      expect(hero.photo, FFHeroPhoto.vendor);
      expect(hero.variant, FFHeroVariant.band);
      expect(_heroText(tester), contains('ASHA GEAR'));
      expect(_heroText(tester), contains('Stock up. Sell more.'));
      expect(_key('vendor-add-product'), findsOneWidget);
      expect(_inHero(_key('vendor-add-product')), isTrue);
      expect(find.byType(FloatingActionButton), findsNothing);

      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(_key('vendor-add-product'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FloatingActionButton),
          matching: find.byType(Text),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    heroTest('empty products: hero + Add product, empty state, no FAB', (
      tester,
      api,
    ) async {
      seed(api, products: 0);
      await _host(tester, api, const VendorHomePage(), user: vendor());
      expect(find.byType(FFPhotoHero), findsOneWidget);
      expect(find.byType(FFEmptyState), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(_key('vendor-add-product'), findsOneWidget);
    });

    heroTest('pending approval: "Almost ready to sell." and the banner under', (
      tester,
      api,
    ) async {
      seed(api);
      await _host(
        tester,
        api,
        const VendorHomePage(),
        user: vendor(status: 'pending_approval'),
      );
      expect(_heroText(tester), contains('Almost ready to sell.'));
      expect(_key('vendor-pending-banner'), findsOneWidget);
      expect(
        tester.getTopLeft(_key('vendor-pending-banner')).dy,
        greaterThan(tester.getBottomLeft(find.byType(FFPhotoHero)).dy),
      );
    });

    heroTest('staff without Products: no hero', (tester, api) async {
      seed(api);
      await _host(
        tester,
        api,
        const VendorHomePage(),
        user: {
          ...vendor(),
          'userType': 'vendor_staff',
          'vendorPermissions': ['orders'],
        },
      );
      expect(find.byType(FFPhotoHero), findsNothing);
    });

    heroTest('flag off: the FAB, no hero', (tester, api) async {
      seed(api);
      await _host(tester, api, const VendorHomePage(), user: vendor());
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    }, flag: false);
  });

  group('Gym owner home', () {
    OwnerData owner({bool gym = true}) => OwnerData()
      ..me = {
        'user': {'displayName': 'Rehema Mushi'},
      }
      ..ownerGyms = [
        if (gym) {'id': 'g1', 'name': 'Mikocheni Fitness'},
      ]
      ..activeGymId = gym ? 'g1' : null
      ..dashboard = {'totalMembers': 12, 'periodVisits': 30};

    Widget page(OwnerData d) => OwnerDataScope(
      data: d,
      child: OwnerHomeTab(now: DateTime(2026, 10, 19, 19)),
    );

    heroTest('band hero: greeting, Check-in once, gym name not repeated', (
      tester,
      api,
    ) async {
      await _host(tester, api, page(owner()));
      final hero = _hero(tester);
      expect(hero.photo, FFHeroPhoto.owner);
      expect(hero.variant, FFHeroVariant.band);
      expect(_heroText(tester), contains('GOOD EVENING, REHEMA'));
      expect(_heroText(tester), contains('Keep your gym moving.'));
      expect(_key('owner-checkin-primary'), findsOneWidget);
      expect(_inHero(_key('owner-checkin-primary')), isTrue);
      expect(find.text('Good evening, Rehema'), findsNothing);
      expect(find.text('Mikocheni Fitness'), findsNothing);
      expect(_key('owner-date-filter'), findsOneWidget);
      expect(_inHero(_key('owner-date-filter')), isFalse);
    });

    heroTest('no approved gym: Welcome to FitFlex, no action', (
      tester,
      api,
    ) async {
      await _host(tester, api, page(owner(gym: false)), settle: false);
      expect(_heroText(tester), contains('Welcome to FitFlex'));
      expect(_hero(tester).actions, isEmpty);
      expect(find.byType(FFGymUnapprovedCard), findsOneWidget);
    });

    heroTest('flag off: greeting text and full-width Check-in', (
      tester,
      api,
    ) async {
      await _host(tester, api, page(owner()));
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(find.text('Good evening, Rehema'), findsOneWidget);
      expect(find.text('Mikocheni Fitness'), findsOneWidget);
      expect(
        tester.widget<FFButton>(_key('owner-checkin-primary')).fullWidth,
        isTrue,
      );
    }, flag: false);
  });

  // ── Band variant and avatar: the scrim stop rule (AC-H20) ──────────────

  group('Scrim rule on the new variants', () {
    Future<void> checkStop(WidgetTester tester) async =>
        expectHeroScrimRule(tester);

    for (final scale in [1.0, 1.3, 2.0]) {
      heroTest('band at ${scale}x: all text in the >= 0.86 zone', (
        tester,
        api,
      ) async {
        await _host(
          tester,
          api,
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: FFHeroBand(
              photo: FFHeroPhoto.owner,
              eyebrow: 'Habari za jioni, Rehema',
              headlineLead: _tr('sw', 'hero.owner.lead'),
              headlineAccent: _tr('sw', 'hero.owner.accent'),
              subline: _tr('sw', 'checkin.body'),
              actions: [
                FFButton(label: _tr('sw', 'owner.checkin'), onPressed: () {}),
              ],
            ),
          ),
          size: const Size(360, 800),
          textScale: scale,
        );
        await checkStop(tester);
        final hero = _hero(tester);
        expect(hero.variant, FFHeroVariant.band);
        // A card: rounded 24px corners and no melt into the ground.
        final clip = tester.widget<ClipRRect>(
          find
              .descendant(
                of: find.byType(FFPhotoHero),
                matching: find.byType(ClipRRect),
              )
              .first,
        );
        expect(clip.borderRadius, BorderRadius.circular(FFTokens.radiusXl));
        expect(tester.takeException(), isNull);
      });
    }

    heroTest('band in dark theme keeps a >= 0.86 bottom edge (no melt)', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        const Padding(
          padding: EdgeInsets.all(24),
          child: FFHeroBand(
            photo: FFHeroPhoto.vendor,
            headlineLead: 'Stock up.',
            headlineAccent: 'Sell more.',
          ),
        ),
        dark: true,
      );
      final zone = find.byKey(const Key('ff-hero-text-zone'));
      final gradients = find.descendant(
        of: zone,
        matching: find.byWidgetPredicate(
          (w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient != null,
        ),
      );
      expect(gradients, findsNothing);
    });

    heroTest('wide (>= 840): band becomes a rounded panel banner', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        const Padding(
          padding: EdgeInsets.all(24),
          child: FFHeroBand(photo: FFHeroPhoto.owner, headlineLead: 'Hi'),
        ),
        size: const Size(1280, 800),
      );
      final hero = _hero(tester);
      expect(hero.variant, FFHeroVariant.panel);
      expect(hero.rounded, isTrue);
      expect(
        tester.getSize(find.byType(FFPhotoHero)).height,
        greaterThanOrEqualTo(220),
      );
    });

    heroTest(
      'Profile avatar sits in the >= 0.86 zone, 24px below the ramp start',
      (tester, api) async {
        await _host(
          tester,
          api,
          _scoped(_member(subscription: _pass()), const MemberProfileTab()),
          textScale: 1.3,
          size: const Size(360, 800),
        );
        await checkStop(tester);
        final zone = find.byKey(const Key('ff-hero-text-zone'));
        final stopY = tester.getTopLeft(zone).dy;
        expect(
          tester.getTopLeft(_key('ff-hero-leading')).dy - stopY,
          greaterThanOrEqualTo(24 - 0.01),
        );
        expect(
          find.descendant(of: zone, matching: _key('ff-hero-leading')),
          findsOneWidget,
        );
      },
    );

    test('avatar ring and band edge colours over pure white', () {
      double ratio(Color a, Color b) {
        final la = a.computeLuminance(), lb = b.computeLuminance();
        return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
      }

      final zone = Color.alphaBlend(
        FFTokens.heroScrim.withValues(alpha: FFTokens.heroScrimText),
        Colors.white,
      );
      expect(ratio(FFTokens.heroText, zone), greaterThanOrEqualTo(3));
    });

    test('every addendum photo has a focal point and a distinct file', () {
      const added = [
        FFHeroPhoto.profile,
        FFHeroPhoto.pin,
        FFHeroPhoto.upgrade,
        FFHeroPhoto.activityToday,
        FFHeroPhoto.activityTraining,
        FFHeroPhoto.activityChallenges,
        FFHeroPhoto.activityProgress,
        FFHeroPhoto.trainer,
        FFHeroPhoto.vendor,
        FFHeroPhoto.owner,
      ];
      expect({
        for (final p in FFHeroPhoto.values) p.file,
      }, hasLength(FFHeroPhoto.values.length));
      for (final p in added) {
        expect(p.focal, isNot(Alignment.center), reason: p.name);
      }
      // Sign in (2026-10-22) has a focal point too: its door sign.
      expect(FFHeroPhoto.signIn.focal, isNot(Alignment.center));
    });
  });

  // ── Swahili at 1.3x on a 360px phone ───────────────────────────────────

  group('Swahili at 1.3x on 360px: no overflow', () {
    final screens = <String, (Widget Function(), Map<String, dynamic>?)>{
      'profile': (
        () => _scoped(_member(subscription: _pass()), const MemberProfileTab()),
        null,
      ),
      'passes buy': (
        () => _scoped(
          _member()
            ..passes = _passes
            ..passesLoaded = true,
          const MemberPassesPage(),
        ),
        null,
      ),
      'activity': (
        () => _scoped(_activityData(), MemberActivityTab(now: _now)),
        null,
      ),
      'activity progress': (
        () => _scoped(
          _activityData(),
          MemberActivityTab(now: _now, initialSection: 'progress'),
        ),
        null,
      ),
      'forgot PIN': (() => const ForgotPinScreen(contact: '0712345678'), null),
      'trainer home': (
        () => const TrainerHomePage(),
        {
          'id': 't1',
          'userType': 'trainer',
          'approvalStatus': 'approved',
          'onboardingCompleted': true,
          'displayName': 'Juma Ali',
        },
      ),
      'vendor home': (
        () => const VendorHomePage(),
        {
          'id': 'v1',
          'userType': 'vendor',
          'approvalStatus': 'approved',
          'onboardingCompleted': true,
        },
      ),
      'owner home': (
        () => OwnerDataScope(
          data: OwnerData()
            ..me = {
              'user': {'displayName': 'Rehema'},
            }
            ..ownerGyms = [
              {'id': 'g1', 'name': 'Mikocheni Fitness'},
            ]
            ..activeGymId = 'g1',
          child: OwnerHomeTab(now: DateTime(2026, 10, 19, 19)),
        ),
        null,
      ),
    };
    for (final MapEntry(:key, :value) in screens.entries) {
      for (final dark in [false, true]) {
        heroTest('$key (${dark ? 'dark' : 'light'})', (tester, api) async {
          final errors = <FlutterErrorDetails>[];
          final previous = FlutterError.onError;
          FlutterError.onError = errors.add;
          await _host(
            tester,
            api,
            value.$1(),
            user:
                value.$2 ??
                const {
                  'id': 'u1',
                  'userType': 'member',
                  'approvalStatus': 'approved',
                  'onboardingCompleted': true,
                },
            lang: 'sw',
            dark: dark,
            textScale: 1.3,
            size: const Size(360, 640),
            scaffold: key != 'forgot PIN',
            settle: !key.startsWith('activity'),
          );
          FlutterError.onError = previous;
          // The Activity "Recent" row and activity tiles no longer
          // overflow (fix/activity-pin-layout), so nothing is set aside.
          final unexpected = _unexpectedErrors(errors, const []);
          expect(unexpected, isEmpty, reason: unexpected.join('\n---\n'));
          for (final e in errors) {
            expect(e.toString(), isNot(contains('ff_photo_hero')));
            expect(e.toString(), isNot(contains('ff_button')));
          }
          expect(find.byType(FFPhotoHero), findsOneWidget);
        });
      }
    }

    heroTest('PIN entry, Swahili, 360x800 at 1.0x (hero shown)', (
      tester,
      api,
    ) async {
      await _host(
        tester,
        api,
        const EmailAuthScreen(initialEmail: '0712345678'),
        lang: 'sw',
        size: const Size(360, 800),
        scaffold: false,
      );
      expect(tester.takeException(), isNull);
      expect(_heroText(tester), contains('PIN YA UTHIBITISHO'));
      expect(_heroText(tester), contains('Hatua ya mwisho.'));
    });
  });

  test('every addendum string has English and Swahili, and they differ', () {
    const keys = [
      'hero.pin.signIn',
      'hero.pin.create',
      'hero.pin.code',
      'hero.pin.reset',
      'hero.upgrade',
      'hero.upgrade.top',
      'hero.activity.today',
      'hero.activity.training',
      'hero.activity.challenges',
      'hero.activity.progress',
      'hero.trainer',
      'hero.vendor',
      'hero.vendor.pending',
      'hero.owner',
    ];
    for (final k in [
      for (final b in keys) ...['$b.lead', '$b.accent'],
      'member.nameFallback',
    ]) {
      final en = FFLocale.textOf('en', k);
      final sw = FFLocale.textOf('sw', k);
      expect(en, isNotNull, reason: k);
      expect(sw, isNotNull, reason: k);
      expect(sw, isNot(en), reason: k);
    }
  });
}
