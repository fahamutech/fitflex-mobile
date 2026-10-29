import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app_scope.dart';
import '../api_client.dart';

/// Which image addresses the app may draw (security fix 2026-10-28,
/// fitflex-functions#273).
///
/// Gym, trainer, vendor, product, event and profile photos are strings the
/// server stores for partners and shows to members. A partner-set address on
/// another host would make every member's phone fetch that host (tracking,
/// IP leaks, a session header sent to a stranger). So the app draws only:
///
/// - `data:image/(png|jpeg|webp);base64,…`: decoded on the device, at most
///   [kMediaSrcMaxBytes] decoded, and the bytes must start like a PNG, JPEG
///   or WebP file;
/// - root-relative `/storage/<cid>/<file>` paths, resolved against the
///   configured API_BASE;
/// - absolute addresses on the API_BASE host (same scheme and port, no user
///   info), e.g. the admin portal's `${API_BASE}/storage/…` URLs and the
///   private banner previews;
/// - bundled `assets/…` images;
/// - with `profilePhoto: true` only: Google sign-in photos on
///   [kGoogleProfilePhotoHosts] (https, port 443). The server copies the Google photo
///   into the account's `photoUrl` at every Google sign-in, so without this
///   every Google user would lose their own avatar.
///
/// Anything else resolves to null: callers show their placeholder and no
/// request is made. Admin hero photos (HeroImageStore,
/// HERO_IMAGES_ALLOWED_HOSTS) keep their own rules and do not use this.

/// The decoded size cap for an inline photo (the server's default
/// MEDIA_SRC_MAX_BYTES, 1.4 MB = 1 400 000 bytes, so its base64 form fits a
/// 2 MB request body).
const int kMediaSrcMaxBytes = 1400000;

/// Most photos (and thumbnails) one gym may hold (server GYM_MAX_IMAGES;
/// more → 400 too_many_images).
const int kGymMaxPhotos = 10;

/// Most photos (and thumbnails) on a trainer profile (server
/// PROFILE_LIMITS.images; more → 400 too_many_images).
const int kTrainerMaxPhotos = 8;

/// The only outside hosts allowed, and only for people's profile photos:
/// Google's sign-in photo hosts (the server's SIGNIN_PHOTO_HOSTS default).
const Set<String> kGoogleProfilePhotoHosts = {
  'lh3.googleusercontent.com',
  'lh4.googleusercontent.com',
  'lh5.googleusercontent.com',
  'lh6.googleusercontent.com',
};

/// Where a permitted image comes from.
@immutable
sealed class MediaSource {
  const MediaSource();
}

/// Inline bytes from a data URI (no request).
final class MediaBytes extends MediaSource {
  const MediaBytes(this.bytes);
  final Uint8List bytes;
}

/// A request to [uri], which is on the API host (or Google, for a profile
/// photo).
final class MediaNetwork extends MediaSource {
  const MediaNetwork(this.uri);
  final Uri uri;

  /// True when [uri] is on the API host, the only place a session header
  /// may be sent.
  bool onApiHost(String apiBase) =>
      _sameOrigin(uri, Uri.tryParse(_trim(apiBase)));
}

/// A photo bundled with the app.
final class MediaAsset extends MediaSource {
  const MediaAsset(this.path);
  final String path;
}

/// The API base the checks resolve against. main() sets it from the
/// [ApiClient] it builds; until then the same API_BASE resolution as
/// [ApiClient] is used.
abstract final class MediaSrcPolicy {
  static String? _apiBase;

  static void configure(String apiBase) => _apiBase = apiBase;

  @visibleForTesting
  static void reset() => _apiBase = null;

  static String get apiBase => _apiBase ?? ApiClient.defaultBaseUrl();
}

/// The API base for image checks under [context]: the [ApiClient] in
/// [AppScope] when there is one (the same server the app talks to), else
/// [MediaSrcPolicy.apiBase].
String mediaApiBaseOf(BuildContext context) =>
    context.getInheritedWidgetOfExactType<AppScope>()?.api.baseUrl ??
    MediaSrcPolicy.apiBase;

/// The permitted source for [src], or null when it must not be drawn.
/// [apiBase] defaults to [MediaSrcPolicy.apiBase].
MediaSource? resolveMediaSrc(
  String? src, {
  String? apiBase,
  bool profilePhoto = false,
}) {
  final s = src?.trim() ?? '';
  if (s.isEmpty) return null;
  if (s.startsWith('data:')) return _dataUri(s);
  if (s.startsWith('assets/')) return _asset(s);
  final base = _apiBaseUri(apiBase ?? MediaSrcPolicy.apiBase);
  if (base == null) return null;
  if (s.startsWith('/')) return _storagePath(s, base);
  final uri = Uri.tryParse(s);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty) return null;
  if (_sameOrigin(uri, base)) return MediaNetwork(uri);
  if (profilePhoto &&
      uri.isScheme('https') &&
      kGoogleProfilePhotoHosts.contains(uri.host.toLowerCase()) &&
      uri.port == 443) {
    return MediaNetwork(uri);
  }
  return null;
}

