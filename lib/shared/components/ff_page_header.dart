import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Page header with title, description and optional actions — matches portal's PageHeader.
class FFPageHeader extends StatelessWidget {
  const FFPageHeader({
    super.key,
    required this.title,
    this.description,
    this.actions,
  });

  final String title;
  final String? description;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingLg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge),
                if (description != null) ...[
                  const SizedBox(height: FFTokens.spacing2xs),
                  Text(description!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          if (actions != null) ...[
            const SizedBox(width: FFTokens.spacingSm),
            actions!,
          ],
        ],
      ),
    );
  }
}
