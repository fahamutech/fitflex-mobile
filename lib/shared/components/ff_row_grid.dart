import 'package:flutter/widgets.dart';

import '../design_tokens.dart';

/// Columns for a grid of portrait cards: 4 / 3 on wide screens, 2 on a
/// phone, and 1 when the phone is narrow for its text size (360 wide at text
/// scale 1.3), so names and labels are never cut to "Dev Owner …".
int ffCardGridColumns(BuildContext context, double width) {
  if (width >= 900) return 4;
  if (width >= 600) return 3;
  final scale = MediaQuery.textScalerOf(context).scale(100) / 100;
  return width / scale < 300 ? 1 : 2;
}

/// A sliver grid whose rows are as tall as their tallest card, instead of a
/// fixed aspect ratio: a two-line name or a wrapped label makes the row
/// taller rather than being clipped.
class SliverFFRowGrid extends StatelessWidget {
  const SliverFFRowGrid({
    super.key,
    required this.columns,
    required this.itemCount,
    required this.itemBuilder,
    this.spacing = FFTokens.spacingMd,
    this.runSpacing = FFTokens.spacingMd,
  });

  final int columns;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double spacing;
  final double runSpacing;

  @override
  Widget build(BuildContext context) {
    final cols = columns < 1 ? 1 : columns;
    final rows = (itemCount + cols - 1) ~/ cols;
    return SliverList.builder(
      itemCount: rows,
      itemBuilder: (context, r) => Padding(
        padding: EdgeInsets.only(top: r == 0 ? 0 : runSpacing),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var c = 0; c < cols; c++) ...[
                if (c > 0) SizedBox(width: spacing),
                Expanded(
                  child: r * cols + c < itemCount
                      ? itemBuilder(context, r * cols + c)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
