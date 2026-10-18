// Shop home V2 (Phase 1): the data the personalised shop landing is built
// from, the build flag, the analytics events and the device's recently-viewed
// list. Screens live in lib/shared/widgets/shop_home/.
//
// Contract: GET /shop/home, GET/PATCH /shop/preferences, POST /shop/events.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// `--dart-define=SHOP_HOME_V2=true` turns the new shop home on. Off (the
/// default) leaves today's shop screen exactly as it was.
const bool kShopHomeV2 = bool.fromEnvironment(
  'SHOP_HOME_V2',
  defaultValue: false,
);

/// Lets tests switch the flag without a rebuild of the binary.
@visibleForTesting
bool? debugShopHomeV2Override;

bool get shopHomeV2Enabled => debugShopHomeV2Override ?? kShopHomeV2;

/// The role the customer is shopping as. A default for what is suggested,
/// never a limit on what can be browsed.
enum ShopHomeMode {
  member('member'),
  trainer('trainer'),
  owner('owner'),
  vendorPersonal('vendor_personal');

  const ShopHomeMode(this.wire);
  final String wire;
}

/// A line the server sends in both languages.
class ShopText {
  const ShopText(this.en, this.sw);
  final String en;
  final String sw;

  static ShopText? fromJson(Object? json) {
    if (json is! Map) return null;
    final en = json['en']?.toString() ?? '';
    final sw = json['sw']?.toString() ?? '';
    if (en.isEmpty && sw.isEmpty) return null;
    return ShopText(en, sw);
  }

  String of(String lang) => lang == 'sw' && sw.isNotEmpty
      ? sw
      : en.isNotEmpty
      ? en
      : sw;
}

class ShopHomeCategory {
  const ShopHomeCategory({required this.key, required this.label});
  final String key;
  final ShopText label;
}

class ShopHomeSection {
  const ShopHomeSection({
    required this.key,
    required this.title,
    this.reason,
    this.viewAll = const {},
    this.productIds = const [],
  });

  /// featured, recommended, best_sellers, popular_near_you, essentials,
  /// recently_viewed, deals, new_arrivals (others are shown the same way).
  final String key;
  final ShopText title;
  final ShopText? reason;

  /// The filters "View all" opens the product list with.
  final Map<String, String> viewAll;
  final List<String> productIds;

  factory ShopHomeSection.fromJson(Map<String, dynamic> json) {
    final viewAll = json['viewAll'];
    final query = viewAll is Map ? viewAll['query'] : null;
    return ShopHomeSection(
      key: json['key']?.toString() ?? '',
      title:
          ShopText.fromJson(json['title']) ??
          ShopText(json['key']?.toString() ?? '', ''),
      reason: ShopText.fromJson(json['reason']),
      viewAll: query is Map
          ? {
              for (final e in query.entries)
                if (e.value != null) e.key.toString(): e.value.toString(),
            }
          : const {},
      productIds: (json['productIds'] as List? ?? [])
          .map((id) => id.toString())
          .where((id) => id.isNotEmpty)
          .toList(),
    );
  }
}

/// The answer to GET /shop/home. Products stay raw JSON here so the shop's own
/// product model reads them, exactly as it reads the product list.
class ShopHomeData {
  const ShopHomeData({
    required this.mode,
    this.personalised = false,
    this.signalsUsed = const [],
    this.categories = const [],
    this.sections = const [],
    this.products = const {},
    this.serverNow,
  });

  final String mode;
  final bool personalised;
  final List<String> signalsUsed;
  final List<ShopHomeCategory> categories;
  final List<ShopHomeSection> sections;
  final Map<String, Map<String, dynamic>> products;
  final DateTime? serverNow;

