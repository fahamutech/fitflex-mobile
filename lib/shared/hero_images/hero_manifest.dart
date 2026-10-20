import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'hero_image_url.dart';

/// Largest file the app downloads for one photo (plan slice 6). The server
/// keeps the 2x file at or under 150 KB, so this is headroom, not a target.
const int kHeroMaxFileBytes = 200 * 1024;

/// One published photo for a slot, as `GET /app/hero-images` sends it.
/// Only the 2x file ([uri], 1080 wide) is used: the manifest declares its
/// size, which the download checks.
@immutable
class HeroManifestEntry {
  const HeroManifestEntry({
    required this.id,
    required this.sourceId,
    required this.path,
    required this.uri,
    required this.width,
    required this.height,
    required this.bytes,
    required this.focal,
  });

  /// The entry id: changes whenever the file changes, so it names the
  /// cached file.
  final String id;

  /// The scene: a footer never shows the same scene as the page's top photo.
  final String sourceId;

  /// The root-relative `url` from the server (kept for the saved list).
  final String path;

  /// [path] resolved against the API base after validation.
  final Uri uri;
  final int width;
  final int height;

  /// The declared size of the 2x file.
  final int bytes;

  /// Where `BoxFit.cover` keeps the subject (server x, y in -1..1).
  final Alignment focal;

  double get aspect => width > 0 && height > 0 ? width / height : 1;

  Map<String, Object?> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'url': path,
    'width': width,
    'height': height,
    'bytes': bytes,
    'focal': {'x': focal.x, 'y': focal.y},
  };

  /// A valid entry, or null: an entry with a bad id, address, size or
  /// dimensions is dropped (that slot then uses its bundled photo).
  static HeroManifestEntry? tryParse(Object? raw, String apiBase) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final sourceId = raw['sourceId'];
    if (id is! String || !_safeId.hasMatch(id)) return null;
    if (sourceId is! String || sourceId.isEmpty || sourceId.length > 200) {
      return null;
    }
    final path = raw['url'];
    final uri = heroAssetUri(path, apiBase);
    if (uri == null) return null;
    final width = _int(raw['width']);
    final height = _int(raw['height']);
    final bytes = _int(raw['bytes']);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    if (bytes == null || bytes <= 0) return null;
    final f = raw['focal'];
    final fx = f is Map ? _double(f['x']) : null;
    final fy = f is Map ? _double(f['y']) : null;
    return HeroManifestEntry(
      id: id,
      sourceId: sourceId,
      path: path as String,
      uri: uri,
      width: width,
      height: height,
      bytes: bytes,
      focal: Alignment((fx ?? 0).clamp(-1.0, 1.0), (fy ?? 0).clamp(-1.0, 1.0)),
    );
  }
}

/// The published photo list. [version] 0 means "nothing published, or the
/// feature is off": the app deletes its saved photos and uses bundled ones.
@immutable
class HeroManifest {
  const HeroManifest({
    required this.version,
    required this.etag,
    required this.slots,
  });

  static const empty = HeroManifest(version: 0, etag: null, slots: {});

  final int version;

  /// The cache tag to send back as If-None-Match.
  final String? etag;
  final Map<String, List<HeroManifestEntry>> slots;

  bool get isEmpty => version == 0;

  Iterable<HeroManifestEntry> get entries => slots.values.expand((e) => e);

  Map<String, Object?> toJson() => {
    'version': version,
    'etag': etag,
    'slots': {
      for (final s in slots.entries)
        s.key: [for (final e in s.value) e.toJson()],
    },
  };

  /// Parses the server's body. Null when it is not a manifest at all (the
  /// app then keeps what it had). Unknown slots and bad entries are dropped.
  /// `version` may come as a number or a numeric string (a bigint id).
  static HeroManifest? tryParse(
    Object? body,
    String apiBase, {
    String? etag,
    required Set<String> knownSlots,
  }) {
    if (body is! Map) return null;
    final version = _int(body['version']);
    if (version == null || version < 0) return null;
    if (version == 0) {
      return HeroManifest(version: 0, etag: _safeEtag(etag), slots: const {});
    }
    final rawSlots = body['slots'];
    if (rawSlots is! Map) return null;
    final slots = <String, List<HeroManifestEntry>>{};
    for (final s in rawSlots.entries) {
      final key = s.key;
      if (key is! String || !knownSlots.contains(key) || s.value is! List) {
        continue;
      }
      final list = <HeroManifestEntry>[
        for (final raw in s.value as List)
          ?HeroManifestEntry.tryParse(raw, apiBase),
      ];
      if (list.isNotEmpty) slots[key] = list;
    }
    return HeroManifest(
      version: version,
      etag: _safeEtag(etag) ?? '"hp_$version"',
      slots: Map.unmodifiable(slots),
    );
  }
}

/// A cache tag safe to send back in a header: printable ASCII, short.
String? _safeEtag(String? raw) {
  if (raw == null) return null;
  final t = raw.trim();
  if (t.isEmpty || t.length > 100 || !RegExp(r'^[\x21-\x7e]+$').hasMatch(t)) {
    return null;
  }
  return t;
}

/// Entry ids name cached files: letters, digits, `_` and `-` only.
final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,120}$');

int? _int(Object? v) {
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.roundToDouble()) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

double? _double(Object? v) {
  if (v is num && v.isFinite) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}