/// True when [src] may be drawn.
bool isAllowedMediaSrc(
  String? src, {
  String? apiBase,
  bool profilePhoto = false,
}) =>
    resolveMediaSrc(src, apiBase: apiBase, profilePhoto: profilePhoto) != null;

/// An [ImageProvider] for [src], or null when it must not be drawn.
/// [headers] are only sent to the API host.
ImageProvider? mediaImageProvider(
  String? src, {
  String? apiBase,
  bool profilePhoto = false,
  Map<String, String>? headers,
}) {
  final base = apiBase ?? MediaSrcPolicy.apiBase;
  final source = resolveMediaSrc(
    src,
    apiBase: base,
    profilePhoto: profilePhoto,
  );
  return switch (source) {
    null => null,
    MediaBytes(:final bytes) => MemoryImage(bytes),
    MediaAsset(:final path) => AssetImage(path),
    MediaNetwork(:final uri) => NetworkImage(
      uri.toString(),
      headers: source.onApiHost(base) ? headers : null,
    ),
  };
}

// ── Checks ──────────────────────────────────────────────────────────────────

final _dataUriPattern = RegExp(
  r'^data:image/(png|jpeg|webp);base64,([A-Za-z0-9+/_-]+={0,2})$',
);

MediaSource? _dataUri(String s) {
  final m = _dataUriPattern.firstMatch(s);
  if (m == null) return null;
  final payload = m.group(2)!;
  // Refuse before decoding anything bigger than the cap could be.
  if (payload.length > (kMediaSrcMaxBytes ~/ 3 + 1) * 4) return null;
  final Uint8List bytes;
  try {
    bytes = base64Decode(payload);
  } on FormatException {
    return null;
  }
  if (bytes.isEmpty || bytes.length > kMediaSrcMaxBytes) return null;
  if (!_looksLikeRaster(bytes)) return null;
  return MediaBytes(bytes);
}

/// PNG, JPEG or WebP by their first bytes (the formats the server accepts).
bool _looksLikeRaster(Uint8List b) {
  bool at(int offset, List<int> sig) {
    if (b.length < offset + sig.length) return false;
    for (var i = 0; i < sig.length; i++) {
      if (b[offset + i] != sig[i]) return false;
    }
    return true;
  }

  return at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) ||
      at(0, const [0xFF, 0xD8, 0xFF]) ||
      (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
          at(8, const [0x57, 0x45, 0x42, 0x50]));
}

final _assetPattern = RegExp(
  r'^assets/[A-Za-z0-9._/-]+\.(png|jpe?g|webp)$',
  caseSensitive: false,
);

MediaSource? _asset(String s) {
  if (!_assetPattern.hasMatch(s)) return null;
  if (s.split('/').any((seg) => seg.isEmpty || seg == '.' || seg == '..')) {
    return null;
  }
  return MediaAsset(s);
}

// `/storage/<cid>/<file>` with only unreserved characters: no `%` at all
// (no encoded slashes or dots), no whitespace, query, fragment, backslash
// or extra segments (security review, same rule as heroAssetUri).
final _storagePattern = RegExp(
  r'^/storage/([A-Za-z0-9._~-]+)/([A-Za-z0-9._~-]+)$',
);

MediaSource? _storagePath(String s, Uri base) {
  final m = _storagePattern.firstMatch(s);
  if (m == null) return null;
  for (final seg in [m.group(1)!, m.group(2)!]) {
    if (seg == '.' || seg.contains('..')) return null;
  }
  final basePath = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  final Uri out;
  try {
    out = base.replace(path: '$basePath$s');
  } on FormatException {
    return null;
  }
  if (!_sameOrigin(out, base)) return null;
  return MediaNetwork(out);
}

Uri? _apiBaseUri(String raw) {
  final base = Uri.tryParse(_trim(raw));
  if (base == null ||
      !(base.isScheme('https') || base.isScheme('http')) ||
      base.host.isEmpty ||
      base.userInfo.isNotEmpty ||
      base.hasQuery ||
      base.hasFragment) {
    return null;
  }
  return base;
}

String _trim(String raw) => raw.trim().replaceAll(RegExp(r'/+$'), '');

/// Same scheme (http only when the API itself is http, as in local
/// development), host and port as the API base.
bool _sameOrigin(Uri url, Uri? base) {
  if (base == null || base.host.isEmpty) return false;
  if (!(base.isScheme('https') || base.isScheme('http'))) return false;
  return url.scheme.toLowerCase() == base.scheme.toLowerCase() &&
      url.userInfo.isEmpty &&
      url.host.toLowerCase() == base.host.toLowerCase() &&
      url.port == base.port;
}
