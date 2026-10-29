import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api_client.dart';
import '../components/ff_photo_hero.dart' show FFHeroOwnPhoto;
import '../hero_images/device_data.dart';
import '../hero_images/hero_image_files.dart';
import '../hero_images/hero_image_store.dart' show heroDecodeTest;
import 'partner_media_flag.dart';
import 'partner_media_models.dart';

/// A partner photo ready for a band: saved (phones) or loaded in this
/// session (web), and decoded.
typedef PartnerHeroPhoto = FFHeroOwnPhoto;

/// A partner logo ready for the plate.
@immutable
class PartnerLogoImage {
  const PartnerLogoImage({
    required this.id,
    required this.provider,
    required this.aspect,
    required this.dark,
  });

  final String id;
  final ImageProvider provider;
  final double aspect;

  /// The dark plate (a light or white logo).
  final bool dark;

  @override
  bool operator ==(Object other) =>
      other is PartnerLogoImage && other.id == id && other.dark == dark;

  @override
  int get hashCode => Object.hash(id, dark);
}

/// What a home band shows for one partner: its photo and logo, either may
/// be missing.
@immutable
class PartnerHeroMedia {
  const PartnerHeroMedia({this.photo, this.logo});

  final PartnerHeroPhoto? photo;
  final PartnerLogoImage? logo;

  bool get isEmpty => photo == null && logo == null;

  @override
  bool operator ==(Object other) =>
      other is PartnerHeroMedia && other.photo == photo && other.logo == logo;

  @override
  int get hashCode => Object.hash(photo, logo);
}

/// Partner home photos and logos (spec §40.1, plan §1 "App fetch"). Exists
/// only with `PARTNER_MEDIA_UI` (and `PHOTO_HERO_UI`) on; otherwise there is
/// no instance and the app never asks the server.
///
/// - Bundled photos paint first. The homes ask [readyFor] when they are
///   built or come back into view, and keep the answer: nothing here ever
///   changes a band that is on screen.
/// - [refresh] reads `GET /partner/media` (signed in, own data) and saves the
///   live photo (`x2`, at most [maxPhotoBytes]) and logo (`logo256`, at most
///   [maxLogoBytes]): a temporary file then a rename, then a decode test.
///   The files come only from the API host with the session header
///   ([partnerMediaFileUri]).
/// - No live item, a removed or taken-down one, `404 feature_disabled` or a
///   refusal: the saved copy is deleted. Offline: the last saved copy stays.
/// - Data Saver / Low Data Mode: nothing new is downloaded.
/// - Web: nothing on disk; the bytes are kept in memory for the session.
class PartnerMediaStore {
  PartnerMediaStore({
    required ApiClient api,
    HeroFileStore? files,
    DeviceDataProbe? device,
    Future<bool> Function(List<int> bytes)? decodeTest,
    DateTime Function()? clock,
  }) : _api = api,
       _files =
           files ??
           (kIsWeb ? createHeroFileStore() : createPartnerMediaFileStore()),
       _device = device ?? const PlatformDeviceDataProbe(),
       _decodeTest = decodeTest ?? heroDecodeTest,
       _now = clock ?? DateTime.now;

  /// The photo file at most (the server's x2 is at most 150 KB).
  static const int maxPhotoBytes = 200 * 1024;

  /// The logo file at most (the server's logo256 is at most 40 KB).
  static const int maxLogoBytes = 64 * 1024;

  /// The same partner is asked again at most this often by the homes.
  static const Duration refreshEvery = Duration(seconds: 30);

  static const _kIndex = 'partnerMedia.v1.index';

  static PartnerMediaStore? _instance;

  /// The running store, or null with the flag off.
  static PartnerMediaStore? get instance => partnerMediaUi ? _instance : null;

  /// Creates the store (and starts reading the saved copies) when the flag
  /// is on; null otherwise.
  static PartnerMediaStore? startIfEnabled(ApiClient api) {
    if (!partnerMediaUi) return null;
    final s = _instance ??= PartnerMediaStore(api: api);
    unawaited(s.load());
    return s;
  }

  @visibleForTesting
  static set debugInstance(PartnerMediaStore? store) => _instance = store;

