import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_tokens.dart';
import '../../i18n.dart';
import '../../shop_home.dart';

const _icons = <String, IconData>{
  'supplements_nutrition': Icons.science_outlined,
  'sportswear_footwear': Icons.checkroom_outlined,
  'equipment': Icons.fitness_center,
  'accessories_gear': Icons.backpack_outlined,
  'food_drinks': Icons.restaurant_outlined,
  'health_recovery': Icons.spa_outlined,
  'events': Icons.event_outlined,
  'other': Icons.category_outlined,
};

const double _gap = FFTokens.spacingSm;

/// Column width for a tile: 76 (spec §6.1, about 4.5 tiles on a 375 phone),
/// wider only above 130% text so two-line labels keep whole words.
double shopCategoryTileWidth(BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1);
  return scale <= 1.3 ? 76 : 76 * math.min(scale / 1.3, 1.5);
}

/// "Shop by category": a round icon tile per category, in the server's order.
/// Every category is always offered, whatever role the customer shops as.
/// When every tile fits (wide screens), they are spread over one row;
/// otherwise the row scrolls, edge to edge with [inset] padding.
class ShopCategoryRow extends StatelessWidget {
  const ShopCategoryRow({
    super.key,
    required this.categories,
    required this.onSelected,
    this.inset = 16,
  });

  final List<ShopHomeCategory> categories;
  final ValueChanged<String> onSelected;
  final double inset;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final tileWidth = shopCategoryTileWidth(context);
    List<Widget> tiles() => [
      for (final c in categories)
        ShopCategoryTile(
          category: c,
          width: tileWidth,
          onTap: () => onSelected(c.key),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Semantics(
            header: true,
            child: Text(
              context.tr('shop.home.categories'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        LayoutBuilder(
          builder: (context, constraints) {
            final needed =
                categories.length * tileWidth +
                (categories.length - 1) * _gap +
                2 * inset;
            if (needed <= constraints.maxWidth) {
              return Padding(
                key: const Key('shop-home-categories'),
                padding: EdgeInsets.symmetric(horizontal: inset),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: tiles(),
                ),
              );
            }
            final list = tiles();
            return SingleChildScrollView(
              key: const Key('shop-home-categories'),
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: inset),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0) const SizedBox(width: _gap),
                    list[i],
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

class ShopCategoryTile extends StatelessWidget {
  const ShopCategoryTile({
    super.key,
    required this.category,
    required this.onTap,
    this.width = 76,
  });

  final ShopHomeCategory category;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    // The server's name in this language, else the app's own for the key.
    final server = lang == 'sw' ? category.label.sw : category.label.en;
    final full = server.isNotEmpty
        ? server
        : shopCategoryText(category.key).of(lang);
    final shortKey = 'shop.cat.short.${category.key}';
    final short = context.tr(shortKey);
    final label = short == shortKey ? full : short;
    // 12/16 without the label style's wide tracking, which made words such
    // as "Supplements" too wide for the 76px column.
    final base = theme.textTheme.labelSmall?.copyWith(
      fontSize: 12,
      height: 16 / 12,
      letterSpacing: 0,
    );
    return Semantics(
      key: Key('shop-home-category-${category.key}'),
      button: true,
      excludeSemantics: true,
      label: context.tr('shop.a11y.category').replaceAll('{category}', full),
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 100),
          child: SizedBox(
            width: width,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _icons[category.key] ?? Icons.category_outlined,
                      size: 28,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    key: Key('shop-home-category-label-${category.key}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: wordSafeStyle(context, label, base, width),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// [style], made just small enough that the label's longest word fits on
/// one line of [width] (down to 70%), so no word is broken in the middle
/// ("Supplement / s"). A word that still does not fit is ended with "…" by
/// the two-line limit rather than split.
TextStyle? wordSafeStyle(
  BuildContext context,
  String label,
  TextStyle? style,
  double width,
) {
  if (style == null) return style;
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  var widest = 0.0;
  for (final word in label.split(RegExp(r'\s+'))) {
    if (word.isEmpty) continue;
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textScaler: scaler,
      textDirection: direction,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, painter.width);
  }
  if (widest <= width) return style;
  final factor = math.max(width / widest, 0.7);
  return style.copyWith(fontSize: (style.fontSize ?? 12) * factor * 0.98);
}
