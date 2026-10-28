// Shop Phase 2 S3: "Popular near you" (flag SHOP_NEAR_YOU on the server).
// Spec: docs/design/shop-home-phase2.md §7 (parent repo).
//
// Privacy rules this file keeps (owner decision O-7, DD-P2-9):
// - The phone works out the area itself, from GET /shop/areas. Only the
//   area's id is ever sent: in the `X-FF-Area` header of GET /shop/home and
//   the product list / details, and only while the last home answer said
//   near-you is available. It is
//   redacted from the app's own debug log (rest_log.dart).
// - The position is read with low accuracy, used once to pick the area and
//   then dropped. It is never stored, logged or sent anywhere.
// - What is kept on the device, per signed-in account: whether the shop may
//   use location ("on" / "off") and the area id last worked out. Nothing
//   else (no coordinates, no area name; names are read from /shop/areas).
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'shop_home.dart' show ShopText;

/// One active area from GET /shop/areas.
class ShopArea {
  const ShopArea({
    required this.id,
    required this.name,
    required this.level,
    this.parentId,
    this.lat,
    this.lng,
    this.radiusKm,
    this.names,
    this.locatable,
  });

  /// `locatable` from the server (M1): only `true` areas may stand for
  /// "where you are" (big enough circle; never the country). False rows
  /// are still offered in the vendor pickers. Null from a backend that
  /// does not send it: then only an area with a circle can match.
  final bool? locatable;

  final String id;

  /// The stored place name (place names are not translated).
  final String name;

  /// `names: {en, sw}` when the server sends it (for a translated name
  /// later); [nameIn] falls back to [name].
  final ShopText? names;

  String nameIn(String lang) {
    final n = names?.of(lang) ?? '';
    return n.isNotEmpty ? n : name;
  }

  /// `country`, `region`, `city` or `district`.
  final String level;
  final String? parentId;
  final double? lat;
  final double? lng;
  final double? radiusKm;

  static const levels = ['country', 'region', 'city', 'district'];

  /// How specific the level is: district 3, city 2, region 1, country 0,
  /// anything else -1.
  int get depth => levels.indexOf(level);

  static double? _num(Object? v) {
    if (v is num && v.isFinite) return v.toDouble();
    final parsed = double.tryParse(v?.toString() ?? '');
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  /// Null for a row without an id, a name or a known level.
  static ShopArea? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id']?.toString() ?? '';
    final name = json['name']?.toString().trim() ?? '';
    final level = json['level']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty || !levels.contains(level)) return null;
    final parent = json['parentId']?.toString();
    return ShopArea(
      id: id,
      name: name,
      level: level,
      parentId: parent == null || parent.isEmpty ? null : parent,
      lat: _num(json['lat']),
      lng: _num(json['lng']),
      radiusKm: _num(json['radiusKm']),
      names: ShopText.fromJson(json['names']),
      locatable: json['locatable'] is bool ? json['locatable'] as bool : null,
    );
  }

  /// Reads `{areas: [...]}` or a bare list.
  static List<ShopArea> listFromJson(Object? json) {
    final raw = json is Map ? json['areas'] : json;
    if (raw is! List) return const [];
    return raw.map(ShopArea.fromJson).whereType<ShopArea>().toList();
  }
}

/// Great-circle distance in km (the same formula as the server's
/// `distanceKm` in promotion-rules).
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final h =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * 6371 * math.asin(math.sqrt(h.toDouble()));
}

/// The area a point is in: among areas the server marks `locatable`, the
/// most specific (district, then city, then region) whose circle (centre +
/// `radiusKm`) contains it. Non-locatable areas, areas without a centre or
/// a positive radius, and the country never match. Ties go to the
/// smaller circle, then the nearer centre. Null when none contains it.
///
/// Pure: runs on the phone, and nothing about the point leaves it.
ShopArea? areaFor(double lat, double lng, List<ShopArea> areas) {
  if (!lat.isFinite || !lng.isFinite) return null;
  ShopArea? best;
  double bestDistance = double.infinity;
  for (final a in areas) {
    final aLat = a.lat, aLng = a.lng, r = a.radiusKm;
    if (a.locatable == false) continue;
    if (aLat == null || aLng == null || r == null || r <= 0) continue;
    if (a.depth < 1) continue;
    final d = haversineKm(lat, lng, aLat, aLng);
    if (d > r) continue;
    if (best == null ||
        a.depth > best.depth ||
        (a.depth == best.depth &&
            (r < best.radiusKm! ||
                (r == best.radiusKm! && d < bestDistance)))) {
      best = a;
      bestDistance = d;
    }
  }
  return best;
}

