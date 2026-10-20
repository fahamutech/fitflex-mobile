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

  /// The saved file (phones) or the bytes that loaded and decoded in this
  /// session (web, a [MemoryImage]). Not resized: callers size it to the box
  /// (`heroRemoteImageProvider`).
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
/// - Redirects (the `/storage` address answers 307 to the file store): on
///   phones none are followed automatically; at most [maxRedirects] hops,
///   each on the API_BASE scheme and on the API host or a host listed in
///   `HERO_IMAGES_ALLOWED_HOSTS` ([isAllowedHop]); anything else is refused.
///   The list itself is never redirected.
/// - Web: nothing on disk; the bytes are fetched like on a phone (same size
///   cap and deadline) and used only after they decode in this session. The
///   browser follows redirects itself and does not show the hops, so only
///   the final address is checked against the same rule before the bytes
///   are used (see [_fetch]).
/// - No sign-in token is sent, to the list or to the files.
class HeroImageStore {
  HeroImageStore({
    required String apiBase,
    http.Client? client,
    HeroFileStore? files,
    DeviceDataProbe? device,
    DateTime Function()? clock,
    Future<bool> Function(List<int> bytes)? decodeTest,
    bool? web,
    bool Function()? footerOn,
    Set<String>? allowedHosts,
  }) : _apiBase = apiBase.trim().replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? http.Client(),
       _files = files ?? createHeroFileStore(),
       _device = device ?? const PlatformDeviceDataProbe(),
       _now = clock ?? DateTime.now,
       _decodeTest = decodeTest ?? heroDecodeTest,
       _web = web ?? kIsWeb,
       _footerOn = footerOn ?? (() => photoFooterUi),
       _allowedHosts =
           allowedHosts ?? parseHeroAllowedHosts(kHeroImagesAllowedHosts);

  static const String manifestPath = '/app/hero-images';
  static const Duration checkInterval = Duration(hours: 6);

  /// One deadline for the whole list request: sending and reading it all.
  static const Duration manifestTimeout = Duration(seconds: 5);

  /// One deadline for a whole photo: every hop, sending and reading it all.
  static const Duration fileTimeout = Duration(seconds: 30);

