import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../api_client.dart';
import '../../api_error_message.dart';
import '../../components/components.dart';
import '../../design_tokens.dart';
import '../../formatters.dart';
import '../../i18n.dart';
import '../../product_categories.dart';
import '../../shop_home.dart';
import '../shop_browse_page.dart' show ShopCart, ShopProduct;
import 'shop_category_row.dart';
import 'shop_product_card.dart';
import 'shop_product_rail.dart';

/// The personalised Shop home (V2, Phase 1): search and cart, "Shop by
/// category", then the sections the server chose, in the server's order.
///
/// It owns only the home request; the cart, product details, checkout and
/// the product list belong to the shop screen around it (ShopBrowseBody),
/// reached through the callbacks. When the backend answers 404
/// `feature_disabled` or 403 `mode_not_allowed`, [onUnavailable] tells the
/// screen to show today's shop instead.
class ShopHomeView extends StatefulWidget {
  const ShopHomeView({
    super.key,
    required this.mode,
    required this.cart,
    required this.onOpen,
    required this.onAdd,
    required this.onSearch,
    required this.onCategory,
    required this.onViewAll,
    required this.onBrowseAll,
    required this.onCheckout,
    required this.onUnavailable,
    this.ordering = false,
  });

  final ShopHomeMode mode;
  final ShopCart cart;
  final void Function(ShopProduct product) onOpen;

  /// Adds one unit (asking for an option first when needed); whether it did.
  final Future<bool> Function(ShopProduct product) onAdd;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onCategory;
  final ValueChanged<Map<String, String>> onViewAll;
  final VoidCallback onBrowseAll;
  final VoidCallback onCheckout;
  final VoidCallback onUnavailable;
  final bool ordering;

  @override
  State<ShopHomeView> createState() => ShopHomeViewState();
}

