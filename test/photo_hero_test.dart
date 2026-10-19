// Photo hero screens behind PHOTO_HERO_UI (docs/design/photo-hero-screens.md).

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/auth_screen.dart';
import 'package:fitflexmobile/screens/language_screen.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/role_screen.dart';
import 'package:fitflexmobile/screens/sign_up_screen.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

final _evening = DateTime(2026, 10, 19, 19);

MemberData _member({
  Map<String, dynamic>? subscription,
  Map<String, dynamic>? pending,
  int used = 0,
  int? cap = 18,
}) => MemberData()
  ..me = MemberMeResponse.fromJson({
    'user': {'id': 'm1', 'displayName': 'Amina', 'onboardingCompleted': true},
    'visitsUsed': used,
    'visitCap': cap,
    'subscription': ?subscription,
    'pendingPayment': ?pending,
  });

Map<String, dynamic> _pass({String status = 'active', int daysLeft = 30}) => {
  'id': 's1',
  'type': 'platform_pass',
  'tier': 'pro',
  'status': status,
  'expiresAt': DateTime.now()
      .add(Duration(days: daysLeft, hours: 12))
      .toUtc()
      .toIso8601String(),
};

Future<AuthState> _pump(
  WidgetTester tester,
  Widget home, {
  String lang = 'en',
  bool dark = false,
  double width = 390,
  double height = 844,
  double textScale = 1,
  bool settle = true,
  bool highContrast = false,
  String role = 'member',
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width * 2, height * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final api = ApiClient(baseUrl: 'http://localhost:0');
  final auth = AuthState(api);
  await auth.setRole(role);
  await tester.pumpWidget(
    AppScope(
      api: api,
      auth: auth,
      child: ThemeScope(
        notifier: ThemeNotifier(),
        child: FFLocaleScope(
          notifier: FFLocale()..set(Locale(lang)),
          child: MaterialApp(
            theme: dark ? buildDarkTheme() : buildTheme(),
            supportedLocales: const [Locale('en'), Locale('sw')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
                highContrast: highContrast,
              ),
              child: child!,
            ),
            home: home,
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
  return auth;
}

Widget _home(MemberData data) => Scaffold(
  body: MemberDataScope(
    data: data,
    child: MemberHomeTab(now: _evening),
  ),
);

/// All visible text inside the hero, joined.
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

void main() {
  setUp(() => debugPhotoHeroUiOverride = true);
  tearDown(() => debugPhotoHeroUiOverride = null);

  group('Home states under the flag', () {
    testWidgets('no pass: full hero, two actions, steps card, no pass card', (
      tester,
    ) async {
      await _pump(tester, _home(_member()));
      expect(find.byKey(const Key('home-hero-none')), findsOneWidget);
      final hero = tester.widget<FFPhotoHero>(find.byType(FFPhotoHero));
      expect(hero.variant, FFHeroVariant.full);
      expect(hero.photo, FFHeroPhoto.homeStart);
      expect(_heroText(tester), contains("Let's get you training."));
      expect(_heroText(tester), contains('GOOD EVENING, AMINA'));
      expect(
        _heroText(tester),
        contains('Pick a pass to open gyms across the network.'),
      );
      expect(find.text('Choose a pass'), findsOneWidget);
      expect(find.text('Explore gyms'), findsOneWidget);
      final secondary = tester.widget<FFButton>(
        find.byKey(const Key('home-hero-secondary')),
      );
      expect(secondary.variant, FFButtonVariant.onPhoto);
      expect(find.byKey(const Key('home-how-it-works')), findsOneWidget);
      expect(find.text('How FitFlex works'), findsOneWidget);
      expect(find.byKey(const Key('pass-primary-action')), findsNothing);
      expect(find.text('No pass yet'), findsNothing);
    });

    testWidgets('payment pending: one step to go, View payment, no card', (
      tester,
    ) async {
      await _pump(
        tester,
        _home(
          _member(pending: {'id': 'p1', 'status': 'pending', 'tier': 'pro'}),
        ),
      );
      expect(find.byKey(const Key('home-hero-pending')), findsOneWidget);
      expect(_heroText(tester), contains('One step to go.'));
      expect(find.text('View payment'), findsOneWidget);
      expect(find.byKey(const Key('pass-primary-action')), findsNothing);
      expect(find.byKey(const Key('home-how-it-works')), findsNothing);
    });

    testWidgets('ended: the date is said once, in the hero', (tester) async {
      await _pump(
        tester,
        _home(_member(subscription: _pass(status: 'expired'))),
      );
      expect(find.byKey(const Key('home-hero-ended')), findsOneWidget);
      expect(_heroText(tester), contains('Ready to come back?'));
      expect(find.textContaining('Your pass ended'), findsOneWidget);
      expect(find.text('Pay again'), findsOneWidget);
      expect(find.text('Explore gyms'), findsOneWidget);
      expect(find.byKey(const Key('pass-primary-action')), findsNothing);
    });

    testWidgets('active: compact hero, Find a gym, card shown, no numbers', (
      tester,
    ) async {
      await _pump(tester, _home(_member(subscription: _pass(), used: 7)));
      expect(find.byKey(const Key('home-hero-pass')), findsOneWidget);
      final hero = tester.widget<FFPhotoHero>(find.byType(FFPhotoHero));
      expect(hero.variant, FFHeroVariant.compact);
      expect(hero.photo, FFHeroPhoto.homePass);
      expect(hero.chip, isNull);
      expect(_heroText(tester), contains('Ready to train?'));
      expect(_heroText(tester), isNot(matches(RegExp(r'\d'))));
      expect(find.text('Find a gym'), findsOneWidget);
      expect(find.byKey(const Key('pass-primary-action')), findsOneWidget);
      expect(find.byKey(const Key('pass-visits-ring')), findsOneWidget);
    });

    testWidgets('ending soon: Fuel chip and next-pass action; Fuel card', (
      tester,
    ) async {
      await _pump(tester, _home(_member(subscription: _pass(daysLeft: 2))));
      expect(find.text('PASS ENDS SOON'), findsOneWidget);
      expect(find.text('Choose your next pass'), findsOneWidget);
      expect(find.text('Find a gym'), findsOneWidget);
      expect(_heroText(tester), isNot(matches(RegExp(r'\d'))));
      // The end date lives on the card only.
      expect(find.textContaining('Your pass ends'), findsOneWidget);
      final ring = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: find.byKey(const Key('pass-visits-ring')),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(ring.color, FFTokens.fuel);
      final badge = tester.widget<FFBadge>(find.byType(FFBadge));
      expect(badge.tone, FFBadgeTone.fuel);
    });

    testWidgets('few visits: Fuel chip; the number only in the ring (dark)', (
      tester,
    ) async {
      await _pump(
        tester,
        _home(_member(subscription: _pass(), used: 15)),
        dark: true,
      );
      expect(find.text('FEW VISITS LEFT'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      final ring = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: find.byKey(const Key('pass-visits-ring')),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(ring.color, FFTokens.fuelOnDark);
    });

    testWidgets('loading: greeting and skeleton, no action, never no-pass', (
      tester,
    ) async {
      await _pump(tester, _home(MemberData()), settle: false);
      expect(find.byKey(const Key('home-hero-loading')), findsOneWidget);
      final hero = tester.widget<FFPhotoHero>(find.byType(FFPhotoHero));
      expect(hero.headlineLoading, isTrue);
      expect(hero.actions, isEmpty);
      expect(_heroText(tester), contains('GOOD EVENING'));
      expect(find.byKey(const Key('pass-summary-loading')), findsOneWidget);
      expect(find.text('No pass yet'), findsNothing);
      expect(find.text('Choose a pass'), findsNothing);
    });

    testWidgets('offline with nothing loaded: tagline, error card, Retry', (
      tester,
    ) async {
      await _pump(tester, _home(MemberData()..offline = true));
      expect(find.byKey(const Key('home-hero-unavailable')), findsOneWidget);
      expect(_heroText(tester), contains('Fitness without limits.'));
      expect(
        tester.widget<FFPhotoHero>(find.byType(FFPhotoHero)).actions,
        isEmpty,
      );
      expect(find.text("We couldn't load your pass."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No pass yet'), findsNothing);
    });

    testWidgets('offline with cached data keeps the cached state', (
      tester,
    ) async {
      await _pump(
        tester,
        _home(_member(subscription: _pass())..offline = true),
      );
      expect(find.byKey(const Key('home-hero-pass')), findsOneWidget);
      expect(find.byKey(const Key('pass-primary-action')), findsOneWidget);
    });

    testWidgets('a non-network failure shows the generic error and Retry', (
      tester,
    ) async {
      await _pump(tester, _home(MemberData()..meLoadFailed = true));
      expect(find.byKey(const Key('home-hero-unavailable')), findsOneWidget);
      expect(find.byKey(const Key('pass-summary-error')), findsOneWidget);
      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('light theme: the sheet overlaps the hero by 24px', (
      tester,
    ) async {
      await _pump(tester, _home(_member()));
      final sheetTop = tester.getTopLeft(
        find.byKey(const Key('ff-hero-sheet')),
      );
      final heroBottom = tester.getBottomLeft(find.byType(FFPhotoHero));
      expect(heroBottom.dy - sheetTop.dy, closeTo(24, 0.5));
    });

    testWidgets('desktop (>= 840): a rounded panel banner, max 960 wide', (
      tester,
    ) async {
      await _pump(tester, _home(_member()), width: 1280, height: 900);
      final hero = tester.widget<FFPhotoHero>(find.byType(FFPhotoHero));
      expect(hero.variant, FFHeroVariant.panel);
      expect(hero.rounded, isTrue);
      expect(
        tester.getSize(find.byType(FFPhotoHero)).width,
        lessThanOrEqualTo(960),
      );
    });
  });

  group('Scrim rule (§5.2)', () {
    Widget hero() => const Scaffold(
      body: SingleChildScrollView(
        child: FFPhotoHero(
          photo: FFHeroPhoto.signIn,
          minHeight: 300,
          topInset: 80,
          eyebrow: 'Sign in',
          headlineLead: 'Karibu',
          headlineAccent: 'tena.',
          subline: 'Pasi yako, QR yako na maendeleo yako, mahali pamoja.',
          chip: 'PASI INAISHA KARIBUNI',
        ),
      ),
    );

    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('the 0.80 stop sits >= 24px above all text at ${scale}x', (
        tester,
      ) async {
        await _pump(tester, hero(), textScale: scale, width: 360);
        final zone = find.byKey(const Key('ff-hero-text-zone'));
        final zoneBox = tester.widget<ColoredBox>(zone);
        expect(zoneBox.color.a, closeTo(FFTokens.heroScrimText, 0.01));
        final stopY = tester.getTopLeft(zone).dy;
        // Every piece of text in the hero is inside the 80% zone, and the
        // first line starts at least 24px below the stop.
        final texts = find.descendant(
          of: find.byType(FFPhotoHero),
          matching: find.byType(RichText),
        );
        expect(texts, findsWidgets);
        for (final e in texts.evaluate()) {
          final top = tester.getTopLeft(find.byWidget(e.widget)).dy;
          expect(top - stopY, greaterThanOrEqualTo(24 - 0.01));
          expect(
            find.descendant(of: zone, matching: find.byWidget(e.widget)),
            findsOneWidget,
          );
        }
        // The fade zone above holds no text and runs 50% -> 80%.
        final fade = find.byKey(const Key('ff-hero-fade-zone'));
        expect(
          find.descendant(of: fade, matching: find.byType(RichText)),
          findsNothing,
        );
        final g =
            (tester.widget<DecoratedBox>(fade).decoration as BoxDecoration)
                    .gradient
                as LinearGradient;
        expect(g.colors.first.a, closeTo(FFTokens.heroScrimTop, 0.01));
        expect(g.colors.last.a, closeTo(FFTokens.heroScrimText, 0.01));
        expect(tester.takeException(), isNull);
      });
    }

    test('scrim tokens meet the measured contrast over pure white', () {
      double ratio(Color a, Color b) {
        final la = a.computeLuminance(), lb = b.computeLuminance();
        return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
      }

      final zone = Color.alphaBlend(
        FFTokens.heroScrim.withValues(alpha: FFTokens.heroScrimText),
        Colors.white,
      );
      expect(ratio(FFTokens.heroText, zone), greaterThanOrEqualTo(10.5));
      expect(ratio(FFTokens.heroTextBody, zone), greaterThanOrEqualTo(7.8));
      expect(ratio(FFTokens.heroAccentDark, zone), greaterThanOrEqualTo(4.5));
      expect(ratio(FFTokens.heroAccentLight, zone), greaterThanOrEqualTo(3));
      expect(ratio(FFTokens.heroChipFuelText, zone), greaterThanOrEqualTo(4.5));
      final top = Color.alphaBlend(
        FFTokens.heroScrim.withValues(alpha: FFTokens.heroScrimTop),
        Colors.white,
      );
      expect(ratio(FFTokens.heroText, top), greaterThanOrEqualTo(3));
    });

    testWidgets('high contrast: navy ground, no photo, same text', (
      tester,
    ) async {
      await _pump(tester, hero(), highContrast: true);
      expect(find.byKey(const Key('ff-hero-photo')), findsNothing);
      expect(find.byKey(const Key('ff-hero-placeholder')), findsOneWidget);
      expect(_heroText(tester), contains('Karibu tena.'));
    });

    testWidgets('photo excluded from semantics; text is one header node', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, hero());
      expect(find.byKey(const Key('ff-hero-photo')), findsOneWidget);
      final node = tester.getSemantics(find.byKey(const Key('ff-hero-text')));
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isHeader, isTrue);
      expect(data.label, contains('Karibu tena.'));
      expect(data.label, contains('PASI INAISHA KARIBUNI'));
      handle.dispose();
    });

    testWidgets('accent: Volt on dark, brand-500 on light', (tester) async {
      Color accentColor() {
        final rich = tester.widget<RichText>(
          find.descendant(
            of: find.byKey(const Key('ff-hero-headline')),
            matching: find.byType(RichText),
          ),
        );
        Color? found;
        rich.text.visitChildren((span) {
          if (span is TextSpan && span.text == 'tena.') {
            found = span.style?.color;
            return false;
          }
          return true;
        });
        return found!;
      }

      await _pump(tester, hero(), dark: true);
      expect(accentColor(), FFTokens.volt);
      await _pump(tester, hero());
      expect(accentColor(), FFTokens.fgBrand);
    });
  });

  group('Pre-sign-in screens under the flag', () {
    testWidgets('language: English tagline only; Continue follows choice', (
      tester,
    ) async {
      await _pump(tester, const LanguageScreen());
      expect(find.byType(FFPhotoHero), findsOneWidget);
      expect(_heroText(tester), contains('Fitness without limits.'));
      // Owner 2026-10-19 (spec §19, AC-A10): no Swahili tagline line.
      expect(_heroText(tester), isNot(contains('Pamoja')));
      expect(find.text('Continue · Endelea'), findsOneWidget);
      await tester.tap(find.byKey(const Key('langKiswahili')));
      await tester.pumpAndSettle();
      expect(find.text('Endelea'), findsOneWidget);
      await tester.tap(find.byKey(const Key('langEnglish')));
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      expect(find.textContaining('Dar es Salaam'), findsNothing);
    });

    testWidgets('sign in: hero carries the title; form keys unchanged', (
      tester,
    ) async {
      await _pump(tester, const AuthScreen(enableFirebaseRecovery: false));
      expect(_heroText(tester), contains('Welcome back.'));
      expect(_heroText(tester), contains('SIGN IN'));
      expect(find.byKey(const Key('login-identifier')), findsOneWidget);
      expect(find.byKey(const Key('login-continue')), findsOneWidget);
      expect(find.byKey(const Key('ff-wordmark')), findsOneWidget);
    });

    testWidgets('role: small hero, canon role colours, radio tiles', (
      tester,
    ) async {
      await _pump(tester, const RoleScreen());
      expect(_heroText(tester), contains('Welcome to FitFlex'));
      expect(find.byType(FFChoiceTile), findsNWidgets(5));
      Color iconColor(String label) => tester
          .widget<Icon>(
            find.descendant(
              of: find.widgetWithText(FFChoiceTile, label),
              matching: find.byType(Icon),
            ),
          )
          .color!;
      expect(iconColor('Personal Trainer'), FFTokens.roleTrainer);
      expect(iconColor('Gym Member'), FFTokens.roleMemberLight);
      // The first two tiles are visible without scrolling on 390x844.
      final second = tester.getBottomLeft(find.byType(FFChoiceTile).at(1));
      expect(second.dy, lessThan(844));
    });

    for (final (role, headline) in [
      ('member', 'One pass. Many gyms.'),
      ('gym_owner', 'Grow your gym.'),
      ('trainer', 'Coach on your terms.'),
      ('vendor', 'Sell to people who train.'),
      ('gym_staff', 'Welcome to the team.'),
    ]) {
      testWidgets('sign up headline for $role', (tester) async {
        await _pump(tester, const SignUpScreen(), role: role);
        expect(_heroText(tester), contains(headline));
      });
    }
  });

  group('Flag off: unchanged screens', () {
    setUp(() => debugPhotoHeroUiOverride = false);

    testWidgets('Home has no photo hero and keeps the page header and card', (
      tester,
    ) async {
      await _pump(tester, _home(_member()));
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(find.byType(FFPageHeader), findsOneWidget);
      expect(find.text('Amina'), findsOneWidget);
      expect(find.text('Good evening'), findsOneWidget);
      expect(find.text('No pass yet'), findsOneWidget);
      expect(find.byKey(const Key('home-how-it-works')), findsNothing);
    });

    testWidgets('Home loading with a failed profile keeps the spinner', (
      tester,
    ) async {
      await _pump(
        tester,
        _home(MemberData()..meLoadFailed = true),
        settle: false,
      );
      expect(find.byKey(const Key('pass-summary-loading')), findsOneWidget);
    });

    testWidgets('Home low visits keeps the amber ring', (tester) async {
      await _pump(tester, _home(_member(subscription: _pass(), used: 15)));
      final ring = tester.widget<CircularProgressIndicator>(
        find.descendant(
          of: find.byKey(const Key('pass-visits-ring')),
          matching: find.byType(CircularProgressIndicator),
        ),
      );
      expect(ring.color, isNot(FFTokens.fuel));
    });

    testWidgets('Sign in has its title and form, no hero', (tester) async {
      await _pump(tester, const AuthScreen(enableFirebaseRecovery: false));
      expect(find.byType(FFPhotoHero), findsNothing);
      expect(find.byType(FFPhotoHeroPage), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.byKey(const Key('login-identifier')), findsOneWidget);
      expect(find.byKey(const Key('login-continue')), findsOneWidget);
    });

    testWidgets('Language, Role and Sign up have no hero', (tester) async {
      for (final screen in const [
        LanguageScreen(),
        RoleScreen(),
        SignUpScreen(),
      ]) {
        await _pump(tester, screen);
        expect(find.byType(FFPhotoHero), findsNothing);
      }
      expect(find.text('Sign up'), findsOneWidget);
    });
  });

  group('Swahili at 1.3x on a 360px phone', () {
    final screens = <String, Widget Function()>{
      'language': () => const LanguageScreen(),
      'sign in': () => const AuthScreen(enableFirebaseRecovery: false),
      'role': () => const RoleScreen(),
      'sign up': () => const SignUpScreen(),
      'home none': () => _home(_member()),
      'home pending': () => _home(
        _member(pending: {'id': 'p1', 'status': 'pending', 'tier': 'pro'}),
      ),
      'home ended': () =>
          _home(_member(subscription: _pass(status: 'expired'))),
      'home ending soon': () =>
          _home(_member(subscription: _pass(daysLeft: 2))),
      'home few visits': () => _home(_member(subscription: _pass(), used: 15)),
      'home offline': () => _home(MemberData()..offline = true),
    };
    for (final MapEntry(:key, :value) in screens.entries) {
      for (final dark in [false, true]) {
        testWidgets('$key (${dark ? 'dark' : 'light'}) does not overflow', (
          tester,
        ) async {
          await _pump(
            tester,
            value(),
            lang: 'sw',
            dark: dark,
            width: 360,
            height: 640,
            textScale: 1.3,
            role: 'vendor',
          );
          expect(tester.takeException(), isNull);
          expect(find.byType(FFPhotoHero), findsOneWidget);
        });
      }
    }
  });

  test('every new hero string has English and Swahili', () {
    final en = FFLocale.keysOf('en');
    final sw = FFLocale.keysOf('sw');
    final keys = en.where(
      (k) =>
          k.startsWith('hero.') ||
          k.startsWith('home.hero.') ||
          k.startsWith('home.how.'),
    );
    expect(keys.length, greaterThanOrEqualTo(35));
    const sameByDesign = {
      'hero.eyebrow.brand',
      'hero.lang.prompt',
      'hero.lang.continueBoth',
    };
    for (final k in keys) {
      expect(sw, contains(k), reason: k);
      if (!sameByDesign.contains(k)) {
        expect(
          FFLocale.textOf('sw', k),
          isNot(FFLocale.textOf('en', k)),
          reason: k,
        );
      }
    }
    // Owner 2026-10-19: no place footer anywhere (the hero.footer.place /
    // login.hero.footer keys and the "Dar es Salaam · Tanzania" line). The
    // photo footer band's sign-off (footer.*, decision D-2) is not one.
    expect(
      en.where((k) => k.contains('footer') && !k.startsWith('footer.')),
      isEmpty,
    );
    for (final lang in ['en', 'sw']) {
      for (final k in FFLocale.keysOf(
        lang,
      ).where((k) => k.startsWith('footer.'))) {
        expect(FFLocale.textOf(lang, k), isNot(contains('Dar es Salaam')));
      }
    }
  });
}
