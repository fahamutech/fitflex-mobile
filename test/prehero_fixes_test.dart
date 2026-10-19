// Pre-sign-in and Home fixes (F-1..F-4 of docs/design/photo-hero-screens.md).

import 'dart:ui' show CheckedState, Tristate;

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/language_screen.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/pass_summary_card.dart';
import 'package:fitflexmobile/screens/role_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<FFLocale> _pump(
  WidgetTester tester,
  Widget home, {
  String lang = 'en',
  ThemeData? theme,
  bool settle = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  final api = ApiClient(baseUrl: 'http://localhost:0');
  final auth = AuthState(api);
  final locale = FFLocale()..set(Locale(lang));
  await tester.pumpWidget(
    AppScope(
      api: api,
      auth: auth,
      child: ThemeScope(
        notifier: ThemeNotifier(),
        child: FFLocaleScope(
          notifier: locale,
          child: MaterialApp(
            theme: theme ?? buildTheme(),
            supportedLocales: const [Locale('en'), Locale('sw')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
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
  }
  return locale;
}

void main() {
  group('F-1 language screen', () {
    testWidgets('names each language in its own language', (tester) async {
      await _pump(tester, const LanguageScreen());
      expect(find.text('English'), findsOneWidget);
      expect(find.text('Kiswahili'), findsOneWidget);
      expect(find.text('Swahili'), findsNothing);
      expect(find.text('International Standard'), findsNothing);
      expect(find.text('Choose language'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('reads from the Swahili map when Swahili is active', (
      tester,
    ) async {
      await _pump(tester, const LanguageScreen(), lang: 'sw');
      expect(find.text('Chagua Lugha'), findsOneWidget);
      expect(find.text('Endelea'), findsOneWidget);
      expect(find.text('Kiswahili'), findsOneWidget);
    });

    test('new keys exist in both maps; Swahili differs where translated', () {
      for (final k in [
        'lang.name.en',
        'lang.name.sw',
        'auth.errorDialog.title',
        'home.passError.title',
      ]) {
        expect(FFLocale.textOf('en', k), isNotNull, reason: k);
        expect(FFLocale.textOf('sw', k), isNotNull, reason: k);
      }
      for (final k in ['auth.errorDialog.title', 'home.passError.title']) {
        expect(FFLocale.textOf('sw', k), isNot(FFLocale.textOf('en', k)));
      }
    });
  });

  group('F-2 sign-in error dialog', () {
    for (final (lang, title, close) in [
      ('en', "Couldn't sign you in", 'Close'),
      ('sw', 'Hatukuweza kukuingiza', 'Funga'),
    ]) {
      testWidgets('title and Close are translated ($lang)', (tester) async {
        var closed = false;
        await _pump(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showFFAuthErrorDialog(
                  context,
                  'boom',
                  onClose: () => closed = true,
                ),
                child: const Text('open'),
              ),
            ),
          ),
          lang: lang,
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        expect(find.text('boom'), findsOneWidget);
        expect(find.text('Authentication Error'), findsNothing);
        await tester.tap(find.text(close));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('auth-error-dialog')), findsNothing);
        expect(closed, isTrue);
      });
    }
  });

  group('F-3 choice tiles are radios', () {
    testWidgets('language tiles: radio semantics with selected state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const LanguageScreen());
      final en = tester
          .getSemantics(find.byKey(const Key('langEnglish')))
          .getSemanticsData();
      expect(en.label, 'English');
      expect(en.flagsCollection.isButton, isTrue);
      expect(en.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(en.flagsCollection.isChecked, CheckedState.isFalse);
      expect(en.flagsCollection.isFocused, isNot(Tristate.none));
      expect(en.hasAction(SemanticsAction.tap), isTrue);
      await tester.tap(find.byKey(const Key('langEnglish')));
      await tester.pumpAndSettle();
      final data = tester
          .getSemantics(find.byKey(const Key('langEnglish')))
          .getSemanticsData();
      expect(data.flagsCollection.isChecked, CheckedState.isTrue);
      handle.dispose();
    });

    testWidgets('Tab reaches a language tile; Space and Enter select it', (
      tester,
    ) async {
      await _pump(tester, const LanguageScreen());
      FilledButton continueButton() =>
          tester.widget<FilledButton>(find.byType(FilledButton));
      expect(continueButton().onPressed, isNull);

      // Theme toggle first, then English, then Kiswahili.
      Future<void> tabTo(Key key) async {
        for (var i = 0; i < 6; i++) {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
          final focus = FocusManager.instance.primaryFocus;
          final ctx = focus?.context;
          if (ctx != null &&
              find
                  .ancestor(
                    of: find.byElementPredicate((e) => e == ctx),
                    matching: find.byKey(key),
                  )
                  .evaluate()
                  .isNotEmpty) {
            return;
          }
        }
        fail('Tab never reached $key');
      }

      await tabTo(const Key('langKiswahili'));
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(continueButton().onPressed, isNotNull);
      final sw = tester.widget<FFChoiceTile>(
        find.byKey(const Key('langKiswahili')),
      );
      expect(sw.selected, isTrue);

      // Shift+Tab back to English and pick it with Enter.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FFChoiceTile>(find.byKey(const Key('langEnglish')))
            .selected,
        isTrue,
      );
    });

    testWidgets('keyboard focus draws the 2px ring outside the tile', (
      tester,
    ) async {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
      await _pump(tester, const LanguageScreen(), theme: buildDarkTheme());
      BoxDecoration ringOf(Key key) {
        final box = tester.widget<DecoratedBox>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byKey(const Key('ff-choice-focus-ring')),
          ),
        );
        return box.decoration as BoxDecoration;
      }

      expect(ringOf(const Key('langEnglish')).border, isNull);
      final focusNode = Focus.of(
        tester.element(
          find.descendant(
            of: find.byKey(const Key('langEnglish')),
            matching: find.byKey(const Key('ff-choice-focus-ring')),
          ),
        ),
      );
      focusNode.requestFocus();
      await tester.pumpAndSettle();
      final border = ringOf(const Key('langEnglish')).border as Border;
      expect(border.top.width, 2);
      expect(border.top.color, ffFocusRingDark);
      expect(border.top.strokeAlign, BorderSide.strokeAlignOutside);
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    });

    testWidgets('role tiles are radios too', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const RoleScreen());
      final tiles = find.byType(FFChoiceTile);
      expect(tiles, findsNWidgets(5));
      final first = tester.getSemantics(tiles.first).getSemanticsData();
      expect(first.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
      expect(first.flagsCollection.isChecked, CheckedState.isFalse);
      expect(first.label, startsWith('Gym Member'));
      await tester.tap(tiles.first);
      await tester.pumpAndSettle();
      expect(tester.widget<FFChoiceTile>(tiles.first).selected, isTrue);
      handle.dispose();
    });
  });

  group('F-4 pass card offline with nothing loaded', () {
    Future<void> pumpCard(WidgetTester tester, MemberData data) => _pump(
      tester,
      MemberDataScope(
        data: data,
        child: Scaffold(body: PassSummaryCard(data: data)),
      ),
    ).then((_) {});

    testWidgets('shows an error with Retry, never "No pass yet"', (
      tester,
    ) async {
      await pumpCard(tester, MemberData()..offline = true);
      expect(find.byKey(const Key('pass-summary-error')), findsOneWidget);
      expect(find.text("We couldn't load your pass."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No pass yet'), findsNothing);
      expect(find.text('Choose a pass'), findsNothing);
    });

    testWidgets('still loading (online) keeps the spinner', (tester) async {
      final data = MemberData();
      await _pump(
        tester,
        MemberDataScope(
          data: data,
          child: Scaffold(body: PassSummaryCard(data: data)),
        ),
        settle: false,
      );
      expect(find.byKey(const Key('pass-summary-loading')), findsOneWidget);
      expect(find.byKey(const Key('pass-summary-error')), findsNothing);
    });
  });
}
