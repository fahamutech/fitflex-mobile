import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Compact KPI tile — a tinted leading icon, a large value and a caption.
/// Used in stat rows (e.g. Members dashboard: Total / Active / Expiring).
/// Sizing, spacing, radii and typography all come from [FFTokens] / the theme.
class FFStatTile extends StatelessWidget {
  const FFStatTile({
    super.key,
    required this.icon,
    required this.value,
    required this.label,
    this.accent,
  });

  final IconData icon;
  final String value;
  final String label;

  /// Optional accent for the icon chip; defaults to the brand color.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = accent ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(FFTokens.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(FFTokens.radiusSm),
            ),
            child: Icon(icon, size: FFTokens.iconMd, color: accentColor),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: FFTokens.spacing2xs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