  factory ShopHomeData.fromJson(Map<String, dynamic> json) {
    final rawProducts = json['products'];
    return ShopHomeData(
      mode: json['mode']?.toString() ?? '',
      personalised: json['personalised'] == true,
      signalsUsed: (json['signalsUsed'] as List? ?? [])
          .map((s) => s.toString())
          .toList(),
      serverNow: DateTime.tryParse(json['serverNow']?.toString() ?? ''),
      categories: (json['categories'] as List? ?? [])
          .whereType<Map>()
          .map((c) {
            final key = c['key']?.toString() ?? '';
            return ShopHomeCategory(
              key: key,
              label: ShopText.fromJson(c) ?? ShopText(key, ''),
            );
          })
          .where((c) => c.key.isNotEmpty)
          .toList(),
      sections: (json['sections'] as List? ?? [])
          .whereType<Map>()
          .map((s) => ShopHomeSection.fromJson(Map<String, dynamic>.from(s)))
          .where((s) => s.key.isNotEmpty)
          .toList(),
      products: rawProducts is Map
          ? {
              for (final e in rawProducts.entries)
                if (e.value is Map)
                  e.key.toString(): Map<String, dynamic>.from(e.value as Map),
            }
          : const {},
    );
  }
}

/// Shop analytics: `POST /shop/events`, one event per call, fire and forget.
///
/// Only the fields in the contract are ever sent (type, section, productId,
/// position, mode), so no name, phone, email or search text can leave the
/// device through here. A 404 (backend without the endpoint) switches it off
/// for the rest of the session; every other failure is ignored.
class ShopEvents {
  ShopEvents._();

  static const types = {
    'shop_home_viewed',
    'section_viewed',
    'product_impression',
    'product_clicked',
    'search_submitted',
    'filter_applied',
    'product_favorited',
    'add_to_cart',
  };

  static const allowedFields = {
    'type',
    'section',
    'productId',
    'position',
    'mode',
  };

  static bool _disabled = false;
  static final Set<String> _seen = {};

  @visibleForTesting
  static void reset() {
    _disabled = false;
    _seen.clear();
  }

  /// The exact body sent for one event.
  static Map<String, dynamic> build(
    String type, {
    required ShopHomeMode mode,
    String? section,
    String? productId,
    int? position,
  }) => {
    'type': type,
    'mode': mode.wire,
    if (section != null && section.isNotEmpty) 'section': section,
    if (productId != null && productId.isNotEmpty) 'productId': productId,
    'position': ?position,
  };

  /// Sends one event without waiting. [once] drops repeats of the same key
  /// (impressions and section views are counted once per load).
  static void send(
    ApiClient api,
    String type, {
    required ShopHomeMode mode,
    String? section,
    String? productId,
    int? position,
    String? once,
  }) {
    if (_disabled || !types.contains(type)) return;
    if (once != null && !_seen.add(once)) return;
    final body = build(
      type,
      mode: mode,
      section: section,
      productId: productId,
      position: position,
    );
    unawaited(
      Future<void>(() async {
        try {
          await api.postShopEvent(body);
        } on ApiException catch (e) {
          if (e.status == 404) _disabled = true;
        } catch (_) {
          // Analytics never get in the way of shopping.
        }
      }),
    );
  }

  /// Forget which impressions were already counted (a new home load).
  static void newLoad() => _seen.clear();
}

/// Products opened on this device, newest first, at most [max]. Kept per
/// signed-in account so one person's history is not sent for another.
class RecentlyViewedProducts {
  RecentlyViewedProducts._();

  static const max = 20;
  static const _prefix = 'ff.shop.recent';

  static String _key(String? userId) =>
      userId == null || userId.isEmpty ? _prefix : '$_prefix.$userId';

  static Future<List<String>> load(String? userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_key(userId)) ?? const <String>[])
          .take(max)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> add(String? userId, String productId) async {
    if (productId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = [
        productId,
        ...(prefs.getStringList(_key(userId)) ?? const <String>[]).where(
          (id) => id != productId,
        ),
      ].take(max).toList();
      await prefs.setStringList(_key(userId), list);
    } catch (_) {
      // Not remembered; nothing else depends on it.
    }
  }
}
