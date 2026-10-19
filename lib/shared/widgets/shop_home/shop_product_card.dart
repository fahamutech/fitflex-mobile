import 'package:flutter/material.dart';

import '../../components/components.dart';
import '../../design_tokens.dart';
import '../../formatters.dart';
import '../../i18n.dart';
import '../../promotion_events.dart';
import '../shop_browse_page.dart' show ShopProduct;
import 'shop_focus_ring.dart';

/// Whether [product] is on sale: a sale price above zero and below the price.
bool shopOnSale(ShopProduct product) {
  final sale = product.discountPriceTzs;
  return sale != null && sale > 0 && sale < product.priceTzs;
}

/// The discount, rounded down so the claim is never overstated. 0 when the
/// product is not on sale.
int shopDiscountPercent(ShopProduct product) {
  if (!shopOnSale(product) || product.priceTzs <= 0) return 0;
  return ((product.priceTzs - product.discountPriceTzs!) /
          product.priceTzs *
          100)
      .floor();
}

/// "Only 3 left" / "Only 1 left" (Swahili: "Zimebaki 3 tu" / "Imebaki 1 tu").
String shopOnlyLeft(BuildContext context, int n) => n == 1
    ? context.tr('shop.home.onlyLeftOne')
    : context.tr('shop.home.onlyLeft').replaceAll('{n}', '$n');

/// Ratings are shown only when real reviews exist: never "0.0".
bool shopHasRating(ShopProduct product) =>
    product.reviewCount > 0 && product.rating > 0;

/// What a screen reader says for the card: promotion label first, then name,
/// price ("was" for the struck-through price), rating and stock.
String shopProductSemantics(
  BuildContext context,
  ShopProduct product, {
  String? promotionLabel,
}) {
  String tr(String key) => context.tr(key);
  final parts = <String>[
    if (promotionLabel != null && promotionLabel.isNotEmpty) promotionLabel,
    product.name,
    if (shopOnSale(product))
      tr('shop.a11y.salePrice')
          .replaceAll('{sale}', formatCurrency(product.discountPriceTzs!))
          .replaceAll('{old}', formatCurrency(product.priceTzs))
          .replaceAll('{pct}', '${shopDiscountPercent(product)}')
    else
      tr(
        'shop.a11y.price',
      ).replaceAll('{price}', formatCurrency(product.priceTzs)),
    if (shopHasRating(product))
      (product.reviewCount == 1
              ? tr('shop.a11y.ratingOne')
              : tr('shop.a11y.rating'))
          .replaceAll('{rating}', product.rating.toStringAsFixed(1))
          .replaceAll('{count}', '${product.reviewCount}'),
    if (!product.inStock)
      tr('shop.outOfStock')
    else if (product.stock <= 5)
      shopOnlyLeft(context, product.stock),
  ];
  return parts.join('. ');
}

/// A product on the shop home: image on a white well, name, rating (only
/// with real reviews), price block and a round add-to-cart button.
///
/// The card opens details; the cart button is a separate control that never
/// opens details. Out of stock: dimmed image, a badge, no cart button.
class ShopProductCard extends StatelessWidget {
  const ShopProductCard({
    super.key,
    required this.product,
    required this.width,
    required this.qty,
    required this.onOpen,
    required this.onAdd,
    this.placement,
  });

  final ShopProduct product;
  final double width;
  final int qty;
  final VoidCallback onOpen;
  final VoidCallback onAdd;
  final String? placement;

  static const double _hit = 48;
  static const double _button = 40;

  @override
  Widget build(BuildContext context) => PromotionTracked(
    entityType: 'product',
    entityId: product.id,
    promotion: product.promotion,
    placement: placement,
    child: _card(context),
  );

  void _open() {
    trackPromotionClick(
      'product',
      product.id,
      product.promotion,
      placement: placement,
    );
    onOpen();
  }

