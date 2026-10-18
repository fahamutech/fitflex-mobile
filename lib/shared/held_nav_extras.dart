import 'dart:convert';
import 'dart:math';

/// In-memory store behind the router's `extra` codec for values that must
/// never reach browser history (the sign-in email address or phone number).
/// History state only holds a random opaque key into this store.
///
/// A value in use by a mounted screen is pinned: [clear] keeps it so a
/// sign-out fired in the middle of the flow (e.g. a 401 for a wrong PIN) does
/// not throw the user off the screen; it goes when the screen is disposed.
///
/// Lives in `shared/` so [AuthState] can clear it without importing the
/// router.
class HeldNavExtras {
  HeldNavExtras._();

  static const maxHeld = 8;
  static final Map<String, Object> _held = {};
  static final Map<Object, int> _pins = Map.identity();
  static final Random _random = Random.secure();

  /// Stores [value] (by identity) and returns its opaque key.
  static String hold(Object value) {
    final existing = _keyOf(value);
    final key = existing ?? newKey();
    _held[key] = value;
    _evict();
    return key;
  }

  /// The value held under [key], or null (unknown key, cleared, reloaded).
  static Object? lookup(String key) => _held[key];

  /// A screen showing [value] is mounted; keep it through [clear].
  static void pin(Object value) {
    _pins[value] = (_pins[value] ?? 0) + 1;
  }

  /// The screen showing [value] went away: drop it from the store.
  static void release(Object value) {
    final count = (_pins[value] ?? 0) - 1;
    if (count > 0) {
      _pins[value] = count;
      return;
    }
    _pins.remove(value);
    _held.removeWhere((_, v) => identical(v, value));
  }

  /// Drops every held value no mounted screen is using (sign-out, after a
  /// successful sign-in or sign-up).
  static void clear() {
    _held.removeWhere((_, v) => !_pins.containsKey(v));
  }

  /// 16 bytes from a secure random source, base64url without padding.
  static String newKey() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  /// Number of held values (for tests).
  static int get length => _held.length;

  static String? _keyOf(Object value) {
    for (final e in _held.entries) {
      if (identical(e.value, value)) return e.key;
    }
    return null;
  }

  static void _evict() {
    if (_held.length <= maxHeld) return;
    final unpinned = _held.entries
        .where((e) => !_pins.containsKey(e.value))
        .map((e) => e.key)
        .toList();
    for (final key in unpinned) {
      if (_held.length <= maxHeld) break;
      _held.remove(key);
    }
  }
}