class ShopHomeViewState extends State<ShopHomeView> {
  ShopHomeData? _data;
  Object? _error;
  bool _loading = true;
  int _load = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) reload();
    });
  }

  String? _profileValue(Map<String, dynamic>? user, String key) {
    final direct = user?[key];
    if (direct is String && direct.isNotEmpty) return direct;
    final profile = user?['memberProfile'];
    final nested = profile is Map ? profile[key] : null;
    return nested is String && nested.isNotEmpty ? nested : null;
  }

  /// Fetches the home again. Content already shown stays while it loads.
  Future<void> reload() async {
    final scope = AppScope.of(context);
    final id = ++_load;
    setState(() => _loading = true);
    final user = scope.auth.user;
    final recent = await RecentlyViewedProducts.load(user?['id']?.toString());
    try {
      final json = await scope.api.shopHome(
        mode: widget.mode.wire,
        region: _profileValue(user, 'region'),
        city: _profileValue(user, 'city'),
        recent: recent,
      );
      if (!mounted || id != _load) return;
      setState(() {
        _data = ShopHomeData.fromJson(json);
        _error = null;
        _loading = false;
      });
      ShopEvents.newLoad();
      ShopEvents.send(scope.api, 'shop_home_viewed', mode: widget.mode);
    } on ApiException catch (e) {
      if (!mounted || id != _load) return;
      if (e.status == 404 || e.status == 403) {
        setState(() => _loading = false);
        widget.onUnavailable();
        return;
      }
      setState(() {
        _error = e;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _load) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _event(
    String type, {
    String? section,
    String? productId,
    int? position,
    String? once,
  }) => ShopEvents.send(
    AppScope.of(context).api,
    type,
    mode: widget.mode,
    section: section,
    productId: productId,
    position: position,
    once: once,
  );

  Future<void> _add(ShopProduct product, String section, int position) async {
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    final added = await widget.onAdd(product);
    if (!mounted) return;
    if (added) {
      _event(
        'add_to_cart',
        section: section,
        productId: product.id,
        position: position,
      );
      messenger.success(
        locale.t('shop.home.added'),
        actionLabel: locale.t('shop.home.viewCart'),
        onAction: widget.onCheckout,
      );
    } else if (widget.cart.qtyOf(product.id) > 0) {
      // Already in the cart and nothing added: the stock limit was reached.
      // (Nothing in the cart means the option picker was closed.)
      messenger.info(locale.t('shop.home.notAdded'));
    }
  }

  /// "Why am I seeing this?": only the reason the server gave for the
  /// section. (Phase 2 adds the personalisation setting here; TODO.)
  Future<void> _showWhy(ShopHomeSection section, ShopText reason) async {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    await showFFSheet<void>(
      context,
      title: context.tr('shop.why.title'),
      child: Text(
        reason.of(lang),
        key: Key('shop-why-${section.key}'),
        style: Theme.of(context).textTheme.bodyLarge,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final children = <Widget>[_searchRow(context)];
    if (data == null && _loading) {
      children.add(const _ShopHomeSkeleton());
    } else if (data == null) {
      children.add(_errorState(context));
    } else {
      if (_error != null) {
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
            child: FFAlert(
              key: const Key('shop-home-offline-bar'),
              message: context.tr(
                isNetworkError(_error!)
                    ? 'offline.banner'
                    : 'shop.home.errorTitle',
              ),
            ),
          ),
        );
      }
      children.addAll(_content(context, data));
    }
    return Column(
      key: const Key('shop-home'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _searchRow(BuildContext context) {
    final count = widget.cart.itemCount;
    final cartLabel = count == 0
        ? context.tr('shop.home.cart')
        : context.tr('shop.home.cartCount').replaceAll('{n}', '$count');
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: Row(
        children: [
          Expanded(
            child: FFTextField(
              key: const Key('shop-home-search'),
              hint: context.tr('shop.searchHint'),
              prefixIcon: const Icon(Icons.search, size: 20),
              textInputAction: TextInputAction.search,
              onFieldSubmitted: (value) {
                if (value.trim().isEmpty) return;
                // The text itself is never sent: only that a search happened.
                _event('search_submitted');
                widget.onSearch(value.trim());
              },
            ),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          IconButton(
            key: const Key('shop-home-cart'),
            tooltip: cartLabel,
            onPressed: () {
              if (widget.cart.isEmpty) {
                FFSnack.info(context, context.tr('shop.home.cartEmpty'));
              } else {
                widget.onCheckout();
              }
            },
            icon: Badge(
              isLabelVisible: count > 0,
              label: Text('$count'),
              child: const Icon(Icons.shopping_cart_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorState(BuildContext context) {
    final offline = _error != null && isNetworkError(_error!);
    return FFErrorState(
      key: Key(offline ? 'shop-home-offline' : 'shop-home-error'),
      icon: offline ? Icons.wifi_off : Icons.error_outline,
      title: context.tr(
        offline ? 'shop.home.offlineTitle' : 'shop.home.errorTitle',
      ),
      message: context.tr(
        offline ? 'shop.home.offlineBody' : 'shop.home.errorBody',
      ),
      onRetry: reload,
    );
  }

  List<Widget> _content(BuildContext context, ShopHomeData data) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final products = <String, ShopProduct>{
      for (final e in data.products.entries)
        e.key: ShopProduct.fromJson({'id': e.key, ...e.value}),
    };
    final sections = [
      for (final section in data.sections)
        (
          section,
          [
            for (final id in section.productIds)
              if (products[id] != null) products[id]!,
          ],
        ),
    ].where((entry) => entry.$2.isNotEmpty).toList();

    if (products.isEmpty || sections.isEmpty) {
      return [
        FFEmptyState(
          key: const Key('shop-home-empty'),
          icon: Icons.storefront_outlined,
          title: context.tr('shop.home.emptyTitle'),
          body: context.tr('shop.home.emptyBody'),
          action: FFButton(
            label: context.tr('shop.home.browseAll'),
            variant: FFButtonVariant.ghost,
            onPressed: widget.onBrowseAll,
          ),
        ),
      ];
    }

    final categories = data.categories.isNotEmpty
        ? data.categories
        : [
            for (final c in ProductCategories.current)
              ShopHomeCategory(key: c.key, label: ShopText(c.en, c.sw)),
          ];
    final width = shopRailCardWidth(context);
    return [
      ShopCategoryRow(
        categories: categories,
        onSelected: (key) {
          _event('filter_applied');
          widget.onCategory(key);
        },
      ),
      const SizedBox(height: FFTokens.spacingMd),
      for (final (section, items) in sections)
        ShopProductRail(
          key: Key('shop-home-section-${section.key}'),
          sectionKey: section.key,
          title: section.title.of(lang),
          onShown: () => _event(
            'section_viewed',
            section: section.key,
            once: 'section:${section.key}',
          ),
          onWhy: section.reason == null
              ? null
              : () => _showWhy(section, section.reason!),
          onViewAll: () {
            _event('filter_applied', section: section.key);
            widget.onViewAll(section.viewAll);
          },
          children: [
            for (var i = 0; i < items.length; i++)
              _ImpressionOnce(
                key: ValueKey('${section.key}/${items[i].id}'),
                onShown: () => _event(
                  'product_impression',
                  section: section.key,
                  productId: items[i].id,
                  position: i,
                  once: 'impression:${section.key}:${items[i].id}',
                ),
                child: ShopProductCard(
                  product: items[i],
                  width: width,
                  qty: widget.cart.qtyOf(items[i].id),
                  placement: 'shop_home',
                  onOpen: () {
                    _event(
                      'product_clicked',
                      section: section.key,
                      productId: items[i].id,
                      position: i,
                    );
                    widget.onOpen(items[i]);
                  },
                  onAdd: () => _add(items[i], section.key, i),
                ),
              ),
          ],
        ),
      Align(
        child: FFButton(
          key: const Key('shop-home-browse-all'),
          label: context.tr('shop.home.browseAll'),
          variant: FFButtonVariant.ghost,
          onPressed: widget.onBrowseAll,
        ),
      ),
      if (!widget.cart.isEmpty) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('shop-home-checkout'),
          label:
              '${context.tr('shop.checkout')} · ${formatCurrency(widget.cart.totalTzs)}',
          trailingIcon: Icons.arrow_forward,
          onPressed: widget.ordering ? null : widget.onCheckout,
          loading: widget.ordering,
        ),
      ],
    ];
  }
}

/// Calls [onShown] once, when first built.
class _ImpressionOnce extends StatefulWidget {
  const _ImpressionOnce({
    super.key,
    required this.onShown,
    required this.child,
  });
  final VoidCallback onShown;
  final Widget child;

  @override
  State<_ImpressionOnce> createState() => _ImpressionOnceState();
}

class _ImpressionOnceState extends State<_ImpressionOnce> {
  @override
  void initState() {
    super.initState();
    widget.onShown();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Category circles and two rails of card shapes; announced once.
class _ShopHomeSkeleton extends StatelessWidget {
  const _ShopHomeSkeleton();

  @override
  Widget build(BuildContext context) {
    final width = shopRailCardWidth(context);
    Widget rail() => Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FFSkeleton(width: 140, height: 18),
          const SizedBox(height: FFTokens.spacingMd),
          ClipRect(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    SizedBox(
                      width: width,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FFSkeleton(
                            width: width,
                            height: width,
                            radius: FFTokens.radiusMd,
                          ),
                          const SizedBox(height: FFTokens.spacingSm),
                          const FFSkeletonLine(),
                          const SizedBox(height: FFTokens.spacingXs),
                          const FFSkeletonLine(widthFactor: 0.5),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      key: const Key('shop-home-loading'),
      container: true,
      label: context.tr('shop.home.loading'),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRect(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                child: Row(
                  children: [
                    for (var i = 0; i < 5; i++)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Column(
                          children: [
                            FFSkeleton(width: 64, height: 64, radius: 32),
                            SizedBox(height: 6),
                            FFSkeleton(width: 40, height: 10),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: FFTokens.spacingLg),
            rail(),
            rail(),
          ],
        ),
      ),
    );
  }
}
