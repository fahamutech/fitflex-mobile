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
    return Container(
      width: double.infinity,
      margin: margin ?? const EdgeInsets.only(bottom: 10),
      padding: padding ?? const EdgeInsets.all(FFTokens.spacingMd),
      decoration: BoxDecoration(
        color: FFTokens.bgPrimary,
        border: Border.all(color: FFTokens.borderSecondary),
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        boxShadow: FFTokens.shadowSm,
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: FFTokens.borderSecondary)),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: FFTokens.borderSecondary)),
      ),
      child: child,
    );
  }
}
