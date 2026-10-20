// The organisation invitation token (gym / shop / company invites) a visitor
// arrived with, kept on this device so it never has to stay in the address
// bar or browser history. The invitations screen takes it once.

import 'package:flutter/foundation.dart';

import 'kept_link_token.dart';

export 'invite_page_url.dart';

/// The invitation token kept through sign-in / registration, for at most a
/// day. Mirrored in memory so routing can ask [hasPending] synchronously.
class PendingOrgInvite {
  static final _kept = KeptLinkToken(
    tokenKey: 'pending_org_invite_token',
    savedAtKey: 'pending_org_invite_saved_at',
  );

  /// How long a kept token is honoured.
  static const maxAge = KeptLinkToken.maxAge;

  /// Replaceable in tests.
  @visibleForTesting
  static DateTime Function() get clock => _kept.clock;
  @visibleForTesting
  static set clock(DateTime Function() value) => _kept.clock = value;

  /// A kept, unexpired token is waiting (as far as this run knows).
  static bool get hasPending => _kept.hasPending;

  /// Reads a token kept by an earlier run into memory. Call once at startup.
  static Future<void> load() => _kept.load();

  static Future<void> save(String token) => _kept.save(token);

  /// The kept token, without clearing it; null when none or expired.
  static Future<String?> peek() => _kept.peek();

  /// Returns and clears the kept token; null when none or expired.
  static Future<String?> take() => _kept.take();

  /// Forgets any kept token (for example once the invitation was answered
  /// another way).
  static Future<void> clear() => _kept.clear();

  /// Clears the in-memory copy only (tests start from stored values).
  @visibleForTesting
  static void resetMemory() => _kept.resetMemory();
}