/// `nearYou` on GET /shop/home. [available] is true only when the server's
/// SHOP_NEAR_YOU is on and personalisation is available and switched on for
/// this account: only then may the app read the location for the shop.
/// [areaId] / [areaName] echo the area the request was answered for; both
/// are absent when the area sent was not recognised (the rail is then
/// hidden).
class ShopNearYou {
  const ShopNearYou({required this.available, this.areaId, this.areaName});
  final bool available;
  final String? areaId;
  final ShopText? areaName;

  static ShopNearYou? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['areaId']?.toString().trim() ?? '';
    final rawName = json['areaName'];
    return ShopNearYou(
      available: json['available'] == true,
      areaId: id.isEmpty ? null : id,
      areaName: rawName is String
          ? (rawName.trim().isEmpty ? null : ShopText(rawName, rawName))
          : ShopText.fromJson(rawName),
    );
  }
}

/// What this account chose on this device about location in the shop.
enum ShopNearYouChoice {
  /// Never answered: the invite card may be shown.
  notAsked,

  /// "Use my location" and the OS allowed it.
  on,

  /// "Not now", or the OS refused: nothing is shown until turned on again
  /// from the Why sheet or Privacy & data.
  off,
}

/// The device's record for one account. Never holds coordinates.
class ShopNearYouState {
  const ShopNearYouState({
    this.choice = ShopNearYouChoice.notAsked,
    this.areaId,
    this.areaName,
    this.manual = false,
  });

  final ShopNearYouChoice choice;

  /// The area last worked out (or picked), sent in `X-FF-Area`.
  final String? areaId;

  /// For display this session only; never stored.
  final String? areaName;

  /// The area was picked by hand ("Change area") this session: the position
  /// is not read again this session. Never stored.
  final bool manual;

  static const empty = ShopNearYouState();

  /// What is stored on the device: the choice and the area id only.
  Map<String, dynamic> toJson() => {'choice': choice.name, 'areaId': ?areaId};

  static ShopNearYouState fromJson(Object? json) {
    if (json is! Map) return empty;
    final choice = ShopNearYouChoice.values.firstWhere(
      (c) => c.name == json['choice'],
      orElse: () => ShopNearYouChoice.notAsked,
    );
    final id = json['areaId']?.toString() ?? '';
    return ShopNearYouState(
      choice: choice,
      // An area only means something while the choice is on.
      areaId: choice == ShopNearYouChoice.on && id.isNotEmpty ? id : null,
    );
  }
}

/// Keeps [ShopNearYouState] per account on the device (and in memory for
/// the session). Every storage failure is swallowed: the shop just behaves
/// as if nothing was chosen.
class ShopNearYouStore {
  ShopNearYouStore._();

  static const _prefix = 'ff.shop.nearYou';
  static final Map<String, ShopNearYouState> _memory = {};

  /// Accounts whose position was already read this app session.
  static final Set<String> _readThisSession = {};

  /// Whether the last GET /shop/home answer for an account said near-you
  /// is available (L1): the area is sent only then. Memory only.
  static final Map<String, bool> _lastAvailable = {};

  /// The area to send for [userId] right now, or null: near-you on, an
  /// area kept, and the last Shop home answer said available (L1). Used for
  /// GET /shop/home, /shop/products and /shop/products/:id.
  static String? areaToSend(String? userId) {
    final state = _memory[_id(userId)];
    if (state == null || state.choice != ShopNearYouChoice.on) return null;
    return lastAvailable(userId) ? state.areaId : null;
  }

  static bool lastAvailable(String? userId) =>
      _lastAvailable[_id(userId)] == true;

  /// Records the last Shop home answer. Flipping to available while an
  /// area is kept bumps [changes], so screens that loaded first (Results, a
  /// product sheet opened from a link) ask again with the area (QA2 #1).
  static void setLastAvailable(String? userId, bool available) {
    final was = _lastAvailable[_id(userId)] == true;
    _lastAvailable[_id(userId)] = available;
    if (available && !was && areaToSend(userId) != null) changes.value++;
  }

  /// Whether a Shop home answer was seen for [userId] this session.
  static bool availabilityKnown(String? userId) =>
      _lastAvailable.containsKey(_id(userId));

