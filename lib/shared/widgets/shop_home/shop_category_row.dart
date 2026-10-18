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

/// "Shop by category": a round icon tile per category, in the server's order.
/// Every category is always offered, whatever role the customer shops as.
class ShopCategoryRow extends StatelessWidget {
  const ShopCategoryRow({
    super.key,
    required this.categories,
    required this.onSelected,
  });

  final List<ShopHomeCategory> categories;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            context.tr('shop.home.categories'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        SingleChildScrollView(
          key: const Key('shop-home-categories'),
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < categories.length; i++) ...[
                if (i > 0) const SizedBox(width: FFTokens.spacingSm),
                ShopCategoryTile(
                  category: categories[i],
                  onTap: () => onSelected(categories[i].key),
                ),
              ],
            ],
          ),
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
  });

  final ShopHomeCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final full = category.label.of(lang);
    final shortKey = 'shop.cat.short.${category.key}';
    final short = context.tr(shortKey);
    final label = short == shortKey ? full : short;
    // Wider columns at large text so two-line labels keep whole words.
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final width = 76 * math.min(math.max(scale, 1.0), 1.5).toDouble();
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontSize: 12,
                      height: 16 / 12,
                    ),
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
