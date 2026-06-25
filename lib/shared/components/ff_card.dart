import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Surface card matching portal's Card component.
class FFCard extends StatelessWidget {
  const FFCard({super.key, required this.child, this.padding, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.only(bottom: FFTokens.spacingSm),
      padding: padding ?? const EdgeInsets.all(FFTokens.spacingMd),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
      child: child,
    );
  }
}

/// Card header with bottom border — matches portal's CardHeader.
class FFCardHeader extends StatelessWidget {
  const FFCardHeader({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingLg,
        vertical: FFTokens.spacingMd,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: child,
    );
  }
}

/// Card content area — matches portal's CardContent.
class FFCardContent extends StatelessWidget {
  const FFCardContent({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingLg,
        vertical: FFTokens.spacingMd,
      ),
      child: child,
    );
  }
}

/// Card footer with top border — matches portal's CardFooter.
class FFCardFooter extends StatelessWidget {
  const FFCardFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingLg,
        vertical: FFTokens.spacingMd,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Theme.of(context).colorScheme.outline),
        ),
      ),
      child: child,
    );
  }
}
