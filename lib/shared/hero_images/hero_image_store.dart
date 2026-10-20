import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../components/ff_photo_hero.dart' show FFHeroPhoto;
import '../photo_footer_flag.dart';
import 'device_data.dart';
import 'hero_image_files.dart';
import 'hero_image_flag.dart';
import 'hero_manifest.dart';
import 'hero_slots.dart';

/// A downloaded app photo that is saved and has decoded, ready for a hero
/// or footer the next time one is built.
@immutable
class RemoteHeroImage {
  const RemoteHeroImage({
    required this.entryId,
    required this.sourceId,
    required this.focal,
    required this.aspect,
    required this.provider,
  });

  final String entryId;

  /// The scene (footer rule: never the same as the page's top photo).
  final String sourceId;
  final Alignment focal;

  /// Width / height of the file.
  final double aspect;

  /// The saved file (phones) or the network image that decoded in this
  /// session (web). Not resized: callers size it to the box.
  final ImageProvider provider;

  @override
  bool operator ==(Object other) =>
      other is RemoteHeroImage && other.entryId == entryId;

  @override
  int get hashCode => entryId.hashCode;
}

/// Admin-published app photos (photo-hero increment plan, slice 6): reads
/// `GET /app/hero-images`, keeps the photos on the phone, and tells heroes
/// and footers which saved photo to show. Exists only when
/// `HERO_IMAGES_REMOTE` and `PHOTO_HERO_UI` are on ([startIfEnabled]);
/// otherwise there is no instance and the app never calls the server for
/// photos.
///
/// Rules:
/// - Bundled photos always come first. The list is fetched after the first
///   frame, and on resume when more than 6 hours have passed, with a 5 s
///   timeout and If-None-Match. 304 keeps what is saved; version 0 deletes
///   it all.
/// - Only the slots for the signed-in role plus the pre-sign-in screens are
///   downloaded (and the footer pool when the footer is on).
/// - One file at most [maxFileBytes] (declared size checked first, reading
///   stops past it); at most [maxCacheBytes] kept, least recently used
///   removed first; at most [dailyBudgetBytes] downloaded per day.
/// - Written to a temporary file, renamed, then decode-tested; only then is
///   it used, and only by heroes built after that (never mid-view).
/// - Data Saver / Low Data Mode / Save-Data, or little free storage: no
///   downloads. Any error: the bundled photo.
/// - Web: nothing on disk; a photo is used only after it has decoded in
///   this session.
/// - No sign-in token is sent, to the list or to the files.
class HeroImageStore {
  HeroImageStore({
    required String apiBase,
    http.Client? client,
    HeroFileStore? files,
    DeviceDataProbe? device,
    DateTime Function()? clock,
    Future<bool> Function(List<int> bytes)? decodeTest,
    Future<bool> Function(ImageProvider provider)? precache,
    bool? web,
    bool Function()? footerOn,
  }) : _apiBase = apiBase.trim().replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _files = files ?? createHeroFileStore(),
       _device = device ?? const PlatformDeviceDataProbe(),
       _now = clock ?? DateTime.now,
       _decodeTest = decodeTest ?? heroDecodeTest,
       _precache = precache ?? heroPrecache,
       _web = web ?? kIsWeb,
       _footerOn = footerOn ?? (() => photoFooterUi);

  static const String manifestPath = '/app/hero-images';
  static const Duration checkInterval = Duration(hours: 6);
  static const Duration manifestTimeout = Duration(seconds: 5);
  static const Duration fileTimeout = Duration(seconds: 20);
  static const int maxFileBytes = kHeroMaxFileBytes;
  static const int maxCacheBytes = 4 * 1024 * 1024;
  static const int dailyBudgetBytes = 1536 * 1024;

  /// Below this much free storage nothing is downloaded.
  static const int minFreeBytes = 64 * 1024 * 1024;

  /// A manifest body larger than this is ignored.
  static const int maxManifestBytes = 256 * 1024;

  static const _kManifest = 'heroImages.v1.manifest';
  static const _kIndex = 'heroImages.v1.index';
  static const _kBudget = 'heroImages.v1.budget';
  static const _kLastCheck = 'heroImages.v1.lastCheck';
  static const _kFailed = 'heroImages.v1.failed';

  static HeroImageStore? _instance;

  /// The running store, or null when the flag is off (bundled photos only).
  static HeroImageStore? get instance => heroImagesRemote ? _instance : null;

