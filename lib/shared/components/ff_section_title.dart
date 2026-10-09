import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Section heading used between content blocks on a scrollable page.
/// Replaces the per-screen private `_SectionTitle` widgets.
class FFSectionTitle extends StatelessWidget {
  const FFSectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: FFTokens.spacingMd,
        bottom: FFTokens.spacingSm + 2,
      ),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