  /// Redirect hops followed for one photo (the `/storage` 307 is one).
  static const int maxRedirects = 2;
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
  final bool _web;
  final bool Function() _footerOn;
  final Set<String> _allowedHosts;

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
      // Streamed with a 256 KB cut-off and one 5 s deadline for the whole
      // request; never redirected.
      final res = await _fetch(
        uri,
        limit: maxManifestBytes,
        deadline: manifestTimeout,
        redirects: 0,
        // No sign-in token. On the web the browser's own HTTP cache
        // revalidates with the ETag; a custom header would need a CORS
        // preflight.
        headers: {if (!_web && etag != null) 'if-none-match': etag},
      );
      _lastCheck = _now();
      await _saveLastCheck();
      // A redirect, an oversize body or not a 200: keep what is saved.
      // (A timeout or no connection throws: caught below, checked again on
      // the next resume.)
      if (res == null || res.status == 304) return;
      final m = HeroManifest.tryParse(
        jsonDecode(utf8.decode(res.bytes)),
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
  /// file is refused (oversize, corrupt, HTTP error, a refused redirect,
  /// the deadline); null when saving failed (stop).
  Future<bool?> _download(HeroManifestEntry e) async {
    final bytes = await _fetchPhoto(e);
    if (bytes == null) return false;
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

  /// Web: nothing on disk. The bytes are fetched as on a phone (same cap,
  /// deadline and address rule), decode-tested (at most
  /// [kHeroMaxDimension] on a side) and kept in memory for this session.
  Future<bool> _loadWeb(HeroManifestEntry e) async {
    final bytes = await _fetchPhoto(e);
    if (bytes == null || !await _decodeTest(bytes)) return false;
    _ready[e.id] = MemoryImage(bytes);
    return true;
  }

  /// The photo's bytes, at most [maxFileBytes] and what is left of today's
  /// budget; null when refused or on any error. The bytes actually read
  /// count towards the daily budget either way.
  Future<Uint8List?> _fetchPhoto(HeroManifestEntry e) async {
    final remaining = dailyBudgetBytes - _budgetBytes;
    final limit = remaining < maxFileBytes ? remaining : maxFileBytes;
    try {
      final got = await _fetch(
        e.uri,
        limit: limit,
        deadline: fileTimeout,
        redirects: maxRedirects,
        onBytes: (n) => _budgetBytes += n,
      );
      return got != null && got.status == 200 ? got.bytes : null;
    } catch (_) {
      return null;
    } finally {
      await _saveBudget();
    }
  }

  /// True when [url] may be requested: the API_BASE scheme (https; http
  /// only when API_BASE itself is http, as in local development), no user
  /// info, and either the API host and port or a host listed in
  /// `HERO_IMAGES_ALLOWED_HOSTS` (an entry without a port means the
  /// scheme's default port).
  @visibleForTesting
  bool isAllowedHop(Uri url) {
    final base = Uri.tryParse(_apiBase);
    if (base == null ||
        !(base.isScheme('https') || base.isScheme('http')) ||
        base.host.isEmpty) {
      return false;
    }
    if (url.scheme != base.scheme) return false;
    if (url.userInfo.isNotEmpty || url.host.isEmpty) return false;
    if (url.host == base.host && url.port == base.port) return true;
    final host = url.host.toLowerCase();
    return _allowedHosts.contains('$host:${url.port}') ||
        (!url.hasPort && _allowedHosts.contains(host));
  }

  /// One GET under one overall [deadline] that covers every hop, the send
  /// and the whole body (cancelled when it passes). Returns the 200 (or 304)
  /// body, or null when refused: more than [redirects] redirect hops, a hop
  /// [isAllowedHop] refuses, another status, or a body over [limit]
  /// (declared, or while reading: reading stops there). Throws on the
  /// deadline or a network error. Bodies that are not used are cancelled so
  /// the connection is let go.
  ///
  /// Phones follow no redirect automatically: each Location is checked
  /// before it is requested. Web: fetch() cannot hand redirects to the app,
  /// so with [redirects] 0 a redirect is an error, and otherwise the browser
  /// follows them itself and only the final address is checked before any
  /// byte is used. The browser may therefore request an intermediate address
  /// on another host (without credentials); nothing it returns is used
  /// unless the final address passes.
  Future<_Got?> _fetch(
    Uri uri, {
    required int limit,
    required Duration deadline,
    required int redirects,
    Map<String, String> headers = const {},
    void Function(int bytes)? onBytes,
  }) async {
    final abort = Completer<void>();
    StreamSubscription<List<int>>? body;
    Future<_Got?> run() async {
      var url = uri;
      for (var hop = 0; ; hop++) {
        if (!isAllowedHop(url)) return null;
        final browserFollows = _web && redirects > 0;
        final req =
            http.AbortableRequest('GET', url, abortTrigger: abort.future)
              ..followRedirects = browserFollows
              ..headers.addAll(headers);
        final res = await _client.send(req);
        if (browserFollows) {
          final landed = switch (res) {
            http.BaseResponseWithUrl(:final url) => url,
            _ => null,
          };
          if (landed == null || !isAllowedHop(landed)) {
            _discard(res);
            return null;
          }
        }
        if (_redirectStatus.contains(res.statusCode)) {
          _discard(res);
          final location = res.headers['location'];
          if (hop >= redirects || location == null) return null;
          final next = Uri.tryParse(location.trim());
          if (next == null) return null;
          url = url.resolveUri(next);
          continue;
        }
        if (res.statusCode == 304) {
          _discard(res);
          return _Got(304, Uint8List(0), res.headers);
        }
        final declared = res.contentLength;
        if (res.statusCode != 200 || (declared != null && declared > limit)) {
          _discard(res);
          return null;
        }
        final bytes = await _readCapped(
          res.stream,
          limit,
          onBytes,
          (s) => body = s,
        );
        return bytes == null ? null : _Got(200, bytes, res.headers);
      }
    }

    try {
      return await run().timeout(deadline);
    } on TimeoutException {
      // Stops the request (or the body being read) now; not awaited, as a
      // stalled connection may take its time to close.
      if (!abort.isCompleted) abort.complete();
      unawaited(body?.cancel());
      rethrow;
    }
  }

  static const _redirectStatus = {301, 302, 303, 307, 308};

  /// Reads [stream] up to [limit] bytes; null (and the stream cancelled)
  /// once it passes.
  static Future<Uint8List?> _readCapped(
    Stream<List<int>> stream,
    int limit,
    void Function(int bytes)? onBytes,
    void Function(StreamSubscription<List<int>> sub) started,
  ) {
    final out = BytesBuilder(copy: false);
    final done = Completer<Uint8List?>();
    late final StreamSubscription<List<int>> sub;
    sub = stream.listen(
      (chunk) {
        if (done.isCompleted) return;
        onBytes?.call(chunk.length);
        if (out.length + chunk.length > limit) {
          done.complete(null);
          unawaited(sub.cancel()); // stops the download
          return;
        }
        out.add(chunk);
      },
      onError: (Object e, StackTrace s) {
        if (!done.isCompleted) done.completeError(e, s);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(out.takeBytes());
      },
      cancelOnError: true,
    );
    started(sub);
    return done.future;
  }

  /// Lets go of a response whose body is not wanted.
  static void _discard(http.StreamedResponse res) {
    try {
      unawaited(res.stream.listen(null, onError: (Object _) {}).cancel());
    } catch (_) {}
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

/// A response body that was read in full.
class _Got {
  const _Got(this.status, this.bytes, this.headers);
  final int status;
  final Uint8List bytes;
  final Map<String, String> headers;
}

/// The largest picture the app accepts, so a small file cannot unpack into
/// a huge image (the server makes 1080-wide files).
const int kHeroMaxDimension = 2400;

/// True when [bytes] is a picture of a sane size (at most
/// [kHeroMaxDimension] on each side) that decodes. Phones read the size from
/// the header and decode only a small copy; the web engine has no header
/// reader, so the browser decodes it once to learn the size. Either way a
/// larger picture is refused and the bundled photo stays.
Future<bool> heroDecodeTest(List<int> bytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(
      Uint8List.fromList(bytes),
    );
    var w = 0;
    var h = 0;
    // Disposes the buffer.
    codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (iw, ih) {
        w = iw;
        h = ih;
        return const ui.TargetImageSize(width: 64);
      },
    );
    if (w <= 0 || h <= 0 || w > kHeroMaxDimension || h > kHeroMaxDimension) {
      return false;
    }
    image = (await codec.getNextFrame()).image;
    return image.width > 0;
  } catch (_) {
    return false;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
