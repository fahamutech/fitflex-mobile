import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the app-wide theme mode. The choice is saved on the device and
/// restored on the next launch ([load]); the first-run default is dark.
class ThemeNotifier extends ChangeNotifier {
  static const prefsKey = 'ff.theme_mode';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  /// Restores the saved choice. Safe to call when nothing was saved, or when
  /// storage is unavailable (the default stays).
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(prefsKey);
      final mode = switch (saved) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => null,
      };
      if (mode != null && mode != _mode) {
        _mode = mode;
        notifyListeners();
      }
    } catch (_) {
      // Keep the default.
    }
  }

  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    _save();
  }

  void setMode(ThemeMode mode) {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, _mode.name);
    } catch (_) {
      // Not saved; the choice still applies for this session.
    }
  }
}

/// InheritedWidget that exposes [ThemeNotifier] to the widget tree.
class ThemeScope extends InheritedNotifier<ThemeNotifier> {
  const ThemeScope({
    super.key,
    required ThemeNotifier notifier,
    required super.child,
  }) : super(notifier: notifier);

  static ThemeNotifier of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope missing in widget tree');
    return scope!.notifier!;
  }
}
