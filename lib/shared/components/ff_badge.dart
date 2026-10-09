import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Badge tone matching portal's BadgeTone.
enum FFBadgeTone { defaultTone, gray, brand, success, danger, warning }

/// Pill badge — matches portal's Badge component.
class FFBadge extends StatelessWidget {
  const FFBadge({
    super.key,
    required this.label,
    this.tone = FFBadgeTone.defaultTone,
    this.dot = false,
  });

  final String label;
  final FFBadgeTone tone;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color ring, Color dotColor) = switch (tone) {
      FFBadgeTone.defaultTone => (
        FFTokens.bgTertiary,
        FFTokens.fgTertiary,
        FFTokens.borderSecondary,
        FFTokens.fgDisabled,
      ),
      FFBadgeTone.gray => (
        FFTokens.gray100,
        FFTokens.gray700,
        FFTokens.gray200,
        FFTokens.gray500,
      ),
      FFBadgeTone.brand => (
        FFTokens.brand50,
        FFTokens.brand700,
        FFTokens.brand200,
        FFTokens.brand500,
      ),
      FFBadgeTone.success => (
        FFTokens.success50,
        FFTokens.success700,
        FFTokens.success200,
        FFTokens.success500,
      ),
      FFBadgeTone.danger => (
        FFTokens.error50,
        FFTokens.error700,
        FFTokens.error200,
        FFTokens.error500,
      ),
      FFBadgeTone.warning => (
        FFTokens.warning50,
        FFTokens.warning700,
        FFTokens.warning200,
        FFTokens.warning500,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingSm + 2,
        vertical: FFTokens.spacing2xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: ring),
        borderRadius: BorderRadius.circular(FFTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: FFTokens.spacingXs + 2),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
