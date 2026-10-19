import 'package:web/web.dart' as web;

/// Replaces the current browser history entry with `/#/invitations` (no
/// token), keeping Flutter's history state. Hosting is at the site root.
void showInvitationsWithoutToken() => _replaceWithRoute('/invitations');

/// Replaces the current browser history entry with `/#/friend-invite` (no
/// token), keeping Flutter's history state.
void showFriendInviteWithoutToken() => _replaceWithRoute('/friend-invite');

void _replaceWithRoute(String route) {
  try {
    final location = web.window.location;
    web.window.history.replaceState(
      web.window.history.state,
      '',
      '${location.origin}/#$route',
    );
  } catch (_) {}
}
