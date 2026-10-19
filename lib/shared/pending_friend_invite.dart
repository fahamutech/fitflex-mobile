// Friend invitation links keep their token out of server / CDN logs, the
// address bar, browser history and the route location. A link is
// `https://fitflex-af-app.web.app/friend-invite/#<token>` (the fragment is
// never sent to the server); links sent before that were
// `/friend-invite/<token>` and still work. The token is kept on the device
// (a day at most) and the invitation page reads it from there.

import 'package:flutter/foundation.dart';

import 'kept_link_token.dart';

export 'invite_page_url.dart' show showFriendInviteWithoutToken;

/// The shape of a friend-invitation token (the backend makes 43-character
/// base64url tokens and checks this same pattern).
final friendInviteTokenShape = RegExp(r'^[A-Za-z0-9_-]{20,128}$');

const _friendInvitePath = '/friend-invite';

/// A friend-invitation link that carries a token. [token] is null when the
/// part where the token belongs is not a well-formed token.
class FriendInviteLink {
  const FriendInviteLink(this.token);
  final String? token;
}

/// The friend-invitation link in [uri], or null when [uri] is not one that
/// carries a token. Accepts a path (`/friend-invite/#tok`) or a full address
/// (`https://…/friend-invite/#tok`), and the legacy `/friend-invite/tok`;
/// trailing slashes are ignored. The plain `/friend-invite` page (no token)
/// is not a link.
FriendInviteLink? friendInviteLinkFrom(Uri uri) {
  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  String? valid(String t) => friendInviteTokenShape.hasMatch(t) ? t : null;

  if (path == _friendInvitePath) {
    if (!uri.hasFragment || uri.fragment.isEmpty) return null;
    return FriendInviteLink(valid(uri.fragment));
  }
  if (path.startsWith('$_friendInvitePath/')) {
    final rest = path.substring(_friendInvitePath.length + 1);
    return FriendInviteLink(rest.contains('/') ? null : valid(rest));
  }
  return null;
}

/// The well-formed token in a friend-invitation link, or null.
String? friendInviteTokenFromUri(Uri uri) => friendInviteLinkFrom(uri)?.token;

/// The friend-invitation token a visitor arrived with, kept through sign-in /
/// registration (a day at most) so it can be claimed afterwards.
class PendingFriendInvite {
  static final _kept = KeptLinkToken(
    tokenKey: 'pending_friend_invite_token',
    savedAtKey: 'pending_friend_invite_saved_at',
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

  /// Forgets any kept token.
  static Future<void> clear() => _kept.clear();

  /// Clears the in-memory copy only (tests start from stored values).
  @visibleForTesting
  static void resetMemory() => _kept.resetMemory();
}
