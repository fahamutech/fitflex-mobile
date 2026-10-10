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

    test('unknown saved value keeps the default', () async {
      SharedPreferences.setMockInitialValues({ThemeNotifier.prefsKey: 'neon'});
      final n = ThemeNotifier();
      await n.load();
      expect(n.mode, ThemeMode.dark);
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
