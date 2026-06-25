import 'package:flutter/material.dart';
import '../design_tokens.dart';
import 'ff_card.dart';

/// Trend direction for metric cards.
enum FFTrendDirection { up, down, neutral }

/// Dashboard stat tile — matches portal's MetricCard.
class FFMetricCard extends StatelessWidget {
  const FFMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.icon,
    this.trendDirection,
    this.trendLabel,
  });

  final String label;
  final String value;
  final String? sub;
  final Widget? icon;
  final FFTrendDirection? trendDirection;
  final String? trendLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FFCard(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  value,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: FFTokens.spacingXs),
                  Text(
                    sub!,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (trendDirection != null && trendLabel != null) ...[
                  const SizedBox(height: FFTokens.spacingSm),
                  _TrendBadge(direction: trendDirection!, label: trendLabel!),
                ],
              ],
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: FFTokens.spacingMd),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                border: Border.all(color: theme.colorScheme.outline),
                borderRadius: BorderRadius.circular(FFTokens.radiusXl),
              ),
              child: Center(child: icon),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendBadge extends StatelessWidget {
  const _TrendBadge({required this.direction, required this.label});

  final FFTrendDirection direction;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, String arrow) = switch (direction) {
      FFTrendDirection.up => (
        FFTokens.success50,
        FFTokens.success700,
        '\u2191',
      ),
      FFTrendDirection.down => (FFTokens.error50, FFTokens.error700, '\u2193'),
      FFTrendDirection.neutral => (
        FFTokens.bgTertiary,
        FFTokens.fgTertiary,
        '\u2014',
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingSm,
        vertical: FFTokens.spacing2xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FFTokens.radiusFull),
      ),
      child: Text(
        '$arrow $label',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
  }
}
