import 'package:web/web.dart' as web;

/// Replaces the current browser history entry with `/#/event-claim` (no
/// token), keeping Flutter's history state. Hosting is at the site root.
void showEventClaimWithoutToken() {
  try {
    final location = web.window.location;
    web.window.history.replaceState(
      web.window.history.state,
      '',
      '${location.origin}/#/event-claim',
    );
  } catch (_) {}
}
