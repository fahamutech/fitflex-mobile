import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';

/// F-12: four placeholder cards in the Gyms / Trainers grid while the
/// directory loads with nothing cached (photo-hero spec §32.4), instead of
/// "Nothing to show yet.". Read as one "Loading…" node.
class DirectorySkeletonGrid extends StatelessWidget {
  const DirectorySkeletonGrid({
    super.key,
    required this.columns,
    required this.childAspectRatio,
  });

  final int columns;
  final double childAspectRatio;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      sliver: SliverSemantics(
        label: context.tr('common.loading'),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, i) => const ExcludeSemantics(
              child: FFSkeleton(height: 1000, radius: FFTokens.radiusLg),
            ),
            childCount: 4,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: FFTokens.spacingMd,
            mainAxisSpacing: FFTokens.spacingMd,
            childAspectRatio: childAspectRatio,
          ),
        ),
      ),
    );
  }
}