  /// Creates the store when the flags are on; null (and no store, so no
  /// request ever) when they are off.
  static HeroImageStore? startIfEnabled({required String apiBase}) {
    if (!heroImagesRemote) return null;
    return _instance ??= HeroImageStore(apiBase: apiBase);
  }

  @visibleForTesting
  static set debugInstance(HeroImageStore? store) => _instance = store;

  final String _apiBase;
  final http.Client _client;
  final HeroFileStore _files;
  final DeviceDataProbe _device;
  final DateTime Function() _now;
  final Future<bool> Function(List<int>) _decodeTest;
  final Future<bool> Function(ImageProvider) _precache;
  final bool _web;
  final bool Function() _footerOn;

  HeroManifest _manifest = HeroManifest.empty;

  /// Saved files: entry id → size and last use (ms since epoch).
  final Map<String, _Saved> _index = {};

  /// Entries that are saved (or, on the web, loaded) and decoded.
  final Map<String, ImageProvider> _ready = {};

  /// Entries that failed today (oversize, corrupt): not retried until
  /// tomorrow, so they cannot eat the daily budget.
  final Map<String, String> _failed = {};
  String _budgetDay = '';
  int _budgetBytes = 0;
  DateTime? _lastCheck;
  bool _loaded = false;
  bool _signedIn = false;
  String? _role;

  /// What the most recently built top hero of each slot showed (null:
  /// bundled), so its page's footer can keep a different scene.
  final Map<String, RemoteHeroImage?> _lastTop = {};

  Future<void> _queue = Future.value();

  HeroManifest get manifest => _manifest;

  @visibleForTesting
  Set<String> get readyIds => _ready.keys.toSet();

  @visibleForTesting
  int get savedBytes => _index.values.fold(0, (a, s) => a + s.bytes);

  @visibleForTesting
  int get bytesToday => _budgetDay == heroDayKey(_now()) ? _budgetBytes : 0;

  // ── lifecycle ────────────────────────────────────────────────────────

  /// After the app's first frame: load what is saved, check the list, then
  /// download what is missing.
  Future<void> onFirstFrame() => _serial(() async {
    await _load();
    await _checkManifest();
    await _sync();
  });

  /// The app came back: check again if the last check is over 6 hours old.
  Future<void> onResume() => _serial(() async {
    await _load();
    final last = _lastCheck;
    if (last != null && _now().difference(last) < checkInterval) return;
    await _checkManifest();
    await _sync();
  });

  /// Sign-in, sign-out or a role switch: different slots matter now.
  Future<void> setSession({required bool signedIn, String? role}) {
    if (signedIn == _signedIn && role == _role) return _queue;
    _signedIn = signedIn;
    _role = role;
    return _serial(() async {
      if (!_loaded) return; // the first-frame run downloads them
      await _sync();
    });
  }

  Future<void> _serial(Future<void> Function() job) {
    final next = _queue.then((_) => job()).catchError((Object _) {});
    _queue = next;
    return next;
  }

  // ── what to show ─────────────────────────────────────────────────────

  /// The saved photo for [photo]'s slot today, or null for the bundled
  /// photo. Heroes call this once when they are first built and keep the
  /// answer, so a photo saved later shows only on the next build.
  RemoteHeroImage? resolveTop(FFHeroPhoto photo) {
    final slot = heroSlotOf[photo];
    if (slot == null || slot == kFooterPoolSlot) return null;
    final r = _pickTop(slot);
    _lastTop[slot] = r;
    return r;
  }

  /// Like [resolveTop] without recording it (pre-caching).
  RemoteHeroImage? peekTop(FFHeroPhoto photo) {
    final slot = heroSlotOf[photo];
    if (slot == null || slot == kFooterPoolSlot) return null;
    return _pickTop(slot);
  }

  RemoteHeroImage? _pickTop(String slot) {
    final list = _manifest.slots[slot];
    if (list == null || list.isEmpty) return null;
    final e = list[heroRotationIndex(_now(), slot, list.length)];
    return _readyImage(e);
  }

  /// The scene the page's top photo shows: what its hero last resolved
  /// (remote or bundled), else what it would show now.
  String? topSourceIdFor(FFHeroPhoto? top) {
    if (top == null) return null;
    final slot = heroSlotOf[top];
    if (slot != null && _lastTop.containsKey(slot)) {
      return _lastTop[slot]?.sourceId ?? top.sourceId;
    }
    return peekTop(top)?.sourceId ?? top.sourceId;
  }

