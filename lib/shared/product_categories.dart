// The categories a vendor chooses from (product owner, 11 Oct 2026). The list
// is served by GET /shop/categories; the compiled-in copy below keeps the
// forms working when that call fails and gives every screen a label without
// waiting for the network.

import 'package:flutter/foundation.dart';

import 'api_client.dart';

class ProductCategory {
  const ProductCategory(this.key, this.en, this.sw);

  final String key;
  final String en;
  final String sw;

  String label(String lang) => lang == 'sw' ? sw : en;
}

const kFallbackProductCategories = <ProductCategory>[
  ProductCategory(
    'supplements_nutrition',
    'Supplements & nutrition',
    'Virutubisho na lishe',
  ),
  ProductCategory(
    'sportswear_footwear',
    'Sportswear & footwear',
    'Mavazi na viatu vya michezo',
  ),
  ProductCategory(
    'equipment',
    'Gym & fitness equipment',
    'Vifaa vya gym na mazoezi',
  ),
  ProductCategory(
    'accessories_gear',
    'Accessories & gear',
    'Vifaa vidogo na zana',
  ),
  ProductCategory('food_drinks', 'Food & drinks', 'Chakula na vinywaji'),
  ProductCategory('health_recovery', 'Health & recovery', 'Afya na kupona'),
  ProductCategory('events', 'Events & tickets', 'Matukio na tiketi'),
  ProductCategory('other', 'Other', 'Nyingine'),
];

/// Loads and remembers the category list for the session.
class ProductCategories {
  ProductCategories._();

  static List<ProductCategory> _loaded = kFallbackProductCategories;
  static bool _fromServer = false;

  /// The best list known right now (server copy once loaded, else fallback).
  static List<ProductCategory> get current => _loaded;

  @visibleForTesting
  static void reset() {
    _loaded = kFallbackProductCategories;
    _fromServer = false;
  }

  /// Asks the server once; any failure keeps the compiled-in list.
  static Future<List<ProductCategory>> load(ApiClient? api) async {
    if (_fromServer || api == null) return _loaded;
    try {
      final json = await api.shopCategories();
      final parsed = <ProductCategory>[
        for (final c in (json['categories'] as List? ?? const []))
          if (c is Map && (c['key'] ?? '').toString().isNotEmpty)
            ProductCategory(
              c['key'].toString(),
              (c['en'] ?? c['key']).toString(),
              (c['sw'] ?? c['en'] ?? c['key']).toString(),
            ),
      ];
      if (parsed.isNotEmpty) {
        _loaded = parsed;
        _fromServer = true;
      }
    } catch (_) {
      // Keep the compiled-in list.
    }
    return _loaded;
  }

  /// The key a stored value stands for: the key itself, or the English or
  /// Swahili name of a category (case-insensitive). Null when it matches none.
  static String? keyFor(String? raw, [List<ProductCategory>? list]) {
    final value = (raw ?? '').trim().toLowerCase();
    if (value.isEmpty) return null;
    for (final c in list ?? _loaded) {
      if (c.key == value ||
          c.en.toLowerCase() == value ||
          c.sw.toLowerCase() == value) {
        return c.key;
      }
    }
    return null;
  }

  /// The localized name for a known key; the raw text otherwise.
  static String labelFor(String? raw, String lang) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return '';
    for (final c in _loaded) {
      if (c.key == text) return c.label(lang);
    }
    return text;
  }

  /// Several stored values → the keys they stand for, in order, no repeats.
  static List<String> keysFor(Iterable<dynamic> raw) {
    final out = <String>[];
    for (final v in raw) {
      final k = keyFor(v?.toString());
      if (k != null && !out.contains(k)) out.add(k);
    }
    return out;
  }
}
