import 'package:flutter/material.dart';

import '../../design_tokens.dart';
import '../../i18n.dart';

/// Card width for a rail: 156 on phones, 180 on tablets, 200 on wide screens,
/// and at least 180 from 160% text size so names and prices still fit.
double shopRailCardWidth(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final base = width >= 1024
      ? 200.0
      : width >= 600
      ? 180.0
      : 156.0;
  final scale = MediaQuery.textScalerOf(context).scale(1);
  return scale >= 1.6 && base < 180 ? 180 : base;
}

/// A titled home section: header (title, "Why am I seeing this?", "View all")
/// over a horizontally scrolling row of cards. The row is as tall as its
/// tallest card at the current text size, so nothing is clipped.
class ShopProductRail extends StatefulWidget {
  const ShopProductRail({
    super.key,
    required this.sectionKey,
    required this.title,
    required this.children,
    this.onWhy,
    this.onViewAll,
    this.onShown,
  });

  final String sectionKey;
  final String title;
  final List<Widget> children;
  final VoidCallback? onWhy;
  final VoidCallback? onViewAll;

  /// Called once, when the section is first built (it is near the screen:
  /// the page builds lazily).
  final VoidCallback? onShown;

  @override
  State<ShopProductRail> createState() => _ShopProductRailState();
}

class _ShopProductRailState extends State<ShopProductRail> {
  @override
  void initState() {
    super.initState();
    widget.onShown?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The trailing controls drop under the title when they do not fit
          // (long Swahili titles, large text).
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Semantics(
                    header: true,
                    child: Text(
                      widget.title,
                      key: Key('shop-home-title-${widget.sectionKey}'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.onWhy != null)
                    IconButton(
                      key: Key('shop-home-why-${widget.sectionKey}'),
                      tooltip: context.tr('shop.why.a11y'),
                      icon: const Icon(Icons.info_outline),
                      onPressed: widget.onWhy,
                    ),
                  if (widget.onViewAll != null)
                    Semantics(
                      button: true,
                      excludeSemantics: true,
                      label: context
                          .tr('shop.a11y.viewAll')
                          .replaceAll('{section}', widget.title),
                      onTap: widget.onViewAll,
                      child: TextButton.icon(
                        key: Key('shop-home-viewall-${widget.sectionKey}'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: widget.onViewAll,
                        iconAlignment: IconAlignment.end,
                        icon: const Icon(Icons.arrow_forward, size: 18),
                        label: Text(context.tr('shop.home.viewAll')),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingSm),
          SingleChildScrollView(
            key: Key('shop-home-rail-${widget.sectionKey}'),
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  widget.children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
