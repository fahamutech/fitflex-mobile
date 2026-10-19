// A token from an invitation link, kept on this device (a day at most) so it
// never has to stay in the address bar, browser history or route location.
// Used by organisation invitations and friend invitations.

import 'package:shared_preferences/shared_preferences.dart';

/// One kept link token, stored under its own keys and mirrored in memory so
/// routing can ask [hasPending] synchronously.
class KeptLinkToken {
  KeptLinkToken({required this.tokenKey, required this.savedAtKey});

  final String tokenKey;
  final String savedAtKey;

  /// How long a kept token is honoured.
  static const maxAge = Duration(hours: 24);

  /// Replaceable in tests.
  DateTime Function() clock = DateTime.now;

  String? _token;
  DateTime? _savedAt;

  bool _fresh(DateTime? savedAt) =>
      savedAt != null && clock().difference(savedAt) < maxAge;

  /// A kept, unexpired token is waiting (as far as this run knows).
  bool get hasPending =>
      _token != null && _token!.isNotEmpty && _fresh(_savedAt);

  /// Reads a token kept by an earlier run into memory.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(tokenKey);
      final ms = prefs.getInt(savedAtKey);
      final savedAt = ms == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(ms);
      if (token == null || token.isEmpty || !_fresh(savedAt)) {
        if (token != null || ms != null) await _removeStored(prefs);
        // A token saved during this run stays.
        return;
      }
      _token = token;
      _savedAt = savedAt;
    } catch (_) {}
  }

  Future<void> save(String token) async {
    if (token.isEmpty) return;
    final now = clock();
    _token = token;
    _savedAt = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(tokenKey, token);
      await prefs.setInt(savedAtKey, now.millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// The kept token, without clearing it; null when none or expired.
  Future<String?> peek() async {
    await load();
    return hasPending ? _token : null;
  }

  /// Returns and clears the kept token; null when none or expired.
  Future<String?> take() async {
    await load();
    final token = hasPending ? _token : null;
    await clear();
    return token;
  }

  /// Forgets any kept token.
  Future<void> clear() async {
    _token = null;
    _savedAt = null;
    try {
      await _removeStored(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  Future<void> _removeStored(SharedPreferences prefs) async {
    await prefs.remove(tokenKey);
    await prefs.remove(savedAtKey);
  }

  /// Clears the in-memory copy only (tests start from stored values). The
  /// static wrappers expose it to tests only.
  void resetMemory() {
    _token = null;
    _savedAt = null;
    clock = DateTime.now;
  }
}
