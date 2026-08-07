import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../api_client.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../formatters.dart';
import '../i18n.dart';

/// D1/B6/C7 — shared shop browse + cart + order page used by member, owner
/// and trainer roles.
Future<void> openShopBrowsePage(BuildContext context) {
  return Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const ShopBrowsePage()));
}

class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.priceTzs = 0,
    this.stock = 0,
    this.images = const [],
  });

  final String id;
  final String name;
  final String? description;
  final String? category;
  final num priceTzs;
  final int stock;
  final List<String> images;

  factory ShopProduct.fromJson(Map<String, dynamic> json) => ShopProduct(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    category: json['category'] as String?,
    priceTzs: json['priceTzs'] as num? ?? 0,
    stock: (json['stock'] as num?)?.toInt() ?? 0,
    images: (json['images'] as List?)?.whereType<String>().toList() ?? [],
  );

  bool get inStock => stock > 0;
}

/// Pure cart model — unit-testable.
class ShopCart {
  final Map<String, int> _qty = {};
  final Map<String, ShopProduct> _products = {};

  int get itemCount => _qty.values.fold(0, (a, b) => a + b);
  bool get isEmpty => _qty.isEmpty;

  int qtyOf(String productId) => _qty[productId] ?? 0;

  num get totalTzs => _qty.entries.fold(
    0,
    (sum, e) => sum + (_products[e.key]?.priceTzs ?? 0) * e.value,
  );

  /// Adds one unit; capped at available stock. Returns false when capped.
  bool add(ShopProduct product) {
    final current = _qty[product.id] ?? 0;
    if (current >= product.stock) return false;
    _products[product.id] = product;
    _qty[product.id] = current + 1;
    return true;
  }

  void removeOne(String productId) {
    final current = _qty[productId] ?? 0;
    if (current <= 1) {
      _qty.remove(productId);
      _products.remove(productId);
    } else {
      _qty[productId] = current - 1;
    }
  }

  void clear() {
    _qty.clear();
    _products.clear();
  }

  List<Map<String, dynamic>> toOrderItems() =>
      _qty.entries.map((e) => {'productId': e.key, 'qty': e.value}).toList();
}

class ShopBrowsePage extends StatelessWidget {
  const ShopBrowsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('member.shopTitle'))),
      body: const ShopBrowseBody(),
    );
  }
}

/// Scaffold-less shop body — embeddable inside the member/owner shells.
class ShopBrowseBody extends StatefulWidget {
  const ShopBrowseBody({super.key});

  @override
  State<ShopBrowseBody> createState() => _ShopBrowseBodyState();
}

class _ShopBrowseBodyState extends State<ShopBrowseBody> {
  List<ShopProduct> _products = [];
  final ShopCart _cart = ShopCart();
  bool _loading = true;
  bool _ordering = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AppScope.of(context).api.listShopProducts();
      if (!mounted) return;
      setState(() {
        _products = res
            .whereType<Map<String, dynamic>>()
            .map(ShopProduct.fromJson)
            .toList();
        _loading = false;
      });
    } on ApiException {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ShopProduct> get _visible {
    final q = _search.trim().toLowerCase();
    if (q.isEmpty) return _products;
    return _products
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              (p.category ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _placeOrder() async {
    if (_cart.isEmpty) return;
    setState(() => _ordering = true);
    try {
      await AppScope.of(context).api.createShopOrder(_cart.toOrderItems());
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _ordering = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('shop.orderPlaced'))));
      await _load();
    } on ApiException {
      if (!mounted) return;
      setState(() => _ordering = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('shop.orderFailed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          TextField(
            decoration: InputDecoration(
              hintText: context.tr('shop.searchHint'),
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(FFTokens.radiusLg),
              ),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(FFTokens.spacingXl),
                child: FFSpinner(),
              ),
            )
          else if (_visible.isEmpty)
            FFEmptyState(title: context.tr('shop.noProducts'))
          else
            ..._visible.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: _ProductTile(
                  key: Key('shop-product-${p.id}'),
                  product: p,
                  qty: _cart.qtyOf(p.id),
                  onAdd: p.inStock ? () => setState(() => _cart.add(p)) : null,
                  onRemove: _cart.qtyOf(p.id) > 0
                      ? () => setState(() => _cart.removeOne(p.id))
                      : null,
                ),
              ),
            ),
          if (!_cart.isEmpty) ...[
            const SizedBox(height: FFTokens.spacingMd),
            FilledButton(
              key: const Key('shop-place-order'),
              onPressed: _ordering ? null : _placeOrder,
              child: _ordering
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      '${context.tr('shop.placeOrder')} · ${formatCurrency(_cart.totalTzs)}',
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    super.key,
    required this.product,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });

  final ShopProduct product;
  final int qty;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FFCard(
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(FFTokens.radiusMd),
            ),
            child: product.images.isEmpty
                ? Icon(Icons.shopping_bag_outlined, color: cs.primary)
                : FFRemoteImage(
                    src: product.images.first,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    fallback: Icon(
                      Icons.shopping_bag_outlined,
                      color: cs.primary,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  formatCurrency(product.priceTzs),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                FFBadge(
                  label: product.inStock
                      ? '${product.stock} ${context.tr('shop.inStock')}'
                      : context.tr('shop.outOfStock'),
                  tone: product.inStock
                      ? FFBadgeTone.success
                      : FFBadgeTone.gray,
                ),
              ],
            ),
          ),
          if (qty > 0) ...[
            IconButton(
              key: Key('shop-remove-${product.id}'),
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: onRemove,
            ),
            Text('$qty', style: Theme.of(context).textTheme.titleSmall),
          ],
          IconButton(
            key: Key('shop-add-${product.id}'),
            icon: const Icon(Icons.add_circle_outline),
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}