  /// A saved footer-pool photo for [pageKey] today, never from the scene of
  /// the page's top photo [top] (bundled or remote); null for the bundled
  /// footer.
  RemoteHeroImage? resolveFooter(String pageKey, {FFHeroPhoto? top}) {
    final list = _manifest.slots[kFooterPoolSlot];
    if (list == null || list.isEmpty) return null;
    final avoid = {?top?.sourceId, ?topSourceIdFor(top)};
    final start = heroRotationIndex(
      _now(),
      kFooterPoolSlot,
      list.length,
      salt: pageKey,
    );
    for (var i = 0; i < list.length; i++) {
      final e = list[(start + i) % list.length];
      if (avoid.contains(e.sourceId)) continue;
      final r = _readyImage(e);
      if (r != null) return r;
    }
    return null;
  }

  RemoteHeroImage? _readyImage(HeroManifestEntry e) {
    final p = _ready[e.id];
    if (p == null) return null;
    final saved = _index[e.id];
    if (saved != null) saved.lastUsed = _now().millisecondsSinceEpoch;
    return RemoteHeroImage(
      entryId: e.id,
      sourceId: e.sourceId,
      focal: e.focal,
      aspect: e.aspect,
      provider: p,
    );
  }

  // ── loading what is saved ────────────────────────────────────────────

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    if (!_files.persistent) return; // web: memory only
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_kLastCheck);
      if (last != null) {
        _lastCheck = DateTime.fromMillisecondsSinceEpoch(last);
      }
      final budget = _decodeMap(prefs.getString(_kBudget));
      _budgetDay = budget['day']?.toString() ?? '';
      _budgetBytes = (budget['bytes'] as num?)?.toInt() ?? 0;
      _decodeMap(prefs.getString(_kFailed)).forEach((k, v) {
        if (v is String) _failed[k] = v;
      });
      final savedManifest = _decodeMap(prefs.getString(_kManifest));
      final m = savedManifest.isEmpty
          ? null
          : HeroManifest.tryParse(
              savedManifest,
              _apiBase,
              etag: savedManifest['etag']?.toString(),
              knownSlots: kMobileHeroSlots,
            );
      _manifest = m ?? HeroManifest.empty;
      _decodeMap(prefs.getString(_kIndex)).forEach((id, v) {
        if (v is Map) {
          _index[id] = _Saved(
            (v['bytes'] as num?)?.toInt() ?? 0,
            (v['lastUsed'] as num?)?.toInt() ?? 0,
          );
        }
      });
      // Files the list no longer names, or that the index does not know.
      final wanted = {for (final e in _manifest.entries) e.id};
      for (final name in await _files.list()) {
        final id = name.substring(0, name.length - 4);
        if (!wanted.contains(id) || !_index.containsKey(id)) {
          await _files.delete(name);
          _index.remove(id);
        }
      }
      _index.removeWhere((id, _) => !wanted.contains(id));
      // Decode-test every saved file before it is used again.
      for (final id in _index.keys.toList()) {
        final bytes = await _files.read(_fileName(id));
        if (bytes == null || bytes.length > maxFileBytes) {
          await _forget(id);
          continue;
        }
        if (!await _decodeTest(bytes)) {
          await _forget(id);
          continue;
        }
        _ready[id] = _files.provider(_fileName(id));
      }
      await _saveIndex();
    } catch (_) {
      // Anything odd: start from nothing (bundled photos).
      await _purge();
    }
  }

  // ── the list ─────────────────────────────────────────────────────────

  Future<void> _checkManifest() async {
    final uri = Uri.tryParse('$_apiBase$manifestPath');
    if (uri == null) return;
    try {
      final etag = _manifest.etag;
      final res = await _client
          .get(
            uri,
            // No sign-in token. On the web the browser's own HTTP cache
            // revalidates with the ETag; a custom header would need a CORS
            // preflight.
            headers: {if (!_web && etag != null) 'if-none-match': etag},
          )
          .timeout(manifestTimeout);
      _lastCheck = _now();
      await _saveLastCheck();
      if (res.statusCode == 304) return;
      if (res.statusCode != 200) return; // keep what is saved
      if (res.bodyBytes.length > maxManifestBytes) return;
      final m = HeroManifest.tryParse(
        jsonDecode(utf8.decode(res.bodyBytes)),
        _apiBase,
        etag: res.headers['etag'],
        knownSlots: kMobileHeroSlots,
      );
      if (m == null) return;
      if (m.isEmpty) {
        await _purge();
        _manifest = m;
        await _saveManifest();
        return;
      }
      _manifest = m;
      // Photos no longer published (unpublished, replaced) are deleted.
      final wanted = {for (final e in m.entries) e.id};
      for (final id in {..._index.keys, ..._ready.keys}.toList()) {
        if (!wanted.contains(id)) await _forget(id);
      }
      _failed.removeWhere((id, _) => !wanted.contains(id));
      await _saveManifest();
      await _saveIndex();
    } catch (_) {
      // Offline, timeout, bad JSON: keep what is saved.
    }
  }

  // ── downloads ────────────────────────────────────────────────────────

  Future<void> _sync() async {
    if (_manifest.isEmpty) return;
    try {
      if (await _device.reducedData()) return;
      final free = await _device.freeBytes();
      if (free != null && free < minFreeBytes) return;
    } catch (_) {
      return;
    }
    final today = heroDayKey(_now());
    if (_budgetDay != today) {
      _budgetDay = today;
      _budgetBytes = 0;
    }
    _failed.removeWhere((_, day) => day != today);
    for (final e in _plan()) {
      if (_ready.containsKey(e.id) || _failed.containsKey(e.id)) continue;
      if (e.bytes > maxFileBytes) {
        _failed[e.id] = today;
        continue;
      }
      if (_budgetBytes + e.bytes > dailyBudgetBytes) break;
      final ok = _web ? await _loadWeb(e) : await _download(e);
      if (ok == null) break; // storage trouble: stop for now
      if (!ok) _failed[e.id] = today;
    }
    await _saveIndex();
  }

  /// Entries to fetch, most useful first: each relevant slot's photo for
  /// today, then the rest of those slots.
  List<HeroManifestEntry> _plan() {
    final slots = relevantHeroSlots(
      signedIn: _signedIn,
      role: _role,
      footer: _footerOn(),
    );
    final first = <HeroManifestEntry>[];
    final rest = <HeroManifestEntry>[];
    for (final slot in slots) {
      final list = _manifest.slots[slot];
      if (list == null || list.isEmpty) continue;
      if (slot == kFooterPoolSlot) {
        rest.addAll(list);
        continue;
      }
      final pick = heroRotationIndex(_now(), slot, list.length);
      for (var i = 0; i < list.length; i++) {
        (i == pick ? first : rest).add(list[i]);
      }
    }
    final seen = <String>{};
    return [
      for (final e in [...first, ...rest])
        if (seen.add(e.id)) e,
    ];
  }

  /// Phones: download, save, decode-test. True when ready; false when this
  /// file is refused (oversize, corrupt, HTTP error); null when saving
  /// failed (stop).
  Future<bool?> _download(HeroManifestEntry e) async {
    final remaining = dailyBudgetBytes - _budgetBytes;
    final limit = remaining < maxFileBytes ? remaining : maxFileBytes;
    final List<int> bytes;
    try {
      final got = await _fetchCapped(e.uri, limit);
      if (got == null) return false;
      bytes = got;
    } catch (_) {
      return false;
    }
    await _makeRoom(bytes.length);
    final name = _fileName(e.id);
    if (!await _files.write(name, bytes)) return null;
    final back = await _files.read(name);
    if (back == null || !await _decodeTest(back)) {
      await _files.delete(name);
      return false;
    }
    _index[e.id] = _Saved(bytes.length, _now().millisecondsSinceEpoch);
    _ready[e.id] = _files.provider(name);
    return true;
  }

  /// The file's bytes, or null when it is not a 200 or passes [limit]
  /// (declared length, or while reading: reading stops there). The bytes
  /// read count towards the daily budget either way.
  Future<List<int>?> _fetchCapped(Uri uri, int limit) async {
    final req = http.Request('GET', uri)
      ..followRedirects = true
      ..maxRedirects = 3; // the /storage address redirects to the store
    final res = await _client.send(req).timeout(fileTimeout);
    final out = BytesBuilder(copy: false);
    var tooBig = false;
    try {
      if (res.statusCode != 200) return null;
      final declared = res.contentLength;
      if (declared != null && declared > limit) return null;
      await for (final chunk in res.stream.timeout(fileTimeout)) {
        _budgetBytes += chunk.length;
        if (out.length + chunk.length > limit) {
          tooBig = true;
          break; // cancels the download
        }
        out.add(chunk);
      }
    } finally {
      await _saveBudget();
    }
    if (tooBig) return null;
    return out.takeBytes();
  }

  /// Web: no disk; the browser loads it and it must decode in this session.
  Future<bool> _loadWeb(HeroManifestEntry e) async {
    _budgetBytes += e.bytes;
    final provider = NetworkImage(e.uri.toString());
    bool ok;
    try {
      ok = await _precache(provider).timeout(fileTimeout);
    } catch (_) {
      ok = false;
    }
    if (ok) _ready[e.id] = provider;
    return ok;
  }

  /// Removes the least recently used photos until [incoming] fits.
  Future<void> _makeRoom(int incoming) async {
    while (_index.isNotEmpty && savedBytes + incoming > maxCacheBytes) {
      final oldest = _index.entries.reduce(
        (a, b) => a.value.lastUsed <= b.value.lastUsed ? a : b,
      );
      await _forget(oldest.key);
    }
  }

  Future<void> _forget(String id) async {
    _index.remove(id);
    _ready.remove(id);
    await _files.delete(_fileName(id));
  }

  /// Version 0 (or a broken save): delete every saved photo.
  Future<void> _purge() async {
    _index.clear();
    _ready.clear();
    _failed.clear();
    _manifest = HeroManifest.empty;
    await _files.deleteAll();
    if (!_files.persistent) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kManifest);
      await prefs.remove(_kIndex);
      await prefs.remove(_kFailed);
    } catch (_) {}
  }

  // ── saving state (phones only) ───────────────────────────────────────

  Future<void> _saveManifest() async {
    if (!_files.persistent) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kManifest, jsonEncode(_manifest.toJson()));
    } catch (_) {}
  }

  Future<void> _saveIndex() async {
    if (!_files.persistent) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kIndex,
        jsonEncode({
          for (final s in _index.entries)
            s.key: {'bytes': s.value.bytes, 'lastUsed': s.value.lastUsed},
        }),
      );
      await prefs.setString(_kFailed, jsonEncode(_failed));
      await _saveBudget();
    } catch (_) {}
  }

  Future<void> _saveBudget() async {
    if (!_files.persistent) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kBudget,
        jsonEncode({'day': _budgetDay, 'bytes': _budgetBytes}),
      );
    } catch (_) {}
  }

  Future<void> _saveLastCheck() async {
    if (!_files.persistent) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastCheck, _lastCheck!.millisecondsSinceEpoch);
    } catch (_) {}
  }

  static String _fileName(String id) => '$id.img';

  static Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final v = jsonDecode(raw);
      return v is Map<String, dynamic> ? v : const {};
    } catch (_) {
      return const {};
    }
  }
}

