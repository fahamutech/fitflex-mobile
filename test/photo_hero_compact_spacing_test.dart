// Compact Language and PIN heroes behind PHOTO_HERO_UI (owner on preview 7,
// 2026-10-22: "the spacing between the hero photo and the functions is so
// wide that on the Language & PIN pages, the inputs and CTAs are placed so
// much at the bottom. Can you squeeze them a bit up?").
// - Language: the hero is about 42% of the screen (it keeps 80px of clear
//   photo from 760px tall); the prompt, both tiles and Continue follow it.
// - PIN entry and the PIN flows' keypad steps: the hero keeps a compact
//   height, the dots and keypad follow it, and spare room goes below the
//   links; when there is none, the photo's top edge gives way.
// - 44px keys on screen at every size; the scrim rule; flag off unchanged.
//
// Real Inter fonts are loaded so text heights match a phone.

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/screens/language_screen.dart';
import 'package:fitflexmobile/screens/pin_flows.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

import 'support/hero_scrim.dart';
import 'support/recording_api.dart';

// ── harness ─────────────────────────────────────────────────────────────

/// A phone with an iPhone's insets.
class _Phone {
  const _Phone(this.width, this.height, {this.top = 47, this.bottom = 34});
  final double width;
  final double height;
  final double top;
  final double bottom;

  Size get size => Size(width, height);

  @override
  String toString() => '${width.toInt()}x${height.toInt()}';
}

