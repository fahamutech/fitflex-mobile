import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Placeholder block shown while content loads. Pulses gently; stands still
/// when the system asks for reduced motion.
class FFSkeleton extends StatefulWidget {
  const FFSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = FFTokens.radiusSm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<FFSkeleton> createState() => _FFSkeletonState();
}

class _FFSkeletonState extends State<FFSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
      _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: base.withValues(alpha: 0.05 + 0.07 * _c.value),
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      ),
    );
  }
}

/// A text-line placeholder. [widthFactor] is a fraction of the available
/// width.
class FFSkeletonLine extends StatelessWidget {
  const FFSkeletonLine({super.key, this.widthFactor = 1, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor.clamp(0.05, 1.0),
      alignment: Alignment.centerLeft,
      child: FFSkeleton(height: height),
    );
  }
}

/// A card-shaped placeholder: avatar block plus two text lines.
class FFSkeletonCard extends StatelessWidget {
  const FFSkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outline),
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: const Row(
        children: [
          FFSkeleton(
            width: FFTokens.iconBox + 8,
            height: FFTokens.iconBox + 8,
            radius: FFTokens.radiusMd,
          ),
          SizedBox(width: FFTokens.spacingMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FFSkeletonLine(widthFactor: 0.7, height: 14),
                SizedBox(height: FFTokens.spacingSm),
                FFSkeletonLine(widthFactor: 0.45),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A column of [FFSkeletonCard]s for list placeholders. Announced to screen
/// readers as one loading region.
class FFSkeletonList extends StatelessWidget {
  const FFSkeletonList({super.key, this.count = 3, this.semanticLabel});

  final int count;

  /// Spoken label for the whole placeholder (pass `context.tr('common.loading')`).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      container: true,
      child: Column(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(height: FFTokens.spacingSm + 4),
            const FFSkeletonCard(),
          ],
        ],
      ),
    );
  }
}
