import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../file-export.dart';

import '../../app_scope.dart';
import '../api_client.dart';
import '../api_error_message.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../formatters.dart';
import '../discovery_loader.dart';
import '../i18n.dart';
import '../promotion.dart';
import '../promotion_events.dart';

num _shopNumber(dynamic value, [num fallback = 0]) {
  if (value is num) return value;
  return num.tryParse(value?.toString() ?? '') ?? fallback;
}

Future<void> openShopBrowsePage(BuildContext context) {
  return Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const ShopBrowsePage()));
}

class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.vendorId,
    required this.name,
    this.description,
    this.category,
    this.brand,
    this.priceTzs = 0,
    this.discountPriceTzs,
    this.stock = 0,
    this.images = const [],
    this.rating = 0,
    this.reviewCount = 0,
    this.soldCount = 0,
    this.deliveryAvailable = true,
    this.distanceKm,
    this.vendor = const {},
    this.reviews = const [],
    this.similarProducts = const [],
    this.promotion,
  });

  final String id;
  final String vendorId;
  final String name;
  final String? description;
  final String? category;
  final String? brand;
  final num priceTzs;
  final num? discountPriceTzs;
  final int stock;
  final List<String> images;
  final num rating;
  final int reviewCount;
  final int soldCount;
  final bool deliveryAvailable;
  final num? distanceKm;
  final Map<String, dynamic> vendor;
  final List<Map<String, dynamic>> reviews;
  final List<ShopProduct> similarProducts;

  /// Set when this product is promoted for what the customer is looking at.
  final PromotionTag? promotion;

  factory ShopProduct.fromJson(Map<String, dynamic> json) => ShopProduct(
    id: json['id'] as String? ?? '',
    vendorId: json['vendorId'] as String? ?? '',
    name: json['name'] as String? ?? '',
    description: json['description'] as String?,
    category: json['category'] as String?,
    brand: json['brand'] as String?,
    priceTzs: _shopNumber(json['priceTzs']),
    discountPriceTzs: json['discountPriceTzs'] == null
        ? null
        : _shopNumber(json['discountPriceTzs']),
    stock: _shopNumber(json['stock']).toInt(),
    images: (json['images'] as List?)?.whereType<String>().toList() ?? [],
    rating: _shopNumber(json['rating']),
    reviewCount: _shopNumber(json['reviewCount']).toInt(),
    soldCount: _shopNumber(json['soldCount']).toInt(),
    deliveryAvailable: json['deliveryAvailable'] != false,
    distanceKm: json['distanceKm'] == null
        ? null
        : _shopNumber(json['distanceKm']),
    vendor: json['vendor'] is Map
        ? Map<String, dynamic>.from(json['vendor'] as Map)
        : const {},
    reviews: (json['reviews'] as List? ?? [])
        .whereType<Map>()
        .map((value) => Map<String, dynamic>.from(value))
        .toList(),
    similarProducts: (json['similarProducts'] as List? ?? [])
        .whereType<Map>()
        .map((value) => ShopProduct.fromJson(Map<String, dynamic>.from(value)))
        .toList(),
    promotion: PromotionTag.fromJson(json['promotion']),
  );

  bool get inStock => stock > 0;
  num get effectivePrice =>
      discountPriceTzs != null &&
          discountPriceTzs! > 0 &&
          discountPriceTzs! < priceTzs
      ? discountPriceTzs!
      : priceTzs;
}

class ShopCart {
  final Map<String, int> _qty = {};
  final Map<String, ShopProduct> _products = {};

  int get itemCount => _qty.values.fold(0, (a, b) => a + b);
  bool get isEmpty => _qty.isEmpty;
  int qtyOf(String productId) => _qty[productId] ?? 0;
  num get totalTzs => _qty.entries.fold(
    0,
    (sum, entry) =>
        sum + (_products[entry.key]?.effectivePrice ?? 0) * entry.value,
  );

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

  void remove(String productId) {
    _qty.remove(productId);
    _products.remove(productId);
  }

  void clear() {
    _qty.clear();
    _products.clear();
  }

  List<Map<String, dynamic>> toOrderItems() => _qty.entries
      .map((entry) => {'productId': entry.key, 'qty': entry.value})
      .toList();
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

class ShopBrowseBody extends StatefulWidget {
  const ShopBrowseBody({super.key});

  @override
  State<ShopBrowseBody> createState() => _ShopBrowseBodyState();
}

class _ShopBrowseBodyState extends State<ShopBrowseBody> {
  List<ShopProduct> _products = [];

