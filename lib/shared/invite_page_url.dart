// Organisation invitation links: reading a token from the page address the
// web app was opened at, and taking it out of the address bar.

export 'invite_page_url_stub.dart'
    if (dart.library.js_interop) 'invite_page_url_web.dart';

/// The org invitation token in a page address, or null. Covers the current
/// link (`/#/invitations?token=…`) and links sent before it
/// (`/invitations?token=…`).
String? inviteTokenFromPageUri(Uri page) {
  String? from(Uri uri) {
    var path = uri.path;
    if (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path != '/invitations') return null;
    final token = uri.queryParameters['token'];
    return token == null || token.isEmpty ? null : token;
  }

  final legacy = from(page);
  if (legacy != null) return legacy;
  if (page.fragment.isEmpty) return null;
  try {
    return from(Uri.parse(page.fragment));
  } catch (_) {
    return null;
  }
}
