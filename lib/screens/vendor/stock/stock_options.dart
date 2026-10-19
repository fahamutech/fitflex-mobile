// Vendor tools · S1 (stock ledger): which tools the server has on, and the
// small helpers the stock screens share.
//
// The server says which vendor tools are on (GET /vendor/tools/options). The
// app shows the stock ledger only when `stockLedger` is exactly `true`; a
// failed call, a missing field or anything else keeps the old screens. A
// failure is not remembered, so the next refresh asks again.
import 'package:flutter/widgets.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';

/// The vendor tools switched on for this session.
class VendorTools {
  const VendorTools({this.stockLedger = false, this.canSeeCost = false});

  /// Everything off: the old screens.
  static const off = VendorTools();

  /// Stock history, reasons, per-variant stock, reorder levels, low stock.
  final bool stockLedger;

  /// Cost price may be seen and sent (the vendor and their admin staff).
  final bool canSeeCost;
}

class _Cached {
  _Cached(this.token, this.tools);
  final String? token;
  final VendorTools tools;
}

/// Asks the server which vendor tools are on (GET /vendor/tools/options).
class VendorToolsOptions {
  VendorToolsOptions._();

  // One answer per API client and signed-in session (token).
  static final Expando<_Cached> _cache = Expando<_Cached>('vendorTools');

  /// The tools on for this session. Asks once per session, or again when
  /// [refresh] is set (pull to refresh). Never throws: a failure means
  /// everything off and is not remembered.
  static Future<VendorTools> load(
    ApiClient api,
    String? token, {
    bool refresh = false,
  }) async {
    final hit = _cache[api];
    if (!refresh && hit != null && hit.token == token) return hit.tools;
    try {
      final options = await api.vendorToolsOptions();
      final tools = VendorTools(
        stockLedger: options['stockLedger'] == true,
        canSeeCost: options['canSeeCost'] == true,
      );
      _cache[api] = _Cached(token, tools);
      return tools;
    } catch (_) {
      _cache[api] = null;
      return VendorTools.off;
    }
  }

  /// Same as [load], for a widget's context.
  static Future<VendorTools> of(BuildContext context, {bool refresh = false}) {
    final scope = AppScope.of(context);
    return load(scope.api, scope.auth.token, refresh: refresh);
  }
}

/// Whether the signed-in vendor (or staff member) may work on products.
bool canManageProducts(BuildContext context) => canVendor(context, 'products');

/// Whether the signed-in vendor (or staff member) has [permission].
bool canVendor(BuildContext context, String permission) {
  final user = AppScope.of(context).auth.user;
  if (user?['userType'] != 'vendor_staff') return true;
  return (user?['vendorPermissions'] as List? ?? []).contains(permission);
}

/// [template] with each `{name}` replaced by its value.
String fillIn(String template, Map<String, Object?> values) {
  var out = template;
  values.forEach((key, value) => out = out.replaceAll('{$key}', '$value'));
  return out;
}

/// A stock count: plain under 10,000, grouped above (no currency).
String formatStock(num value) =>
    value.abs() < 10000 ? '${value.toInt()}' : formatMoney(value);

/// A signed change, with a real minus sign: `+5`, `−2`, `0`.
String formatDelta(num delta) {
  if (delta > 0) return '+${formatStock(delta)}';
  if (delta < 0) return '−${formatStock(-delta)}';
  return '0';
}

/// Reasons a vendor gives, in the order the chips show them.
const adjustReasons = [
  'count',
  'restock',
  'returned',
  'found',
  'damaged',
  'expired',
  'lost',
  'other',
];

const inReasons = {'restock', 'returned', 'found'};
const outReasons = {'damaged', 'expired', 'lost'};

const _labelledReasons = {...adjustReasons, 'reserve', 'release'};

/// The words for a ledger row's reason; never the raw code.
String stockReasonLabel(BuildContext context, String? reason) => context.tr(
  _labelledReasons.contains(reason)
      ? 'vendor.stock.reason.$reason'
      : 'vendor.stock.reason.unknown',
);

/// Notes the server writes itself, shown in words.
String? stockNoteLabel(BuildContext context, String? note) => switch (note) {
  null || '' => null,
  'product_form' => context.tr('vendor.stock.fromProductForm'),
  'product_created' => context.tr('vendor.stock.initial'),
  'variants_tracked' => context.tr('vendor.stock.toVariants'),
  _ => note,
};

/// Today in East Africa (UTC+3, no daylight saving), as a date.
DateTime eatToday([DateTime? now]) {
  final eat = (now ?? DateTime.now()).toUtc().add(const Duration(hours: 3));
  return DateTime.utc(eat.year, eat.month, eat.day);
}

/// A day as the server takes it: YYYY-MM-DD.
String eatDay(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// The low-stock list (GET /vendor/stock/low), by product.
class LowStockIndex {
  LowStockIndex(List<dynamic> rows)
    : _rows = rows.whereType<Map>().map(Map<String, dynamic>.from).toList();

  LowStockIndex.empty() : _rows = const [];

  final List<Map<String, dynamic>> _rows;

  /// Products that are low (the product itself or any of its variants).
  Set<String> get productIds =>
      _rows.map((r) => r['productId']?.toString() ?? '').toSet()..remove('');

  int get count => productIds.length;

  bool isLow(String? productId) => productIds.contains(productId);

  /// Variant names of [productId] that are low.
  List<String> lowVariants(String? productId) => [
    for (final r in _rows)
      if (r['productId']?.toString() == productId &&
          (r['variant']?.toString() ?? '').isNotEmpty)
        r['variant'].toString(),
  ];

  /// Whether this product row itself (no variant) is low.
  bool productLow(String? productId) => _rows.any(
    (r) =>
        r['productId']?.toString() == productId &&
        (r['variant']?.toString() ?? '').isEmpty,
  );
}