  /// Featured and promoted products from the server's ranked discovery, with
  /// their labels. Empty when the server has none or cannot be reached.
  List<ShopProduct> _featured = [];
  Map<String, PromotionTag> _promoTags = {};
  String? _placement;
  List<Map<String, dynamic>> _orders = [];
  final ShopCart _cart = ShopCart();
  final Set<String> _saved = {};
  bool _loading = true;
  bool _ordering = false;
  String _search = '';
  String? _category;
  String _sort = 'newest';
  bool _deliveryOnly = false;
  bool _promotionsOnly = false;
  String _brand = '';
  String _vendorId = '';
  num? _minPrice;
  num? _maxPrice;
  num? _minRating;
  num? _maxDistanceKm;
  int _section = 0;
  Timer? _trackingTimer;
  bool _trackingRequest = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    _trackingTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshTracking(),
    );
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshTracking() async {
    if (!mounted ||
        _loading ||
        _ordering ||
        _trackingRequest ||
        _section != 1 ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    _trackingRequest = true;
    try {
      final rows = await AppScope.of(context).api.myShopOrders();
      if (!mounted) return;
      final latest = rows.whereType<Map<String, dynamic>>().toList();
      final previous = {
        for (final order in _orders) order['id']: order['status'],
      };
      final changed = latest.any(
        (order) =>
            previous.containsKey(order['id']) &&
            previous[order['id']] != order['status'],
      );
      setState(() => _orders = latest);
      if (changed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('shop.trackingUpdated'))),
        );
      }
    } on ApiException {
      // Preserve the last successful timeline and retry on the next interval.
    } finally {
      _trackingRequest = false;
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        AppScope.of(context).api.listShopProducts(),
        AppScope.of(context).api.myShopOrders(),
      ]);
      if (!mounted) return;
      setState(() {
        _products = results[0]
            .whereType<Map<String, dynamic>>()
            .map(ShopProduct.fromJson)
            .toList();
        _orders = results[1].whereType<Map<String, dynamic>>().toList();
        _loading = false;
      });
      await _loadPromotions();
    } on ApiException {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Which products are Featured or promoted. Only labels and the Featured
  /// section come from here; the list keeps its own filters and sort. Any
  /// failure just leaves the catalogue as it was.
  Future<void> _loadPromotions() async {
    if (!kServerDiscovery) return;
    try {
      final result = DiscoverResult.fromJson<ShopProduct>(
        await AppScope.of(context).api.discover(
          'products',
          const DiscoverQuery(limit: 50),
        ),
        ShopProduct.fromJson,
      );
      if (!mounted) return;
      setState(() {
        _featured = result.featured;
        _placement = result.placement;
        _promoTags = {
          for (final p in [...result.featured, ...result.items])
            if (p.promotion != null) p.id: p.promotion!,
        };
      });
    } catch (_) {
      // Discovery is an improvement, never a requirement.
    }
  }

  /// Whether a product passes the search and every filter the customer set.
  /// The Featured section uses the same test, so a featured product that does
  /// not match what they asked for is not shown.
  bool _passes(ShopProduct product) {
    final query = _search.trim().toLowerCase();
    {
      final searchMatch =
          query.isEmpty ||
          [
            product.name,
            product.category,
            product.brand,
            product.description,
          ].any((value) => (value ?? '').toLowerCase().contains(query));
      return searchMatch &&
          (_category == null || product.category == _category) &&
          (!_deliveryOnly || product.deliveryAvailable) &&
          (!_promotionsOnly || product.discountPriceTzs != null) &&
          (_brand.isEmpty ||
              (product.brand ?? '').toLowerCase().contains(
                _brand.toLowerCase(),
              )) &&
          (_vendorId.isEmpty || product.vendorId == _vendorId) &&
          (_minPrice == null || product.effectivePrice >= _minPrice!) &&
          (_maxPrice == null || product.effectivePrice <= _maxPrice!) &&
          (_minRating == null || product.rating >= _minRating!) &&
          (_maxDistanceKm == null ||
              (product.distanceKm != null &&
                  product.distanceKm! <= _maxDistanceKm!));
    }
  }

  /// Featured products that match what the customer asked for. An explicit
  /// sort switches promotion off, as it does on the server.
  List<ShopProduct> get _visibleFeatured => _sort == 'newest'
      ? _featured.where(_passes).toList()
      : const <ShopProduct>[];

  List<ShopProduct> get _visible {
    final values = _products.where(_passes).toList();
    if (_sort == 'price_asc') {
      values.sort((a, b) => a.effectivePrice.compareTo(b.effectivePrice));
    } else if (_sort == 'price_desc') {
      values.sort((a, b) => b.effectivePrice.compareTo(a.effectivePrice));
    } else if (_sort == 'rating') {
      values.sort((a, b) => b.rating.compareTo(a.rating));
    } else if (_sort == 'popularity') {
      values.sort((a, b) => b.soldCount.compareTo(a.soldCount));
    }
    return values;
  }

  Future<void> _checkout() async {
    if (_cart.isEmpty) return;
    final checkout = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CheckoutSheet(),
    );
    if (checkout == null || !mounted) return;
    setState(() => _ordering = true);
    try {
      await AppScope.of(context).api.createShopOrder(
        _cart.toOrderItems(),
        deliveryMethod: checkout['deliveryMethod']!,
        pickupGymId: checkout['pickupGymId'],
        deliveryAddress: checkout['deliveryAddress'],
        paymentMethod: checkout['paymentMethod']!,
      );
      if (!mounted) return;
      setState(() {
        _cart.clear();
        _ordering = false;
        _section = 1;
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

  /// Cancel an order that is not on its way yet; a paid one is refunded.
  Future<void> _cancelOrder(Map<String, dynamic> order) async {
    final paid = order['paymentStatus'] == 'paid';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('shop.cancelOrder')),
        content: Text(
          context.tr(paid ? 'shop.cancelConfirmPaid' : 'shop.cancelConfirm'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('sessions.keep')),
          ),
          FilledButton(
            key: const Key('order-cancel-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('shop.cancelOrder')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final locale = FFLocaleScope.of(context);
    final done = context.tr(paid ? 'shop.cancelledRefund' : 'shop.cancelled');
    try {
      await AppScope.of(context).api.cancelMyShopOrder(order['id'].toString());
      await _load();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(locale, e))));
    }
  }

  Future<void> _openProduct(ShopProduct product) async {
    var detailedProduct = product;
    try {
      detailedProduct = ShopProduct.fromJson(
        await AppScope.of(context).api.shopProduct(product.id),
      );
    } on ApiException {
      // The cached catalogue record still supports cart actions offline.
    }
    if (!mounted) return;
    PromotionEvents.instance.recordForTouched(
      'detail_view',
      'product',
      product.id,
    );
    final buyNow = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductDetailsSheet(
        product: detailedProduct,
        onAdd: () => setState(() => _cart.add(detailedProduct)),
      ),
    );
    if (!mounted) return;
    setState(() {});
    if (buyNow == true) await _checkout();
  }

  Future<void> _openFilters() async {
    final values = await showModalBottomSheet<_MarketplaceFilterValues>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MarketplaceFiltersSheet(
        initial: _MarketplaceFilterValues(
          brand: _brand,
          vendorId: _vendorId,
          minPrice: _minPrice,
          maxPrice: _maxPrice,
          minRating: _minRating,
          maxDistanceKm: _maxDistanceKm,
        ),
      ),
    );
    if (values == null || !mounted) return;
    setState(() {
      _brand = values.brand;
      _vendorId = values.vendorId;
      _minPrice = values.minPrice;
      _maxPrice = values.maxPrice;
      _minRating = values.minRating;
      _maxDistanceKm = values.maxDistanceKm;
    });
  }

  Future<void> _reorder(Map<String, dynamic> order) async {
    final result = await AppScope.of(
      context,
    ).api.reorderMarketplaceOrder(order['id'].toString());
    for (final item in (result['items'] as List? ?? []).whereType<Map>()) {
      final product = _products
          .where((value) => value.id == item['productId'])
          .firstOrNull;
      if (product == null) continue;
      for (var count = 0; count < (item['qty'] as num? ?? 1); count++) {
        _cart.add(product);
      }
    }
    if (mounted) setState(() => _section = 0);
  }

  void _showInvoice(Map<String, dynamic> order) {
    final items = (order['items'] as List? ?? []).whereType<Map>();
    final invoice = <String>[
      context.tr('shop.invoiceTitle'),
      '${context.tr('shop.order')}: ${order['id']}',
      ...items.map((item) => '${item['qty']} × ${item['name']}'),
      '${context.tr('shop.total')}: ${formatCurrency(order['totalTzs'] as num? ?? 0)}',
    ].join('\n');
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('shop.invoice')),
        content: SelectableText(invoice),
        actions: [
          TextButton(
            key: const Key('shop-download-receipt'),
            onPressed: () async {
              try {
                await saveTextExport(
                  filename: 'fitflex-receipt-${order['id']}.txt',
                  content: invoice,
                );
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (_) {
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(
                    content: Text(dialogContext.tr('shop.exportFailed')),
                  ),
                );
              }
            },
            child: Text(context.tr('shop.downloadReceipt')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          SegmentedButton<int>(
            segments: [
              ButtonSegment(
                value: 0,
                icon: const Icon(Icons.storefront_outlined),
                label: Text(context.tr('shop.browse')),
              ),
              ButtonSegment(
                value: 1,
                icon: const Icon(Icons.local_shipping_outlined),
                label: Text(context.tr('shop.myOrders')),
              ),
            ],
            selected: {_section},
            onSelectionChanged: (value) =>
                setState(() => _section = value.first),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(FFTokens.spacingXl),
                child: FFSpinner(),
              ),
            )
          else if (_section == 0)
            ..._buildCatalogue()
          else
            ..._buildOrders(),
        ],
      ),
    );
  }

  List<Widget> _buildCatalogue() {
    final featured = _visibleFeatured;
    final categories = _products
        .map((product) => product.category)
        .whereType<String>()
        .toSet()
        .toList();
    return [
      TextField(
        key: const Key('shop-search'),
        decoration: InputDecoration(
          hintText: context.tr('shop.searchHint'),
          prefixIcon: const Icon(Icons.search, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          ),
        ),
        onChanged: (value) => setState(() => _search = value),
      ),
      const SizedBox(height: FFTokens.spacingSm),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: Text(context.tr('shop.allCategories')),
              selected: _category == null,
              onSelected: (_) => setState(() => _category = null),
            ),
            for (final category in categories) ...[
              const SizedBox(width: 6),
              FilterChip(
                label: Text(category),
                selected: _category == category,
                onSelected: (_) => setState(() => _category = category),
              ),
            ],
          ],
        ),
      ),
      Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: const Key('shop-sort'),
              initialValue: _sort,
              decoration: InputDecoration(labelText: context.tr('shop.sort')),
              items: [
                DropdownMenuItem(
                  value: 'newest',
                  child: Text(context.tr('shop.newest')),
                ),
                DropdownMenuItem(
                  value: 'popularity',
                  child: Text(context.tr('shop.popularity')),
                ),
                DropdownMenuItem(
                  value: 'price_asc',
                  child: Text(context.tr('shop.priceLow')),
                ),
                DropdownMenuItem(
                  value: 'price_desc',
                  child: Text(context.tr('shop.priceHigh')),
                ),
                DropdownMenuItem(
                  value: 'rating',
                  child: Text(context.tr('shop.rating')),
                ),
              ],
              onChanged: (value) => setState(() => _sort = value ?? 'newest'),
            ),
          ),
          IconButton(
            key: const Key('shop-more-filters'),
            tooltip: context.tr('shop.filters'),
            onPressed: _openFilters,
            icon: const Icon(Icons.tune),
          ),
        ],
      ),
      Wrap(
        spacing: 6,
        children: [
          FilterChip(
            key: const Key('shop-delivery-filter'),
            label: Text(context.tr('shop.delivery')),
            selected: _deliveryOnly,
            onSelected: (value) => setState(() => _deliveryOnly = value),
          ),
          FilterChip(
            key: const Key('shop-promotions-filter'),
            label: Text(context.tr('shop.promotions')),
            selected: _promotionsOnly,
            onSelected: (value) => setState(() => _promotionsOnly = value),
          ),
        ],
      ),
      const SizedBox(height: FFTokens.spacingMd),
      if (featured.isNotEmpty)
        FFFeaturedStrip(
          title: context.tr('member.featuredProducts'),
          count: featured.length,
          height: 210,
          itemWidth: 160,
          itemBuilder: (context, i) => _FeaturedProductCard(
            key: Key('shop-featured-${featured[i].id}'),
            product: featured[i],
            placement: _placement,
            onOpen: () => _openProduct(featured[i]),
          ),
        ),
      if (_visible.isEmpty && featured.isEmpty)
        FFEmptyState(title: context.tr('shop.noProducts'))
      else
        ..._visible.map(
          (product) => Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: _ProductTile(
              key: Key('shop-product-${product.id}'),
              product: product,
              promotion: _promoTags[product.id],
              placement: _placement,
              qty: _cart.qtyOf(product.id),
              saved: _saved.contains(product.id),
              onOpen: () => _openProduct(product),
              onSave: () => setState(() {
                if (_saved.add(product.id)) {
                  PromotionEvents.instance.recordForTouched(
                    'save',
                    'product',
                    product.id,
                  );
                } else {
                  _saved.remove(product.id);
                }
                _cart.remove(product.id);
              }),
              onAdd: product.inStock
                  ? () => setState(() => _cart.add(product))
                  : null,
              onRemove: _cart.qtyOf(product.id) > 0
                  ? () => setState(() => _cart.removeOne(product.id))
                  : null,
            ),
          ),
        ),
      if (_saved.isNotEmpty) ...[
        const SizedBox(height: FFTokens.spacingSm),
        Text('${context.tr('shop.savedForLater')}: ${_saved.length}'),
      ],
      if (!_cart.isEmpty) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FilledButton(
          key: const Key('shop-checkout'),
          onPressed: _ordering ? null : _checkout,
          child: _ordering
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  '${context.tr('shop.checkout')} · ${formatCurrency(_cart.totalTzs)}',
                ),
        ),
      ],
    ];
  }

  List<Widget> _buildOrders() {
    if (_orders.isEmpty) {
      return [FFEmptyState(title: context.tr('shop.noOrders'))];
    }
    return _orders.map((order) {
      final status = order['status']?.toString() ?? 'pending';
      final timeline = (order['timeline'] as List? ?? []).whereType<Map>();
      return Padding(
        padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
        child: FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${context.tr('shop.order')} ${order['id']}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                '${formatCurrency(order['totalTzs'] as num? ?? 0)} · $status',
              ),
              if (order['paymentStatus'] == 'pending')
                Text(
                  context.tr('shop.awaitingPayment'),
                  key: Key('order-awaiting-payment-${order['id']}'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                children: timeline
                    .map(
                      (entry) => Chip(label: Text(entry['status'].toString())),
                    )
                    .toList(),
              ),
              Wrap(
                children: [
                  if (order['canCancel'] == true)
                    TextButton(
                      key: Key('order-cancel-${order['id']}'),
                      onPressed: () => _cancelOrder(order),
                      child: Text(context.tr('shop.cancelOrder')),
                    ),
                  TextButton(
                    onPressed: () => _showInvoice(order),
                    child: Text(context.tr('shop.invoice')),
                  ),
                  TextButton(
                    key: Key('shop-reorder-${order['id']}'),
                    onPressed: () => _reorder(order),
                    child: Text(context.tr('shop.reorder')),
                  ),
                  if (status == 'delivered')
                    TextButton(
                      onPressed: () => _review(order),
                      child: Text(context.tr('shop.review')),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Future<void> _review(Map<String, dynamic> order) async {
    final items = (order['items'] as List? ?? []).whereType<Map>().toList();
    if (items.isEmpty) return;
    final controller = TextEditingController();
    var rating = 5;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(context.tr('shop.review')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<int>(
                value: rating,
                items: [1, 2, 3, 4, 5]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('$value '),
                            const Icon(Icons.star, size: 16),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setDialogState(() => rating = value ?? 5),
              ),
              TextField(
                controller: controller,
                decoration: InputDecoration(
                  labelText: context.tr('shop.comment'),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(context.tr('shop.submitReview')),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) {
      await AppScope.of(context).api.reviewMarketplaceProduct(
        order['id'].toString(),
        items.first['productId'].toString(),
        rating,
        controller.text,
      );
      await _load();
    }
    controller.dispose();
  }
}

class _MarketplaceFilterValues {
  const _MarketplaceFilterValues({
    this.brand = '',
    this.vendorId = '',
    this.minPrice,
    this.maxPrice,
    this.minRating,
    this.maxDistanceKm,
  });

  final String brand;
  final String vendorId;
  final num? minPrice;
  final num? maxPrice;
  final num? minRating;
  final num? maxDistanceKm;
}

class _MarketplaceFiltersSheet extends StatefulWidget {
  const _MarketplaceFiltersSheet({required this.initial});
  final _MarketplaceFilterValues initial;

  @override
  State<_MarketplaceFiltersSheet> createState() =>
      _MarketplaceFiltersSheetState();
}

class _MarketplaceFiltersSheetState extends State<_MarketplaceFiltersSheet> {
  late final TextEditingController _brand;
  late final TextEditingController _vendor;
  late final TextEditingController _minPrice;
  late final TextEditingController _maxPrice;
  late final TextEditingController _rating;
  late final TextEditingController _distance;

  @override
  void initState() {
    super.initState();
    _brand = TextEditingController(text: widget.initial.brand);
    _vendor = TextEditingController(text: widget.initial.vendorId);
    _minPrice = TextEditingController(
      text: widget.initial.minPrice?.toString(),
    );
    _maxPrice = TextEditingController(
      text: widget.initial.maxPrice?.toString(),
    );
    _rating = TextEditingController(text: widget.initial.minRating?.toString());
    _distance = TextEditingController(
      text: widget.initial.maxDistanceKm?.toString(),
    );
  }

  @override
  void dispose() {
    for (final controller in [
      _brand,
      _vendor,
      _minPrice,
      _maxPrice,
      _rating,
      _distance,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  num? _number(TextEditingController controller) =>
      num.tryParse(controller.text.trim());

  @override
  Widget build(BuildContext context) {
    InputDecoration decoration(String key) =>
        InputDecoration(labelText: context.tr(key));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          MediaQuery.viewInsetsOf(context).bottom + FFTokens.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                context.tr('shop.filters'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextField(
                key: const Key('shop-filter-brand'),
                controller: _brand,
                decoration: decoration('shop.brand'),
              ),
              TextField(
                key: const Key('shop-filter-vendor'),
                controller: _vendor,
                decoration: decoration('shop.vendor'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('shop-filter-min-price'),
                      controller: _minPrice,
                      keyboardType: TextInputType.number,
                      decoration: decoration('shop.minPrice'),
                    ),
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: TextField(
                      key: const Key('shop-filter-max-price'),
                      controller: _maxPrice,
                      keyboardType: TextInputType.number,
                      decoration: decoration('shop.maxPrice'),
                    ),
                  ),
                ],
              ),
              TextField(
                key: const Key('shop-filter-rating'),
                controller: _rating,
                keyboardType: TextInputType.number,
                decoration: decoration('shop.minimumRating'),
              ),
              TextField(
                key: const Key('shop-filter-distance'),
                controller: _distance,
                keyboardType: TextInputType.number,
                decoration: decoration('shop.maximumDistance'),
              ),
              const SizedBox(height: FFTokens.spacingLg),
              Row(
                children: [
                  TextButton(
                    key: const Key('shop-clear-filters'),
                    onPressed: () => Navigator.pop(
                      context,
                      const _MarketplaceFilterValues(),
                    ),
                    child: Text(context.tr('shop.clearFilters')),
                  ),
                  const Spacer(),
                  FilledButton(
                    key: const Key('shop-apply-filters'),
                    onPressed: () => Navigator.pop(
                      context,
                      _MarketplaceFilterValues(
                        brand: _brand.text.trim(),
                        vendorId: _vendor.text.trim(),
                        minPrice: _number(_minPrice),
                        maxPrice: _number(_maxPrice),
                        minRating: _number(_rating),
                        maxDistanceKm: _number(_distance),
                      ),
                    ),
                    child: Text(context.tr('shop.applyFilters')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A product in the Featured row: image, name, price and its label.
class _FeaturedProductCard extends StatelessWidget {
  const _FeaturedProductCard({
    super.key,
    required this.product,
    required this.onOpen,
    this.placement,
  });

  final ShopProduct product;
  final VoidCallback onOpen;
  final String? placement;

  @override
  Widget build(BuildContext context) => PromotionTracked(
    entityType: 'product',
    entityId: product.id,
    promotion: product.promotion,
    placement: placement,
    child: _card(context),
  );

  Widget _card(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final tag = product.promotion;
    return FFCard(
      child: InkWell(
        onTap: () {
          trackPromotionClick('product', product.id, product.promotion, placement: placement);
          onOpen();
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                ),
                child: product.images.isEmpty
                    ? Icon(Icons.shopping_bag_outlined, color: colors.primary)
                    : FFRemoteImage(
                        src: product.images.first,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        fallback: Icon(
                          Icons.shopping_bag_outlined,
                          color: colors.primary,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              product.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              formatCurrency(product.effectivePrice),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (tag != null) FFPromotionBadge(tag: tag),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({
    super.key,
    required this.product,
    this.promotion,
    this.placement,
    required this.qty,
    required this.saved,
    required this.onOpen,
    required this.onSave,
    required this.onAdd,
    required this.onRemove,
  });
  final ShopProduct product;
  final PromotionTag? promotion;
  final String? placement;
  final int qty;
  final bool saved;
  final VoidCallback onOpen;
  final VoidCallback onSave;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) => PromotionTracked(
    entityType: 'product',
    entityId: product.id,
    promotion: promotion,
    placement: placement,
    child: _card(context),
  );

  Widget _card(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return FFCard(
      child: InkWell(
        onTap: () {
          trackPromotionClick('product', product.id, promotion, placement: placement);
          onOpen();
        },
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(FFTokens.radiusMd),
              ),
              child: product.images.isEmpty
                  ? Icon(Icons.shopping_bag_outlined, color: colors.primary)
                  : FFRemoteImage(
                      src: product.images.first,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      fallback: Icon(
                        Icons.shopping_bag_outlined,
                        color: colors.primary,
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
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (product.brand != null)
                    Text(
                      product.brand!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (promotion != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: FFPromotionBadge(tag: promotion!),
                    ),
                  Text(
                    formatCurrency(product.effectivePrice),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 16),
                      Text(
                        ' ${product.rating.toStringAsFixed(1)} · ${product.stock} ${context.tr('shop.inStock')}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  key: Key('shop-save-${product.id}'),
                  tooltip: context.tr('shop.saveForLater'),
                  icon: Icon(saved ? Icons.bookmark : Icons.bookmark_border),
                  onPressed: onSave,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (qty > 0)
                      IconButton(
                        key: Key('shop-remove-${product.id}'),
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: onRemove,
                      ),
                    if (qty > 0) Text('$qty'),
                    IconButton(
                      key: Key('shop-add-${product.id}'),
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: onAdd,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutSheet extends StatefulWidget {
  const _CheckoutSheet();
  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  String _delivery = 'home_delivery';
  String _payment = 'mpesa';
  final _address = TextEditingController();
  String? _gymId;
  List<Map<String, dynamic>> _gyms = [];
  String _gymSearch = '';
  Position? _pickupPosition;

  double? _gymDistance(Map<String, dynamic> gym) {
    final coordinates = gym['coordinates'];
    if (_pickupPosition == null || coordinates is! Map) return null;
    final lat = double.tryParse('${coordinates['lat']}');
    final lng = double.tryParse(
      '${coordinates['lng'] ?? coordinates['longitude']}',
    );
    if (lat == null || lng == null) return null;
    return Geolocator.distanceBetween(
          _pickupPosition!.latitude,
          _pickupPosition!.longitude,
          lat,
          lng,
        ) /
        1000;
  }

  Future<void> _nearestGyms() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() {
        _pickupPosition = position;
        _gyms.sort(
          (a, b) => (_gymDistance(a) ?? double.infinity).compareTo(
            _gymDistance(b) ?? double.infinity,
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('shop.locationUnavailable'))),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final rows = await AppScope.of(context).api.listGyms();
        if (mounted) {
          setState(
            () => _gyms = rows.whereType<Map<String, dynamic>>().toList(),
          );
        }
      } on ApiException {
        // The address checkout remains available when gym discovery is offline.
      }
    });
  }

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _submit() {
    if (_delivery == 'home_delivery' && _address.text.trim().isEmpty) return;
    if (_delivery == 'gym_pickup' && _gymId == null) return;
    Navigator.pop(context, {
      'deliveryMethod': _delivery,
      if (_delivery == 'home_delivery') 'deliveryAddress': _address.text.trim(),
      if (_delivery == 'gym_pickup') 'pickupGymId': _gymId!,
      'paymentMethod': _payment,
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          0,
          FFTokens.spacingLg,
          MediaQuery.viewInsetsOf(context).bottom + FFTokens.spacingLg,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('shop.checkout'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              RadioGroup<String>(
                groupValue: _delivery,
                onChanged: (value) => setState(() => _delivery = value!),
                child: Column(
                  children: [
                    RadioListTile(
                      value: 'home_delivery',
                      title: Text(context.tr('shop.homeDelivery')),
                    ),
                    RadioListTile(
                      value: 'gym_pickup',
                      title: Text(context.tr('shop.gymPickup')),
                    ),
                  ],
                ),
              ),
              if (_delivery == 'home_delivery')
                TextField(
                  key: const Key('shop-delivery-address'),
                  controller: _address,
                  decoration: InputDecoration(
                    labelText: context.tr('shop.deliveryAddress'),
                  ),
                )
              else ...[
                TextField(
                  key: const Key('shop-pickup-search'),
                  decoration: InputDecoration(
                    labelText: context.tr('shop.searchPickup'),
                  ),
                  onChanged: (value) =>
                      setState(() => _gymSearch = value.trim().toLowerCase()),
                ),
                TextButton.icon(
                  onPressed: _nearestGyms,
                  icon: const Icon(Icons.near_me_outlined),
                  label: Text(context.tr('shop.nearestGyms')),
                ),
                DropdownButtonFormField<String>(
                  key: const Key('shop-pickup-gym'),
                  initialValue: _gymId,
                  decoration: InputDecoration(
                    labelText: context.tr('shop.selectGym'),
                  ),
                  items: _gyms
                      .where(
                        (gym) =>
                            gym['id'] == _gymId ||
                            '${gym['name']} ${gym['location'] ?? ''}'
                                .toLowerCase()
                                .contains(_gymSearch),
                      )
                      .map(
                        (gym) => DropdownMenuItem(
                          value: gym['id'].toString(),
                          child: Text(
                            '${gym['name']} · ${gym['location'] ?? ''}'
                            '${_gymDistance(gym) == null ? '' : ' · ${_gymDistance(gym)!.toStringAsFixed(1)} km'}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _gymId = value),
                  isExpanded: true,
                ),
              ],
              const SizedBox(height: FFTokens.spacingMd),
              DropdownButtonFormField<String>(
                key: const Key('shop-payment-method'),
                initialValue: _payment,
                decoration: InputDecoration(
                  labelText: context.tr('shop.paymentMethod'),
                ),
                items: const [
                  DropdownMenuItem(value: 'mpesa', child: Text('M-Pesa')),
                  DropdownMenuItem(
                    value: 'airtel_money',
                    child: Text('Airtel Money'),
                  ),
                  DropdownMenuItem(value: 'mixx', child: Text('Mixx')),
                  DropdownMenuItem(value: 'card', child: Text('Card')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                ],
                onChanged: (value) =>
                    setState(() => _payment = value ?? 'mpesa'),
              ),
              const SizedBox(height: FFTokens.spacingLg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('shop-place-order'),
                  onPressed: _submit,
                  child: Text(context.tr('shop.payAndOrder')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductDetailsSheet extends StatelessWidget {
  const _ProductDetailsSheet({required this.product, required this.onAdd});
  final ShopProduct product;
  final VoidCallback onAdd;

  Future<void> _chat(BuildContext context) async {
    final controller = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('shop.chatVendor')),
        content: TextField(
          key: const Key('shop-enquiry-message'),
          controller: controller,
          maxLines: 3,
          decoration: InputDecoration(hintText: context.tr('shop.enquiryHint')),
        ),
        actions: [
          FilledButton(
            key: const Key('shop-enquiry-send'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('shop.send')),
          ),
        ],
      ),
    );
    if (send == true && controller.text.trim().isNotEmpty && context.mounted) {
      await AppScope.of(
        context,
      ).api.sendMarketplaceEnquiry(product.id, controller.text.trim());
    }
    controller.dispose();
  }

  Future<void> _visitStore(BuildContext context) async {
    try {
      final store = await AppScope.of(
        context,
      ).api.vendorStore(product.vendorId);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => VendorStoreSheet(store: store),
      );
    } on ApiException {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('shop.storeLoadFailed'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.88,
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const Key('shop-product-close'),
                tooltip: context.tr('member.close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            if (product.images.isNotEmpty)
              SizedBox(
                height: 220,
                child: PageView(
                  children: product.images
                      .map(
                        (image) => FFRemoteImage(src: image, fit: BoxFit.cover),
                      )
                      .toList(),
                ),
              ),
            Text(
              product.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (product.brand != null) Text(product.brand!),
            Text(
              formatCurrency(product.effectivePrice),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (product.discountPriceTzs != null)
              Text(
                formatCurrency(product.priceTzs),
                style: const TextStyle(decoration: TextDecoration.lineThrough),
              ),
            Row(
              children: [
                Text('${product.stock} ${context.tr('shop.inStock')} · '),
                const Icon(Icons.star, size: 16),
                Text(
                  ' ${product.rating.toStringAsFixed(1)} (${product.reviewCount})',
                ),
              ],
            ),
            if (product.distanceKm != null)
              Text('${product.distanceKm} km · ${context.tr('shop.delivery')}'),
            const SizedBox(height: FFTokens.spacingMd),
            Text(product.description ?? ''),
            if (product.vendor.isNotEmpty) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                '${context.tr('shop.vendor')}: ${product.vendor['businessName'] ?? product.vendorId}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              context.tr('shop.reviews'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (product.reviews.isEmpty)
              Text(context.tr('shop.noReviews'))
            else
              ...product.reviews.map(
                (review) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _RatingLabel(rating: review['rating']),
                  title: Text(
                    review['comment']?.toString().trim().isNotEmpty == true
                        ? review['comment'].toString()
                        : context.tr('shop.ratingOnly'),
                  ),
                ),
              ),
            if (product.similarProducts.isNotEmpty) ...[
              Text(
                context.tr('shop.similarProducts'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              ...product.similarProducts.map(
                (similar) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shopping_bag_outlined),
                  title: Text(similar.name),
                  trailing: Text(formatCurrency(similar.effectivePrice)),
                ),
              ),
            ],
            const SizedBox(height: FFTokens.spacingLg),
            FilledButton(
              key: Key('shop-detail-add-${product.id}'),
              onPressed: product.inStock ? onAdd : null,
              child: Text(context.tr('shop.addToCart')),
            ),
            OutlinedButton(
              onPressed: product.inStock
                  ? () {
                      onAdd();
                      Navigator.pop(context, true);
                    }
                  : null,
              child: Text(context.tr('shop.buyNow')),
            ),
            TextButton(
              key: const Key('shop-chat-vendor'),
              onPressed: () => _chat(context),
              child: Text(context.tr('shop.chatVendor')),
            ),
            TextButton(
              key: const Key('shop-visit-store'),
              onPressed: () => _visitStore(context),
              child: Text(context.tr('shop.visitStore')),
            ),
          ],
        ),
      ),
    );
  }
}

class VendorStoreSheet extends StatefulWidget {
  const VendorStoreSheet({super.key, required this.store});
  final Map<String, dynamic> store;

  @override
  State<VendorStoreSheet> createState() => _VendorStoreSheetState();
}

class _VendorStoreSheetState extends State<VendorStoreSheet> {
  String _search = '';

  List<ShopProduct> get _products => (widget.store['products'] as List? ?? [])
      .whereType<Map>()
      .map((value) => ShopProduct.fromJson(Map<String, dynamic>.from(value)))
      .where(
        (product) =>
            _search.isEmpty ||
            [product.name, product.category, product.brand].any(
              (value) =>
                  (value ?? '').toLowerCase().contains(_search.toLowerCase()),
            ),
      )
      .toList();

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final products = _products;
    final categories = products
        .map((product) => product.category)
        .whereType<String>()
        .toSet()
        .join(', ');
    final reviews = (store['reviews'] as List? ?? []).whereType<Map>();
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.94,
        child: ListView(
          key: const Key('shop-vendor-storefront'),
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const Key('shop-store-close'),
                tooltip: context.tr('member.close'),
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
            if (store['banner']?.toString().isNotEmpty == true)
              ClipRRect(
                borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                child: FFRemoteImage(
                  src: store['banner'].toString(),
                  height: 160,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: FFTokens.spacingMd),
            Row(
              children: [
                if (store['logo']?.toString().isNotEmpty == true)
                  ClipOval(
                    child: FFRemoteImage(
                      src: store['logo'].toString(),
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  ),
                const SizedBox(width: FFTokens.spacingMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store['businessName']?.toString() ??
                            context.tr('shop.vendorStore'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 16),
                          Text(
                            ' ${_shopNumber(store['rating']).toStringAsFixed(1)} (${_shopNumber(store['reviewCount']).toInt()})',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingMd),
            Text(store['description']?.toString() ?? ''),
            Text(
              '${context.tr('shop.contact')}: ${store['contactNumber'] ?? ''}',
            ),
            Text('${store['email'] ?? ''} · ${store['address'] ?? ''}'),
            if (categories.isNotEmpty)
              Text('${context.tr('shop.categories')}: $categories'),
            const SizedBox(height: FFTokens.spacingMd),
            TextField(
              key: const Key('shop-store-search'),
              decoration: InputDecoration(
                labelText: context.tr('shop.searchStore'),
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              context.tr('shop.products'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (products.isEmpty)
              Text(context.tr('shop.noProducts'))
            else
              ...products.map(
                (product) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.shopping_bag_outlined),
                  title: Text(product.name),
                  subtitle: Text(product.category ?? ''),
                  trailing: Text(formatCurrency(product.effectivePrice)),
                ),
              ),
            Text(
              context.tr('shop.reviews'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (reviews.isEmpty)
              Text(context.tr('shop.noReviews'))
            else
              ...reviews.map(
                (review) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _RatingLabel(rating: review['rating']),
                  title: Text(review['comment']?.toString() ?? ''),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _RatingLabel extends StatelessWidget {
  const _RatingLabel({required this.rating});
  final dynamic rating;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [Text('${rating ?? 0} '), const Icon(Icons.star, size: 16)],
    );
  }
}
