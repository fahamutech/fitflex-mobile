import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Small pill / chip used for tags, filters, and tier badges.
///
/// When [onTap] is set the pill is a button: it has a ripple, button
/// semantics and a hit area of at least 48dp.
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
    final text = label.replaceAll('_', ' ');
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
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: filled ? Colors.white : FFTokens.brandDark,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    if (onTap == null) return child;
    return Semantics(
      button: true,
      selected: filled,
      label: text,
      excludeSemantics: true,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(FFTokens.radiusFull),
          child: Center(widthFactor: 1, child: child),
        ),
      ),
    );
  }
}