  final ApiClient _api;
  final HeroFileStore _files;
  final DeviceDataProbe _device;
  final Future<bool> Function(List<int>) _decodeTest;
  final DateTime Function() _now;

  /// Subject key → what is saved for it.
  final Map<String, _Entry> _index = {};

  /// File name → a decoded image provider.
  final Map<String, ImageProvider> _ready = {};
  final Map<String, DateTime> _asked = {};

  /// Requests in flight, so a home and its settings page share one.
  final Map<String, Future<PartnerMediaOverview?>> _inflight = {};

  /// Partners asked about at least once this session (answered or not).
  final Set<String> _resolved = {};

  /// Whether [subject] has been asked about this session. Until then a home
  /// may show what the first answer brings once, fading it in (web after a
  /// reload, a first sign-in: spec §40.1 "fetched after the first frame").
  bool resolved(PartnerMediaSubject subject) => _resolved.contains(subject.key);
  Future<void>? _loading;
  bool _featureOff = false;

  /// The server answered `404 feature_disabled`: treat as off.
  bool get featureOff => _featureOff;

  Future<void> _queue = Future.value();
  Future<T> _serial<T>(Future<T> Function() job) {
    final c = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await job());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  /// Reads the saved copies (phones): each file is decode-tested before use.
  Future<void> load() => _loading ??= _serial(_load);

