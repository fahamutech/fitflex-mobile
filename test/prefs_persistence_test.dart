// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeNotifier', () {
    test('first run defaults to dark and nothing is saved by load', () async {
      SharedPreferences.setMockInitialValues({});
      final n = ThemeNotifier();
      await n.load();
      expect(n.mode, ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ThemeNotifier.prefsKey), isNull);
    });

    test('toggle is saved and restored by a new notifier', () async {
      SharedPreferences.setMockInitialValues({});
      final a = ThemeNotifier()..toggle();
      expect(a.mode, ThemeMode.light);
      await Future<void>.delayed(Duration.zero);
      final b = ThemeNotifier();
      await b.load();
      expect(b.mode, ThemeMode.light);
    });

    test('legacy "system" value is read as auto', () async {
      SharedPreferences.setMockInitialValues({
        ThemeNotifier.prefsKey: 'system',
      });
      final n = ThemeNotifier();
      await n.load();
      expect(n.preference, ThemePreference.auto);
    });

    test('auto is dark at night and light in the daytime', () {
      DateTime t(int h, [int m = 0]) => DateTime(2026, 10, 10, h, m);
      for (final (hour, dark) in [
        (0, true),
        (5, true),
        (6, false),
        (12, false),
        (17, false),
        (18, true),
        (23, true),
      ]) {
        final n = ThemeNotifier(clock: () => t(hour))
          ..setPreference(ThemePreference.auto);
        expect(n.isDark, dark, reason: 'hour $hour');
        n.dispose();
      }
    });

    test('fixed light stays light at night, fixed dark stays dark by day', () {
      final night = ThemeNotifier(clock: () => DateTime(2026, 10, 10, 22))
        ..setPreference(ThemePreference.light);
      expect(night.mode, ThemeMode.light);
      final day = ThemeNotifier(clock: () => DateTime(2026, 10, 10, 12));
      expect(day.mode, ThemeMode.dark); // first-run default
      night.dispose();
      day.dispose();
    });

    test('auto flips when the clock crosses dusk', () {
      fakeAsync((async) {
        var now = DateTime(2026, 10, 10, 17, 59, 30);
        final n = ThemeNotifier(clock: () => now)
          ..setPreference(ThemePreference.auto);
        var changes = 0;
        n.addListener(() => changes++);
        expect(n.isDark, isFalse);
        now = DateTime(2026, 10, 10, 18, 0, 5);
        async.elapse(const Duration(seconds: 40));
        expect(changes, greaterThanOrEqualTo(1));
        expect(n.isDark, isTrue);
        n.dispose();
      });
    });

    test('auto choice is saved and restored', () async {
      SharedPreferences.setMockInitialValues({});
      final a = ThemeNotifier()..setPreference(ThemePreference.auto);
      await Future<void>.delayed(Duration.zero);
      final b = ThemeNotifier();
      await b.load();
      expect(b.preference, ThemePreference.auto);
      a.dispose();
      b.dispose();
    });

    test('unknown saved value keeps the default', () async {
      SharedPreferences.setMockInitialValues({ThemeNotifier.prefsKey: 'neon'});
      final n = ThemeNotifier();
      await n.load();
      expect(n.mode, ThemeMode.dark);
    });
  });

  group('toggles', () {
    testWidgets('language button switches the page language in place', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final locale = FFLocale();
      await t.pumpWidget(
        FFLocaleScope(
          notifier: locale,
          child: AnimatedBuilder(
            animation: locale,
            builder: (_, _) => const MaterialApp(
              home: Scaffold(body: Center(child: LanguageToggleButton())),
            ),
          ),
        ),
      );
      expect(find.text('EN'), findsOneWidget);
      await t.tap(find.byType(LanguageToggleButton));
      await t.pumpAndSettle();
      expect(locale.locale.languageCode, 'sw');
      expect(find.text('SW'), findsOneWidget);
      await t.tap(find.byType(LanguageToggleButton));
      await t.pumpAndSettle();
      expect(locale.locale.languageCode, 'en');
    });

    testWidgets('theme menu offers dark, light and auto', (t) async {
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeNotifier();
      await t.pumpWidget(
        ThemeScope(
          notifier: theme,
          child: AnimatedBuilder(
            animation: theme,
            builder: (_, _) => FFLocaleScope(
              notifier: FFLocale(),
              child: const MaterialApp(
                home: Scaffold(body: Center(child: ThemeToggleButton())),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.byType(ThemeToggleButton));
      await t.pumpAndSettle();
      expect(find.text('Dark'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Auto (dark at night)'), findsOneWidget);
      await t.tap(find.text('Auto (dark at night)'));
      await t.pumpAndSettle();
      expect(theme.preference, ThemePreference.auto);
      theme.dispose();
    });
  });

  group('FFLocale', () {
    test('defaults to English', () async {
      SharedPreferences.setMockInitialValues({});
      final l = FFLocale();
      await l.load();
      expect(l.locale.languageCode, 'en');
    });

    test('choice is saved and restored', () async {
      SharedPreferences.setMockInitialValues({});
      FFLocale().set(const Locale('sw'));
      await Future<void>.delayed(Duration.zero);
      final restored = FFLocale();
      await restored.load();
      expect(restored.locale.languageCode, 'sw');
    });

    test('an unsupported saved language is ignored', () async {
      SharedPreferences.setMockInitialValues({FFLocale.prefsKey: 'fr'});
      final l = FFLocale();
      await l.load();
      expect(l.locale.languageCode, 'en');
    });

    test('an unsupported choice is not saved', () async {
      SharedPreferences.setMockInitialValues({});
      FFLocale().set(const Locale('fr'));
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(FFLocale.prefsKey), isNull);
    });
  });
}
