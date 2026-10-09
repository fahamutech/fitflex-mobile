import 'package:flutter/material.dart';
import '../design_tokens.dart';
import '../tone_theme.dart';

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
    final tones = FFToneTheme.of(context);
    final c = switch (tone) {
      FFBadgeTone.defaultTone => tones.neutral,
      FFBadgeTone.gray => tones.gray,
      FFBadgeTone.brand => tones.brand,
      FFBadgeTone.success => tones.success,
      FFBadgeTone.danger => tones.danger,
      FFBadgeTone.warning => tones.warning,
    };
    final (bg, fg, ring, dotColor) = (c.bg, c.fg, c.border, c.dot);

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
