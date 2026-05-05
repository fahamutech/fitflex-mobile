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
    return FFCard(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: FFTokens.fgQuaternary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: FFTokens.fgPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                if (sub != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    sub!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: FFTokens.fgQuaternary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (trendDirection != null && trendLabel != null) ...[
                  const SizedBox(height: 12),
                  _TrendBadge(direction: trendDirection!, label: trendLabel!),
                ],
              ],
            ),
          ),
          if (icon != null) ...[
            const SizedBox(width: 16),
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: FFTokens.bgSecondary,
                border: Border.all(color: FFTokens.borderSecondary),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(FFTokens.radiusFull),
      ),
      child: Text(
        '$arrow $label',
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg),
      ),
    );
  }
}
