// The organisation invitation token (gym / shop / company invites) a visitor
// arrived with, kept on this device so it never has to stay in the address
// bar or browser history. The invitations screen takes it once.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

export 'invite_page_url.dart';

/// The invitation token kept through sign-in / registration, for at most a
/// day. Mirrored in memory so routing can ask [hasPending] synchronously.
class PendingOrgInvite {
  static const _tokenKey = 'pending_org_invite_token';
  static const _savedAtKey = 'pending_org_invite_saved_at';

  /// How long a kept token is honoured.
  static const maxAge = Duration(hours: 24);

  /// Replaceable in tests.
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static String? _token;
  static DateTime? _savedAt;

  static bool _fresh(DateTime? savedAt) =>
      savedAt != null && clock().difference(savedAt) < maxAge;

  /// A kept, unexpired token is waiting (as far as this run knows).
  static bool get hasPending =>
      _token != null && _token!.isNotEmpty && _fresh(_savedAt);

  /// Reads a token kept by an earlier run into memory. Call once at startup.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      final ms = prefs.getInt(_savedAtKey);
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

  static Future<void> save(String token) async {
    if (token.isEmpty) return;
    final now = clock();
    _token = token;
    _savedAt = now;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setInt(_savedAtKey, now.millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// The kept token, without clearing it; null when none or expired.
  static Future<String?> peek() async {
    await load();
    return hasPending ? _token : null;
  }

  /// Returns and clears the kept token; null when none or expired.
  static Future<String?> take() async {
    await load();
    final token = hasPending ? _token : null;
    await clear();
    return token;
  }

  /// Forgets any kept token (for example once the invitation was answered
  /// another way).
  static Future<void> clear() async {
    _token = null;
    _savedAt = null;
    try {
      await _removeStored(await SharedPreferences.getInstance());
    } catch (_) {}
  }

  static Future<void> _removeStored(SharedPreferences prefs) async {
    await prefs.remove(_tokenKey);
    await prefs.remove(_savedAtKey);
  }

  /// Clears the in-memory copy only (tests start from stored values).
  @visibleForTesting
  static void resetMemory() {
    _token = null;
    _savedAt = null;
    clock = DateTime.now;
  }
}
