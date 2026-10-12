import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the user picked for the theme.
///  * [dark] / [light]: fixed.
///  * [auto]: dark at night ([ThemeNotifier.nightStartHour]–
///    [ThemeNotifier.nightEndHour] local time), light in the daytime.
enum ThemePreference { dark, light, auto }

/// Manages the app-wide theme. The choice is saved on the device and
/// restored on the next launch ([load]); the first-run default is dark until
/// the user picks light or auto.
class ThemeNotifier extends ChangeNotifier {
  ThemeNotifier({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  static const prefsKey = 'ff.theme_mode';

  /// Night is from [nightStartHour]:00 to [nightEndHour]:00 the next morning.
  static const nightStartHour = 18;
  static const nightEndHour = 6;

  static bool isNight(DateTime t) =>
      t.hour >= nightStartHour || t.hour < nightEndHour;

  final DateTime Function() _now;
  ThemePreference _pref = ThemePreference.dark;
  Timer? _timer;

  ThemePreference get preference => _pref;

  /// The mode in effect right now (auto resolves by the time of day).
  ThemeMode get mode => switch (_pref) {
    ThemePreference.dark => ThemeMode.dark,
    ThemePreference.light => ThemeMode.light,
    ThemePreference.auto => isNight(_now()) ? ThemeMode.dark : ThemeMode.light,
  };

  bool get isDark => mode == ThemeMode.dark;

  /// Restores the saved choice. Safe when nothing was saved or storage is
  /// unavailable (the default stays). The legacy value `system` means auto.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pref = switch (prefs.getString(prefsKey)) {
        'light' => ThemePreference.light,
        'dark' => ThemePreference.dark,
        'auto' || 'system' => ThemePreference.auto,
        _ => null,
      };
      if (pref != null && pref != _pref) {
        _apply(pref, save: false);
      }
    } catch (_) {
      // Keep the default.
    }
  }

  void setPreference(ThemePreference pref) {
    if (_pref == pref) return;
    _apply(pref, save: true);
  }

  /// Flips between dark and light (auto becomes the opposite of what is
  /// showing now).
  void toggle() =>
      setPreference(isDark ? ThemePreference.light : ThemePreference.dark);

  void setMode(ThemeMode mode) => setPreference(switch (mode) {
    ThemeMode.dark => ThemePreference.dark,
    ThemeMode.light => ThemePreference.light,
    ThemeMode.system => ThemePreference.auto,
  });

  void _apply(ThemePreference pref, {required bool save}) {
    _pref = pref;
    _schedule();
    notifyListeners();
    if (save) _save();
  }

  /// In auto mode, re-evaluate when the clock crosses dusk or dawn.
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_pref != ThemePreference.auto) return;
    final now = _now();
    var next = DateTime(now.year, now.month, now.day, nightEndHour);
    final dusk = DateTime(now.year, now.month, now.day, nightStartHour);
    if (!next.isAfter(now)) next = dusk;
    if (!next.isAfter(now)) {
      next = DateTime(now.year, now.month, now.day + 1, nightEndHour);
    }
    _timer = Timer(next.difference(now) + const Duration(seconds: 1), () {
      notifyListeners();
      _schedule();
    });
  }

  /// Call when the app returns to the foreground: the clock may have crossed
  /// a boundary while timers were suspended.
  void refresh() {
    if (_pref != ThemePreference.auto) return;
    _schedule();
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, _pref.name);
    } catch (_) {
      // Not saved; the choice still applies for this session.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
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