  Widget _card(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final tag = product.promotion;
    final promoLabel = tag == null
        ? null
        : FFPromotionBadge(tag: tag).text(context);
    final onSale = shopOnSale(product);
    final percent = shopDiscountPercent(product);
    final fuel = dark ? FFTokens.fuelOnDark : FFTokens.fuel;

    final well = SizedBox(
      width: width,
      height: width,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              clipBehavior: Clip.antiAlias,
              padding: const EdgeInsets.all(FFTokens.spacingSm),
              decoration: BoxDecoration(
                // Product photos are shot on white: a white well in both themes.
                color: Colors.white,
                borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                border: dark ? Border.all(color: colors.outlineVariant) : null,
              ),
              child: product.images.isEmpty
                  ? const _ImageFallback()
                  : FFRemoteImage(
                      src: product.images.first,
                      fit: BoxFit.contain,
                      fallback: const _ImageFallback(),
                    ),
            ),
          ),
          if (!product.inStock)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                ),
              ),
            ),
          Positioned(
            top: FFTokens.spacingSm,
            left: FFTokens.spacingSm,
            right: FFTokens.spacingSm + _hit,
            child: Align(
              alignment: Alignment.topLeft,
              child: !product.inStock
                  ? ShopOutOfStockBadge(
                      key: Key('shop-home-oos-${product.id}'),
                      label: context.tr('shop.outOfStock'),
                    )
                  : percent >= 1
                  ? FFBadge(
                      key: Key('shop-home-discount-${product.id}'),
                      label: '−$percent%',
                      tone: FFBadgeTone.fuel,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        well,
        const SizedBox(height: FFTokens.spacingSm),
        if (tag != null)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
            child: FFPromotionBadge(tag: tag),
          ),
        Text(
          product.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 20 / 14,
          ),
        ),
        if (shopHasRating(product))
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacing2xs),
            child: Wrap(
              key: Key('shop-home-rating-${product.id}'),
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(
                  Icons.star_rounded,
                  size: FFTokens.iconXs,
                  color: dark ? FFTokens.accent : FFTokens.accent700,
                ),
                const SizedBox(width: FFTokens.spacing2xs),
                Text(
                  '${product.rating.toStringAsFixed(1)} (${product.reviewCount})',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        const SizedBox(height: FFTokens.spacingXs),
        if (onSale) ...[
          Text(
            formatCurrency(product.discountPriceTzs!),
            key: Key('shop-home-sale-${product.id}'),
            style: theme.textTheme.titleSmall?.copyWith(
              color: fuel,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            formatCurrency(product.priceTzs),
            key: Key('shop-home-was-${product.id}'),
            style: theme.textTheme.labelSmall?.copyWith(
              color: FFTokens.mutedText(context),
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ] else
          Text(
            formatCurrency(product.priceTzs),
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        if (product.inStock && product.stock <= 5)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacing2xs),
            child: Text(
              shopOnlyLeft(context, product.stock),
              style: theme.textTheme.labelSmall?.copyWith(
                color: fuel,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          Semantics(
            key: Key('shop-home-card-${product.id}'),
            container: true,
            button: true,
            excludeSemantics: true,
            label: shopProductSemantics(
              context,
              product,
              promotionLabel: promoLabel,
            ),
            onTap: _open,
            child: ShopFocusRing(
              shape: BoxShape.rectangle,
              builder: (node) => InkWell(
                borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                onTap: _open,
                focusNode: node,
                child: body,
              ),
            ),
          ),
          if (product.inStock)
            Positioned(
              top: width - _hit - 2,
              right: 2,
              child: _CartButton(
                key: Key('shop-home-add-${product.id}'),
                qty: qty,
                label: qty > 0
                    ? context
                          .tr('shop.a11y.inCart')
                          .replaceAll('{name}', product.name)
                          .replaceAll('{qty}', '$qty')
                    : context
                          .tr(
                            product.variants.isNotEmpty
                                ? 'shop.a11y.addWithOption'
                                : 'shop.a11y.addToCart',
                          )
                          .replaceAll('{name}', product.name),
                onPressed: onAdd,
              ),
            ),
        ],
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) => const Center(
    child: Icon(
      Icons.shopping_bag_outlined,
      size: FFTokens.iconXl,
      // On the white well in both themes, so a fixed mid slate (>= 3:1).
      color: FFTokens.inputBorderDark,
    ),
  );
}

/// "Out of stock": white on the inverse surface (slate-700 family), the
/// same on the home cards and in the product list.
class ShopOutOfStockBadge extends StatelessWidget {
  const ShopOutOfStockBadge({super.key, required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingSm,
        vertical: FFTokens.spacing2xs,
      ),
      decoration: BoxDecoration(
        color: colors.inverseSurface,
        borderRadius: BorderRadius.circular(FFTokens.radiusFull),
      ),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.onInverseSurface),
      ),
    );
  }
}

/// 40px visual, 48px target. Light theme: brand fill, white icon. Dark theme:
/// slate fill with a Volt icon (Volt never sits on the white well itself).
class _CartButton extends StatelessWidget {
  const _CartButton({
    super.key,
    required this.qty,
    required this.label,
    required this.onPressed,
  });

  final int qty;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final fill = dark ? FFTokens.darkSurface : theme.colorScheme.primary;
    final ink = dark ? FFTokens.volt : theme.colorScheme.onPrimary;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      onTap: onPressed,
      child: SizedBox(
        width: ShopProductCard._hit,
        height: ShopProductCard._hit,
        child: Material(
          type: MaterialType.transparency,
          child: ShopFocusRing(
            shape: BoxShape.circle,
            builder: (node) => InkResponse(
              onTap: onPressed,
              focusNode: node,
              radius: ShopProductCard._hit / 2,
              child: Center(
                child: Container(
                  width: ShopProductCard._button,
                  height: ShopProductCard._button,
                  decoration: BoxDecoration(
                    color: fill,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: qty > 0
                      ? Text(
                          '$qty',
                          // Fixed size inside a fixed circle; the label carries it.
                          textScaler: TextScaler.noScaling,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: ink,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : Icon(
                          Icons.add_shopping_cart,
                          size: FFTokens.iconMd,
                          color: ink,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
