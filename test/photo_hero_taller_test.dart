// Taller photo heroes behind PHOTO_HERO_UI (owner 2026-10-20, spec §5.3 of
// docs/design/photo-hero-screens.md): more clear photo between the bar band
// and the ramp on Sign in, Create account, Choose role and Profile, while
// Continue and the first three role tiles stay on screen, the PIN keypad
// and Activity keep their heights, and the scrim rule holds at every scale.
// Sign in's first must-see control is the "Create account" link under
// Continue (owner 2026-10-20): the photo is trimmed so it fits on screen.
//
// Real Inter fonts are loaded so text heights match a phone.

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/auth_screen.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/pin_flows.dart';
import 'package:fitflexmobile/screens/role_screen.dart';
import 'package:fitflexmobile/screens/sign_up_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
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

/// A member with a profile, for the shell's Profile and Activity tabs.
class _MeApi extends ApiClient {
  _MeApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<Map<String, dynamic>> me() async => {
    'user': {
      'id': 'm1',
      'displayName': 'Amina Juma',
      'onboardingCompleted': true,
    },
    'visitsUsed': 7,
    'visitCap': 18,
  };
}

/// A phone: 390x844 with an iPhone's insets (47 top, 34 bottom) by default.
class _Phone {
  const _Phone(this.size, {this.top = 47, this.bottom = 34});
  final Size size;
  final double top;
  final double bottom;

  @override
  String toString() =>
      '${size.width.toInt()}x${size.height.toInt()}'
      '${top == 0 ? ' (no insets)' : ''}';
}