  static final Map<String, Future<void>> _probes = {};

  /// For a screen that loads without the Shop home (cold Results, a
  /// `?product=` link): once a session, and only when near-you is on with a
  /// kept area, ask GET /shop/home (without the area) whether near-you is
  /// available. Nothing location-derived is sent. Failures are ignored.
  static Future<void> probe(
    ApiClient api,
    String? userId, {
    String? mode,
  }) async {
    final state = await load(userId);
    if (state.choice != ShopNearYouChoice.on || state.areaId == null) return;
    if (availabilityKnown(userId)) return;
    final id = _id(userId);
    return _probes[id] ??= () async {
      try {
        final json = await api.shopHome(mode: mode);
        final near = ShopNearYou.fromJson(json['nearYou']);
        final p = json['personalisation'];
        if (near?.available == false || (p is Map && p['enabled'] == false)) {
          setLastAvailable(userId, false);
          await clear(userId);
        } else {
          setLastAvailable(userId, near?.available == true);
        }
      } catch (_) {
        // Unknown: nothing is sent until the Shop home answers.
      }
    }();
  }

  /// Bumped whenever an account's choice or area changes, so a Shop home
  /// kept alive in another tab reloads with the new area (or without one).
  static final ValueNotifier<int> changes = ValueNotifier(0);

  static String _id(String? userId) =>
      userId == null || userId.isEmpty ? '_' : userId;

  static String _key(String? userId) => '$_prefix.${_id(userId)}';

  static Future<ShopNearYouState> load(String? userId) async {
    final id = _id(userId);
    final mem = _memory[id];
    if (mem != null) return mem;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(userId));
      final state = raw == null
          ? ShopNearYouState.empty
          : ShopNearYouState.fromJson(jsonDecode(raw));
      return _memory[id] = state;
    } catch (_) {
      return ShopNearYouState.empty;
    }
  }

  /// The state already loaded this session (null before [load]).
  static ShopNearYouState? peek(String? userId) => _memory[_id(userId)];

  static Future<void> save(String? userId, ShopNearYouState state) async {
    _memory[_id(userId)] = state;
    changes.value++;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(userId), jsonEncode(state.toJson()));
    } catch (_) {
      // Kept for this session only.
    }
  }

  /// Forgets the choice and the area ("Personalised shop" switched off).
  static Future<void> clear(String? userId) async {
    final before = _memory[_id(userId)];
    _memory[_id(userId)] = ShopNearYouState.empty;
    _readThisSession.remove(_id(userId));
    // Only a real change reloads the Shop home (the switch reloads it too).
    if (before != null && before.choice != ShopNearYouChoice.notAsked) {
      changes.value++;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (_) {
      // Nothing kept anyway once the app restarts without it.
    }
  }

  static bool readThisSession(String? userId) =>
      _readThisSession.contains(_id(userId));
  static void markRead(String? userId) => _readThisSession.add(_id(userId));

  @visibleForTesting
  static void reset() {
    _memory.clear();
    _readThisSession.clear();
    _lastAvailable.clear();
    _probes.clear();
  }
}

/// GET /shop/areas, asked once per session. A backend without it (404, a
/// non-JSON answer, SHOP_NEAR_YOU off) means no areas: the shop then behaves
/// as before (distance filter kept, no area pickers).
class ShopAreas {
  ShopAreas._();

  static final Expando<List<ShopArea>> _cache = Expando('shopAreas');

  /// The areas, or an empty list when there are none or the call failed.
  /// A clear "not here" (404, non-JSON) is remembered for the session; a
  /// network or server failure is not, so the next call asks again.
  static Future<List<ShopArea>> load(
    ApiClient api, {
    bool refresh = false,
  }) async {
    final cached = _cache[api];
    if (cached != null && !refresh) return cached;
    try {
      return _cache[api] = ShopArea.listFromJson(await api.shopAreas());
    } on ApiException catch (e) {
      if (e.status == 404) _cache[api] = const [];
      return const [];
    } on FormatException {
      return _cache[api] = const [];
    } catch (_) {
      return const [];
    }
  }