class _Saved {
  _Saved(this.bytes, this.lastUsed);
  final int bytes;
  int lastUsed;
}

/// The largest picture the app accepts, so a small file cannot unpack into
/// a huge image (the server makes 1080-wide files).
const int kHeroMaxDimension = 2400;

/// True when [bytes] is a picture of a sane size that decodes. Reads the
/// size from the header first, then decodes a small copy.
Future<bool> heroDecodeTest(List<int> bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes));
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final w = descriptor.width;
    final h = descriptor.height;
    if (w <= 0 || h <= 0 || w > kHeroMaxDimension || h > kHeroMaxDimension) {
      return false;
    }
    final codec = await descriptor.instantiateCodec(targetWidth: 64);
    final frame = await codec.getNextFrame();
    final ok = frame.image.width > 0;
    frame.image.dispose();
    codec.dispose();
    return ok;
  } catch (_) {
    return false;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

/// Resolves [provider] into the image cache, like `precacheImage`, without
/// a widget: true once it decodes, false on error.
Future<bool> heroPrecache(ImageProvider provider) {
  final done = Completer<bool>();
  final stream = provider.resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (image, _) {
      if (!done.isCompleted) done.complete(true);
      // The decoded image stays in the image cache for the hero.
      scheduleMicrotask(() => stream.removeListener(listener));
    },
    onError: (_, _) {
      if (!done.isCompleted) done.complete(false);
      scheduleMicrotask(() => stream.removeListener(listener));
    },
  );
  stream.addListener(listener);
  return done.future;
}