const _iphone = _Phone(Size(390, 844));
const _bare = _Phone(Size(390, 844), top: 0, bottom: 0);

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  _Phone phone = _iphone,
  String lang = 'en',
  bool dark = false,
  double textScale = 1,
  String role = 'member',
  ApiClient? api,
  String? shellLocation,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = phone.size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: phone.top, bottom: phone.bottom);
  addTearDown(tester.view.reset);
  final client = api ?? ApiClient(baseUrl: 'http://localhost:0');
  final auth = AuthState(client);
  await auth.setRole(role);
  final router = shellLocation == null
      ? GoRouter(
          routes: [GoRoute(path: '/', builder: (_, _) => page)],
        )
      : GoRouter(
          initialLocation: shellLocation,
          routes: [
            ShellRoute(
              builder: (context, state, child) =>
                  MemberShell(state: state, child: child),
              routes: [
                GoRoute(path: '/member', builder: (_, _) => const SizedBox()),
                GoRoute(path: shellLocation, builder: (_, _) => page),
              ],
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
  if (shellLocation == null) {
    await tester.pumpAndSettle();
  } else {
    // The shell keeps loading spinners running: pump past the fades.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  }
}

/// Unmounts a shell page and lets its timers finish.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

String _tr(String lang, String key) => FFLocale.textOf(lang, key)!;

/// The "Don't have an account? Create account" link on Sign in.
final _link = find.byKey(const Key('login-create-account-link'));

/// Clear photo on Sign in at 390x844 with an iPhone's insets, at 1.0x, now
/// that the Create account link must be on screen (reported in the PR).
const _signInClear390 = 125.0;

/// Continue on Sign in / Create account (an upper-case label).
Finder _continue(String lang) => find.ancestor(
  of: find.text(_tr(lang, 'lang.continue').toUpperCase()),
  matching: find.byType(FilledButton),
);

double _clear(WidgetTester tester) => heroClearPhoto(tester).clear;

FFPhotoHero _hero(WidgetTester tester) =>
    tester.widget<FFPhotoHero>(find.byType(FFPhotoHero));

const _signUpRoles = ['member', 'gym_owner', 'trainer', 'vendor', 'gym_staff'];

void main() {
  setUpAll(loadAppFonts);
  setUp(() => debugPhotoHeroUiOverride = true);
  tearDown(() => debugPhotoHeroUiOverride = null);

  // ── sizing rules ───────────────────────────────────────────────────────

  group('heroTallClearTarget / heroTallFade', () {
    test('target: share of the viewport, clamped; none below 760', () {
      expect(heroTallClearTarget(844, 1), closeTo(160.36, 0.01));
      expect(heroTallClearTarget(932, 1), closeTo(177.08, 0.01));
      expect(heroTallClearTarget(760, 1), closeTo(144.4, 0.01));
      expect(heroTallClearTarget(1200, 1), FFTokens.heroTallClearMax);
      expect(heroTallClearTarget(759, 1), 0);
      // Larger text takes room from the photo first.
      expect(heroTallClearTarget(844, 2), closeTo(80.18, 0.01));
      expect(heroTallClearTarget(844, 0.8), closeTo(160.36, 0.01));
    });

    test('hosted bar: clear = fade - lead-in - bar band', () {
      final f = heroTallFade(
        text: 200,
        topInset: 103,
        barHosted: true,
        clearPhoto: 160,
      );
      expect(f, 103 + 32 + 160 + 48);
      expect(heroTallClearOf(f, 200, 103, true), 160);
    });

    test('own band (cards): the 16% band is allowed for', () {
      final f = heroTallFade(
        text: 212,
        topInset: 0,
        barHosted: false,
        clearPhoto: 120,
      );
      expect(heroTallClearOf(f, 212, 0, false), closeTo(120, 1e-9));
    });

    test('cap: the clear photo gives way, the text never does', () {
      // Room for 60px of the 160 asked for.
      final f = heroTallFade(
        text: 200,
        topInset: 103,
        barHosted: true,
        clearPhoto: 160,
        maxHeight: 103 + 32 + 48 + 60 + 200,
      );
      expect(heroTallClearOf(f, 200, 103, true), closeTo(60, 1e-9));
      // No room left: today's height, not a taller hero with no photo.
      expect(
        heroTallFade(
          text: 400,
          topInset: 103,
          barHosted: true,
          clearPhoto: 160,
          minHeight: 320,
          maxHeight: 500,
        ),
        103,
      );
      expect(
        heroTallFade(
          text: 150,
          topInset: 103,
          barHosted: true,
          clearPhoto: 160,
          minHeight: 320,
          maxHeight: 300,
        ),
        320 - 150,
      );
    });
  });

  // ── Sign in, Create account, Choose role at 1.0x ───────────────────────

  for (final phone in [_iphone, _bare]) {
    for (final lang in ['en', 'sw']) {
      for (final dark in [false, true]) {
        final tag = '$phone $lang ${dark ? 'dark' : 'light'}';

        testWidgets('Sign in $tag: clear photo, Continue and the Create '
            'account link on screen', (tester) async {
          await _pump(
            tester,
            const AuthScreen(enableFirebaseRecovery: false),
            phone: phone,
            lang: lang,
            dark: dark,
          );
          // With an iPhone's insets the photo gives way to the link; with
          // none there is room for the full target.
          expect(
            _clear(tester),
            greaterThanOrEqualTo(phone.top > 0 ? _signInClear390 - 0.01 : 160),
          );
          expect(
            tester.getRect(_continue(lang)).bottom,
            lessThanOrEqualTo(phone.size.height),
          );
          expect(
            tester.getRect(_link).bottom,
            lessThanOrEqualTo(phone.size.height),
          );
          expectHeroScrimRule(tester);
          expect(tester.takeException(), isNull);
        });

        testWidgets('Create account $tag: every role >= 150px clear photo, '
            'Continue on screen', (tester) async {
          for (final role in _signUpRoles) {
            await _pump(
              tester,
              const SignUpScreen(),
              phone: phone,
              lang: lang,
              dark: dark,
              role: role,
            );
            expect(_clear(tester), greaterThanOrEqualTo(150), reason: role);
            expect(
              tester.getRect(_continue(lang)).bottom,
              lessThanOrEqualTo(phone.size.height),
              reason: role,
            );
            expectHeroScrimRule(tester);
            await tester.pumpWidget(const SizedBox());
          }
        });

        testWidgets('Choose role $tag: >= 150px clear photo, first three '
            'tiles on screen', (tester) async {
          await _pump(
            tester,
            const RoleScreen(),
            phone: phone,
            lang: lang,
            dark: dark,
          );
          expect(_clear(tester), greaterThanOrEqualTo(150));
          expect(
            tester.getRect(find.byType(FFChoiceTile).at(2)).bottom,
            lessThanOrEqualTo(phone.size.height),
          );
          expectHeroScrimRule(tester);
        });
      }
    }
  }

  // ── larger text ────────────────────────────────────────────────────────

  group('larger text: the photo gives way, never below zero', () {
    for (final scale in [1.3, 2.0]) {
      for (final lang in ['en', 'sw']) {
        testWidgets('Sign in, Create account, Choose role at ${scale}x '
            '($lang)', (tester) async {
          for (final (page, role) in <(Widget, String)>[
            (const AuthScreen(enableFirebaseRecovery: false), 'member'),
            for (final r in _signUpRoles) (const SignUpScreen(), r),
            (const RoleScreen(), 'member'),
          ]) {
            await _pump(tester, page, lang: lang, textScale: scale, role: role);
            final what = '${page.runtimeType} $role';
            final c = _clear(tester);
            expect(c, greaterThanOrEqualTo(0), reason: what);
            expect(
              c,
              lessThanOrEqualTo(heroTallClearTarget(844, scale) + 0.01),
              reason: what,
            );
            expectHeroScrimRule(tester);
            // At 1.3x the first control is still on screen (Role keeps
            // today's height there, whose third tile is on screen too).
            if (scale == 1.3) {
              final first = page is RoleScreen
                  ? find.byType(FFChoiceTile).at(2)
                  : _continue(lang);
              expect(
                tester.getRect(first).bottom,
                lessThanOrEqualTo(844),
                reason: what,
              );
            }
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }

    testWidgets('2.0x: Sign in keeps today\'s height (no growth without '
        'clear photo; the Create account link scrolls)', (tester) async {
      await _pump(
        tester,
        const AuthScreen(enableFirebaseRecovery: false),
        textScale: 2,
      );
      expect(_clear(tester), 0);
      final text = tester.getSize(find.byKey(const Key('ff-hero-text-zone')));
      final fade = tester.getSize(find.byKey(const Key('ff-hero-fade-zone')));
      const topInset = 47 + kToolbarHeight;
      final today = 844 * 0.38 - text.height;
      expect(fade.height, closeTo(today > topInset ? today : topInset, 0.01));
      // No photo left to give: the link is reached by scrolling.
      expect(tester.getRect(_link).top, greaterThan(844));
    });
  });

  // ── Sign in: the Create account link stays on screen ───────────────────

  group('Sign in: Create account link on screen (owner 2026-10-20)', () {
    const tall = _Phone(Size(430, 932), top: 59, bottom: 34);

    for (final lang in ['en', 'sw']) {
      for (final dark in [false, true]) {
        final tag = '$lang ${dark ? 'dark' : 'light'}';

        testWidgets('390x844 1.0x $tag: link fully visible, Continue '
            'visible, >= ${_signInClear390.toInt()}px clear', (tester) async {
          await _pump(
            tester,
            const AuthScreen(enableFirebaseRecovery: false),
            lang: lang,
            dark: dark,
          );
          final link = tester.getRect(_link);
          expect(link.top, greaterThanOrEqualTo(0));
          expect(link.bottom, lessThanOrEqualTo(844));
          expect(tester.getRect(_continue(lang)).bottom, lessThan(link.top));
          final c = _clear(tester);
          expect(c, greaterThanOrEqualTo(_signInClear390 - 0.01));
          // Trimmed only as much as needed: never below the owner's 120.
          expect(c, greaterThanOrEqualTo(120));
          expectHeroScrimRule(tester);
        });

        testWidgets('430x932 1.0x $tag: link visible, full clear target', (
          tester,
        ) async {
          await _pump(
            tester,
            const AuthScreen(enableFirebaseRecovery: false),
            phone: tall,
            lang: lang,
            dark: dark,
          );
          expect(tester.getRect(_link).bottom, lessThanOrEqualTo(932));
          expect(
            tester.getRect(_continue(lang)).bottom,
            lessThanOrEqualTo(932),
          );
          // The link already fits: no trim on this phone.
          expect(_clear(tester), closeTo(heroTallClearTarget(932, 1), 0.01));
        });
      }

      for (final phone in [_iphone, tall]) {
        testWidgets('$phone 1.3x $lang: photo left, so the link is on '
            'screen', (tester) async {
          await _pump(
            tester,
            const AuthScreen(enableFirebaseRecovery: false),
            phone: phone,
            lang: lang,
            textScale: 1.3,
          );
          // The link may only scroll off when no photo is left (then the
          // hero keeps today's height: see the 2.0x test above). At 1.3x
          // both phones still have photo, so the link must be on screen.
          expect(_clear(tester), greaterThan(0));
          expect(
            tester.getRect(_link).bottom,
            lessThanOrEqualTo(phone.size.height),
          );
          expect(
            tester.getRect(_continue(lang)).bottom,
            lessThanOrEqualTo(phone.size.height),
          );
          expectHeroScrimRule(tester);
        });
      }
    }

    testWidgets('Create account has no "Sign in" link: Continue stays its '
        'must-see control', (tester) async {
      for (final lang in ['en', 'sw']) {
        await _pump(tester, const SignUpScreen(), lang: lang);
        expect(find.text(_tr(lang, 'auth.haveAccount')), findsNothing);
        expect(_clear(tester), greaterThanOrEqualTo(150));
        expect(tester.getRect(_continue(lang)).bottom, lessThanOrEqualTo(844));
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  // ── where the taller hero does not apply ───────────────────────────────

  group('limits', () {
    testWidgets('below 760px tall: today\'s heights', (tester) async {
      const short = _Phone(Size(390, 740), top: 24, bottom: 0);
      await _pump(
        tester,
        const AuthScreen(enableFirebaseRecovery: false),
        phone: short,
      );
      expect(_hero(tester).clearPhoto, 0);
      expect(_hero(tester).maxHeight, double.infinity);
      expect(
        tester.getSize(find.byType(FFPhotoHero)).height,
        greaterThanOrEqualTo(740 * 0.34 - 0.01),
      );
    });

    testWidgets('tablet (600+): today\'s band, no taller hero', (tester) async {
      await _pump(
        tester,
        const AuthScreen(enableFirebaseRecovery: false),
        phone: const _Phone(Size(800, 1100), top: 24, bottom: 0),
      );
      expect(_hero(tester).clearPhoto, 0);
    });

    testWidgets('taller phone (430x932): more clear photo', (tester) async {
      await _pump(
        tester,
        const AuthScreen(enableFirebaseRecovery: false),
        phone: const _Phone(Size(430, 932), top: 59, bottom: 34),
      );
      expect(_clear(tester), greaterThanOrEqualTo(170));
      expect(tester.getRect(_continue('en')).bottom, lessThanOrEqualTo(932));
      expect(tester.getRect(_link).bottom, lessThanOrEqualTo(932));
    });

    testWidgets('PIN entry: the keypad sets the height (no taller hero)', (
      tester,
    ) async {
      final api = RecordingApi();
      await api.run(() async {
        await _pump(
          tester,
          const EmailAuthScreen(
            initialEmail: 'qa@example.test',
            initialMode: EmailAuthMode.signIn,
          ),
        );
        // Not the taller hero's target: the compact PIN hero's own floor
        // (owner 2026-10-22), with no cap from a content reserve.
        expect(_hero(tester).clearPhoto, pinHeroClearPhoto);
        expect(_hero(tester).maxHeight, double.infinity);
        final one = find
            .ancestor(of: find.text('1'), matching: find.byType(Material))
            .first;
        expect(tester.getSize(one).height, closeTo(52, 0.5));
        final ok = find
            .ancestor(of: find.text('OK'), matching: find.byType(Material))
            .first;
        expect(tester.getRect(ok).bottom, lessThanOrEqualTo(844));
        await _unmount(tester);
      });
    });
  });

  // ── Profile and Activity (member shell) ────────────────────────────────

  group('member shell', () {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.3, 2.0]) {
        testWidgets('Profile ${dark ? 'dark' : 'light'} ${scale}x: clear '
            'photo above the name, scrim rule', (tester) async {
          await _pump(
            tester,
            const MemberProfileTab(),
            api: _MeApi(),
            dark: dark,
            textScale: scale,
            shellLocation: '/member/profile',
          );
          final c = _clear(tester);
          if (scale == 1) {
            expect(c, greaterThanOrEqualTo(150));
          } else {
            expect(c, greaterThan(0));
            expect(
              c,
              lessThanOrEqualTo(heroTallClearTarget(844, scale) + 0.01),
            );
          }
          expectHeroScrimRule(tester);
          await _unmount(tester);
        });
      }
    }

    // Owner 2026-10-22: Activity grows for clear photo above its text, as
    // far as the switcher can stay above 55% of the screen.
    testWidgets('Activity: clear photo, switcher stays above 55%', (
      tester,
    ) async {
      await _pump(
        tester,
        const MemberActivityTab(),
        api: _MeApi(),
        shellLocation: '/member/activity',
      );
      expect(_hero(tester).clearPhoto, FFTokens.heroBandClearPhoto);
      // The shell's activity is the sample here: room for its badge too,
      // which leaves too little clear photo, so the hero keeps today's
      // height (the sample-free case is in photo_hero_bands_test.dart).
      expect(_hero(tester).maxHeight, closeTo(844 * 0.55 - 8 - 28, 0.01));
      expect(find.byKey(const Key('activity-sample-badge')), findsOneWidget);
      expect(
        tester.getRect(find.byKey(const Key('activity-sections'))).top,
        lessThanOrEqualTo(844 * 0.55 + 0.01),
      );
      await _unmount(tester);
    });
  });

  // ── flag off ───────────────────────────────────────────────────────────

  group('flag off: unchanged', () {
    setUp(() => debugPhotoHeroUiOverride = false);

    testWidgets('Sign in, Create account, Choose role: no hero', (
      tester,
    ) async {
      for (final page in const <Widget>[
        AuthScreen(enableFirebaseRecovery: false),
        SignUpScreen(),
        RoleScreen(),
      ]) {
        await _pump(tester, page);
        expect(find.byType(FFPhotoHero), findsNothing);
        expect(find.byType(FFPhotoHeroPage), findsNothing);
        expect(find.byKey(const Key('ff-photo-bar-scrim')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Sign in: Continue and the link where they were', (
      tester,
    ) async {
      for (final lang in ['en', 'sw']) {
        await _pump(
          tester,
          const AuthScreen(enableFirebaseRecovery: false),
          lang: lang,
        );
        // Measured on release-candidate before this change.
        expect(tester.getRect(_link), const Rect.fromLTRB(24, 500, 366, 548));
        expect(
          tester.getRect(find.byKey(const Key('login-continue'))),
          const Rect.fromLTRB(24, 424, 366, 476),
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Profile: no hero', (tester) async {
      await _pump(
        tester,
        const MemberProfileTab(),
        api: _MeApi(),
        shellLocation: '/member/profile',
      );
      expect(find.byType(FFPhotoHero), findsNothing);
      await _unmount(tester);
    });
  });
}