const _p390 = _Phone(390, 844);
const _p430 = _Phone(430, 932, top: 59);
const _p360 = _Phone(360, 640, top: 24, bottom: 0);
const _p700 = _Phone(390, 700, top: 24, bottom: 0);

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  _Phone phone = _p390,
  String lang = 'en',
  bool dark = false,
  double textScale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = phone.size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: phone.top, bottom: phone.bottom);
  addTearDown(tester.view.reset);
  final client = ApiClient(baseUrl: 'http://localhost:0');
  final auth = AuthState(client);
  await auth.setRole('member');
  await tester.pumpWidget(
    AppScope(
      api: client,
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
            builder: (context, c) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: c!,
            ),
            home: page,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Unmounts the page and lets its timers finish.
Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

/// Where the hero visibly ends: its own bottom edge on the dark ground, the
/// top of the light sheet that overlaps it.
double _heroBottom(WidgetTester tester) {
  final sheet = find.byKey(const Key('ff-hero-sheet'));
  return sheet.evaluate().isNotEmpty
      ? tester.getRect(sheet).top
      : tester.getRect(find.byType(FFPhotoHero)).bottom;
}

/// A keypad key (its Material) by label.
Finder _key(String label) => find
    .ancestor(
      of: find.descendant(
        of: find.byType(CustomKeypad),
        matching: find.text(label),
      ),
      matching: find.byType(Material),
    )
    .first;

/// Every key at least 44x44, fully on screen and tappable where drawn.
void _expectKeys(WidgetTester tester, Size size) {
  for (final label in [for (var d = 0; d <= 9; d++) '$d', 'OK']) {
    final key = _key(label);
    final r = tester.getRect(key);
    expect(r.height, greaterThanOrEqualTo(44), reason: '$label $r');
    expect(r.width, greaterThanOrEqualTo(44), reason: '$label $r');
    expect(r.top, greaterThanOrEqualTo(0), reason: '$label $r');
    expect(r.bottom, lessThanOrEqualTo(size.height), reason: '$label $r');
    expect(
      tester
          .hitTestOnBinding(r.center)
          .path
          .any((e) => e.target == tester.renderObject(key)),
      isTrue,
      reason: '$label not hittable',
    );
  }
}

const _pinEntry = EmailAuthScreen(
  initialEmail: 'qa@example.test',
  initialMode: EmailAuthMode.signIn,
);
const _pinCreate = EmailAuthScreen(
  initialEmail: 'qa@example.test',
  initialMode: EmailAuthMode.signUp,
);
const _pinSetup = PinSetupScreen(
  setupToken: 't',
  contact: '0712345678',
  needsCode: false,
  needsNewPin: true,
  currentPin: '12345',
);

const _lPrompt = Key('lang-prompt');
const _lSw = Key('langKiswahili');
const _lContinue = Key('lang-continue');

void main() {
  setUpAll(loadAppFonts);
  setUp(() => debugPhotoHeroUiOverride = true);
  tearDown(() => debugPhotoHeroUiOverride = null);

  // ── Language ───────────────────────────────────────────────────────────

  group('Language: compact hero, content right under it', () {
    for (final phone in [_p390, _p430]) {
      for (final lang in ['en', 'sw']) {
        for (final dark in [false, true]) {
          final tag = '$phone $lang ${dark ? 'dark' : 'light'}';
          testWidgets('$tag: hero <= 48%, >= 80px clear photo, prompt and '
              'Continue close, scrim rule', (tester) async {
            await _pump(
              tester,
              const LanguageScreen(),
              phone: phone,
              lang: lang,
              dark: dark,
            );
            final h = phone.height;
            final bottom = _heroBottom(tester);
            // Was 56% (473px at 844); now 42% of the screen, or just what
            // the headline and 80px of clear photo need (48% at 390x844,
            // where the headline takes two lines).
            expect(bottom, lessThanOrEqualTo(h * 0.483), reason: '$bottom');
            expect(
              bottom,
              greaterThanOrEqualTo(h * languageHeroFraction - 24 - 0.01),
            );
            expect(
              heroClearPhoto(tester).clear,
              greaterThanOrEqualTo(languageHeroClearPhoto - 0.01),
            );
            final prompt = tester.getRect(find.byKey(_lPrompt));
            expect(prompt.top - bottom, inInclusiveRange(0, 32));
            final tile = tester.getRect(find.byKey(_lSw));
            expect(tile.height, greaterThanOrEqualTo(64));
            final cont = tester.getRect(find.byKey(_lContinue));
            // Continue follows the tiles; it is not pinned to the bottom.
            expect(cont.top - tile.bottom, inInclusiveRange(0, 32));
            expect(cont.bottom, lessThanOrEqualTo(h - phone.bottom - 24));
            expect(h - cont.bottom, greaterThan(100));
            expectHeroScrimRule(tester);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }

    for (final phone in [_p360, _p700]) {
      testWidgets('$phone: no overflow, Continue reachable (scrolls if '
          'needed)', (tester) async {
        await _pump(tester, const LanguageScreen(), phone: phone, lang: 'sw');
        expect(tester.takeException(), isNull);
        final prompt = tester.getRect(find.byKey(_lPrompt));
        expect(prompt.top - _heroBottom(tester), inInclusiveRange(0, 32));
        await tester.ensureVisible(find.byKey(_lContinue));
        await tester.pumpAndSettle();
        expect(
          tester.getRect(find.byKey(_lContinue)).bottom,
          lessThanOrEqualTo(phone.height),
        );
        expectHeroScrimRule(tester);
      });
    }

    testWidgets('1.3x text: the clear photo gives way to the text', (
      tester,
    ) async {
      await _pump(tester, const LanguageScreen(), textScale: 1.3);
      expect(
        heroClearPhoto(tester).clear,
        greaterThanOrEqualTo(languageHeroClearPhoto / 1.3 - 0.01),
      );
      expectHeroScrimRule(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the tiles and Continue still work', (tester) async {
      await _pump(tester, const LanguageScreen());
      final button = find.descendant(
        of: find.byKey(_lContinue),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      await tester.tap(find.byKey(_lSw));
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
      expect(
        tester.getSemantics(find.byKey(_lSw)),
        isSemantics(
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
        ),
      );
    });
  });

  // ── PIN entry and the PIN flows ────────────────────────────────────────

  group('PIN: content right under a compact hero', () {
    for (final phone in [_p390, _p430]) {
      for (final lang in ['en', 'sw']) {
        for (final dark in [false, true]) {
          final tag = '$phone $lang ${dark ? 'dark' : 'light'}';

          for (final (name, page) in <(String, Widget)>[
            ('entry', _pinEntry),
            ('create', _pinCreate),
          ]) {
            testWidgets('PIN $name $tag: dots under the hero, keys on '
                'screen, spare room at the bottom', (tester) async {
              await RecordingApi().run(() async {
                await _pump(tester, page, phone: phone, lang: lang, dark: dark);
                final bottom = _heroBottom(tester);
                final dots = tester.getRect(find.byType(PinInputRow));
                expect(dots.top - bottom, inInclusiveRange(0, 32));
                expect(
                  tester.getRect(_key('1')).top - dots.bottom,
                  inInclusiveRange(0, 32),
                );
                _expectKeys(tester, phone.size);
                // Never more clear photo than the compact hero asks for:
                // whatever is spare lies below the content.
                expect(
                  heroClearPhoto(tester).clear,
                  lessThanOrEqualTo(pinHeroClearPhoto + 0.01),
                );
                final content = tester.getRect(
                  find.byKey(const Key('pin-pinned-content')),
                );
                expect(content.bottom, lessThanOrEqualTo(phone.height));
                expectHeroScrimRule(tester);
                expect(tester.takeException(), isNull);
                await _unmount(tester);
              });
            });
          }

          testWidgets('PIN setup choose step $tag: text under the hero, '
              'keys on screen', (tester) async {
            await RecordingApi().run(() async {
              await _pump(
                tester,
                _pinSetup,
                phone: phone,
                lang: lang,
                dark: dark,
              );
              final bottom = _heroBottom(tester);
              // The step's first line (its intro) follows the hero.
              final step = tester.getRect(find.byType(ChoosePinStep));
              expect(step.top - bottom, inInclusiveRange(0, 32));
              _expectKeys(tester, phone.size);
              expect(
                heroClearPhoto(tester).clear,
                lessThanOrEqualTo(pinHeroClearPhoto + 0.01),
              );
              expectHeroScrimRule(tester);
              expect(tester.takeException(), isNull);
              await _unmount(tester);
            });
          });
        }
      }
    }

    testWidgets('430x932: the hero keeps its compact height and the room '
        'it no longer takes is below the links', (tester) async {
      await RecordingApi().run(() async {
        await _pump(tester, _pinEntry, phone: _p430, dark: true);
        expect(heroClearPhoto(tester).clear, closeTo(pinHeroClearPhoto, 0.5));
        final hero = tester.getRect(find.byType(FFPhotoHero));
        expect(hero.top, 0);
        final content = tester.getRect(
          find.byKey(const Key('pin-pinned-content')),
        );
        // Below the content: the sheet's own padding (16 + the 34px inset)
        // and the spare room.
        expect(932 - content.bottom, greaterThan(16 + 34 + 20));
        await _unmount(tester);
      });
    });

    testWidgets('a taller phone (430x1100): spare room at the bottom, not '
        'between the hero and the dots', (tester) async {
      await RecordingApi().run(() async {
        const tall = _Phone(430, 1100, top: 59);
        await _pump(tester, _pinEntry, phone: tall, dark: true);
        final bottom = _heroBottom(tester);
        final dots = tester.getRect(find.byType(PinInputRow));
        expect(dots.top - bottom, inInclusiveRange(0, 32));
        expect(bottom, lessThan(1100 * 0.40));
        final content = tester.getRect(
          find.byKey(const Key('pin-pinned-content')),
        );
        expect(1100 - content.bottom, greaterThan(200));
        _expectKeys(tester, tall.size);
        await _unmount(tester);
      });
    });

    for (final phone in [_p360, _p700, _p390, _p430]) {
      for (final scale in [1.0, 1.15]) {
        testWidgets('$phone ${scale}x: 44px keys on screen (PIN entry, '
            'create, setup)', (tester) async {
          await RecordingApi().run(() async {
            for (final page in const <Widget>[
              _pinEntry,
              _pinCreate,
              _pinSetup,
            ]) {
              await _pump(tester, page, phone: phone, textScale: scale);
              _expectKeys(tester, phone.size);
              expect(tester.takeException(), isNull);
              await _unmount(tester);
            }
          });
        });
      }
    }

    testWidgets('below 760px tall: PIN entry keeps today\'s layout (no '
        'hero)', (tester) async {
      await RecordingApi().run(() async {
        for (final phone in const [_p360, _p700, _Phone(390, 759)]) {
          await _pump(tester, _pinEntry, phone: phone);
          expect(find.byType(FFPhotoHero), findsNothing, reason: '$phone');
          expect(find.byKey(const Key('pin-pad-layout')), findsOneWidget);
          await _unmount(tester);
        }
        await _pump(tester, _pinEntry, phone: const _Phone(390, 760));
        expect(find.byType(FFPhotoHero), findsOneWidget);
        await _unmount(tester);
      });
    });
  });

  // ── flag off ───────────────────────────────────────────────────────────

  group('flag off: unchanged', () {
    setUp(() => debugPhotoHeroUiOverride = false);

    testWidgets('Language: no hero, Continue where it was', (tester) async {
      for (final lang in ['en', 'sw']) {
        await _pump(tester, const LanguageScreen(), lang: lang);
        expect(find.byType(FFPhotoHero), findsNothing);
        expect(find.byType(FFPhotoHeroPage), findsNothing);
        // Measured on release-candidate before this change.
        _expectRect(
          tester.getRect(find.byKey(const Key('langKiswahili'))),
          _flagOffSwTile,
        );
        _expectRect(
          tester.getRect(
            find.ancestor(
              of: find.text(FFLocale.textOf(lang, 'lang.continue')!),
              matching: find.byType(FilledButton),
            ),
          ),
          _flagOffContinue,
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('PIN entry: no hero, keypad where it was', (tester) async {
      await RecordingApi().run(() async {
        await _pump(tester, _pinEntry);
        expect(find.byType(FFPhotoHero), findsNothing);
        expect(find.byKey(const Key('pin-pad-layout')), findsOneWidget);
        _expectRect(tester.getRect(_key('1')), _flagOffKey1);
        _expectRect(tester.getRect(_key('OK')), _flagOffOk);
        await _unmount(tester);
      });
    });

    testWidgets('PIN setup: no hero, keypad where it was', (tester) async {
      await RecordingApi().run(() async {
        await _pump(tester, _pinSetup);
        expect(find.byType(FFPhotoHero), findsNothing);
        _expectRect(tester.getRect(_key('1')), _flagOffSetupKey1);
        await _unmount(tester);
      });
    });
  });
}

// Flag-off positions at 390x844 (iPhone insets, 1.0x, light), measured on
// release-candidate before this change.
const _flagOffSwTile = Rect.fromLTRB(24, 401, 366, 465);
const _flagOffContinue = Rect.fromLTRB(24, 738, 366, 786);
const _flagOffKey1 = Rect.fromLTRB(32, 379, 130, 434.8);
const _flagOffOk = Rect.fromLTRB(260, 594.3, 358, 650);
const _flagOffSetupKey1 = Rect.fromLTRB(32, 346, 130, 405);

/// [actual] matches [expected] to within 0.1px on every edge.
void _expectRect(Rect actual, Rect expected) {
  expect(actual.left, closeTo(expected.left, 0.1), reason: '$actual');
  expect(actual.top, closeTo(expected.top, 0.1), reason: '$actual');
  expect(actual.right, closeTo(expected.right, 0.1), reason: '$actual');
  expect(actual.bottom, closeTo(expected.bottom, 0.1), reason: '$actual');
}