  Future<void> _load() async {
    if (!_files.persistent) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kIndex);
      final map = raw == null ? const {} : jsonDecode(raw);
      if (map is Map) {
        for (final e in map.entries) {
          final entry = _Entry.fromJson(e.value);
          if (entry != null) _index[e.key.toString()] = entry;
        }
      }
      final wanted = <String>{for (final e in _index.values) ...e.fileNames};
      for (final name in await _files.list()) {
        if (!wanted.contains(name)) await _files.delete(name);
      }
      for (final key in _index.keys.toList()) {
        final e = _index[key]!;
        final hero = e.hero;
        if (hero != null && !await _check(hero.file, maxPhotoBytes)) {
          e.hero = null;
        }
        final logo = e.logo;
        if (logo != null && !await _check(logo.file, maxLogoBytes)) {
          e.logo = null;
        }
        if (e.hero == null && e.logo == null) _index.remove(key);
      }
      await _saveIndex();
    } catch (_) {
      _index.clear();
      _ready.clear();
      await _files.deleteAll();
    }
  }

  Future<bool> _check(String file, int cap) async {
    final bytes = await _files.read(file);
    if (bytes == null || bytes.length > cap || !await _decodeTest(bytes)) {
      await _files.delete(file);
      return false;
    }
    _ready[file] = _files.provider(file);
    return true;
  }

  /// What the band for [subject] shows now, or null for the bundled photo
  /// and no plate. Homes call this when they are built or come back into
  /// view and keep the answer.
  PartnerHeroMedia? readyFor(PartnerMediaSubject? subject) {
    if (subject == null || _featureOff) return null;
    final e = _index[subject.key];
    if (e == null) return null;
    final hero = e.hero;
    final logo = e.logo;
    final photoP = hero == null ? null : _ready[hero.file];
    final logoP = logo == null ? null : _ready[logo.file];
    final out = PartnerHeroMedia(
      photo: hero == null || photoP == null
          ? null
          : PartnerHeroPhoto(
              id: hero.id,
              provider: photoP,
              focal: Alignment(hero.focalX, hero.focalY),
              aspect: hero.aspect,
            ),
      logo: logo == null || logoP == null
          ? null
          : PartnerLogoImage(
              id: logo.id,
              provider: logoP,
              aspect: logo.aspect,
              dark: logo.dark,
            ),
    );
    return out.isEmpty ? null : out;
  }

  /// Reads `GET /partner/media` for [subject] and saves what is live. At
  /// most every [refreshEvery] per partner unless [force]. Returns the answer
  /// (null when it could not be read). Never throws.
  Future<PartnerMediaOverview?> refresh(
    PartnerMediaSubject subject, {
    bool force = false,
  }) {
    final running = _inflight[subject.key];
    if (running != null) return running;
    final last = _asked[subject.key];
    if (!force && last != null && _now().difference(last) < refreshEvery) {
      return Future.value(null);
    }
    _asked[subject.key] = _now();
    final f = _refresh(subject).whenComplete(() {
      _inflight.remove(subject.key);
      _resolved.add(subject.key);
    });
    _inflight[subject.key] = f;
    return f;
  }

  Future<PartnerMediaOverview?> _refresh(PartnerMediaSubject subject) async {
    await load();
    try {
      final raw = await _api.partnerMedia(gymId: subject.gymId);
      final o = PartnerMediaOverview.tryParse(raw);
      if (o == null) return null;
      await apply(subject, o);
      return o;
    } on ApiException catch (e) {
      if (e.status == 404 && e.code == 'feature_disabled') {
        _featureOff = true;
        await forget(subject);
      } else if (e.status == 403 || e.status == 404 || e.status == 400) {
        // Not this person's partner any more: nothing of it is kept.
        await forget(subject);
      }
      return null;
    } catch (_) {
      // Offline or a timeout: the saved copy stays.
      return null;
    }
  }

  /// Saves what [o] says is live for [subject] (the settings page hands in
  /// its own fresh answer) and deletes what no longer is.
  Future<void> apply(PartnerMediaSubject subject, PartnerMediaOverview o) =>
      _serial(() async {
        _featureOff = false;
        _resolved.add(subject.key);
        final e = _index[subject.key] ?? _Entry();
        e.hero = await _sync(e.hero, o.hero, 'x2', maxPhotoBytes);
        e.logo = await _sync(e.logo, o.logo, 'logo256', maxLogoBytes);
        if (e.hero == null && e.logo == null) {
          _index.remove(subject.key);
        } else {
          _index[subject.key] = e;
        }
        await _saveIndex();
      });

  Future<_Saved?> _sync(
    _Saved? saved,
    PartnerMediaItem? live,
    String variant,
    int cap,
  ) async {
    if (live == null) {
      if (saved != null) await _drop(saved.file);
      return null;
    }
    final name = '${live.id}_$variant.img';
    if (saved != null &&
        saved.id == live.id &&
        _ready.containsKey(saved.file)) {
      // The same item: revalidate the saved file (functions#277 review M1,
      // `no-cache` + ETag). 304 keeps it; 404 means it is gone; offline or
      // any other answer keeps the saved copy. A focal or plate change by
      // FitFlex is taken from the answer as is.
      if (!_files.persistent || saved.etag == null) {
        return _Saved.of(live, saved.file, etag: saved.etag);
      }
      final got = await _download(
        live,
        variant,
        saved.file,
        cap,
        etag: saved.etag,
      );
      switch (got.outcome) {
        case _Fetch.gone:
          await _drop(saved.file);
          return null;
        case _Fetch.fresh:
          return _Saved.of(live, saved.file, etag: got.etag);
        case _Fetch.notModified:
        case _Fetch.failed:
          return _Saved.of(live, saved.file, etag: saved.etag);
      }
    }
    final got = await _download(live, variant, name, cap);
    if (saved != null && saved.file != name) await _drop(saved.file);
    return got.outcome == _Fetch.fresh
        ? _Saved.of(live, name, etag: got.etag)
        : null;
  }

  Future<({_Fetch outcome, String? etag})> _download(
    PartnerMediaItem item,
    String variant,
    String name,
    int cap, {
    String? etag,
  }) async {
    const failed = (outcome: _Fetch.failed, etag: null);
    if ((item.bytes[variant] ?? 0) > cap) return failed;
    final uri = partnerMediaFileUri(item.files[variant], _api.baseUrl);
    if (uri == null) return failed;
    try {
      // Data Saver: nothing new is downloaded (a 304 check still is).
      if (etag == null && await _device.reducedData()) return failed;
    } catch (_) {
      return failed;
    }
    ({int status, Uint8List? bytes, String? etag})? res;
    try {
      // On the web nothing is saved, so no If-None-Match (a custom header
      // would also need a CORS preflight); the browser revalidates.
      res = await _api.partnerMediaFile(
        uri,
        maxBytes: cap,
        etag: _files.persistent ? etag : null,
      );
    } on ApiException catch (e) {
      return e.status == 404 ? (outcome: _Fetch.gone, etag: null) : failed;
    } catch (_) {
      return failed;
    }
    if (res == null) return failed;
    if (res.status == 304) return (outcome: _Fetch.notModified, etag: res.etag);
    final bytes = res.bytes;
    if (bytes == null || !await _decodeTest(bytes)) return failed;
    if (!_files.persistent) {
      _ready[name] = MemoryImage(bytes);
      return (outcome: _Fetch.fresh, etag: res.etag);
    }
    _evict(_ready.remove(name));
    if (!await _files.write(name, bytes)) return failed;
    final back = await _files.read(name);
    if (back == null || !await _decodeTest(back)) {
      await _files.delete(name);
      return failed;
    }
    // Each item has its own name, so an older item's decoded copy in the
    // image cache is never reused.
    _ready[name] = _files.provider(name);
    return (outcome: _Fetch.fresh, etag: res.etag);
  }

  Future<void> _drop(String file) async {
    _evict(_ready.remove(file));
    await _files.delete(file);
  }

  /// Deletes what is saved for [subject].
  Future<void> forget(PartnerMediaSubject subject) => _serial(() async {
    final e = _index.remove(subject.key);
    if (e == null) return;
    for (final f in e.fileNames) {
      await _drop(f);
    }
    await _saveIndex();
  });

  /// Signed out: nothing of the last person stays on the phone.
  Future<void> clearAll() => _serial(() async {
    _index.clear();
    _ready.values.forEach(_evict);
    _ready.clear();
    _asked.clear();
    _resolved.clear();
    await _files.deleteAll();
    if (!_files.persistent) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kIndex);
    } catch (_) {}
  });

  /// Drops a decoded copy from the image cache (none outside an app).
  static void _evict(ImageProvider? p) {
    if (p == null) return;
    try {
      unawaited(p.evict().catchError((Object _) => false));
    } catch (_) {}
  }

  @visibleForTesting
  Set<String> get savedFiles => {for (final e in _index.values) ...e.fileNames};

  Future<void> _saveIndex() async {
    if (!_files.persistent) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kIndex,
        jsonEncode({for (final e in _index.entries) e.key: e.value.toJson()}),
      );
    } catch (_) {}
  }
}