  /// Like [load], but null when the list could not be fetched (no
  /// connection, 5xx): the caller says "Couldn't find your area" with Try
  /// again, not "no sellers here". 404 / non-JSON = no areas (empty).
  static Future<List<ShopArea>?> tryLoad(ApiClient api) async {
    final cached = _cache[api];
    if (cached != null && cached.isNotEmpty) return cached;
    try {
      return _cache[api] = ShopArea.listFromJson(await api.shopAreas());
    } on ApiException catch (e) {
      if (e.status == 404) return _cache[api] = const [];
      return null;
    } on FormatException {
      return _cache[api] = const [];
    } catch (_) {
      return null;
    }
  }

  /// The areas already loaded for [api] this session, else null.
  static List<ShopArea>? peek(ApiClient api) => _cache[api];

  /// Like [load] but throws on failure (the vendor pickers say so).
  static Future<List<ShopArea>> loadOrThrow(ApiClient api) async {
    final cached = _cache[api];
    if (cached != null && cached.isNotEmpty) return cached;
    return _cache[api] = ShopArea.listFromJson(await api.shopAreas());
  }
}

/// Whether the OS lets the app read the location.
enum ShopLocationAccess { granted, denied, deniedForever, servicesOff }

/// The location calls the shop makes, so tests can stand in for the OS.
abstract class ShopLocator {
  Future<bool> servicesEnabled();

  /// The current permission, without asking.
  Future<ShopLocationAccess> check();

  /// Shows the OS / browser prompt (only after the rationale sheet).
  Future<ShopLocationAccess> request();

  /// One low-accuracy fix, or null when none came within [timeout]. The
  /// caller uses it once and drops it.
  Future<({double lat, double lng})?> position({
    Duration timeout = const Duration(seconds: 10),
  });

  Future<void> openAppSettings();

  /// Phones can open the app's settings; a browser cannot.
  bool get canOpenSettings;
}

class GeolocatorShopLocator implements ShopLocator {
  const GeolocatorShopLocator();

  static ShopLocationAccess _map(LocationPermission p) => switch (p) {
    LocationPermission.always ||
    LocationPermission.whileInUse => ShopLocationAccess.granted,
    LocationPermission.deniedForever => ShopLocationAccess.deniedForever,
    _ => ShopLocationAccess.denied,
  };

  @override
  Future<bool> servicesEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<ShopLocationAccess> check() async =>
      _map(await Geolocator.checkPermission());

  @override
  Future<ShopLocationAccess> request() async =>
      _map(await Geolocator.requestPermission());

  @override
  Future<({double lat, double lng})?> position({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final p = await Geolocator.getCurrentPosition(
        // Low accuracy: an area is all the shop needs (coarse on Android).
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: timeout,
        ),
      ).timeout(timeout + const Duration(seconds: 1));
      return (lat: p.latitude, lng: p.longitude);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> openAppSettings() => Geolocator.openAppSettings();

  @override
  bool get canOpenSettings => !kIsWeb;
}

@visibleForTesting
ShopLocator? debugShopLocatorOverride;

ShopLocator get shopLocator =>
    debugShopLocatorOverride ?? const GeolocatorShopLocator();

/// What came of trying to work out the area.
enum ShopAreaOutcome {
  found,
  noArea,
  unavailable,
  denied,
  deniedForever,
  servicesOff,
}

/// Works out the area on the phone: permission (asking only when [ask]),
/// one low-accuracy fix, then [areaFor] over [areas]. The position never
/// leaves this function.
Future<(ShopAreaOutcome, ShopArea?)> detectShopArea({
  required List<ShopArea> areas,
  required bool ask,
  ShopLocator? locator,
}) async {
  final loc = locator ?? shopLocator;
  try {
    if (!await loc.servicesEnabled()) {
      return (ShopAreaOutcome.servicesOff, null);
    }
    var access = await loc.check();
    if (access == ShopLocationAccess.denied && ask) {
      access = await loc.request();
    }
    switch (access) {
      case ShopLocationAccess.granted:
        break;
      case ShopLocationAccess.deniedForever:
        return (ShopAreaOutcome.deniedForever, null);
      case ShopLocationAccess.servicesOff:
        return (ShopAreaOutcome.servicesOff, null);
      case ShopLocationAccess.denied:
        return (ShopAreaOutcome.denied, null);
    }
    final fix = await loc.position();
    if (fix == null) return (ShopAreaOutcome.unavailable, null);
    final area = areaFor(fix.lat, fix.lng, areas);
    return area == null
        ? (ShopAreaOutcome.noArea, null)
        : (ShopAreaOutcome.found, area);
  } catch (_) {
    return (ShopAreaOutcome.unavailable, null);
  }
}
