import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Small pill / chip used for tags, filters, and tier badges.
class FFPill extends StatelessWidget {
  const FFPill({
    super.key,
    required this.label,
    this.filled = false,
    this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final child = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingSm + 2,
        vertical: FFTokens.spacingXs + 2,
      ),
      decoration: BoxDecoration(
        color: filled ? FFTokens.brand : FFTokens.brandLight,
        borderRadius: BorderRadius.circular(FFTokens.radiusFull),
      ),
      child: Text(
        label.replaceAll('_', ' '),
        style: theme.textTheme.labelSmall?.copyWith(
          color: filled ? Colors.white : FFTokens.brandDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: child);
    }
    return child;
  }
}
