// Events S3 (spec §3.7, §5.11): claim links carry their token in the URL
// fragment (`/event-claim/#<token>`), exactly like friend invitations, so it
// never reaches a server or a log. The token is kept on the device (a day
// at most) through sign-in and the claim page reads it from there.
import 'package:flutter/foundation.dart';

import '../kept_link_token.dart';
import '../pending_friend_invite.dart' show friendInviteTokenShape;

export 'event_claim_url.dart' show showEventClaimWithoutToken;

const _claimPath = '/event-claim';

/// The claim-link token shape (43-char base64url; the same rule as friend
/// invitations).
RegExp get eventClaimTokenShape => friendInviteTokenShape;

/// A claim link that carries a token; [token] is null when the part where
/// the token belongs is malformed.
class EventClaimLink {
  const EventClaimLink(this.token);
  final String? token;
}

/// The claim link in [uri], or null when [uri] is not one that carries a
/// token: `/event-claim/#tok`, a full `https://…/event-claim/#tok`, or the
/// legacy `/event-claim/tok`. The plain `/event-claim` page is not a link.
EventClaimLink? eventClaimLinkFrom(Uri uri) {
  var path = uri.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  String? valid(String t) => eventClaimTokenShape.hasMatch(t) ? t : null;
  if (path == _claimPath) {
    if (!uri.hasFragment || uri.fragment.isEmpty) return null;
    return EventClaimLink(valid(uri.fragment));
  }
  if (path.startsWith('$_claimPath/')) {
    final rest = path.substring(_claimPath.length + 1);
    return EventClaimLink(rest.contains('/') ? null : valid(rest));
  }
  return null;
}

/// The claim token a visitor arrived with, kept through sign-in (a day at
/// most). Kept even while the registration feature is off, so a link opened
/// before the flag flips still works (§4).
class PendingEventClaim {
  static final _kept = KeptLinkToken(
    tokenKey: 'eventClaim.token',
    savedAtKey: 'eventClaim.savedAt',
  );

  static const maxAge = KeptLinkToken.maxAge;

  @visibleForTesting
  static DateTime Function() get clock => _kept.clock;
  @visibleForTesting
  static set clock(DateTime Function() value) => _kept.clock = value;

  static bool get hasPending => _kept.hasPending;
  static Future<void> load() => _kept.load();
  static Future<void> save(String token) => _kept.save(token);
  static Future<String?> peek() => _kept.peek();
  static Future<String?> take() => _kept.take();
  static Future<void> clear() => _kept.clear();

  @visibleForTesting
  static void resetMemory() => _kept.resetMemory();
}
