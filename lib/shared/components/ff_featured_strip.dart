import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A titled, horizontally scrolling row for the Featured section above a list.
/// It renders nothing when there is nothing to feature, so an empty section
/// never takes up room.
class FFFeaturedStrip extends StatelessWidget {
  const FFFeaturedStrip({
    super.key,
    required this.title,
    required this.count,
    required this.itemBuilder,
    this.itemWidth = 168,
    this.height = 250,
  });

  final String title;
  final int count;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final double itemWidth;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();
    final tt = Theme.of(context).textTheme;
    return Column(
      key: const Key('featured-strip'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FFTokens.spacingLg,
            FFTokens.spacingMd,
            FFTokens.spacingLg,
            FFTokens.spacingSm,
          ),
          child: Text(
            title,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          height: height,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: FFTokens.spacingLg),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: FFTokens.spacingMd),
            itemBuilder: (context, i) =>
                SizedBox(width: itemWidth, child: itemBuilder(context, i)),
          ),
        ),
      ],
    );
  }
}