class _Entry {
  _Entry({this.hero, this.logo});

  _Saved? hero;
  _Saved? logo;

  Iterable<String> get fileNames => [?hero?.file, ?logo?.file];

  Map<String, dynamic> toJson() => {
    if (hero != null) 'hero': hero!.toJson(),
    if (logo != null) 'logo': logo!.toJson(),
  };

  static _Entry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return _Entry(
      hero: _Saved.fromJson(raw['hero']),
      logo: _Saved.fromJson(raw['logo']),
    );
  }
}

enum _Fetch { fresh, notModified, gone, failed }

class _Saved {
  const _Saved({
    this.etag,
    required this.id,
    required this.file,
    this.focalX = 0,
    this.focalY = 0,
    this.aspect = 1,
    this.dark = false,
  });

  factory _Saved.of(PartnerMediaItem item, String file, {String? etag}) =>
      _Saved(
        etag: etag,
        id: item.id,
        file: file,
        focalX: item.focalX,
        focalY: item.focalY,
        aspect: item.aspect,
        dark: item.plate == 'dark',
      );

  /// The file's ETag, for revalidation.
  final String? etag;
  final String id;
  final String file;
  final double focalX;
  final double focalY;
  final double aspect;
  final bool dark;

  Map<String, dynamic> toJson() => {
    'id': id,
    'file': file,
    'fx': focalX,
    'fy': focalY,
    'aspect': aspect,
    'dark': dark,
    if (etag != null) 'etag': etag,
  };

  static _Saved? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final file = raw['file'];
    if (id is! String || file is! String || !heroFileName.hasMatch(file)) {
      return null;
    }
    double d(Object? v, double f) => v is num && v.isFinite ? v.toDouble() : f;
    return _Saved(
      id: id,
      file: file,
      focalX: d(raw['fx'], 0).clamp(-1.0, 1.0),
      focalY: d(raw['fy'], 0).clamp(-1.0, 1.0),
      aspect: d(raw['aspect'], 1) <= 0 ? 1 : d(raw['aspect'], 1),
      dark: raw['dark'] == true,
      etag: raw['etag'] is String ? raw['etag'] as String : null,
    );
  }
}
